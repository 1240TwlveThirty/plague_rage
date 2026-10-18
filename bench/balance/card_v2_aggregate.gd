extends SceneTree
# Абляция карточек v2 (задача 6b, этап 4): сборщик bench/balance/card_v2_runs/ (card_v2_run.sh) -> bench/card_ablation_v2.txt.
# Бот B7: держит линию пехотой и ремонтирует ворота. Метрика — непрерывная волна смерти, медиана по seed 1-5, сдвиг от B7 без карточек.
# Пометки: «заработало» — сдвиг по модулю не меньше THRESH; иначе «бот всё ещё не использует» с причиной. Плюс по логу бота: ремонтов и пропусков
# ремонта (не хватило золота) за забег, средняя цена ремонта.
const OUT := "res://bench/card_ablation_v2.txt"
const DIR := "res://bench/balance/card_v2_runs/"
const SEEDS := [1, 2, 3, 4, 5]
const ALIVE := 41.0
const THRESH := 0.1
const SETS := [["steadfast", "№10 Стойкость (HP всех +15% при «Держать»)", "условие «Держать» выполняется, но получаемый урон пехоты у B7 почти не влияет на исход"],
	["mobile_reserve", "№11 Подвижный резерв (скорость +20% при отходе)", "B7 не отводит отряды: условие «отход» не выполняется"],
	["sentries", "№12 Дозорные (окно сигнала +1 с)", "сигнал всплеска меняет только предупреждение, B7 на сигнал не реагирует"],
	["stone_parapets", "№14 Каменные брустверы (ворота +25%, ремонт +20%)", "ворота почти не падают ниже 60% до последней волны: прочность и цена ремонта почти не участвуют"],
	["quick_repair", "№16 Быстрый ремонт (ремонт −30%)", "ремонтов мало, и золота на них хватает и без скидки"],
	["iron_wall", "№31 Железная стена (HP пехоты +30% при «Держать», урон пехоты −10%)", "бонус и издержка друг друга гасят"],
	["repairers_1", "дар «Ремонтники» 1 (ремонт −15%)", "ремонтов мало, и золота на них хватает и без скидки"],
	["repairers_2", "дар «Ремонтники» 2 (ремонт −30%)", "ремонтов мало, и золота на них хватает и без скидки"],
	["repairers_3", "дар «Ремонтники» 3 (ремонт −45%)", "ремонтов мало, и золота на них хватает и без скидки"],
	["watch_1", "дар «Дозор» 1 (окно сигнала +0.25 с)", "сигнал всплеска меняет только предупреждение, B7 на сигнал не реагирует"],
	["watch_2", "дар «Дозор» 2 (окно сигнала +0.5 с)", "сигнал всплеска меняет только предупреждение, B7 на сигнал не реагирует"],
	["watch_3", "дар «Дозор» 3 (окно сигнала +0.75 с)", "сигнал всплеска меняет только предупреждение, B7 на сигнал не реагирует"]]

func load_run(cfg: String, seed: int) -> Dictionary:
	var path := "%s%s_B7_s%d.txt" % [DIR, cfg, seed]
	var r := {"death": -1.0, "repairs": 0, "skips": 0, "repair_gold": 0.0, "holds": 0}
	if not FileAccess.file_exists(path):
		return r
	var frac := 0.0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE" and f.size() >= 19:
			frac = float(f[18]) / float(f[9]) if int(f[9]) > 0 else 0.0
		elif f[0] == "RUN":
			var d := int(f[3])
			r.death = d + minf(frac, 0.99) if d > 0 else (ALIVE if int(f[4]) == 1 else -1.0)
		elif f[0] == "B7" and f.size() >= 3:
			match f[2]:
				"repair":
					r.repairs += 1
					r.repair_gold += float(line.get_slice("цена ", 1))
				"repair_skip":
					r.skips += 1
				"hold":
					r.holds += 1
	return r

func runs(cfg: String) -> Array:
	return SEEDS.map(func(s): return load_run(cfg, s)).filter(func(r): return r.death >= 0.0)

func median(rs: Array) -> float:
	if rs.is_empty():
		return -1.0
	var d := rs.map(func(r): return r.death)
	d.sort()
	return d[d.size() / 2]

func mean(rs: Array, key: String) -> float:
	return 0.0 if rs.is_empty() else rs.reduce(func(a, r): return a + r[key], 0.0) / rs.size()

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 0
	var L: Array[String] = []
	L.append("card_ablation_v2: карточки и дары, которые B2 и B5 использовать не могут, на боте B7 (задача 6b, этап 4). Только измерения.")
	L.append("Пересчёт (из корня проекта):  sh bench/balance/card_v2_run.sh \"<путь к godot.exe>\"")
	L.append("Время прогона: %s; 65 забегов." % ("%d мин %02d с" % [secs / 60, secs % 60] if secs > 0 else "не измерялось"))
	L.append("B7: покупки как у B5 (по кругу пехота, лучники); перед ними ремонт ворот, если их HP ниже 60% и хватает золота; перед каждой волной —")
	L.append("приказ «держать» всем отрядам пехоты; на сигнал всплеска не реагирует; не отходит. Без даров (кроме строк даров), осада I, seed 1-5.")
	L.append("Метрика — непрерывная волна смерти, медиана по seed; сдвиг — от B7 без карточек. «Заработало» — сдвиг по модулю не меньше %.2f." % THRESH)
	L.append("Ремонтов / пропусков — за забег в среднем (пропуск: ворота ниже 60%, но золота на ремонт не хватило); цена — средняя за ремонт.")
	L.append("")
	var base := runs("none")
	L.append("База B7 без карточек: медиана %.2f (%s); ремонтов %.1f, пропусков %.1f, средняя цена ремонта %s." % [median(base), "/".join(base.map(func(r): return "%.2f" % r.death)),
		mean(base, "repairs"), mean(base, "skips"), "%.0f" % (mean(base, "repair_gold") / maxf(mean(base, "repairs"), 0.001)) if mean(base, "repairs") > 0.0 else "—"])
	L.append("")
	L.append("  %-62s | смерть s1-s5                 | медиана | сдвиг | ремонтов | пропусков | цена | итог" % "набор")
	for st in SETS:
		var rs := runs(st[0])
		var med := median(rs)
		var sh := NAN if med < 0.0 or median(base) < 0.0 else med - median(base)
		var reps := mean(rs, "repairs")
		var verdict: String = "—" if is_nan(sh) else ("заработало" if absf(sh) >= THRESH else "бот всё ещё не использует: " + st[2])
		L.append("  %-62s | %-28s | %7s | %s | %8.1f | %9.1f | %4s | %s" % [st[1], "/".join(rs.map(func(r): return "%.2f" % r.death)), "—" if med < 0.0 else "%.2f" % med,
			"     —" if is_nan(sh) else "%+6.2f" % sh, reps, mean(rs, "skips"), "%.0f" % (mean(rs, "repair_gold") / reps) if reps > 0.0 else "—", verdict])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
