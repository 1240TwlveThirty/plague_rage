extends SceneTree
# Равный бюджет (задача 8, этап D): сборщик bench/balance/spear_budget_runs/ -> bench/spear_budget.txt. Аргумент — метка итерации (для отчёта).
# Метрика — непрерывная волна смерти (волна + доля убитых волны смерти), медиана по seed 1-5. Критерий готовности: копейщики на «держать»
# лучше пехоты на «держать» на +15…+30% (отношение медиан), без «держать» — не лучше пехоты без «держать».
const DIR := "res://bench/balance/spear_budget_runs/"
const OUT := "res://bench/spear_budget.txt"
const SETS := [["inf_hold", "B7, пехота 300, «держать»"], ["spear_hold", "B7, копейщики 200 (та же цена), «держать»"], ["inf_free", "B7, пехота 300, без «держать»"],
	["spear_free", "B7, копейщики 200, без «держать»"], ["b8_hold", "B8 (половина пехотных покупок — копейщики), «держать»"], ["b8_free", "B8, без «держать»"]]

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

func med(cfg: String) -> Array:
	var v := []
	for s in [1, 2, 3, 4, 5]:
		var d := death("%s_s%d" % [cfg, s])
		if d >= 0.0:
			v.append(d)
	var sorted := v.duplicate()
	sorted.sort()
	return [sorted[sorted.size() / 2] if not sorted.is_empty() else -1.0, v]

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var args := OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() > 0 else ""
	var L: Array[String] = []
	L.append("spear_budget: копейщики против пехоты при равной цене (задача 8, этап D)%s. Только измерения." % ("" if tag == "" else ", " + tag))
	L.append("Пересчёт:  sh bench/balance/spear_budget_run.sh \"<путь к godot.exe>\"")
	L.append("Метрика — непрерывная волна смерти, медиана по seed 1-5. B7: покупки по кругу «пехота» (или копейщики при армии копейщиков), лучники;")
	L.append("ремонт ворот ниже 60%; «держать» отрядам пехоты и копейщиков перед каждой волной (если не «без держать»).")
	L.append("")
	var m := {}
	for st in SETS:
		var r := med(st[0])
		m[st[0]] = r[0]
		L.append("  %-58s | %s | медиана %.2f" % [st[1], "/".join(r[1].map(func(x): return "%.2f" % x)), r[0]])
	var hold_gain: float = (m.spear_hold / m.inf_hold - 1.0) * 100.0 if m.inf_hold > 0.0 else 0.0
	var free_gain: float = (m.spear_free / m.inf_free - 1.0) * 100.0 if m.inf_free > 0.0 else 0.0
	L.append("")
	L.append("Копейщики против пехоты: на «держать» %+.1f%%, без «держать» %+.1f%%." % [hold_gain, free_gain])
	var ok_hold := hold_gain >= 15.0 and hold_gain <= 30.0
	var ok_free := free_gain <= 0.0
	L.append("Критерий: на «держать» +15…+30%% — %s; без «держать» не лучше пехоты — %s. Итог: %s." % ["да" if ok_hold else "нет", "да" if ok_free else "нет",
		"выполнен" if ok_hold and ok_free else "не выполнен"])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
