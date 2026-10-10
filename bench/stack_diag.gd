extends SceneTree
# stack_diag: лазейка «много отрядов лучников в одном квадрате». Аргументы: old | new | both.
# old — bench/main_stack30_old.gd (копия bak30), new — bench/main_stack30_new.gd (после правок);
# в обеих копиях SQUAD_MAX = 12, чтобы собрать 10 отрядов лучников (в игре предел 8 отрядов).
# both пишет bench/stack_diag.txt.
const P := Vector2(1032, 630)            # центр стопки
const TARGETS := [["ближняя", Vector2(1032, 552)], ["средняя", Vector2(1080, 552)], ["дальняя", Vector2(1032, 504)]]   # центры грубых клеток

func new_main(v: String) -> Node2D:
	var m: Node2D = load("res://bench/main_stack30_%s.gd" % v).new()
	m.spawn_seed = 1
	m.waves_enabled = true
	m.record_path = "user://record_bench.json"
	m._setup_data()
	# пехота в стороне, чтобы не мешала
	m.squad_pos[0] = Vector2(300, 300)
	m.squad_target[0] = m.squad_pos[0]
	teleport(m, 0)
	return m

func slot_world(m: Node2D, i: int) -> Vector2:
	var s: int = m.unit_squad[i]
	return m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])

func teleport(m: Node2D, s: int) -> void:
	for i in m.count:
		if m.unit_squad[i] == s:
			m.pos[i] = slot_world(m, i)
			m.prev_pos[i] = m.pos[i]

# Лучники: squads отрядов по per юнитов, строй шириной width (5 × 5 для 25). Возвращает индексы отрядов.
func build(m: Node2D, squads: int, per: int, width: int) -> Array:
	var ids := []
	for i in m.count:
		if m.unit_squad[i] == 1:
			ids.append(i)
	if per < ids.size():
		for q in range(per, ids.size()):
			m.hp[ids[q]] = 0.0
		m._remove_dead()
		m._update_squads(0.6)
	elif per > ids.size():
		m._squad_add_units(1, m.archer_type, per - ids.size())
	var out := [1]
	for k in squads - 1:
		var s: int = m._squad_create(1)
		m._squad_add_units(s, m.archer_type, per)
		out.append(s)
	for s in out:
		m.squad_user_width[s] = width
		m._reflow_squad(s)
	return out

# Все отряды в одну точку (spread = 0) или в точки в пределах spread px; юниты сразу в слотах.
func stack(m: Node2D, squads: Array, spread: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for s in squads:
		var off := Vector2.ZERO
		if spread > 0.0:
			off = Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
		m.squad_angle[s] = -PI / 2.0
		m.squad_pos[s] = P + off
		m.squad_target[s] = P + off
		teleport(m, s)
	# разброс ±1.5 px, как в сериях боёв: при точном совпадении позиций отталкивание не срабатывает совсем (d2 > 0.0001)
	for i in m.count:
		if m.unit_type[i] == m.archer_type:
			m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))

func archers(m: Node2D) -> Array:
	var r := []
	for i in m.count:
		if m.unit_type[i] == m.archer_type:
			r.append(i)
	return r

# После 10 с без врагов: мин. расстояние между юнитами разных отрядов, пар ближе MIN_DIST, площадь прямоугольника.
func settle(m: Node2D) -> Dictionary:
	for t in 300:
		m._physics_process(1.0 / 30.0)
	var ids := archers(m)
	var dmin := INF
	var close := 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for a in ids.size():
		var pa: Vector2 = m.pos[ids[a]]
		lo = lo.min(pa)
		hi = hi.max(pa)
		for b in range(a + 1, ids.size()):
			if m.unit_squad[ids[a]] != m.unit_squad[ids[b]]:
				var d: float = pa.distance_to(m.pos[ids[b]])
				dmin = minf(dmin, d)
				if d < m.MIN_DIST:
					close += 1
	return {"n": ids.size(), "dmin": dmin, "close": close, "size": hi - lo, "area": (hi.x - lo.x) * (hi.y - lo.y)}

func in_range(m: Node2D, target: Vector2) -> int:
	var n := 0
	for i in archers(m):
		if m.pos[i].distance_to(target) <= m.type_range_far[m.archer_type]:
			n += 1
	return n

