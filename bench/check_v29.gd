extends SceneTree
# Тесты v29 (управление строем): (а) якорь, (б) геометрия, (в) лицо, (г) F вне протяжки, (д) угол без команд,
# (е) Shift+колесо, (ж) щит, (и) регрессия против bak29. Кольцо дальности — функция _range_ring_radius.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/main_bak29.gd"

func new_main(path: String, seed: int, waves: bool) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func slot_world(m: Node2D, i: int) -> Vector2:
	var s: int = m.unit_squad[i]
	return m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])

func units_of(m: Node2D, s: int) -> Array:
	var ids := []
	for i in m.count:
		if m.unit_squad[i] == s:
			ids.append(i)
	return ids

# Сетка: слоты уникальны, в колонке ряды 0..h-1 без дыр, глубины отличаются не больше чем на 1.
func grid_ok(m: Node2D, s: int, strict := true) -> bool:
	var width: int = m.squad_width[s]
	var seen := {}
	var heights := {}
	var top := {}
	for i in units_of(m, s):
		var k: int = m.unit_slot_idx[i]
		if k < 0 or seen.has(k):
			return false
		seen[k] = true
		heights[k % width] = heights.get(k % width, 0) + 1
		top[k % width] = maxi(top.get(k % width, 0), k / width)
	var lo := 1 << 30
	var hi := 0
	for col in heights:
		if strict and top[col] != heights[col] - 1:
			return false
		lo = mini(lo, heights[col])
		hi = maxi(hi, heights[col])
	return not strict or hi - lo <= 1

func in_bounds(m: Node2D, s: int) -> bool:
	for i in units_of(m, s):
		var p := slot_world(m, i)
		if p.x < -0.02 or p.x > m.FIELD.x + 0.02 or p.y < -0.02 or p.y > m.WALL_Y - 12.0 + 0.02:
			return false
	return true

