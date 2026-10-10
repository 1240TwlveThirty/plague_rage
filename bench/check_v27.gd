extends SceneTree
# Тесты v27 (расстановка перетаскиванием): (а) геометрия, (б) пересечения путей, (в) потери, (г) детерминизм,
# (д) регрессия против bak27, (ж) время раздачи слотов на 1400 юнитах.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/main_bak27.gd"

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

func squad_n(m: Node2D, s: int) -> int:
	var n := 0
	for i in m.count:
		if m.unit_squad[i] == s:
			n += 1
	return n

# Сетка отряда: слоты уникальны, в каждой колонке ряды 0..h-1 без дыр, глубины колонок отличаются не больше чем на 1.
# Возвращает число занятых колонок или -1.
func grid_ok(m: Node2D, s: int) -> int:
	var width: int = m.squad_width[s]
	var seen := {}
	var heights := {}
	var top := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			var k: int = m.unit_slot_idx[i]
			if seen.has(k):
				return -1
			seen[k] = true
			var col := k % width
			heights[col] = heights.get(col, 0) + 1
			top[col] = maxi(top.get(col, 0), k / width)
	var lo := 1 << 30
	var hi := 0
	for col in heights:
		if top[col] != heights[col] - 1:
			return -1
		lo = mini(lo, heights[col])
		hi = maxi(hi, heights[col])
	if hi - lo > 1 or hi > m.squad_rows[s]:
		return -1
	return heights.size()

func in_bounds(m: Node2D, s: int) -> bool:
	for i in m.count:
		if m.unit_squad[i] == s:
			var p := slot_world(m, i)
			if p.x < -0.01 or p.x > m.FIELD.x + 0.01 or p.y < -0.01 or p.y > m.WALL_Y - 12.0 + 0.01:
				return false
	return true

func checksum(m: Node2D) -> Vector2:
	var c := Vector2.ZERO
	for i in m.count:
		c += m.pos[i] * (1.0 + (i % 7)) + Vector2(m.hp[i], m.count)
	for s in m.squad_count:
		c += m.squad_pos[s] + Vector2(m.squad_angle[s], m.squad_width[s])
	return c

func test_geometry() -> void:
	var m300 := new_main(NEW, 1, true)
	var m1400 := new_main(NEW, 1, true)
	m1400._squad_add_units(0, m1400.infantry_type, 1100)
	var cases := [[m300, 1], [m300, 0], [m1400, 0]]
	var total := 0
	var bad := []
	var unshifted := 0
	var stretched := 0
	for c in cases:
		var m: Node2D = c[0]
		var s: int = c[1]
		var n := squad_n(m, s)
		for length in [60.0, 200.0, 700.0]:
			for k in 8:
				var dir := Vector2.from_angle(k * PI / 4.0)
				var base := Vector2(1100, 366)
				m.squad_pos[s] = base
				var mid := base + dir * 150.0
				var axis := dir.orthogonal()
				var a: Vector2 = mid - axis * length * 0.5
				var b: Vector2 = mid + axis * length * 0.5
				var g: Dictionary = m._formation_geometry(s, a, b)
				m._place_formation(s, a, b)
				var want := roundi(length / m.SLOT_SPACING) + 1
				var user_w := clampi(want, ceili(n / float(m.ROWS_MAX)), m.WIDTH_MAX)
				var w := mini(user_w, n)
				var rows := ceili(n / float(w))
				var ok: bool = m.squad_width[s] == w and m.squad_rows[s] == rows and m.squad_user_width[s] == user_w
				ok = ok and absf(angle_difference(m.squad_angle[s], dir.angle())) < 0.0001
				ok = ok and grid_ok(m, s) == w and in_bounds(m, s)
				ok = ok and m.squad_target[s] == m.squad_pos[s]
				var shifted: bool = g.front.distance_to(mid) > 0.01
				if not shifted:
					unshifted += 1
					ok = ok and g.adjusted == (user_w > want)
					var sum := Vector2.ZERO
					var front_n := 0
					for i in m.count:
						if m.unit_squad[i] == s and m.unit_slot_idx[i] / w == 0:
							var p := slot_world(m, i)
							sum += p
							front_n += 1
							ok = ok and absf((p - a).dot(dir)) <= 0.5   # расстояние до прямой AB
					ok = ok and front_n == w and (sum / front_n).distance_to(mid) <= 0.5
				if user_w > want:
					stretched += 1
				total += 1
				if not ok:
					bad.append("n=%d L=%d угол %d°" % [n, int(length), k * 45])
	print("(а) геометрия: %d случаев (n 100/300/1400 × линии 60/200/700 × 8 сторон), без сдвига %d, растянутых %d, ошибок %d %s" % [
		total, unshifted, stretched, bad.size(), bad])
	# У края поля: строй обязан сдвинуться внутрь (контур красный), слоты в поле и не ниже WALL_Y - 12.
	var edge := [
		[Vector2(1100, 740), Vector2(900, 700), Vector2(1300, 700), "низ, лицом вверх"],
		[Vector2(5, 400), Vector2(20, 300), Vector2(20, 500), "левый край, лицом вправо"],
		[Vector2(1100, 2), Vector2(900, 10), Vector2(1300, 10), "верх, лицом вниз"],
		[Vector2(2206, 400), Vector2(2198, 250), Vector2(2198, 550), "правый край, лицом влево"],
		[Vector2(2300, 800), Vector2(2100, 720), Vector2(2190, 630), "правый нижний угол, диагональ"]]
	var edge_bad := []
	for e in edge:
		m1400.squad_pos[0] = e[0]
		var g: Dictionary = m1400._formation_geometry(0, e[1], e[2])
		m1400._place_formation(0, e[1], e[2])
		if not (g.adjusted and in_bounds(m1400, 0) and grid_ok(m1400, 0) == m1400.squad_width[0]):
			edge_bad.append(e[3])
	print("    у края (n=1400, 5 случаев: низ, лево, верх, право, угол): сдвинут внутрь, слоты в поле, сетка цела; ошибок %d %s" % [edge_bad.size(), edge_bad])
	m300.free()
	m1400.free()

