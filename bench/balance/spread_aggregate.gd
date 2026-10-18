extends SceneTree
# Абляция разброса HP зомби (задача 6b, этап 3): сборщик bench/balance/spread_v1_runs/ (spread_ablation_run.sh) -> bench/spread_ablation_v1.txt.
# Аргумент (необязательный): сколько секунд шли забеги. Метрика — непрерывная волна смерти, медиана по seed 1-5; сдвиг — от «без карточек»
# того же бота при том же s. Нет файлов — «—», сборщик не падает.
const OUT := "res://bench/spread_ablation_v1.txt"
const DIR := "res://bench/balance/spread_v1_runs/"
const SPREADS := ["0", "0.10", "0.15", "0.20"]
const BOTS := ["B2", "B5"]
const SEEDS := [1, 2, 3, 4, 5]
const ALIVE := 41.0
const SETS := [["meteor_blades", "№1 Клинки из метеоритного железа (урон пехоты +12%)"], ["silver_vs_dead", "№2 Серебро против мёртвых (урон всех +10%)"],
	["serrated_arrows", "№3 Зазубренные стрелы (урон лучников +15%)"], ["last_stand", "№17 Последний рубеж (урон всех +25% у ворот < 30%)"],
	["desperate_charge", "№25 Отчаянный натиск (урон отряда +25% ниже половины)"], ["long_spears", "№27 Длинные копья (урон всех +15%, враги +10%)"],
	["reserve_fund", "№36 Резервный фонд (урон всех +10% при 300 золота)"], ["blood_for_blood", "№37 Кровь за кровь (+5% за 10% потерь)"],
	["tempered_steel_3", "дар «Закалённая сталь» 3 (урон пехоты +18%)"]]

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
			out = d + minf(frac, 0.99) if d > 0 else (ALIVE if int(f[4]) == 1 else -1.0)
	return out

func median(s: String, cfg: String, bot: String) -> float:
	var v := []
	for seed in SEEDS:
		var d := death("%s_%s_%s_s%d" % [s, cfg, bot, seed])
		if d >= 0.0:
			v.append(d)
	if v.is_empty():
		return -1.0
	v.sort()
	return v[v.size() / 2]

func fs(v: float) -> String:
	return "     —" if is_nan(v) else "%+6.2f" % v

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 0
	var L: Array[String] = []
	L.append("spread_ablation_v1: разброс HP зомби s (data/waves.json hp_spread, по умолчанию 0) — только измерения, значение по умолчанию не менялось.")
	L.append("Пересчёт (из корня проекта):  sh bench/balance/spread_ablation_run.sh \"<путь к godot.exe>\"")
	L.append("Время прогона: %s; 400 забегов, до 10 процессов сразу." % ("%d мин %02d с" % [secs / 60, secs % 60] if secs > 0 else "не измерялось"))
	L.append("HP каждого зомби при появлении x (1 + s (2u - 1)), u — хэш (seed, волна, номер зомби в волне). Боты B2 и B5, seed 1-5, без даров,")
	L.append("осада I, волны без предела. Метрика — непрерывная волна смерти (волна + доля убитых волны смерти), медиана по seed;")
	L.append("сдвиг — от «без карточек» того же бота при том же s.")
	L.append("")
	L.append("1. База (без карточек и даров): медиана волны смерти.")
	L.append("     s | B2    | B5")
	for s in SPREADS:
		L.append("  %4s | %5.2f | %5.2f" % [s, median(s, "none", "B2"), median(s, "none", "B5")])
	L.append("")
	L.append("2. Сдвиг от базы того же s: B2 / B5.")
	var head := "  %-56s" % "набор"
	for s in SPREADS:
		head += " | s = %-4s     " % s
	L.append(head)
	var nonzero := {}
	for st in SETS:
		var row := "  %-56s" % st[1]
		for s in SPREADS:
			var cells := PackedStringArray()
			for bot in BOTS:
				var a := median(s, "none", bot)
				var b := median(s, st[0], bot)
				var v := NAN if a < 0.0 or b < 0.0 else b - a
				cells.append(fs(v).strip_edges())
				if not is_nan(v) and absf(v) >= 0.1:
					nonzero[s] = nonzero.get(s, 0) + 1
			row += " | %-13s" % " / ".join(cells)
		L.append(row)
	L.append("")
	L.append("3. Сколько сдвигов из %d (9 наборов x 2 бота) по модулю не меньше 0.10 при каждом s: %s" % [SETS.size() * 2,
		", ".join(SPREADS.map(func(s): return "s %s — %d" % [s, nonzero.get(s, 0)]))])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
