extends SceneTree
# Абляции задачи 6d: сборщик прогонов bench/balance/ablation_<версия>_runs/ -> таблицы в bench/.
# Аргументы: <версия v8 | v9 | v10> [секунды прогона].
# Метрика — непрерывная волна смерти (волна + доля убитых волны смерти, не больше 0.99), медиана по seed 1-5;
# сдвиг — от набора без даров и карточек того же бота («none»).
const SEEDS := [1, 2, 3, 4, 5]
const BOTS := ["B2", "B5", "B7", "B8"]
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

# Среднее по seed поля строки <tag>,<число> (RECOVER); -1 — нет строк.
func tag_mean(cfg: String, bot: String, tag: String) -> float:
	var sum := 0.0
	var n := 0
	for s in SEEDS:
		var path := dir + "%s_%s_s%d.txt" % [cfg, bot, s]
		if not FileAccess.file_exists(path):
			continue
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var f := line.strip_edges().split(",")
			if f[0] == tag and f.size() >= 2:
				sum += float(f[1])
				n += 1
	return sum / n if n > 0 else -1.0

func median(cfg: String, bot: String) -> Array:
	var v := []
	for s in SEEDS:
		var d := death("%s_%s_s%d" % [cfg, bot, s])
		if d >= 0.0:
			v.append(d)
	var sorted := v.duplicate()
	sorted.sort()
	return [sorted[sorted.size() / 2] if not sorted.is_empty() else -1.0, v]

func shift(cfg: String, bot: String, base := "none") -> float:
	var r: float = median(cfg, bot)[0]
	var b: float = median(base, bot)[0]
	return r - b if r >= 0.0 and b >= 0.0 else NAN

func fmt(x: float) -> String:
	return "—" if is_nan(x) else "%+.2f" % x

func line(label: String, cfg: String, bot: String, extra := "") -> String:
	var r := median(cfg, bot)
	var sh := shift(cfg, bot)
	return "  %-44s | %s | %-28s | медиана %5.2f | сдвиг %s%s" % [label, bot, "/".join(r[1].map(func(x): return "%.2f" % x)), r[0],
		fmt(sh), "" if extra == "" else " | " + extra]

func write(path: String, L: Array[String]) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)

func head(script: String, runs: int, secs: int) -> Array[String]:
	return ["Пересчёт (из корня проекта):  sh bench/balance/%s \"<путь к godot.exe>\"; время прогона %s, %d забегов." % [script,
		"%d мин %02d с" % [secs / 60, secs % 60] if secs > 0 else "не измерялось", runs],
		"B2: пехота, оружие. B5: пехота, лучники. B7: как B5 + ремонт ворот ниже 60% + «держать» пехоте. B8: как B7, по кругу пехота, лучники, копейщики, лучники.",
		"Метрика — непрерывная волна смерти, медиана по seed 1-5; сдвиг — от того же бота без даров и карточек. Осада I.", ""]

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	TranslationServer.set_locale("ru")
	var args := OS.get_cmdline_user_args()
	var ver: String = args[0] if args.size() > 0 else "v8"
	var secs := int(args[1]) if args.size() > 1 else 0
	dir = "res://bench/balance/ablation_%s_runs/" % ver
	match ver:
		"v8":
			v8(secs)
		"v9":
			v9(secs)
	quit()

# Этап A: «Лазарет» 1-3 (recover +10/20/30%) и карточка №40 «Полевой госпиталь» (recover +20%).
# «слишком сильно» — сдвиг больше +1.5 у №40 или «Лазарета» 3 (значения не меняются, только пометка).
func v8(secs: int) -> void:
	var H := head("ablation_v8_run.sh", 100, secs)
	var G: Array[String] = ["gift_ablation_v8: дар «Лазарет» — возврат павших после волны (recover +10/20/30%) вместо лечения (задача 6d, этап A). Только измерения."]
	G.append_array(H)
	var C: Array[String] = ["card_ablation_v4: карточка №40 «Полевой госпиталь» — возврат 20% павших после волны (задача 6d, этап A). Только измерения."]
	C.append_array(H)
	var strong := []
	for bot in BOTS:
		G.append(line("без даров", "none", bot, "вернулось за забег %.1f" % tag_mean("none", bot, "RECOVER")))
		for lvl in [1, 2, 3]:
			var cfg := "infirmary_%d" % lvl
			var sh := shift(cfg, bot)
			var mark := "вернулось за забег %.1f" % tag_mean(cfg, bot, "RECOVER")
			if lvl == 3 and not is_nan(sh) and sh > 1.5:
				mark += " | СЛИШКОМ СИЛЬНО (> +1.5)"
				strong.append("«Лазарет» 3 у %s" % bot)
			G.append(line("«Лазарет» %d (возврат %d%% павших)" % [lvl, lvl * 10], cfg, bot, mark))
		C.append(line("без карточек", "none", bot))
		var sc := shift("card_field_kitchen", bot)
		var cm := "вернулось за забег %.1f" % tag_mean("card_field_kitchen", bot, "RECOVER")
		if not is_nan(sc) and sc > 1.5:
			cm += " | СЛИШКОМ СИЛЬНО (> +1.5)"
			strong.append("№40 у %s" % bot)
		C.append(line("№40 Полевой госпиталь (возврат 20%)", "card_field_kitchen", bot, cm))
	var verdict := "Итог: «слишком сильно» (> +1.5) — %s." % (", ".join(strong) if not strong.is_empty() else "нет")
	G.append("")
	G.append(verdict)
	C.append("")
	C.append(verdict)
	write("res://bench/gift_ablation_v8.txt", G)
	write("res://bench/card_ablation_v4.txt", C)

