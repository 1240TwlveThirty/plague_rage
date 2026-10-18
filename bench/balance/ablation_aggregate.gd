extends SceneTree
# Абляция даров: сборщик bench/balance/ablation_<версия>_runs/*.txt (bench/balance/ablation_run.sh) -> bench/gift_ablation_<версия>.txt.
# Аргументы: <секунд шли забеги, 0 — не измерялось> [версия, по умолчанию v4] [id даров через запятую для наборов «по одному»; по умолчанию все видимые].
# Наборы «все дары» — все видимые дары gifts.json. Прежние итоги v1, v2 собраны прежними версиями этого файла (история git) и не пересчитываются;
# v3 собран этим же файлом с версией v3 и даром «Резерв» +5/10/15% (до задачи 6a).
# Метрика: непрерывная волна смерти = номер волны смерти + доля убитых зомби этой волны (7.64 — умер на волне 7, убив 64% её зомби).
# Шкала: линейная сила = sqrt(H * D) по bench/balance/strength.gd; P — игрок на старте волны после покупок, E — вся волна.
const GAME := preload("res://scripts/game.gd")   # формула Сияния и загрузчики run.json, radiance.json
const MODS := preload("res://scripts/mods.gd")
const BOTS := ["B2", "B5"]
const DESC := {"B2": "по кругу пехота, оружие", "B5": "по кругу пехота, лучники"}
const SEEDS := [1, 2, 3, 4, 5]
const WAVES := [1, 4, 7]
const LAST := 10
const ALIVE := 41.0   # дожил до страховки 40 волн
var gifts := []   # из data/gifts.json, в порядке файла, без скрытых (hidden): все видимые — для наборов «все дары»
var singles := [] # дары для наборов «по одному» (аргумент или все видимые)
var game: Node    # узел Game вне дерева: только run_reward по data/radiance.json и дарам набора (radiance_pct)
var ver := "v4"
var DIR := ""
var waves_per_run := 0

# Забег: waves [{p, e}], defeat — волна смерти (ALIVE — дожил, -1 — нет данных), death — непрерывная волна смерти, gold — золото в начале последней волны после покупок.
func load_run(cfg: String, bot: String, seed: int) -> Dictionary:
	var path := "%s%s_%s_s%d.txt" % [DIR, cfg, bot, seed]
	var r := {"waves": [], "defeat": -1, "death": -1.0, "gold": 0}
	if not FileAccess.file_exists(path):
		return r
	var frac := 0.0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE":
			r.waves.append({"p": sqrt(float(f[12]) * float(f[13])), "e": sqrt(float(f[14]) * float(f[15]))})
			r.gold = int(f[17])
			frac = float(f[18]) / float(f[9]) if int(f[9]) > 0 else 0.0
		elif f[0] == "RUN":
			r.defeat = int(f[3]) if int(f[3]) > 0 else (int(ALIVE) if int(f[4]) == 1 else -1)
			r.death = -1.0 if r.defeat < 0 else (ALIVE if r.defeat == int(ALIVE) else r.defeat + minf(frac, 0.99))
	return r

func runs_of(cfg: String, bot: String) -> Array:
	var out := []
	for seed in SEEDS:
		out.append(load_run(cfg, bot, seed))
	return out

func fmt_death(v: float) -> String:
	return "—" if v < 0.0 else ("≥40" if v >= ALIVE else "%.2f" % v)

func median(rs: Array) -> float:
	var d := rs.map(func(r): return r.death)
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

# Среднее золото в начале последней волны после покупок.
func mean_gold(rs: Array) -> float:
	var s := 0.0
	for r in rs:
		s += r.gold
	return s / rs.size()

# Дары набора: id -> уровень (как --gifts в ablation_run.sh).
func gifts_of(cfg: String) -> Dictionary:
	var out := {}
	if cfg == "none":
		return out
	var lvl := int(cfg.right(1))
	if cfg.begins_with("all_"):
		for g in gifts:
			out[g.id] = lvl
	else:
		out[cfg.left(cfg.length() - 2)] = lvl
	return out

# Средняя награда Сияния: забег игры кончается победой на волне waves_per_run, поэтому смерть бота позже неё считается победой.
# Дары набора действуют и здесь (Резерв Сияния — через Game.run_reward).
func mean_radiance(cfg: String, rs: Array) -> float:
	game.active_gifts = gifts_of(cfg)
	var s := 0.0
	for r in rs:
		s += game.run_reward("win", waves_per_run) if r.defeat > waves_per_run else game.run_reward("loss", r.defeat)
	return s / rs.size()

