extends SceneTree
# Абляция задачи 9 (v11): сборщик bench/balance/ablation_v11_runs/<итерация>/ -> bench/gift_ablation_v11.txt, все итерации по порядку имён.
# Метрика — непрерывная волна смерти (волна + доля убитых волны смерти, не больше 0.99), медиана по seed 1-5; сдвиг — от набора «none»
# того же бота в той же итерации. Критерий: дар заметен — среднее сдвига по B2, B5, B7 на уровне 3 не меньше +0.2;
# не «слишком силён» — сдвиг каждого уровня у каждого бота меньше +1.5.
const SEEDS := [1, 2, 3, 4, 5]
const BOTS := ["B2", "B5", "B7"]
const ROOT := "res://bench/balance/ablation_v11_runs/"
var dir := ""

func death(name: String) -> float:
	var path := dir + name + ".txt"
	if not FileAccess.file_exists(path):
		return -1.0
	var frac := 0.0
	var out := -1.0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE" and f.size() >= 19:
			frac = float(f[18]) / float(f[9]) if int(f[9]) > 0 else 0.0
		elif f[0] == "RUN":
			var d := int(f[3])
			out = d + minf(frac, 0.99) if d > 0 else (41.0 if int(f[4]) == 1 else -1.0)
	return out

func median(cfg: String, bot: String) -> Array:
	var v := []
	for s in SEEDS:
		var d := death("%s_%s_s%d" % [cfg, bot, s])
		if d >= 0.0:
			v.append(d)
	var sorted := v.duplicate()
	sorted.sort()
	return [sorted[sorted.size() / 2] if not sorted.is_empty() else -1.0, v]

func shift(cfg: String, bot: String) -> float:
	var r: float = median(cfg, bot)[0]
	var b: float = median("none", bot)[0]
	return r - b if r >= 0.0 and b >= 0.0 else NAN

func fmt(x: float) -> String:
	return "—" if is_nan(x) else "%+.2f" % x

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var its := Array(DirAccess.get_directories_at(ROOT))
	its.sort()
	var L: Array[String] = ["gift_ablation_v11: дар spear_wall «Сомкнутые щиты» — блок +п. п. всем воинам со щитом (на деле пехоте), постоянно (задача 9, этап C).",
		"Пересчёт (из корня проекта):  sh bench/balance/ablation_v11_run.sh \"<путь к godot.exe>\" [итерация]; 60 забегов на итерацию.",
		"B2: пехота, оружие. B5: пехота, лучники. B7: как B5 + ремонт ворот ниже 60% + «держать» пехоте. B8 пропущен: копейщики выключены в данных v1.",
		"Метрика — непрерывная волна смерти, медиана по seed 1-5; сдвиг — от того же бота без даров. Осада I.",
		"Критерий: заметен — среднее B2, B5, B7 на уровне 3 от +0.2; не слишком силён — каждый сдвиг меньше +1.5.", ""]
	for it in its:
		dir = ROOT + it + "/"
		var lv := FileAccess.get_file_as_string(dir + "levels.txt").strip_edges()
		var secs := int(FileAccess.get_file_as_string(dir + "secs.txt").strip_edges())
		L.append("Итерация %s: уровни %s; время прогона %d мин %02d с" % [it, lv, secs / 60, secs % 60])
		for bot in BOTS:
			var r := median("none", bot)
			L.append("  без даров | %s | %-28s | медиана %5.2f" % [bot, "/".join(r[1].map(func(x): return "%.2f" % x)), r[0]])
		var means := []
		var strong := []
		for lvl in [1, 2, 3]:
			var cells := []
			var sum := 0.0
			for bot in BOTS:
				var sh := shift("sw_%d" % lvl, bot)
				cells.append("%s %s" % [bot, fmt(sh)])
				sum += sh
				if not is_nan(sh) and sh >= 1.5:
					strong.append("ур. %d у %s" % [lvl, bot])
			means.append(sum / BOTS.size())
			L.append("  «Сомкнутые щиты» %d | %s | среднее %s" % [lvl, " | ".join(cells), fmt(sum / BOTS.size())])
		var ok_seen: bool = not is_nan(means[2]) and means[2] >= 0.2
		L.append("  Итог: заметен (ур. 3, среднее %s >= +0.2) — %s; слишком силён (>= +1.5) — %s; критерий %s" % [fmt(means[2]),
			"да" if ok_seen else "НЕТ", ", ".join(strong) if not strong.is_empty() else "нет", "ВЫПОЛНЕН" if ok_seen and strong.is_empty() else "НЕ ВЫПОЛНЕН"])
		L.append("")
	var f := FileAccess.open("res://bench/gift_ablation_v11.txt", FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