# (а) + (б) + (в): 8 направлений × 5 длин × 3 размера отряда, в середине поля и у краёв.
func test_geometry() -> void:
	var m300 := new_main(NEW, 1, true)
	var m1400 := new_main(NEW, 1, true)
	m1400._squad_add_units(0, m1400.infantry_type, 1100)
	var cases := [[m300, 1], [m300, 0], [m1400, 0]]
	var total := 0
	var bad := []
	var moved := 0
	var extended := 0
	var stretched := 0
	var face_bad := 0
	for c in cases:
		var m: Node2D = c[0]
		var s: int = c[1]
		var n: int = m.squad_n[s]
		for length: float in [10.0, 30.0, 60.0, 200.0, 700.0]:
			for k in 8:
				var dir := Vector2.from_angle(k * PI / 4.0)
				var a := Vector2(1100, 366)
				var b := a + dir * length
				var g: Dictionary = m._formation_geometry(s, a, b)
				m._place_formation(s, a, b)
				var w_min := ceili(n / float(m.ROWS_MAX))
				var l_eff := maxf(length, (w_min - 1) * m.SLOT_SPACING)
				var w := mini(clampi(roundi(l_eff / m.SLOT_SPACING) + 1, w_min, m.WIDTH_MAX), n)
				var width: int = m.squad_width[s]
				var ok: bool = width >= w_min and width <= m.WIDTH_MAX and m.squad_rows[s] == ceili(n / float(width)) and grid_ok(m, s) and in_bounds(m, s)
				ok = ok and m.squad_target[s] == m.squad_pos[s]
				# лицо по правилу п. 2
				var face := Vector2(dir.y, -dir.x)
				if absf(angle_difference(m.squad_angle[s], face.angle())) > 0.0001:
					face_bad += 1
					ok = false
				# ряд 0: все слоты на прямой A–B_eff, колонка 0 в A, последняя в B_eff
				var first := Vector2.INF
				var last := Vector2.INF
				var front_n := 0
				for i in units_of(m, s):
					if m.unit_slot_idx[i] / width == 0:
						var p := slot_world(m, i)
						front_n += 1
						ok = ok and absf((p - g.a).dot(face)) <= 0.5
						if m.unit_slot_idx[i] == 0:
							first = p
						if m.unit_slot_idx[i] == width - 1:
							last = p
				ok = ok and front_n == width and first.distance_to(g.a) <= 0.5 and last.distance_to(g.b) <= 0.5
				if g.adjusted:
					moved += 1
				else:
					ok = ok and first.distance_to(a) <= 0.5   # якорь: A на месте
					if width > w:
						extended += 1
					else:
						ok = ok and width == w
				if length < (w_min - 1) * m.SLOT_SPACING:
					stretched += 1
					ok = ok and (last - a).dot(dir) >= length - 0.5   # растянуто за курсор, в сторону B
				total += 1
				if not ok:
					bad.append("n=%d L=%d угол %d°" % [n, int(length), k * 45])
	print("(а)(б) середина поля: %d случаев (n 100/300/1400 × длины 10/30/60/200/700 × 8 направлений): A на месте (0.5 px) во всех, кроме сдвинутых: %d; удлинено за курсор ради места: %d; короткая линия растянута за курсор: %d; ошибок %d %s" % [
		total, moved, extended, stretched, bad.size(), bad.slice(0, 5)])
	print("(в) лицо по правилу front = (d.y, -d.x): расхождений %d из %d; слева направо — %s, справа налево — %s" % [face_bad, total,
		"вверх" if Vector2.from_angle(m300._formation_geometry(0, Vector2(900, 400), Vector2(1000, 400)).angle).y < -0.99 else "НЕ вверх",
		"вниз" if Vector2.from_angle(m300._formation_geometry(0, Vector2(1000, 400), Vector2(900, 400)).angle).y > 0.99 else "НЕ вниз"])
	var gf: Dictionary = m300._formation_geometry(0, Vector2(900, 400), Vector2(1000, 400), true)
	var gn: Dictionary = m300._formation_geometry(0, Vector2(900, 400), Vector2(1000, 400))
	m300._place_formation(0, Vector2(900, 400), Vector2(1000, 400), true)
	var flip_ok: bool = absf(absf(angle_difference(gf.angle, gn.angle)) - PI) < 0.0001 and gf.a == gn.a and gf.b == gn.b and absf(angle_difference(m300.squad_angle[0], PI / 2.0)) < 0.0001
	var on_line := true
	for i in units_of(m300, 0):
		if m300.unit_slot_idx[i] / m300.squad_width[0] == 0:
			on_line = on_line and absf(slot_world(m300, i).y - 400.0) <= 0.5
		else:
			on_line = on_line and slot_world(m300, i).y < 400.0   # строй растёт назад: при лице вниз — вверх
	print("    F во время протяжки (flip): лицо наоборот, линия A–B та же, ряд 0 на линии, остальные ряды за ней: %s" % (flip_ok and on_line and grid_ok(m300, 0)))
	# удлинение за курсор: n = 300 у стены, 20 рядов не помещаются, а 14 помещаются
	var a_ext := Vector2(900, 650)
	var g_ext: Dictionary = m300._formation_geometry(0, a_ext, Vector2(960, 650))
	m300._place_formation(0, a_ext, Vector2(960, 650))
	var col0 := Vector2.INF
	for i in units_of(m300, 0):
		if m300.unit_slot_idx[i] == 0:
			col0 = slot_world(m300, i)
	print("    удлинение за курсор (n = 300, линия 60 px в 83 px от стены): строй %d × %d вместо 15 × 20, A на месте: %s, красный: %s, в поле: %s" % [
		g_ext.width, g_ext.rows, col0.distance_to(a_ext) <= 0.5, g_ext.adjusted, in_bounds(m300, 0) and grid_ok(m300, 0)])
	# края поля: n = 1400, якорь у границы
	var edge := [
		[Vector2(900, 725), Vector2(1100, 725), "низ, лицом вверх: блок уходит под стену"],
		[Vector2(1100, 10), Vector2(900, 10), "верх, лицом вниз: блок уходит за верхний край"],
		[Vector2(20, 300), Vector2(20, 500), "левый край, лицом вправо: блок уходит влево"],
		[Vector2(2180, 500), Vector2(2180, 300), "правый край, лицом влево: блок уходит вправо"],
		[Vector2(2100, 300), Vector2(2150, 300), "линия упирается в правый край (растянута за курсор)"],
		[Vector2(1000, 700), Vector2(1100, 700), "низ, лицом вверх, короткая линия"],
		[Vector2(300, 200), Vector2(700, 200), "середина: помещается"]]
	var out := []
	var edge_bad := 0
	for e in edge:
		var g: Dictionary = m1400._formation_geometry(0, e[0], e[1])
		m1400._place_formation(0, e[0], e[1])
		var shift: float = g.a.distance_to(e[0])
		var okk: bool = in_bounds(m1400, 0) and grid_ok(m1400, 0) and (g.adjusted == (shift > 0.5))
		if not okk:
			edge_bad += 1
		out.append("      %s: %d × %d, %s%s" % [e[2], g.width, g.rows, "A на месте" if shift <= 0.5 else "A сдвинута на %.0f px (не помещается, предпросмотр красный)" % shift, "" if okk else " ОШИБКА"])
	print("    у края поля (n = 1400), всё в поле и не ниже WALL_Y - 12, ошибок %d:\n%s" % [edge_bad, "\n".join(out)])
	m300.free()
	m1400.free()

