extends SceneTree
# Абляция v7 (задача 8, этап D): сборщик bench/balance/ablation_v7_runs/ (ablation_v7_run.sh) -> bench/gift_ablation_v7.txt и bench/card_ablation_v3.txt.
# Метрика — непрерывная волна смерти (волна + доля убитых волны смерти), медиана по seed 1-5; сдвиг — от набора без даров и карточек того же бота.
# Пометка «бот не умеет»: сдвиг по модулю меньше 0.10 и бот не создаёт условия (отход у B7 и B8 не бывает). Строки WARCRY и B8 в разборе не нужны.
const DIR := "res://bench/balance/ablation_v7_runs/"
const SEEDS := [1, 2, 3, 4, 5]

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

func row(cfg: String, bot: String) -> Array:
	var v := []
	for s in SEEDS:
		var d := death("%s_%s_s%d" % [cfg, bot, s])
		if d >= 0.0:
			v.append(d)
	var sorted := v.duplicate()
	sorted.sort()
	return [sorted[sorted.size() / 2] if not sorted.is_empty() else -1.0, v]

func line(label: String, cfg: String, bot: String, note := "") -> String:
	var r := row(cfg, bot)
	var b := row("none", bot)
	var sh: float = r[0] - b[0] if r[0] >= 0.0 and b[0] >= 0.0 else NAN
	var mark := note if not is_nan(sh) and absf(sh) < 0.10 and note != "" else ""
	return "  %-46s | %s | %-28s | медиана %5.2f | сдвиг %s%s" % [label, bot, "/".join(r[1].map(func(x): return "%.2f" % x)), r[0],
		"—" if is_nan(sh) else "%+.2f" % sh, "" if mark == "" else " | " + mark]

func write(path: String, L: Array[String]) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 0
	var head: Array[String] = ["Пересчёт (из корня проекта):  sh bench/balance/ablation_v7_run.sh \"<путь к godot.exe>\"; время прогона %s, 75 забегов."
		% ("%d мин %02d с" % [secs / 60, secs % 60] if secs > 0 else "не измерялось"),
		"B7: по кругу пехота, лучники; ремонт ворот ниже 60%; «держать» отрядам пехоты и копейщиков. B8: так же, но по кругу пехота, лучники, копейщики, лучники.",
		"Метрика — непрерывная волна смерти, медиана по seed 1-5; сдвиг — от того же бота без даров и карточек. Без даров (кроме строк даров), осада I.", ""]
	var G: Array[String] = ["gift_ablation_v7: дар «Стена щитов» (block копейщиков +5/10/15 п. п.) и набор «все дары» с ним и без (задача 8). Только измерения."]
	G.append_array(head)
	G.append(line("без даров", "none", "B8"))
	for lvl in [1, 2, 3]:
		G.append(line("«Стена щитов» %d (block +%d п. п.)" % [lvl, lvl * 5], "spear_wall_%d" % lvl, "B8"))
	for lvl in [1, 2, 3]:
		G.append(line("все дары ур. %d, со «Стеной щитов»" % lvl, "all_%d" % lvl, "B8"))
		G.append(line("все дары ур. %d, без «Стены щитов»" % lvl, "allno_%d" % lvl, "B8"))
	write("res://bench/gift_ablation_v7.txt", G)
	var C: Array[String] = ["card_ablation_v3: карточки №9 «Строй щитов» (block +15 п. п. при «держать») и №11 «Подвижный резерв» (скорость +20% при отходе) на B7 и B8 (задача 8)."]
	C.append_array(head)
	for bot in ["B7", "B8"]:
		C.append(line("без карточек", "none", bot))
		C.append(line("№9 Строй щитов", "card_shield_wall", bot, "бот не использует: блок растёт, но исход не меняется"))
		C.append(line("№11 Подвижный резерв", "card_mobile_reserve", bot, "бот не умеет: боты не отходят, условие «отход» не выполняется"))
	write("res://bench/card_ablation_v3.txt", C)
	quit()
