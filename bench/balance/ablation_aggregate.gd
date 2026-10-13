extends SceneTree
# Абляция даров: сборщик bench/balance/ablation_v2_runs/*.txt (bench/balance/ablation_run.sh) -> bench/gift_ablation_v2.txt.
# Аргумент (необязательный): сколько секунд шли забеги — попадает в шапку итога.
# Шкала: линейная сила = sqrt(H * D) по bench/balance/strength.gd; P — игрок на старте волны после покупок, E — вся волна.
const OUT := "res://bench/gift_ablation_v2.txt"
const DIR := "res://bench/balance/ablation_v2_runs/"
const GAME := preload("res://scripts/game.gd")   # формула Сияния и загрузчики run.json, radiance.json
const BOTS := ["B2", "B5"]
const DESC := {"B2": "по кругу пехота, оружие", "B5": "по кругу пехота, лучники"}
const SEEDS := [1, 2, 3, 4, 5]
const WAVES := [1, 4, 7]
const LAST := 10
var gifts := []   # из data/gifts.json, в порядке файла
var game: Node    # узел Game вне дерева: только run_reward по data/radiance.json
var waves_per_run := 0

func load_run(cfg: String, bot: String, seed: int) -> Dictionary:
	var path := "%s%s_%s_s%d.txt" % [DIR, cfg, bot, seed]
	var r := {"waves": [], "defeat": -1, "gold": 0}
	if not FileAccess.file_exists(path):
		return r
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE":
			r.waves.append({"p": sqrt(float(f[12]) * float(f[13])), "e": sqrt(float(f[14]) * float(f[15]))})
		elif f[0] == "RUN":
			r.defeat = int(f[3]) if int(f[3]) > 0 else (41 if int(f[4]) == 1 else -1)
			r.gold = int(f[5]) if f.size() > 5 else 0
	return r

func runs_of(cfg: String, bot: String) -> Array:
	var out := []
	for seed in SEEDS:
		out.append(load_run(cfg, bot, seed))
	return out

func fmt_wave(v: int) -> String:
	return "—" if v < 0 else ("≥40" if v >= 41 else str(v))

func median(rs: Array) -> int:
	var d := rs.map(func(r): return r.defeat)
	d.sort()
	return d[d.size() / 2]

# Среднее геометрическое значения key на волне w по seed, дошедшим до неё; 0 — никто не дошёл.
func gmean(rs: Array, key: String, w: int) -> float:
	var s := 0.0
	var n := 0
	for r in rs:
		if r.waves.size() >= w:
			s += log(r.waves[w - 1][key])
			n += 1
	return exp(s / n) if n > 0 else 0.0

# Эффективный b игрока: exp(наклон прямой наименьших квадратов ln P по w), волны 1-LAST или до смерти.
func fit(rs: Array) -> float:
	var xs := []
	var ys := []
	for w in range(1, LAST + 1):
		var v := gmean(rs, "p", w)
		if v > 0.0:
			xs.append(float(w))
			ys.append(log(v))
	var n := xs.size()
	if n < 2:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for k in n:
		mx += xs[k] / n
		my += ys[k] / n
	var num := 0.0
	var den := 0.0
	for k in n:
		num += (xs[k] - mx) * (ys[k] - my)
		den += (xs[k] - mx) * (xs[k] - mx)
	return exp(num / den)

# Среднее золото, не потраченное к моменту смерти.
func mean_gold(rs: Array) -> float:
	var s := 0.0
	for r in rs:
		s += r.gold
	return s / rs.size()

# Средняя награда Сияния: забег игры кончается победой на волне waves_per_run, поэтому смерть бота позже неё считается победой.
func mean_radiance(rs: Array) -> float:
	var s := 0.0
	for r in rs:
		s += game.run_reward("win", waves_per_run) if r.defeat > waves_per_run else game.run_reward("loss", r.defeat)
	return s / rs.size()