# (г) F вне протяжки: мировые позиции слотов не меняются.
func test_about_face() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var out := []
	for mode in ["полный (300)", "117 убитых (183)", "3 юнита"]:
		var worst := 0.0
		var angle_bad := 0
		var grid_bad := 0
		for q in 30:
			var m := new_main(NEW, 1, true)
			if mode != "полный (300)":
				var ids := units_of(m, 0)
				var keep := 183 if mode.begins_with("117") else 3
				while ids.size() > keep:
					var k := rng.randi_range(0, ids.size() - 1)
					m.hp[ids[k]] = 0.0
					ids.remove_at(k)
				m._remove_dead()
				m._update_squads(0.6)
			m.squad_angle[0] = rng.randf_range(-PI, PI)
			var before := {}
			for i in units_of(m, 0):
				before[i] = slot_world(m, i)
			var a0: float = m.squad_angle[0]
			m._select_only(0)
			var done: bool = m._cmd_about_face()
			for i in before:
				worst = maxf(worst, slot_world(m, i).distance_to(before[i]))
			if not done or absf(absf(angle_difference(m.squad_angle[0], a0)) - PI) > 0.0001:
				angle_bad += 1
			if not grid_ok(m, 0, false):
				grid_bad += 1
			m.free()
		out.append("%s: макс. сдвиг слота %.4f px, угол не на 180° в %d, сетка нарушена в %d" % [mode, worst, angle_bad, grid_bad])
	var e := new_main(NEW, 1, true)
	e._cmd_new_squad()
	var ignored: bool = e.squad_n[e.sel_primary] == 0 and not e._cmd_about_face() and not e._cmd_rotate(1)
	e.free()
	print("(г) F вне протяжки, 30 случайных углов (допуск 0.01 px): %s; пустой отряд игнорирует F и колесо: %s" % ["; ".join(out), ignored])

# (д) угол отрядов игрока не меняется без команд.
func test_angle_stable() -> void:
	var out := []
	for seed in [1, 2, 3]:
		var m := new_main(NEW, seed, true)
		var a0: PackedFloat32Array = m.squad_angle.duplicate()
		var worst := 0.0
		var ticks := 0
		for wave in 5:
			if m.wave_state != m.WS_RESPITE:
				break
			m._start_wave()
			var t := 0
			while m.wave_state == m.WS_BATTLE and t < 1800:
				m._physics_process(1.0 / 30.0)
				t += 1
				for s in m.SQUAD_MAX:
					worst = maxf(worst, absf(m.squad_angle[s] - a0[s]))
			ticks += t
		out.append("seed %d: волн %d, тиков %d, макс. изменение угла %.6f" % [seed, m.wave_number, ticks, worst])
		m.free()
	print("(д) squad_angle без команд, волны 1-5 (до 60 с на волну): %s" % "; ".join(out))

# (е) Shift + колесо.
func test_rotate() -> void:
	var m := new_main(NEW, 1, true)
	m._select_only(0)
	var a0: float = m.squad_angle[0]
	var t0: Vector2 = m.squad_target[0]
	var c0 := Vector2.ZERO
	for i in units_of(m, 0):
		c0 += slot_world(m, i) / 300.0
	var worst := 0.0
	var ok := true
	for step in 24:
		ok = ok and m._cmd_rotate(1)
		var c := Vector2.ZERO
		for i in units_of(m, 0):
			c += slot_world(m, i) / 300.0
		worst = maxf(worst, c.distance_to(c0))
		ok = ok and grid_ok(m, 0)
		if step == 0:
			ok = ok and absf(angle_difference(m.squad_angle[0], a0 + deg_to_rad(15.0))) < 0.0001
	var back := absf(angle_difference(m.squad_angle[0], a0))
	ok = ok and m._cmd_rotate(-1) and absf(angle_difference(m.squad_angle[0], a0 - deg_to_rad(15.0))) < 0.0001
	m._cmd_rotate(1)
	m.squad_order[0] = m.ORDER_RETREAT
	var a1: float = m.squad_angle[0]
	var refused: bool = not m._cmd_rotate(1) and m.squad_angle[0] == a1
	print("(е) Shift+колесо: шаг 15°, центр группы смещается не больше %.4f px, слоты уникальны, цель не менялась: %s; 24 шага возвращают угол (отклонение %.6f); при «отходе» игнорируется: %s" % [
		worst, ok and m.squad_target[0] == t0, back, refused])
	m.free()

