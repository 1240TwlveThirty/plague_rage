extends SceneTree
# Калибровка осады I, этап 2: сборщик свипа множителя численности волн -> bench/calibration_v2.txt.
# Вход: bench/balance/calib2_runs/m<множитель>_<бот>_s<seed>.txt (bench/balance/calib2_sweep.sh), точка 1.0 — bench/balance/calib_runs (этап 1),
# контроль на рабочем data/waves.json — bench/balance/calib2_final/m1_*. Раздел проверок берётся как есть из bench/balance/calib2_checks.txt.
# Шкала: линейная сила = sqrt(H * D) по bench/balance/strength.gd.
const OUT := "res://bench/calibration_v2.txt"
const BOTS := ["B1", "B2", "B3", "B4", "B5", "B6"]
const SEEDS := [1, 2, 3, 4, 5]
const ASKED := ["1.4", "1.6", "1.8", "2.0", "2.2"]            # свип из задания
const EXTRA := ["2.6", "2.7", "2.8", "2.9", "3.0", "3.5", "4.0"]   # продолжение: в заданном диапазоне цель не достигается
const CHOSEN := "2.7"
const BASE := {"count_base": 50.0, "count_step": 45.0, "knight_per_wave": 0.8}   # значения до этапа 2
const BEST := "B5"
const WEAK := "B3"
const LAST := 10

func load_run(path: String) -> Dictionary:
	var r := {"waves": [], "defeat": -1}
	if not FileAccess.file_exists(path):
		return r
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE":
			r.waves.append({"w": int(f[3]), "gold": int(f[7]), "zombies": int(f[9]), "p": sqrt(float(f[12]) * float(f[13])), "e": sqrt(float(f[14]) * float(f[15]))})
		elif f[0] == "RUN":
			r.defeat = int(f[3]) if int(f[3]) > 0 else (41 if int(f[4]) == 1 else -1)
	return r

func load_point(mult: String) -> Dictionary:
	var runs := {}
	for bot in BOTS:
		runs[bot] = []
		for seed in SEEDS:
			var path := "res://bench/balance/calib2_runs/m%s_%s_s%d.txt" % [mult, bot, seed]
			if mult == "1.0":
				path = "res://bench/balance/calib_runs/%s_s%d.txt" % [bot, seed]
			elif mult == "final":
				path = "res://bench/balance/calib2_final/m1_%s_s%d.txt" % [bot, seed]
			runs[bot].append(load_run(path))
	return runs

func deaths(rs: Array) -> Array:
	var d := []
	for r in rs:
		d.append(r.defeat)
	return d

func median(d: Array) -> int:
	var s := d.duplicate()
	s.sort()
	return s[s.size() / 2]

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

# Среднее геометрическое значения key на волне w по seed, дошедшим до неё; 0 — никто не дошёл.
func gmean(rs: Array, key: String, w: int) -> float:
	var s := 0.0
	var n := 0
	for r in rs:
		if r.waves.size() >= w:
			s += log(r.waves[w - 1][key])
			n += 1
	return exp(s / n) if n > 0 else 0.0

func fit(rs: Array, key: String) -> float:
	var xs := []
	var ys := []
	for w in range(1, LAST + 1):
		var v := gmean(rs, key, w)
		if v > 0.0:
			xs.append(float(w))
			ys.append(log(v))
	return exp(slope(xs, ys))