# Доля пересечений путей (5000 случайных пар) и суммарный путь позиция -> слот для отряда s.
func paths(m: Node2D, s: int) -> Array:
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	var total := 0.0
	for i in m.count:
		if m.unit_squad[i] == s:
			from.append(m.pos[i])
			to.append(slot_world(m, i))
			total += m.pos[i].distance_to(slot_world(m, i))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var cross := 0
	for q in 5000:
		var i := rng.randi_range(0, from.size() - 1)
		var j := rng.randi_range(0, from.size() - 2)
		if j >= i:
			j += 1
		if Geometry2D.segment_intersects_segment(from[i], to[i], from[j], to[j]) != null:
			cross += 1
	return [cross / 5000.0, total]

func test_paths() -> void:
	var a := new_main(NEW, 1, true)
	var b := new_main(NEW, 1, true)
	var c: Vector2 = a.squad_pos[0]
	var p1 := c + Vector2(100, -50)
	var p2 := c + Vector2(100, 50)
	a._place_formation(0, p1, p2)
	# Прежняя раздача: та же геометрия, но слоты раздаёт _reflow_squad (колонка за колонкой по старым слотам).
	var g: Dictionary = b._formation_geometry(0, p1, p2)
	b.squad_user_width[0] = g.user_width
	b._reflow_squad(0)
	b.squad_angle[0] = g.angle
	b.squad_pos[0] = g.front + b.squad_center_off[0].rotated(g.angle)
	var ra := paths(a, 0)
	var rb := paths(b, 0)
	print("(б) пехота 300 -> линия 100 px перпендикулярно фронту, в 100 px справа (строй %d × %d): пересечений %.1f%% новая / %.1f%% прежняя; сумма путей %.0f / %.0f px" % [
		a.squad_width[0], a.squad_rows[0], ra[0] * 100.0, rb[0] * 100.0, ra[1], rb[1]])
	a.free()
	b.free()

func kill(m: Node2D, s: int, keep: int, rng: RandomNumberGenerator) -> void:
	var ids := []
	for i in m.count:
		if m.unit_squad[i] == s:
			ids.append(i)
	while ids.size() > keep:
		var q := rng.randi_range(0, ids.size() - 1)
		m.hp[ids[q]] = 0.0
		ids.remove_at(q)
	m._remove_dead()
	m._update_squads(0.6)   # сжатие и проверка перестройки (раз в 0.5 с)

func state(m: Node2D, s: int) -> String:
	return "n %d: %d × %d, занято колонок %d" % [squad_n(m, s), m.squad_width[s], m.squad_rows[s], grid_ok(m, s)]

