extends SceneTree
# Замер героя v1 (задача 10): bench/balance/hero_v1_runs/ -> bench/hero_v1.txt. Аргументы: секунды прогона [версия v1|v2].
# v2 (задача 11): то же с ручным ударом — бот B9 держит J (удар сектором по перезарядке), папка hero_v2_runs, итог bench/hero_v2.txt.
# Метрика — непрерывная волна смерти (волна + доля убитых волны смерти, не больше 0.99), как в абляциях; медиана и среднее по seed 1-10,
# разница B9 − B7 на каждом seed. Строка HERO воркера: ударов, попаданий, добито героем, смертей героя.
var DIR := "res://bench/balance/hero_v1_runs/"
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

func death(name: String) -> float:
	var path := DIR + name + ".txt"
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

func hero(name: String) -> PackedInt32Array:
	for line in FileAccess.get_file_as_string(DIR + name + ".txt").split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "HERO" and f.size() >= 5:
			return PackedInt32Array([int(f[1]), int(f[2]), int(f[3]), int(f[4])])
	return PackedInt32Array([0, 0, 0, 0])

func stats(v: Array) -> Array:
	var s := v.duplicate()
	s.sort()
	var sum := 0.0
	for x in v:
		sum += x
	return [(s[s.size() / 2 - 1] + s[s.size() / 2]) / 2.0, sum / v.size()]

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 0
	var ver: String = args[1] if args.size() > 1 else "v1"
	DIR = "res://bench/balance/hero_%s_runs/" % ver
	var what := "бот ведёт его к ближайшему скоплению зомби) (задача 10, этап F)" if ver == "v1" else 		"бот ведёт его к ближайшему скоплению зомби и держит J — ручной удар сектором) (задача 11)"
	var L: Array[String] = ["hero_%s: герой — B7 (без героя) против B9 (B7 + герой, %s. Только измерения." % [ver, what],
		"Пересчёт (из корня проекта):  sh bench/balance/hero_%s_run.sh \"<путь к godot.exe>\"; время прогона %d мин %02d с, 20 забегов." % [ver, secs / 60, secs % 60],
		"Метрика — непрерывная волна смерти (волна + доля убитых), seed 1-10, осада I, без даров и карточек. B9 — нижняя граница вклада героя:",
		"бот не уклоняется, не отступает и не выбирает момент, герой гибнет в каждой волне.", "",
		"  seed | B7    | B9    | B9 − B7 | герой B9: ударов / попаданий / добито / смертей"]
	var a := []
	var b := []
	var diffs := []
	var tot := PackedInt32Array([0, 0, 0, 0])
	for s in SEEDS:
		var x := death("B7_s%d" % s)
		var y := death("B9_s%d" % s)
		var h := hero("B9_s%d" % s)
		for k in 4:
			tot[k] += h[k]
		a.append(x)
		b.append(y)
		diffs.append(y - x)
		L.append("  %4d | %5.2f | %5.2f | %+7.2f | %d / %d / %d / %d" % [s, x, y, y - x, h[0], h[1], h[2], h[3]])
	var sa := stats(a)
	var sb := stats(b)
	var sd := stats(diffs)
	var better := diffs.filter(func(d): return d > 0.0).size()
	var worse := diffs.filter(func(d): return d < 0.0).size()
	L.append("")
	L.append("  медиана: B7 %.2f, B9 %.2f (сдвиг медиан %+.2f); среднее: B7 %.2f, B9 %.2f; разница по seed: медиана %+.2f, среднее %+.2f" % [sa[0], sb[0], sb[0] - sa[0], sa[1], sb[1], sd[0], sd[1]])
	L.append("  B9 лучше на %d seed, хуже на %d, равно на %d" % [better, worse, SEEDS.size() - better - worse])
	L.append("  герой за забег в среднем: ударов %.1f, попаданий %.1f, добито %.1f, смертей %.1f" % [tot[0] / 10.0, tot[1] / 10.0, tot[2] / 10.0, tot[3] / 10.0])
	var f := FileAccess.open("res://bench/hero_%s.txt" % ver, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
