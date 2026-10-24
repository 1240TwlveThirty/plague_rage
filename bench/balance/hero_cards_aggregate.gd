extends SceneTree
# Абляция карточек героя v1 (задача 14, этап C): bench/balance/hero_cards_v1_runs/ -> bench/hero_card_ablation_v1.txt. Аргумент: секунды прогона.
# Метрика — непрерывная волна смерти (волна + доля убитых волны смерти, не больше 0.99), как в абляциях; бот B9, seed 1-10, осада I.
# Сдвиг — медиана по seed разницы «с карточкой − без карточек» на том же seed и сдвиг медиан; строка HERO воркера — удары героя.
const DIR := "res://bench/balance/hero_cards_v1_runs/"
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const SETS := [["card_wide_swing", "№41 Широкий замах (дуга +40°, радиус +15%)"], ["card_quick_hands", "№42 Быстрые руки (скорость удара +20%)"],
	["card_commander_temper", "№43 Закалка командира (HP героя +50%)"]]

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
	var path := DIR + name + ".txt"
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var f := line.strip_edges().split(",")
			if f[0] == "HERO" and f.size() >= 5:
				return PackedInt32Array([int(f[1]), int(f[2]), int(f[3]), int(f[4])])
	return PackedInt32Array([0, 0, 0, 0])

func median(v: Array) -> float:
	var s := v.duplicate()
	s.sort()
	return (s[s.size() / 2 - 1] + s[s.size() / 2]) / 2.0 if s.size() % 2 == 0 else s[s.size() / 2]

func mean(v: Array) -> float:
	var sum := 0.0
	for x in v:
		sum += x
	return sum / v.size()

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 0
	var hd = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	var L: Array[String] = ["hero_card_ablation_v1: карточки героя №41–43 (задача 14, этап C). Только измерения.",
		"Пересчёт (из корня проекта):  sh bench/balance/hero_cards_v1_run.sh \"<путь к godot.exe>\"; время прогона %d мин %02d с, 40 забегов." % [secs / 60, secs % 60],
		"Бот B9: армия как у B7 (покупки, ремонт ворот ниже 60%, «держать» пехоте) + герой, бот ведёт его к скоплению зомби и держит J.",
		"Метрика — непрерывная волна смерти (волна + доля убитых), seed 1-10, осада I, без даров; карточка — с начала забега (--cards).",
		"Сдвиг — от того же B9 без карточек на том же seed. Данные героя — рабочий data/hero.json (hp %s, attack_interval %s, arc_angle %s, arc_range %s)." % [hd.hp, hd.attack_interval, hd.arc_angle, hd.arc_range],
		"№44 «Последний рубеж» и №45 «Знамя командира» не замерялись: бот к ним слеп — герой гибнет с контакта (ниже 40% HP живёт доли секунды),",
		"а B9 уводит героя к скоплению зомби, прочь от отрядов (центр отряда ближе 150 px бывает случайно).", ""]
	var base := []
	var hb := PackedInt32Array([0, 0, 0, 0])
	for s in SEEDS:
		base.append(death("none_B9_s%d" % s))
		var h := hero("none_B9_s%d" % s)
		for k in 4:
			hb[k] += h[k]
	L.append("  без карточек: медиана %.2f, среднее %.2f; герой за забег: ударов %.1f, попаданий %.1f, добито %.1f, смертей %.1f" % [median(base), mean(base),
		hb[0] / 10.0, hb[1] / 10.0, hb[2] / 10.0, hb[3] / 10.0])
	L.append("")
	L.append("  карточка                                          | сдвиг (медиана разниц) | среднее разниц | сдвиг медиан | лучше/хуже/равно | герой: ударов / попаданий / добито / смертей")
	var rows := []
	for st in SETS:
		var v := []
		var d := []
		var ht := PackedInt32Array([0, 0, 0, 0])
		for k in SEEDS.size():
			var x := death("%s_B9_s%d" % [st[0], SEEDS[k]])
			v.append(x)
			d.append(x - base[k])
			var h := hero("%s_B9_s%d" % [st[0], SEEDS[k]])
			for q in 4:
				ht[q] += h[q]
		var better := d.filter(func(x): return x > 0.0).size()
		var worse := d.filter(func(x): return x < 0.0).size()
		L.append("  %-49s | %+22.2f | %+14.2f | %+12.2f | %d / %d / %d | %.1f / %.1f / %.1f / %.1f" % [st[1], median(d), mean(d), median(v) - median(base), better, worse,
			SEEDS.size() - better - worse, ht[0] / 10.0, ht[1] / 10.0, ht[2] / 10.0, ht[3] / 10.0])
		rows.append([st[0], d])
	L.append("")
	L.append("  по seed (волна смерти):")
	var head := "  seed | без   "
	for st in SETS:
		head += " | %-6s" % st[0].trim_prefix("card_").left(6)
	L.append(head)
	for k in SEEDS.size():
		var line := "  %4d | %5.2f " % [SEEDS[k], base[k]]
		for st in SETS:
			line += " | %6.2f" % death("%s_B9_s%d" % [st[0], SEEDS[k]])
		L.append(line)
	var f := FileAccess.open("res://bench/hero_card_ablation_v1.txt", FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
