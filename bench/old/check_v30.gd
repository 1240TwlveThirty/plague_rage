extends SceneTree
# Тесты v30 (лазейка со стопкой отрядов лучников): (а) регрессия против bak30 при старом правиле дальности,
# (в) запрет пересечения блоков при расстановке, (г) arrows_out_of_range в обычном бою, (д) детерминизм.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/old/main_bak30.gd"

func new_main(path: String, seed: int, waves: bool, own_range := true) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	if "archer_own_range" in m:
		m.archer_own_range = own_range
	m._setup_data()
	return m

func slot_world(m: Node2D, i: int) -> Vector2:
	var s: int = m.unit_squad[i]
	return m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])

func compare(waves: bool) -> String:
	var a := new_main(OLD, 1, waves)
	var b := new_main(NEW, 1, waves, false)   # лучники по старому правилу
	var first := -1
	for t in range(1, 901):
		if waves and a.wave_state == a.WS_RESPITE:
			for m in [a, b]:
				m._buy(0)
				m._buy(1)
				m._start_wave()
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0:
			if a.count != b.count or a.gate_hp != b.gate_hp or a.gold != b.gold or a.arrows_fired != b.arrows_fired or a.arrows_hit != b.arrows_hit:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.unit_slot_idx[i] != b.unit_slot_idx[i]:
						first = t
						break
	var res := ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first) + " (юнитов %d, волна %d, отменено по дальности %d)" % [b.count, b.wave_number, b.arrows_out_of_range]
	a.free()
	b.free()
	return res

# (в) лучники: блок 25 × 4 по линии (600,300)-(744,300), прямоугольник 150 × 24 px (3600 px²) от y 297 до 321.
# Пехота: блок 20 × 15 (120 × 90 px) сверху; перекрытие по высоте h даёт 120 * h px² общей площади.
func test_overlap() -> void:
	var m := new_main(NEW, 1, true)
	m._place_formation(1, Vector2(600, 300), Vector2(744, 300))
	var out := []
	var ok := true
	for c in [[0.0, "касание"], [1.5, "5%"], [7.2, "24%"], [7.5, "25%"], [12.0, "40%"], [24.0, "80%"]]:
		var h: float = c[0]
		var a := Vector2(600, 210 + h)
		var b := Vector2(714, 210 + h)
		var before := [m.squad_pos[0], m.squad_angle[0], m.squad_width[0], m.squad_target[0], m.squad_user_width[0]]
		var slots := {}
		for i in m.count:
			if m.unit_squad[i] == 0:
				slots[i] = slot_world(m, i)
		m.hud_msg = ""
		var g: Dictionary = m._formation_geometry(0, a, b)
		m._place_formation(0, a, b)
		var placed: bool = m.squad_pos[0] != before[0]
		var expect_refuse: bool = h >= 7.5
		var same := true
		for i in slots:
			same = same and slot_world(m, i) == slots[i]
		var good: bool
		if expect_refuse:
			good = not placed and same and g.overlap == 1 and m.hud_msg == "Блок пересекается с отрядом 2" and is_equal_approx(m.hud_msg_t, 2.0) \
				and before == [m.squad_pos[0], m.squad_angle[0], m.squad_width[0], m.squad_target[0], m.squad_user_width[0]]
		else:
			good = placed and g.overlap == -1 and m.hud_msg == ""
		ok = ok and good
		out.append("%s — %s%s" % [c[1], "отказ (предпросмотр красный, отряд на месте)" if not placed else "поставлен", "" if good else " ОШИБКА"])
		if placed:
			# вернуть пехоту в сторону, чтобы следующий случай не зависел от этого
			m._place_formation(0, Vector2(1400, 300), Vector2(1514, 300))
	print("(в) пересечение с отрядом лучников (доля площади меньшего блока): %s; всё по правилу «отказ с 25%%»: %s" % ["; ".join(out), ok])
	# свой прежний блок не мешает: сдвиг того же отряда на пару пикселей
	var p0: Vector2 = m.squad_pos[0]
	m._place_formation(0, Vector2(1402, 302), Vector2(1516, 302))
	# пустой отряд и чужая команда не проверяются; после гибели лучников блок ставится
	for i in m.count:
		if m.unit_squad[i] == 1:
			m.hp[i] = 0.0
	m._remove_dead()
	var g2: Dictionary = m._formation_geometry(0, Vector2(600, 300), Vector2(714, 300))
	print("    свой прежний блок не мешает (сдвиг на 2 px выполнен): %s; пустой отряд не мешает: %s" % [m.squad_pos[0] != p0, g2.overlap == -1])
	m.free()