# 30 неподвижных бессмертных зомби в точке target; 8 с стрельбы. Возвращает [выпущено, вне дальности, попало, залпов на отряд].
func shoot(m: Node2D, squads: Array, target: Vector2) -> Array:
	m.type_speed[m.zombie_type] = 0.0
	for k in 30:
		m._spawn_zombie(target + Vector2((k % 6 - 2.5) * 5.0, (k / 6 - 2.0) * 5.0))
		m.hp[m.count - 1] = 1000000.0
	m.arrows_fired = 0
	m.arrows_hit = 0
	if "arrows_out_of_range" in m:
		m.arrows_out_of_range = 0
	for s in squads:
		m.squad_volley_t[s] = 0.0
		m.squad_volley_fired[s] = 0
		m.squad_volley_mode[s] = m.MODE_VOLLEY
	var volleys := 0
	var prev: int = m.squad_volley_fired[squads[0]]
	for t in 240:
		m._physics_process(1.0 / 30.0)
		if m.squad_volley_fired[squads[0]] == 1 and prev == 0:
			volleys += 1
		prev = m.squad_volley_fired[squads[0]]
	return [m.arrows_fired, m.arrows_out_of_range if "arrows_out_of_range" in m else 0, m.arrows_hit, volleys]

func report(v: String) -> Array[String]:
	var L: Array[String] = []
	var rf := 130.0
	# 1.2: два отряда по 25 в одной точке
	var m := new_main(v)
	var two := build(m, 2, 25, 5)
	stack(m, two, 0.0)
	var r := settle(m)
	L.append("  1.2. два отряда по 25 (5 × 5) с одной целью, 10 с: мин. расстояние между юнитами разных отрядов %.2f px, пар ближе MIN_DIST (5 px): %d, прямоугольник %.0f × %.0f px = %.0f px² (один блок 5 × 5 по слотам: 24 × 24 = 576 px²)" % [
		r.dmin, r.close, r.size.x, r.size.y, r.area])
	m.free()
	# 1.3: 10 отрядов по 25 в одной точке / в пределах 20 px / один блок 250 (16 × 16)
	for mode in ["10 отрядов по 25, цель в одной точке", "10 отрядов по 25, цели в пределах 20 px", "один блок 250 той же формы (16 × 16)"]:
		var rows := []
		var st := {}
		for tg in TARGETS:
			var mm := new_main(v)
			var squads: Array
			if mode.begins_with("один"):
				squads = build(mm, 1, 250, 16)
				stack(mm, squads, 0.0)
			else:
				squads = build(mm, 10, 25, 5)
				stack(mm, squads, 20.0 if mode.contains("20 px") else 0.0)
			st = settle(mm)
			var reach := in_range(mm, tg[1])
			var sh := shoot(mm, squads, tg[1])
			rows.append("      %s цель (%.0f px от центра): достают по своей позиции %d из %d; за 8 с залпов %d, выпущено %d (на залп %.0f из %d), вне дальности %d, попало %d" % [
				tg[0], P.distance_to(tg[1]), reach, st.n, sh[3], sh[0], sh[0] / float(maxi(sh[3], 1)), st.n, sh[1], sh[2]])
			mm.free()
		L.append("  1.3. %s: после 10 с прямоугольник %.0f × %.0f px = %.0f px², мин. расстояние между юнитами разных отрядов %s, пар ближе 5 px: %d" % [
			mode, st.size.x, st.size.y, st.area, "—" if is_inf(st.dmin) else "%.2f px" % st.dmin, st.close])
		L.append_array(rows)
	return L

func _initialize() -> void:
	var arg := OS.get_cmdline_user_args()[0]
	var lines: Array[String] = []
	lines.append("stack_diag: лазейка «много отрядов лучников в одном квадрате». Центр стопки %s, range_far 130 px, цели — центры грубых клеток (48 px)." % P)
	lines.append("В игре предел 8 отрядов (7 отрядов лучников); для 10 отрядов в копиях bench/main_stack30_*.gd SQUAD_MAX = 12.")
	lines.append("Отряды поставлены в одну точку напрямую (squad_pos = squad_target), как обычным кликом; юниты стартуют из слотов с разбросом ±1.5 px (при точном совпадении позиций отталкивание не срабатывает вовсе).")
	lines.append("")
	for v in (["old", "new"] if arg == "both" else [arg]):
		lines.append("ДО правок (копия bak30):" if v == "old" else "ПОСЛЕ правок:")
		lines.append_array(report(v))
		lines.append("")
	for l in lines:
		print(l)
	if arg == "both":
		var f := FileAccess.open("res://bench/stack_diag.txt", FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	quit()