func label(cfg: String) -> String:
	if cfg == "none":
		return "без даров"
	if cfg.begins_with("all_"):
		return "все дары (%d), уровень %s" % [gifts.size(), cfg.right(1)]
	for g in gifts:
		if cfg == "%s_%s" % [g.id, cfg.right(1)]:
			var v: float = g.levels[int(cfg.right(1)) - 1]
			var num := ("%+d" % int(v)) if v == floorf(v) else ("+" if v > 0 else "") + String.num(v)
			return "%s %s (%s %s%s)" % [g.id, cfg.right(1), g.stat, num, "%" if g.op == "add_pct" else (" с" if g.stat == "signal_window" else "")]
	return cfg

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега
	gifts = JSON.parse_string(FileAccess.get_file_as_string("res://data/gifts.json")).filter(func(g): return not g.get("hidden", false))
	game = GAME.new()
	game.radiance_cfg = GAME.load_radiance_cfg("res://data/radiance.json")
	game.gift_defs = MODS.load_gifts("res://data/gifts.json")
	waves_per_run = GAME.load_run_cfg("res://data/run.json").waves_per_run
	var rc: Dictionary = game.radiance_cfg
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 0
	ver = args[1] if args.size() > 1 else "v4"
	DIR = "res://bench/balance/ablation_%s_runs/" % ver
	singles = gifts
	if args.size() > 2:
		var want := args[2].split(",", false)
		singles = gifts.filter(func(g): return g.id in want)
	var cfgs := ["none"]
	for lvl in [1, 2, 3]:
		for g in singles:
			cfgs.append("%s_%d" % [g.id, lvl])
	for lvl in [1, 2, 3]:
		cfgs.append("all_%d" % lvl)
	var total := cfgs.size() * BOTS.size() * SEEDS.size()
	var L: Array[String] = []
	var missing := 0
	for cfg in cfgs:
		for bot in BOTS:
			for r in runs_of(cfg, bot):
				if r.defeat < 0:
					missing += 1
	var ids := PackedStringArray(singles.map(func(g): return g.id))
	L.append("gift_ablation_%s: абляция даров с непрерывной волной смерти, только измерения. Дары по одному: %s; «все дары» — все %d видимых в gifts.json (скрытые не входят)." % [
		ver, ", ".join(ids), gifts.size()])
	L.append("Рабочие scripts/main.gd и data/*.json, осада I (слой 1), волны без предела до поражения.")
	L.append("Пересчёт (из корня проекта):  sh bench/balance/ablation_run.sh \"<путь к godot.exe>\"")
	L.append("Время этого прогона: %s (%d забегов, до 10 процессов сразу, %d потоков процессора)." % ["%d мин %02d с" % [secs / 60, secs % 60] if secs > 0 else "не измерялось (сборщик запущен отдельно)",
		total, OS.get_processor_count()])
	L.append("Боты B2 (%s) и B5 (%s), seed 1-5; отряды стоят на старте, приказ «атака», всё золото тратится в передышке." % [DESC.B2, DESC.B5])
	L.append("Смерть — непрерывная волна смерти: номер волны смерти + доля убитых зомби этой волны (7.64 — умер на волне 7, убив 64% её зомби; доля не больше 0.99). Медиана по seed, в скобках — разница с «без даров».")
	L.append("Шкала: линейная сила = sqrt(H * D) (bench/balance/strength.gd); P — игрок на старте волны после покупок, E — вся волна.")
	L.append("P/E и b — среднее геометрическое по seed, дошедшим до волны; b — exp(наклон ln P по w) на волнах 1-%d или до смерти." % LAST)
	L.append("Золото — среднее по seed золото в начале последней волны (волны смерти) после покупок: остаток, на который бот ничего не смог купить.")
	L.append("Сияние — средняя по seed награда за забег по data/radiance.json: %d + %d * номер за каждую пройденную волну, +%d за победу. В игре забег кончается победой на волне %d," % [
		rc.wave_base, rc.wave_step, rc.win_bonus, waves_per_run])
	L.append("  поэтому смерть бота позже волны %d считается победой (%d Сияния без даров); дары набора (Резерв Сияния) действуют через Game.run_reward." % [waves_per_run, game.run_reward("win", waves_per_run)])
	if missing > 0:
		L.append("ВНИМАНИЕ: не завершено забегов: %d из %d." % [missing, total])
	L.append("")
	for bot in BOTS:
		L.append("%s. Бот %s (%s)." % ["1-3" if bot == BOTS[0] else "1-3 (продолжение)", bot, DESC[bot]])
		L.append("  %-42s | смерть s1/s2/s3/s4/s5            | медиана (разница) | P/E в.1 | P/E в.4 | P/E в.7 | b игрока | золото | Сияние" % "набор")
		var base_med := median(runs_of("none", bot))
		for cfg in cfgs:
			var rs := runs_of(cfg, bot)
			var pe := PackedStringArray()
			for w in WAVES:
				var p := gmean(rs, "p", w)
				pe.append("%7s" % ("—" if p <= 0.0 else "%.2f" % (p / gmean(rs, "e", w))))
			var med := median(rs)
			L.append("  %-42s | %-32s | %5s (%s) | %s | %s | %s | %8.3f | %6.0f | %6.1f" % [label(cfg), "/".join(rs.map(func(r): return fmt_death(r.death))), fmt_death(med),
				"%+6.2f" % (med - base_med) if cfg != "none" else "  0.00", pe[0], pe[1], pe[2], fit(rs), mean_gold(rs), mean_radiance(cfg, rs)])
			if cfg == "none" or cfg.begins_with(singles[-1].id + "_"):
				L.append("")
		L.append("")
	L.append("4. Влияние дара: сдвиг медианы непрерывной волны смерти относительно «без даров», среднее двух ботов. Сортировка по убыванию (сверху — сильнейшие).")
	L.append("  %-42s |     B2 |     B5 | среднее | сдвиг на 100 Сияния цены" % "набор")
	var rows := []
	for cfg in cfgs:
		if cfg == "none":
			continue
		var shifts := []
		for bot in BOTS:
			shifts.append(median(runs_of(cfg, bot)) - median(runs_of("none", bot)))
		var price := 0
		if not cfg.begins_with("all_"):
			var lvl := int(cfg.right(1))
			var id: String = cfg.left(cfg.length() - 2)
			for g in gifts:
				if g.id == id:
					price = int(g.prices[lvl - 1]) if g.has("prices") else rc.gift_prices[lvl - 1]
		rows.append({"cfg": cfg, "b2": shifts[0], "b5": shifts[1], "avg": (shifts[0] + shifts[1]) / 2.0, "price": price})
	rows.sort_custom(func(a, b): return a.avg > b.avg)
	for r in rows:
		L.append("  %-42s | %+6.2f | %+6.2f | %+7.2f | %s" % [label(r.cfg), r.b2, r.b5, r.avg, "—" if r.price == 0 else "%+.3f (цена %d)" % [r.avg * 100.0 / r.price, r.price]])
	L.append("")
	L.append("5. Вклад дара в линейную силу армии на волне 4: P(4) с даром / P(4) без дара, тот же бот, среднее геометрическое по seed. Сортировка по среднему двух ботов.")
	L.append("  %-42s |    B2 |    B5 | среднее" % "набор")
	var prow := []
	for cfg in cfgs:
		if cfg == "none":
			continue
		var vals := []
		for bot in BOTS:
			vals.append(gmean(runs_of(cfg, bot), "p", 4) / gmean(runs_of("none", bot), "p", 4))
		prow.append({"cfg": cfg, "b2": vals[0], "b5": vals[1], "avg": sqrt(vals[0] * vals[1])})
	prow.sort_custom(func(a, b): return a.avg > b.avg)
	for r in prow:
		L.append("  %-42s | %5.3f | %5.3f | %7.3f" % [label(r.cfg), r.b2, r.b5, r.avg])
	L.append("  В P входят только HP и урон армии: золото (spoils, mine) — только через купленное к волне 4.")
	L.append("")
	L.append("6. Сияние за забег, среднее по seed и сколько таких забегов нужно на первый уровень дара (цена %d): контроль и набор «все дары, уровень 1»." % rc.gift_prices[0])
	for cfg in ["none", "all_1"]:
		for bot in BOTS:
			var rad := mean_radiance(cfg, runs_of(cfg, bot))
			L.append("  %-28s | %s | Сияние %6.1f | забегов до дара %d | золото в начале последней волны %5.0f" % [label(cfg), bot, rad, ceili(rc.gift_prices[0] / rad), mean_gold(runs_of(cfg, bot))])
	game.free()
	var f := FileAccess.open("res://bench/gift_ablation_%s.txt" % ver, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