# Цель задания: лучший бот — медиана 7 и все seed на волнах 6-8; медианы остальных не позже; слабый бот не раньше волны 4.
func verdict(runs: Dictionary) -> Array:
	var best: Array = deaths(runs[BEST])
	var best_ok: bool = median(best) == 7 and best.min() >= 6 and best.max() <= 8
	var others_ok := true
	for bot in BOTS:
		if bot != BEST and median(deaths(runs[bot])) > median(best):
			others_ok = false
	var weak_ok: bool = deaths(runs[WEAK]).min() >= 4
	return [best_ok and others_ok and weak_ok, best_ok, others_ok, weak_ok]

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега
	var L: Array[String] = []
	var points := {}
	for mult in ["1.0"] + ASKED + EXTRA + ["final"]:
		points[mult] = load_point(mult)
	L.append("calibration_v2: калибровка осады I, этап 2 — подбор силы врага. Игрок (unit_types.json, shop.json, castle.json) и scripts/main.gd не менялись.")
	L.append("")
	L.append("Ручка: общий множитель численности волн k. В data/waves.json умножены count_base, count_step и knight_per_wave —")
	L.append("  число зомби каждого типа в волне растёт в k раз, доли типов и рост hp/урона +4% за волну те же.")
	L.append("  Выбрано k = %s: count_base %s -> %s, count_step %s -> %s, knight_per_wave %s -> %s." % [CHOSEN, BASE.count_base, BASE.count_base * float(CHOSEN),
		BASE.count_step, BASE.count_step * float(CHOSEN), BASE.knight_per_wave, BASE.knight_per_wave * float(CHOSEN)])
	L.append("Шкала: линейная сила = sqrt(H * D) (bench/balance/strength.gd); P — игрок на старте волны после покупок, E — вся волна.")
	L.append("Боты B1-B6, seed 1-5, слой 1, волны без предела до поражения; отряды стоят на старте, приказ «атака», всё золото тратится в передышке.")
	L.append("Цель: %s — медиана волны смерти 7, все seed на волнах 6-8; медианы остальных ботов не позже; %s не раньше волны 4." % [BEST, WEAK])
	L.append("")
	L.append("1. Волна смерти по ботам и seed (s1/s2/s3/s4/s5, в скобках медиана). k 1.0 — этап 1; 1.4-2.2 — свип из задания; дальше — продолжение свипа.")
	L.append("     k | " + " | ".join(BOTS.map(func(b): return "%-19s" % b)) + " | цель")
	var first_ok := ""
	for mult in ["1.0"] + ASKED + EXTRA:
		var runs: Dictionary = points[mult]
		var cells := PackedStringArray()
		for bot in BOTS:
			var d: Array = deaths(runs[bot])
			cells.append("%-19s" % ("/".join(d.map(fmt_wave)) + " (%s)" % fmt_wave(median(d))))
		var v := verdict(runs)
		var why := PackedStringArray()
		if not v[1]:
			why.append("%s: медиана %s" % [BEST, fmt_wave(median(deaths(runs[BEST])))])
		if not v[2]:
			why.append("другой бот живёт дольше")
		if not v[3]:
			why.append("%s раньше волны 4" % WEAK)
		if v[0] and first_ok == "":
			first_ok = mult
		L.append("  %4s | %s | %s" % [mult, " | ".join(cells), "да" if v[0] else "нет (" + ", ".join(why) + ")"])
	L.append("  В диапазоне из задания (1.4-2.2) цель не достигается: %s умирает на волнах 8-11. Минимальный k из проверенных, при котором цель выполнена: %s." % [BEST, first_ok])
	L.append("  Отклик на k слабый (1.8-2.2 — почти плато): золото за волну растёт вместе с k (gold_per_kill за каждого зомби), армия ботов растёт следом.")
	L.append("  Это вероятная причина, отдельно не проверялась.")
	L.append("")
	L.append("2. Отношение линейных сил P/E по волнам 1-%d (среднее геометрическое по seed, дошедшим до волны)." % LAST)
	for mult in ASKED + [CHOSEN]:
		var runs: Dictionary = points[mult]
		L.append("  k = %s%s" % [mult, " (выбран)" if mult == CHOSEN else ""])
		L.append("  волна | зомби |    E |" + " |".join(BOTS.map(func(b): return "%6s" % b)))
		for w in range(1, LAST + 1):
			var e := 0.0
			var z := 0
			var cells := PackedStringArray()
			for bot in BOTS:
				var p := gmean(runs[bot], "p", w)
				if p > 0.0:
					e = gmean(runs[bot], "e", w)
					for r in runs[bot]:
						if r.waves.size() >= w:
							z = r.waves[w - 1].zombies
					cells.append("%6.2f" % (p / e))
				else:
					cells.append("%6s" % "—")
			if z > 0:
				L.append("  %5d | %5d | %4.0f |%s" % [w, z, e, " |".join(cells)])
		L.append("")
	L.append("3. Эффективный b в линейной шкале: exp(наклон ln силы по w), волны 1-%d или до смерти, среднее ln по seed." % LAST)
	L.append("     k | b врага (волны 1-%d) | b игрока: " % LAST + " | ".join(BOTS.map(func(b): return "%5s" % b)))
	for mult in ["1.0"] + ASKED + EXTRA:
		var runs: Dictionary = points[mult]
		var longest: Array = runs[BEST]
		for bot in BOTS:
			if median(deaths(runs[bot])) > median(deaths(longest)):
				longest = runs[bot]
		var cells := PackedStringArray()
		for bot in BOTS:
			cells.append("%5.3f" % fit(runs[bot], "p"))
		L.append("  %4s | %19.3f |           %s" % [mult, fit(longest, "e"), " | ".join(cells)])
	L.append("  b врага считается по боту, дожившему дольше всех (волн меньше %d — подгонка по тем, что были)." % LAST)
	L.append("")
	var same := true
	for bot in BOTS:
		for q in SEEDS.size():
			var a: Dictionary = points["final"][bot][q]
			var b: Dictionary = points[CHOSEN][bot][q]
			same = same and a.defeat == b.defeat and a.defeat > 0 and a.waves.size() == b.waves.size()
	var early := 99
	for bot in BOTS:
		if bot != WEAK:
			early = mini(early, deaths(points["final"][bot]).min())
	L.append("4. Проверки с k = %s." % CHOSEN)
	L.append("  30 забегов на рабочем data/waves.json дают те же волны смерти, что точка %s свипа: %s." % [CHOSEN, "да" if same else "НЕТ"])
	L.append("  Волны 1-3 никем из ботов, кроме %s, не проигрываются: %s (самая ранняя смерть — волна %d)." % [WEAK, "да" if early > 3 else "НЕТ", early])
	if FileAccess.file_exists("res://bench/balance/calib2_checks.txt"):
		for line in FileAccess.get_file_as_string("res://bench/balance/calib2_checks.txt").split("\n"):
			if line.strip_edges() != "":
				L.append("  " + line.strip_edges())
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