# Строка «оригинал и вариант рядом» для одного бота: сдвиги медиан от «none» и разница вариант минус оригинал.
func pair_line(label: String, orig: String, alt: String, bot: String) -> String:
	var a := shift(orig, bot)
	var b := shift(alt, bot)
	return "  %-40s | %s | damage %s | attack_rate %s | разница %s" % [label, bot, fmt(a), fmt(b), fmt(b - a)]

# Средняя разница (вариант минус оригинал) по B2, B5, B7 — для выбора в этапе D.
func pair_mean(orig: String, alt: String) -> float:
	var sum := 0.0
	for bot in ["B2", "B5", "B7"]:
		sum += shift(alt, bot) - shift(orig, bot)
	return sum / 3.0

func pair_block(L: Array[String], label: String, orig: String, alt: String) -> void:
	for bot in BOTS:
		L.append(pair_line(label, orig, alt, bot))
	var d := pair_mean(orig, alt)
	L.append("  %-40s | среднее B2, B5, B7: разница %s -> %s" % ["", fmt(d), "attack_rate" if d >= 0.1 else ("damage" if d <= -0.1 else "разница < 0.1")])
	L.append("")

# Этап C: оригинал (damage) и вариант (attack_rate с теми же процентами и целями) рядом.
func v9(secs: int) -> void:
	var H := head("ablation_v9_run.sh", 840, secs)
	var C: Array[String] = ["card_ablation_v5: карточки — damage (оригинал) против attack_rate (вариант, те же проценты и цели); для издержек №7, 31, 33 — сдвиг карточки целиком (задача 6d, этап C). Только измерения."]
	C.append_array(H)
	for bot in BOTS:
		C.append("  без карточек | %s | медиана %.2f" % [bot, median("none", bot)[0]])
	C.append("")
	var cards := [[1, "meteor_blades", "пехота +12"], [2, "silver_vs_dead", "все +10"], [3, "serrated_arrows", "лучники +15"],
		[17, "last_stand", "C, все +25"], [25, "desperate_charge", "C, все +25"], [27, "long_spears", "все +15"], [36, "reserve_fund", "C, все +10"],
		[37, "blood_for_blood", "C, все +5 за ступень"], [7, "long_shot", "издержка: лучники −5"], [31, "iron_wall", "издержка: пехота −10"],
		[33, "shield_cover", "издержка: пехота −5"]]
	for c in cards:
		pair_block(C, "№%d %s (%s)" % [c[0], tr("CARD_%s_NAME" % c[1].to_upper()), c[2]], "card_" + c[1], "card_%s_ar" % c[1])
	write("res://bench/card_ablation_v5.txt", C)
	var G: Array[String] = ["gift_ablation_v9: дары и «Оружие» — damage (оригинал) против attack_rate (вариант, те же проценты и цели) (задача 6d, этап C). Только измерения."]
	G.append_array(H)
	for bot in BOTS:
		G.append("  без даров | %s | медиана %.2f" % [bot, median("none", bot)[0]])
	G.append("")
	for lvl in [1, 2, 3]:
		pair_block(G, "«Закалённая сталь» %d (пехота +%d)" % [lvl, lvl * 6], "ts_%d" % lvl, "ts_rate_%d" % lvl)
	for lvl in [1, 2, 3]:
		pair_block(G, "«Меткие стрелки» %d (лучники +%d)" % [lvl, lvl * 8], "mk_%d" % lvl, "mk_rate_%d" % lvl)
	for n in [1, 2, 3]:
		pair_block(G, "«Оружие +10%%»: %d покупк%s даром" % [n, "а" if n == 1 else "и"], "w_dmg_%d" % n, "w_rate_%d" % n)
	G.append("  «Оружие» на скорости боя без даровых покупок (меняются только покупки бота; B2 покупает оружие, B5, B7, B8 — нет):")
	for bot in BOTS:
		G.append(line("«Оружие» attack_rate, 0 даром", "w_rate_0", bot))
	write("res://bench/gift_ablation_v9.txt", G)