# (ж) щит: один удар зомби по юниту спереди и сзади строя; урон 0.3 = блок, 1.0 = без блока.
func hit_from(m: Node2D, victim: int, offset: Vector2) -> float:
	var z := -1
	for i in m.count:
		if m.team[i] == 1:
			z = i
			break
	m.pos[z] = m.pos[victim] + offset
	m.cooldown[z] = 0.0
	m.hp[victim] = 3.0
	m._build_grid()
	m._update_unit(z, 1.0 / 15.0)
	var dmg: float = 3.0 - m.hp[victim]
	m.pos[z] = Vector2(100, 50)   # убрать зомби в сторону
	m.hp[victim] = 3.0
	return dmg

func test_shield() -> void:
	var m := new_main(NEW, 1, false)   # без волн: на поле есть зомби
	for i in m.count:
		if m.team[i] == 1:
			m.pos[i] = Vector2(100 + (i % 20) * 6, 20 + (i / 20) * 6)   # орда в углу, далеко от строя
	m._place_formation(0, Vector2(900, 400), Vector2(1014, 400))   # слева направо: лицом вверх
	var top := -1
	var bottom := -1
	for i in units_of(m, 0):
		m.pos[i] = slot_world(m, i)
		if top < 0 or m.pos[i].y < m.pos[top].y - 0.01 or (absf(m.pos[i].y - m.pos[top].y) <= 0.01 and absf(m.pos[i].x - 957.0) < absf(m.pos[top].x - 957.0)):
			top = i
		if bottom < 0 or m.pos[i].y > m.pos[bottom].y + 0.01 or (absf(m.pos[i].y - m.pos[bottom].y) <= 0.01 and absf(m.pos[i].x - 957.0) < absf(m.pos[bottom].x - 957.0)):
			bottom = i
	var up := Vector2(0, -5)
	var r1 := [hit_from(m, top, up), hit_from(m, bottom, -up)]
	m._select_only(0)
	m._cmd_about_face()
	var r2 := [hit_from(m, top, up), hit_from(m, bottom, -up)]
	var ok: bool = is_equal_approx(r1[0], 0.3) and is_equal_approx(r1[1], 1.0) and is_equal_approx(r2[0], 1.0) and is_equal_approx(r2[1], 0.3)
	print("(ж) щит: лицом вверх — удар сверху (спереди) %.1f, снизу (сзади) %.1f; после F — сверху %.1f, снизу %.1f; блок 0.3 только из переднего сектора: %s" % [r1[0], r1[1], r2[0], r2[1], ok])
	m.free()

func test_ring() -> void:
	var m := new_main(NEW, 1, true)
	m._select_only(1)
	var arch: float = m._range_ring_radius(m.sel_primary)
	m._select_only(0)
	var inf: float = m._range_ring_radius(m.sel_primary)
	m._cmd_new_squad()
	var empty: float = m._range_ring_radius(m.sel_primary)
	print("(з) кольцо дальности: у выбранных лучников радиус %.0f, у пехоты %.0f, у пустого отряда %.0f" % [arch, inf, empty])
	m.free()

func compare(waves: bool) -> String:
	var a := new_main(OLD, 1, waves)
	var b := new_main(NEW, 1, waves)
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
			if a.count != b.count or a.gate_hp != b.gate_hp or a.gold != b.gold:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.unit_slot_idx[i] != b.unit_slot_idx[i]:
						first = t
						break
				for s in a.SQUAD_MAX:
					if a.squad_angle[s] != b.squad_angle[s] or a.squad_pos[s] != b.squad_pos[s]:
						first = t
	var res := ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first) + " (юнитов %d, волна %d)" % [b.count, b.wave_number]
	a.free()
	b.free()
	return res

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	test_geometry()
	test_about_face()
	test_angle_stable()
	test_rotate()
	test_shield()
	test_ring()
	print("(и) без новых команд против bak29, waves off: " + compare(false))
	print("    то же с волнами и покупками: " + compare(true))
	quit()