func label(cfg: String) -> String:
	if cfg == "none":
		return "без даров"
	if cfg.begins_with("all_"):
		return "все шесть, уровень " + cfg.right(1)
	for g in gifts:
		if cfg.begins_with(g.id + "_"):
			return "%s %s (%s %s%s)" % [g.id, cfg.right(1), g.stat, "+%d" % int(g.levels[int(cfg.right(1)) - 1]), "%" if g.op == "add_pct" else ""]
	return cfg

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега
	gifts = JSON.parse_string(FileAccess.get_file_as_string("res://data/gifts.json"))
	game = GAME.new()
	game.radiance_cfg = GAME.load_radiance_cfg("res://data/radiance.json")
	waves_per_run = GAME.load_run_cfg("res://data/run.json").waves_per_run
	var rc: Dictionary = game.radiance_cfg
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 0
	var cfgs := ["none"]
	for lvl in [1, 2, 3]:
		for g in gifts:
			cfgs.append("%s_%d" % [g.id, lvl])
	for lvl in [1, 2, 3]:
		cfgs.append("all_%d" % lvl)
	var L: Array[String] = []
	var missing := 0
	for cfg in cfgs:
		for bot in BOTS:
			for r in runs_of(cfg, bot):
				if r.defeat < 0:
					missing += 1
	L.append("gift_ablation_v2: абляция даров после среза золота (data/waves.json: за убитого 1.5; в v1 было 2), только измерения.")
	L.append("Рабочие scripts/main.gd и data/*.json (не менялись), осада I (слой 1), волны без предела до поражения.")
	L.append("Пересчёт (из корня проекта):  sh bench/balance/ablation_run.sh \"<путь к godot.exe>\"")
	L.append("Время этого прогона: %s (220 забегов, до 10 процессов сразу, %d потоков процессора)." % ["%d мин %02d с" % [secs / 60, secs % 60] if secs > 0 else "не измерялось (сборщик запущен отдельно)",
		OS.get_processor_count()])
	L.append("Боты B2 (%s) и B5 (%s), seed 1-5; отряды стоят на старте, приказ «атака», всё золото тратится в передышке." % [DESC.B2, DESC.B5])
	L.append("Шкала: линейная сила = sqrt(H * D) (bench/balance/strength.gd); P — игрок на старте волны после покупок, E — вся волна.")
	L.append("P/E и b — среднее геометрическое по seed, дошедшим до волны; b — exp(наклон ln P по w) на волнах 1-%d или до смерти." % LAST)
	L.append("Золото — среднее по seed золото, не потраченное к моменту смерти (бот тратит всё в передышке: это заработок последней волны и остаток, на который ничего не купить).")
	L.append("Сияние — средняя по seed награда за забег по data/radiance.json: %d + %d * номер за каждую пройденную волну, +%d за победу. В игре забег кончается победой на волне %d," % [
		rc.wave_base, rc.wave_step, rc.win_bonus, waves_per_run])
	L.append("  поэтому смерть бота позже волны %d считается победой (%d Сияния); золото у таких забегов — на момент смерти в бесконечных волнах." % [waves_per_run, game.run_reward("win", waves_per_run)])
	if missing > 0:
		L.append("ВНИМАНИЕ: не завершено забегов: %d из %d." % [missing, cfgs.size() * BOTS.size() * SEEDS.size()])
	L.append("")
	for bot in BOTS:
		L.append("%s. Бот %s (%s)." % ["1-3" if bot == BOTS[0] else "1-3 (продолжение)", bot, DESC[bot]])
		L.append("  %-42s | смерть s1/s2/s3/s4/s5 | медиана | P/E в.1 | P/E в.4 | P/E в.7 | b игрока | золото | Сияние" % "набор")
		var base_med := median(runs_of("none", bot))
		for cfg in cfgs:
			var rs := runs_of(cfg, bot)
			var pe := PackedStringArray()
			for w in WAVES:
				var p := gmean(rs, "p", w)
				pe.append("%7s" % ("—" if p <= 0.0 else "%.2f" % (p / gmean(rs, "e", w))))
			var med := median(rs)
			L.append("  %-42s | %-21s | %2s (%s) | %s | %s | %s | %8.3f | %6.0f | %6.1f" % [label(cfg), "/".join(rs.map(func(r): return fmt_wave(r.defeat))), fmt_wave(med),
				"%+d" % (med - base_med) if cfg != "none" else " 0", pe[0], pe[1], pe[2], fit(rs), mean_gold(rs), mean_radiance(rs)])
			if cfg == "none" or cfg == "%s_3" % gifts[-1].id or (cfg.ends_with("_%s" % cfg.right(1)) and cfg.begins_with(gifts[-1].id)):
				L.append("")
		L.append("")
	L.append("4. Вклад дара в линейную силу армии на волне 4: P(4) с даром / P(4) без дара, тот же бот, среднее геометрическое по seed. Сортировка по среднему двух ботов.")
	L.append("  %-42s |    B2 |    B5 | среднее | сдвиг медианы смерти B2 / B5" % "набор")
	var rows := []
	for cfg in cfgs:
		if cfg == "none":
			continue
		var vals := []
		var shifts := PackedStringArray()
		for bot in BOTS:
			vals.append(gmean(runs_of(cfg, bot), "p", 4) / gmean(runs_of("none", bot), "p", 4))
			shifts.append("%+d" % (median(runs_of(cfg, bot)) - median(runs_of("none", bot))))
		rows.append({"cfg": cfg, "b2": vals[0], "b5": vals[1], "avg": sqrt(vals[0] * vals[1]), "shift": " / ".join(shifts)})
	rows.sort_custom(func(a, b): return a.avg > b.avg)
	for r in rows:
		L.append("  %-42s | %5.3f | %5.3f | %7.3f | %s" % [label(r.cfg), r.b2, r.b5, r.avg, r.shift])
	L.append("  В P входят только HP и урон армии: ворота (fortress_walls) в метрику не попадают совсем, золото (spoils, mine) — только через купленное к волне 4.")
	L.append("")
	L.append("5. Сияние за забег, среднее по seed и сколько таких забегов нужно на первый уровень дара (цена %d): контроль и набор «все шесть, уровень 1»." % rc.gift_prices[0])
	for cfg in ["none", "all_1"]:
		for bot in BOTS:
			var rad := mean_radiance(runs_of(cfg, bot))
			L.append("  %-28s | %s | Сияние %6.1f | забегов до дара %d | золото при смерти %5.0f" % [label(cfg), bot, rad, ceili(rc.gift_prices[0] / rad), mean_gold(runs_of(cfg, bot))])
	game.free()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