func test_losses() -> void:
	var m := new_main(NEW, 1, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	m._place_formation(0, Vector2(900, 400), Vector2(1100, 400))   # 200 px -> ширина 34
	var w0: int = m.squad_user_width[0]
	var out := ["старт " + state(m, 0)]
	var ok := true
	kill(m, 0, 180, rng)
	out.append("потери 40% " + state(m, 0))
	ok = ok and m.squad_width[0] == w0 and grid_ok(m, 0) == w0
	# целиком выбита одна колонка
	for i in m.count:
		if m.unit_squad[i] == 0 and m.unit_slot_idx[i] % m.squad_width[0] == 5:
			m.hp[i] = 0.0
	m._remove_dead()
	m._update_squads(0.6)
	out.append("выбита колонка " + state(m, 0))
	ok = ok and m.squad_width[0] == w0 and grid_ok(m, 0) == w0
	kill(m, 0, 20, rng)
	out.append("осталось 20 " + state(m, 0))
	ok = ok and m.squad_width[0] == 20 and grid_ok(m, 0) == 20 and m.squad_rows[0] == 1
	m._squad_add_units(0, m.infantry_type, 800)
	out.append("покупка +800 " + state(m, 0))
	ok = ok and m.squad_width[0] == 41 and m.squad_rows[0] <= m.ROWS_MAX and grid_ok(m, 0) == 41 and m.squad_user_width[0] == w0
	m.squad_user_width[0] = 0   # клавиша T
	m._reflow_squad(0)
	out.append("после T и перестройки " + state(m, 0))
	var auto := maxi(ceili(sqrt(820 * 20.0 / 15.0)), ceili(820 / float(m.ROWS_MAX)))   # прежняя формула: пропорция 20/15
	ok = ok and m.squad_width[0] == auto
	print("(в) заданная ширина %d: %s" % [w0, "; ".join(out)])
	print("    ширина сохраняется, рядов не больше %d, n < ширины даёт ширину n, после T — авто (%d): %s" % [m.ROWS_MAX, auto, ok])
	m.free()

func scripted(seed: int) -> PackedVector2Array:
	var m := new_main(NEW, seed, true)
	var tr := PackedVector2Array()
	m._start_wave()
	for t in 900:
		match t:
			20:
				m._place_formation(0, Vector2(850, 560), Vector2(1150, 560))
			90:
				m._place_formation(1, Vector2(900, 640), Vector2(1120, 640))
			200:
				m._place_formation(0, Vector2(1100, 500), Vector2(1100, 620))
			400:
				m._place_formation(0, Vector2(960, 600), Vector2(1060, 610))
		m._physics_process(1.0 / 30.0)
		tr.append(checksum(m))
	tr.append(Vector2(m.wave_number, m.count))
	m.free()
	return tr

func test_determinism() -> void:
	var r1 := scripted(5)
	var r2 := scripted(5)
	var d := -1
	for k in mini(r1.size(), r2.size()):
		if r1[k] != r2[k]:
			d = k
			break
	print("(г) волна 1, 4 перетаскивания (тики 20, 90, 200, 400), 900 тиков, два прогона: %s; в конце волна %d, юнитов %d" % [
		"совпадает на каждом тике" if d < 0 and r1.size() == r2.size() else "расходится с тика %d" % d, int(r1[r1.size() - 1].x), int(r1[r1.size() - 1].y)])

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
	var res := ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first) + " (юнитов %d, волна %d)" % [b.count, b.wave_number]
	a.free()
	b.free()
	return res

func test_timing() -> void:
	var m := new_main(NEW, 1, true)
	m._squad_add_units(0, m.infantry_type, 1100)
	var ms := PackedFloat64Array()
	for q in 21:
		var t0 := Time.get_ticks_usec()
		if q % 2 == 0:
			m._place_formation(0, Vector2(800, 400), Vector2(1300, 400))
		else:
			m._place_formation(0, Vector2(1100, 200), Vector2(1100, 600))
		ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	ms.sort()
	print("(ж) раздача слотов _place_formation, %d юнитов, 21 вызов: медиана %.2f мс, максимум %.2f мс" % [squad_n(m, 0), ms[10], ms[20]])
	m.free()

func _initialize() -> void:
	test_geometry()
	test_paths()
	test_losses()
	test_determinism()
	print("(д) без перетаскиваний против bak27, waves off: " + compare(false))
	print("    то же с волнами и покупками пехоты и лучников: " + compare(true))
	test_timing()
	quit()
