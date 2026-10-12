extends SceneTree
# Калибровка осады I, этап 1: сборщик. bench/balance/calib_runs/*.txt (calib_worker.gd) -> bench/calibration_v1.txt.
# Таблица силы волн считается здесь же: рабочий scripts/main.gd строит план каждой волны (_start_wave без боя).
const STRENGTH := preload("res://bench/balance/strength.gd")
const MAIN := "res://scripts/main.gd"
const OUT := "res://bench/calibration_v1.txt"
const BOTS := ["B1", "B2", "B3", "B4", "B5", "B6"]
const SEEDS := [1, 2, 3, 4, 5]
const DESC := {"B1": "по кругу пехота, оружие, лучники, ворота", "B2": "по кругу пехота, оружие", "B3": "только ворота",
	"B4": "оружие, пока хватает золота, остаток в пехоту", "B5": "по кругу пехота, лучники (без оружия)", "B6": "по кругу оружие, пехота, оружие, лучники"}
const TARGET := 1.3   # рост силы врага за волну по ТЗ

func load_run(bot: String, seed: int) -> Dictionary:
	var path := "res://bench/balance/calib_runs/%s_s%d.txt" % [bot, seed]
	var r := {"waves": [], "defeat": -1, "done": false}
	if not FileAccess.file_exists(path):
		return r
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE":
			r.waves.append({"w": int(f[3]), "inf": int(f[4]), "arch": int(f[5]), "weapons": int(f[6]), "gold": int(f[7]), "lost": int(f[8]), "zombies": int(f[9]),
				"gate0": int(f[10]), "gate1": int(f[11]), "p": float(f[12]) * float(f[13]), "e": float(f[14]) * float(f[15]), "secs": float(f[16])})
		elif f[0] == "RUN":
			r.done = true
			r.defeat = int(f[3]) if int(f[3]) > 0 else (41 if int(f[4]) == 1 else -1)
	return r

func fmt_wave(v: int) -> String:
	return "—" if v < 0 else ("≥40" if v >= 41 else str(v))

# Наклон прямой наименьших квадратов y по x.
func slope(xs: Array, ys: Array) -> float:
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
	return num / den if den > 0.0 else 0.0

# Сила волн 1..last при данном seed: записи {w, n, runners, knights, hp_mult, dmg_mult, hp, dps, power}.
func wave_table(seed: int, last: int) -> Array:
	var m: Node2D = load(MAIN).new()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = seed
	m.debug_layer = 1
	m._setup_data()
	var out := []
	for w in range(1, last + 1):
		m.wave_state = m.WS_RESPITE
		m.wave_number = w - 1
		m.wave_plan_for = -1   # план строится заново для волны w
		m._start_wave()
		var e: Dictionary = STRENGTH.enemy(m)
		var runners := 0
		var knights := 0
		for r in m.wave_plan:
			if r.type == m.runner_type:
				runners += r.count
			elif r.type == m.knight_type:
				knights += r.count
		out.append({"w": w, "n": e.n, "runners": runners, "knights": knights, "hp_mult": m.wave_hp_mult, "dmg_mult": m.team_dmg_mult[1], "hp": e.hp, "dps": e.dps, "power": e.power})
	m.free()
	return out

