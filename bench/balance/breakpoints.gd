extends SceneTree
# Пороги урона (задача 6, этап E): bench/damage_breakpoints.txt и .csv. Только расчёт по данным (data/unit_types.json, data/waves.json, data/shop.json).
# Для каждого типа зомби волны (крестьянин, бегун, рыцарь) и атакующего (пехота — удар, лучник — стрела), волны 1-10:
# HP цели = HP типа * (1 + hp_growth * (волна - 1)); ударов до убийства = ceil(HP / урон) для базового урона и +12%, +25%, +50%.
# «Пересекает порог» — бонус уменьшает число ударов против базового на этой волне. Рыцари появляются с волны knight_from_wave (раньше — «нет»).
# Второй блок: пехота с покупками оружия (x dmg_mult за покупку, 0-5 покупок) против крестьян — так играет бот B2.
const BONUSES := [0, 12, 25, 50]
const WAVES := 10
const OUT := "res://bench/damage_breakpoints"

func hits(hp: float, dmg: float) -> int:
	return ceili(hp / dmg - 1e-6)

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var m: Node2D = load("res://scripts/main.gd").new()
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var growth: float = m.wave_cfg.hp_growth
	var knight_from := int(m.wave_cfg.knight_from_wave)
	var targets := [["крестьянин", m.zombie_type], ["бегун", m.runner_type], ["рыцарь", m.knight_type]]
	var attackers := [["пехота (удар)", m.base_type_damage[m.infantry_type]], ["лучник (стрела)", m.base_type_arrow_dmg[m.archer_type]]]
	var L: Array[String] = []
	var C: Array[String] = ["attacker,target,wave,target_hp,base_damage,hits_base,hits_12,hits_25,hits_50,crosses"]
	L.append("damage_breakpoints: удары до убийства (ceil(HP цели / урон)), волны 1-%d. HP цели = HP типа x (1 + %.2f x (волна - 1)), урон без покупок оружия." % [WAVES, growth])
	L.append("Пересекает — бонусы, при которых ударов меньше, чем при базовом уроне. Рыцари — с волны %d. CSV рядом: bench/damage_breakpoints.csv." % knight_from)
	var works := {}   # атакующий|бонус -> волны, где бонус работает хоть против одного типа
	for a in attackers:
		for tg in targets:
			L.append("")
			L.append("%s против: %s (HP типа %.2f), урон %.2f" % [a[0], tg[0], m.base_type_hp[tg[1]], a[1]])
			L.append("  волна |  HP цели | база | +12% | +25% | +50% | пересекает")
			for w in range(1, WAVES + 1):
				var hp: float = m.base_type_hp[tg[1]] * (1.0 + growth * (w - 1))
				if tg[1] == m.knight_type and w < knight_from:
					L.append("  %5d |        — |    — |    — |    — |    — | нет рыцарей" % w)
					continue
				var hs := BONUSES.map(func(b): return hits(hp, a[1] * (1.0 + b / 100.0)))
				var cross := PackedStringArray()
				for k in range(1, BONUSES.size()):
					if hs[k] < hs[0]:
						cross.append("+%d%%" % BONUSES[k])
						var key := "%s|%d" % [a[0], BONUSES[k]]
						works[key] = works.get(key, []) + ["%d (%s)" % [w, tg[0]]]
				L.append("  %5d | %8.3f | %4d | %4d | %4d | %4d | %s" % [w, hp, hs[0], hs[1], hs[2], hs[3], "—" if cross.is_empty() else ", ".join(cross)])
				C.append("%s,%s,%d,%.4f,%.4f,%d,%d,%d,%d,%s" % [a[0], tg[0], w, hp, a[1], hs[0], hs[1], hs[2], hs[3], " ".join(cross)])
	L.append("")
	L.append("Где процентный бонус к урону меняет число ударов (волны 1-%d, урон без покупок оружия):" % WAVES)
	for a in attackers:
		for k in range(1, BONUSES.size()):
			var key := "%s|%d" % [a[0], BONUSES[k]]
			L.append("  %s +%d%%: %s" % [a[0], BONUSES[k], ", ".join(works.get(key, ["нигде"]))])
	var wk: int = m.SHOP_ITEMS.find("weapons")
	var gain: float = m.shop_param[wk]
	L.append("")
	L.append("Пехота с покупками оружия (урон x%.2f за покупку) против крестьян: удары до убийства без бонуса / +12%% / +25%% / +50%%." % gain)
	L.append("  волна | " + " | ".join(range(0, 6).map(func(n): return "оружие %d" % n)))
	for w in range(1, WAVES + 1):
		var hp: float = m.base_type_hp[m.zombie_type] * (1.0 + growth * (w - 1))
		var cells := PackedStringArray()
		for n in range(0, 6):
			var d: float = m.base_type_damage[m.infantry_type] * pow(gain, n)
			cells.append("%d/%d/%d/%d" % BONUSES.map(func(b): return hits(hp, d * (1.0 + b / 100.0))))
		L.append("  %5d | %s" % [w, " | ".join(cells)])
	m.free()
	for pair in [[OUT + ".txt", L], [OUT + ".csv", C]]:
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		f.store_string("\n".join(pair[1]) + "\n")
		f.close()
	for l in L:
		print(l)
	quit()