# (г) обычный бой без волн (пехота 300 + лучники 100 позади, как на старте): сколько выстрелов отменено по дальности.
func test_out_of_range() -> void:
	var rows := []
	for own in [false, true]:
		var fired := 0
		var hit := 0
		var out := 0
		var loss := [0, 0]
		for seed in range(1, 11):
			var m := new_main(NEW, seed, false, own)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			for i in m.count:
				m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			var start := [0, 0]
			for i in m.count:
				start[m.team[i]] += 1
			var left: Array = start.duplicate()
			var last_death := -1
			for t in range(1, 1801):
				var before: int = m.count
				m._physics_process(1.0 / 30.0)
				if m.count < before:
					last_death = t
					left = [0, 0]
					for i in m.count:
						left[m.team[i]] += 1
				if left[0] == 0 or left[1] == 0 or (last_death > 0 and t - last_death >= 90):
					break
			fired += m.arrows_fired
			hit += m.arrows_hit
			out += m.arrows_out_of_range
			loss[0] += start[0] - left[0]
			loss[1] += start[1] - left[1]
			m.free()
		rows.append("%s: выпущено %.0f, попало %.0f (%.0f%%), отменено по дальности %.1f на бой; потери %.1f / %.1f, ratio %.3f" % [
			"новое правило" if own else "старое правило", fired / 10.0, hit / 10.0, 100.0 * hit / maxi(fired, 1), out / 10.0, loss[0] / 10.0, loss[1] / 10.0, loss[1] / float(maxi(loss[0], 1))])
	print("(г) обычный бой без волн, 10 seed, лучники самостоятельные: %s" % "; ".join(rows))

func scripted(seed: int) -> PackedVector2Array:
	var m := new_main(NEW, seed, true)
	var tr := PackedVector2Array()
	m._place_formation(1, Vector2(900, 560), Vector2(1100, 560))    # лучники широкой линией: фланги дальше от цели
	m._place_formation(0, Vector2(960, 566), Vector2(1060, 566))    # пересекается с лучниками: отказ
	m._place_formation(0, Vector2(953, 500), Vector2(1067, 500))
	m._start_wave()
	for t in 900:
		if t == 300 and m.wave_state == m.WS_RESPITE:
			m._start_wave()
		m._physics_process(1.0 / 30.0)
		var c := Vector2(m.count, m.arrows_fired * 3 + m.arrows_out_of_range)
		for i in m.count:
			c += m.pos[i] * (1.0 + (i % 7)) + Vector2(m.hp[i], 0.0)
		tr.append(c)
	tr.append(Vector2(m.arrows_fired, m.arrows_out_of_range))
	m.free()
	return tr

func test_determinism() -> void:
	var r1 := scripted(4)
	var r2 := scripted(4)
	print("(д) 30 с, волны с расстановкой, два прогона seed 4: %s (за последнюю волну выпущено %d, отменено по дальности %d)" % [
		"совпадает на каждом тике" if r1 == r2 else "РАСХОДИТСЯ", int(r1[r1.size() - 1].x), int(r1[r1.size() - 1].y)])

func _initialize() -> void:
	print("(а) против bak30, лучники по старому правилу, waves off: " + compare(false))
	print("    то же с волнами и покупками: " + compare(true))
	test_overlap()
	test_out_of_range()
	test_determinism()
	quit()