# b по ln(значение) на волнах 1..last: среднее ln по тем забегам, что дошли до волны.
func fit_runs(rs: Array, key: String, last: int) -> Array:
	var xs := []
	var ys := []
	for w in range(1, last + 1):
		var s := 0.0
		var n := 0
		for r in rs:
			if r.waves.size() >= w and r.waves[w - 1][key] > 0.0:
				s += log(r.waves[w - 1][key])
				n += 1
		if n > 0:
			xs.append(float(w))
			ys.append(s / n)
	return [exp(slope(xs, ys)), xs.size()]

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var cfg: Dictionary = load("res://scripts/game.gd").load_run_cfg("res://data/run.json")
	var last: int = cfg.waves_per_run
	var L: Array[String] = []
	L.append("calibration_v1: калибровка осады I, этап 1 — только измерения. Рабочие scripts/main.gd и data/*.json (не менялись), слой 1.")
	L.append("")
	L.append("Метрика (bench/balance/strength.gd, один код для игрока и врага):")
	L.append("  Сила = H * D, H = сумма hp по юнитам, D = сумма dps по юнитам; dps ближнего боя = damage * множитель команды / cooldown, стрелка = arrow_dmg / volley_period.")
	L.append("  Закон Ланчестера: H и D пропорциональны числу N, сила растёт как N^2. Линейный масштаб (как «число юнитов») — корень из силы.")
	L.append("  Не входят: щит пехоты, дальность и промахи стрел, одиночный огонь и ближний бой лучников, скорость, ворота, подход орды всплесками.")
	L.append("")

	# --- п.2: сила волн ---
	var tab := wave_table(SEEDS[0], last)
	var same := true
	for seed in SEEDS:
		var other := wave_table(seed, last)
		for k in last:
			# состав по типам один и тот же, порядок сложения по сторонам разный — сравнение с допуском
			same = same and absf(other[k].power / tab[k].power - 1.0) < 1e-6 and other[k].n == tab[k].n
	L.append("1. Сила волн осады I, волны 1-%d. E одинакова при seed %d-%d: %s (seed меняет только стороны появления)." % [last, SEEDS[0], SEEDS[-1], "да" if same else "НЕТ"])
	L.append("  волна | зомби | бегуны | рыцари | hp_mult | dmg_mult |      H |      D |        E | E(w)/E(1) | %.1f^(w-1) | факт / цель" % TARGET)
	var xs := []
	var ys := []
	for v in tab:
		var rel: float = v.power / tab[0].power
		var want := pow(TARGET, v.w - 1)
		xs.append(float(v.w))
		ys.append(log(v.power))
		L.append("  %5d | %5d | %6d | %6d | %7.2f | %8.2f | %6.1f | %6.1f | %8.0f | %9.2f | %9.2f | %8.2f" % [v.w, v.n, v.runners, v.knights, v.hp_mult, v.dmg_mult, v.hp, v.dps, v.power,
			rel, want, rel / want])
	var b_enemy := exp(slope(xs, ys))
	var b_ends := pow(tab[last - 1].power / tab[0].power, 1.0 / (last - 1))
	L.append("  Эффективный b врага: %.3f (подгонка ln E по w, волны 1-%d); по концам (E(%d)/E(1))^(1/%d) = %.3f. Цель ТЗ: %.2f." % [b_enemy, last, last, last - 1, b_ends, TARGET])
	L.append("  Рост неравномерный: шаг E(2)/E(1) = %.2f, шаг E(%d)/E(%d) = %.2f — число зомби растёт линейно (+count_step за волну), а не геометрически." % [
		tab[1].power / tab[0].power, last, last - 1, tab[last - 1].power / tab[last - 2].power])
	L.append("  В линейном масштабе (корень из силы): b = %.3f по подгонке, %.3f по концам." % [sqrt(b_enemy), sqrt(b_ends)])
	L.append("")

	# --- п.3: боты ---
	var runs := {}
	var missing := 0
	var e_match := true
	var longest := 0
	for bot in BOTS:
		runs[bot] = []
		for seed in SEEDS:
			var r := load_run(bot, seed)
			runs[bot].append(r)
			if not r.done:
				missing += 1
			longest = maxi(longest, r.waves.size())
			for v in r.waves:
				if v.w <= last and absf(v.e / tab[v.w - 1].power - 1.0) > 1e-4:
					e_match = false
	var total := BOTS.size() * SEEDS.size()
	L.append("2. Боты B1-B6, seed %d-%d, волны без предела до поражения (страховка 40). Отряды стоят на старте, приказ «атака», кликов нет, всё золото тратится в передышке." % [SEEDS[0], SEEDS[-1]])
	if missing > 0:
		L.append("  ВНИМАНИЕ: результаты частичные, не завершено прогонов: %d из %d." % [missing, total])
	L.append("  Сила врага в прогонах ботов совпадает с таблицей п.1: %s." % ("да" if e_match else "НЕТ"))
	L.append("")
	L.append("  Волна смерти:")
	L.append("  бот | покупки | s1/s2/s3/s4/s5 | медиана | разброс")
	var meds := {}
	for bot in BOTS:
		var d := []
		for r in runs[bot]:
			d.append(r.defeat)
		var sorted := d.duplicate()
		sorted.sort()
		meds[bot] = sorted[sorted.size() / 2]
		var parts := PackedStringArray()
		for v in d:
			parts.append(fmt_wave(v))
		L.append("  %s | %s | %s | %s | %s–%s" % [bot, DESC[bot], "/".join(parts), fmt_wave(meds[bot]), fmt_wave(sorted[0]), fmt_wave(sorted[-1])])
	L.append("")
	L.append("  Сила игрока P(w) на старте волны после покупок, тыс. (среднее геометрическое по seed; в скобках — сколько seed дошло, если не все). E — сила волны, тыс.")
	L.append("  волна |       E |" + " |".join(BOTS.map(func(b): return "%11s" % b)))
	var ratio_rows: Array[String] = []
	for w in range(1, longest + 1):
		var e := 0.0
		var cells := PackedStringArray()
		var rcells := PackedStringArray()
		for bot in BOTS:
			var s := 0.0
			var n := 0
			for r in runs[bot]:
				if r.waves.size() >= w:
					s += log(r.waves[w - 1].p)
					e = r.waves[w - 1].e
					n += 1
			if n == 0:
				cells.append("%11s" % "—")
				rcells.append("%7s" % "—")
			else:
				var p := exp(s / n)
				cells.append("%11s" % ("%.0f" % (p / 1000.0) + ("" if n == SEEDS.size() else " (%d)" % n)))
				rcells.append("%7.2f" % (p / e))
		L.append("  %5d | %7.0f |%s" % [w, e / 1000.0, " |".join(cells)])
		ratio_rows.append("  %5d |%s" % [w, " |".join(rcells)])
	L.append("")
	L.append("  Отношение P(w)/E(w) (те же средние):")
	L.append("  волна |" + " |".join(BOTS.map(func(b): return "%7s" % b)))
	L.append_array(ratio_rows)
	L.append("")
	L.append("  Эффективный b игрока: exp(наклон прямой наименьших квадратов ln P по w), среднее ln P по seed, дошедшим до волны.")
	L.append("  бот | b, волны 1-%d | волн в подгонке | b по seed, мин–макс | b, весь забег | b врага на тех же волнах | медиана смерти" % last)
	for bot in BOTS:
		var rs: Array = runs[bot]
		var fit := fit_runs(rs, "p", last)
		var fit_e := fit_runs(rs, "e", last)
		var all_len := 0
		var lo := INF
		var hi := -INF
		for r in rs:
			all_len = maxi(all_len, r.waves.size())
			if r.waves.size() >= 2:
				var one: float = fit_runs([r], "p", last)[0]
				lo = minf(lo, one)
				hi = maxf(hi, one)
		var fit_all := fit_runs(rs, "p", all_len)
		L.append("  %s | %.3f | %d | %.3f–%.3f | %.3f (волны 1-%d) | %.3f | %s" % [bot, fit[0], fit[1], lo, hi, fit_all[0], fit_all[1], fit_e[0], fmt_wave(meds[bot])])
	L.append("")
	L.append("  Модель ТЗ: b игроков 1.05…1.29, враг 1.3; цель — лучший бот без меты умирает на волне 6-8, идеальная игра (b≈1.29) едва проходит %d волн." % last)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
