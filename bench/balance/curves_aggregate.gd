extends SceneTree
# Сборщик кривых роста: bench/balance/curves_runs/*.txt -> bench/balance_curves.txt.
const BOTS := ["B1", "B2", "B3", "B4", "B5", "B6"]
const DESC := {"B1": "по кругу пехота, оружие, лучники, ворота", "B2": "по кругу пехота, оружие", "B3": "только ворота",
	"B4": "оружие, пока хватает золота, остаток в пехоту", "B5": "по кругу пехота, лучники (без оружия)", "B6": "по кругу оружие, пехота, оружие, лучники"}
const S := 4.0

func load_run(bot: String, seed: int) -> Dictionary:
	var path := "res://bench/balance/curves_runs/%s_s%d.txt" % [bot, seed]
	var r := {"waves": [], "defeat": -1, "done": false}
	if not FileAccess.file_exists(path):
		return r
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE":
			r.waves.append({"w": int(f[3]), "inf": int(f[4]), "arch": int(f[5]), "weapons": int(f[6]), "gold": int(f[7]), "lost": int(f[8]), "zombies": int(f[9]),
				"hp_mult": float(f[10]), "dmg_mult": float(f[11]), "gate0": int(f[12]), "gate1": int(f[13]), "p": float(f[14]), "e": float(f[15]), "secs": float(f[18])})
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

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var L: Array[String] = []
	var runs := {}
	var missing := 0
	for bot in BOTS:
		runs[bot] = []
		for seed in [1, 2, 3]:
			var r := load_run(bot, seed)
			runs[bot].append(r)
			if not r.done:
				missing += 1
	L.append("balance_curves: кривые роста ботов, слой 1 (DEBUG_LAYER = 1), рабочие JSON, волны до поражения (лимит 40), seed 1-3.")
	L.append("Копия main: bench/balance/main_bal_curves.gd (коммит a0af58a). Отряды стоят на старте, приказ «атака», кликов нет; в каждой передышке бот тратит всё золото, пределы магазина учитываются.")
	if missing > 0:
		L.append("ВНИМАНИЕ: результаты частичные, не завершено прогонов: %d из 18." % missing)
	L.append("")
	L.append("Формулы (всё на старте волны, после покупок):")
	L.append("  P(w) = пехота * hp_пехоты * урон_пехоты + лучники * hp_лучника * урон_стрелы; урон уже с покупками оружия (type_damage[infantry], type_arrow_dmg[archer]).")
	L.append("  E(w) = сумма по типам зомби: число * (hp типа * hp_mult) * (урон типа * dmg_mult); hp_mult = 1 + hp_growth * (w - 1), dmg_mult = 1 + dmg_growth * (w - 1).")
	L.append("  Темп атак (перезарядка, период залпа), щиты и дальность в индексы не входят. Потери = погибшие за волну / армия на старте волны.")
	L.append("")
	for bot in BOTS:
		var r: Dictionary = runs[bot][0]
		L.append("%s (%s), seed 1, поражение на волне %s:" % [bot, DESC[bot], fmt_wave(r.defeat)])
		L.append("  волна | пехота | лучники | оружие | золото | потери | зомби | hp_mult | dmg_mult | ворота старт/конец |        P |        E |  P/E")
		for v in r.waves:
			L.append("  %5d | %6d | %7d | %6d | %6d | %5.1f%% | %5d | %7.2f | %8.2f | %8d/%-8d | %8.0f | %8.0f | %4.2f" % [v.w, v.inf, v.arch, v.weapons, v.gold,
				100.0 * v.lost / maxi(v.inf + v.arch, 1), v.zombies, v.hp_mult, v.dmg_mult, v.gate0, v.gate1, v.p, v.e, v.p / maxf(v.e, 0.001)])
		L.append("")
	L.append("Итоги по ботам и seed:")
	L.append("  бот | поражение s1/s2/s3 | медиана | разброс | потери впервые > 30%% армии, волна s1/s2/s3 | P/E на волне 1 / 5 / 10 (seed 1)".replace("%%", "%"))
	var best := ""
	var best_med := -1
	var meds := {}
	for bot in BOTS:
		var d := []
		var first30 := []
		for r in runs[bot]:
			d.append(r.defeat)
			var f30 := -1
			for v in r.waves:
				if f30 < 0 and v.lost > 0.3 * (v.inf + v.arch):
					f30 = v.w
			first30.append(f30)
		var sorted := d.duplicate()
		sorted.sort()
		var med: int = sorted[1]
		meds[bot] = med
		if med > best_med:
			best_med = med
			best = bot
		var pe := []
		for w in [1, 5, 10]:
			var s := "—"
			for v in runs[bot][0].waves:
				if v.w == w:
					s = "%.2f" % (v.p / maxf(v.e, 0.001))
			pe.append(s)
		L.append("  %s | %s/%s/%s | %s | %s–%s | %s/%s/%s | %s / %s / %s" % [bot, fmt_wave(d[0]), fmt_wave(d[1]), fmt_wave(d[2]), fmt_wave(med), fmt_wave(sorted[0]), fmt_wave(sorted[2]),
			fmt_wave(first30[0]), fmt_wave(first30[1]), fmt_wave(first30[2]), pe[0], pe[1], pe[2]])
	L.append("")
	L.append("Подгонка: прямая наименьших квадратов для ln P(w) и ln E(w) по волнам 1-10 (или до поражения, если раньше), среднее ln по seed.")
	L.append("  L0_emp = exp(наклон E), b_emp = exp(наклон P); предсказанная волна поражения = ln(S) / ln(L0/b) при S = %.0f (S — гипотетическое значение, не вывод)." % S)
	L.append("  бот | волн в подгонке | L0_emp | b_emp | L0/b | предсказанная волна | фактическая медиана")
	var fits := {}
	for bot in BOTS:
		var last := 10
		for r in runs[bot]:
			if r.waves.size() > 0:
				last = mini(last, r.waves.size())
		var xs := []
		var lp := []
		var le := []
		for w in range(1, last + 1):
			var sp := 0.0
			var se := 0.0
			var n := 0
			for r in runs[bot]:
				if r.waves.size() >= w and r.waves[w - 1].p > 0.0:
					sp += log(r.waves[w - 1].p)
					se += log(r.waves[w - 1].e)
					n += 1
			if n > 0:
				xs.append(float(w))
				lp.append(sp / n)
				le.append(se / n)
		var b_emp := exp(slope(xs, lp))
		var l0 := exp(slope(xs, le))
		var ratio := l0 / b_emp
		fits[bot] = [l0, b_emp]
		L.append("  %s | %d | %.3f | %.3f | %.3f | %s | %s" % [bot, xs.size(), l0, b_emp, ratio, "%.1f" % (log(S) / log(ratio)) if ratio > 1.0001 else "— (P растёт не медленнее E)", fmt_wave(meds[bot])])
	L.append("")
	# лучший бот: с какой волны P растёт быстрее E (по seed 1, шаг от волны к волне, до конца забега)
	var bw: Array = runs[best][0].waves
	var from_wave := -1
	for k in range(bw.size() - 1, 0, -1):
		if bw[k].p / maxf(bw[k - 1].p, 0.001) > bw[k].e / maxf(bw[k - 1].e, 0.001):
			from_wave = bw[k].w
		else:
			break
	var faster: bool = fits[best][1] > fits[best][0]
	var growth := "P растёт медленнее E (b %.3f против L0 %.3f за волну на волнах 1-10)" % [fits[best][1], fits[best][0]]
	if faster:
		growth = "P растёт быстрее E (b %.3f против L0 %.3f за волну на волнах 1-10)" % [fits[best][1], fits[best][0]]
	if from_wave > 0 and not faster:
		growth += ", но с волны %d и до конца забега каждый шаг P больше шага E" % from_wave
	elif from_wave < 0:
		growth += "; к концу забега шаг E больше шага P"
	var verdict := "Вывод: сильнее всего стратегия %s (%s): медиана поражения на волне %s; %s." % [best, DESC[best], fmt_wave(best_med), growth]
	L.append(verdict)
	var f := FileAccess.open("res://bench/balance_curves.txt", FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		if l.begins_with("  B") or l.begins_with("Вывод") or l.begins_with("ВНИМАНИЕ"):
			print(l)
	quit()
