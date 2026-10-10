extends SceneTree
# v20: (а) детерминизм, (в) дымовой тест 60 с, (д) размеры массивов сеток.
func smoke(label: String, no_player: bool) -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	if no_player:
		for i in m.count:
			if m.team[i] == 0:
				m.hp[i] = 0.0
		m._remove_dead()
		m.squad_dirty.fill(0)
		m.first_death_tick = -1
	var field: Vector2 = m.FIELD
	var wall: float = m.WALL_Y
	var bad := 0
	var bad_wall := 0
	var last_death := -1
	var freezes := []
	var gate_first := -1.0
	var line := ""
	var front_y := INF
	var zfront := -INF
	for i in m.count:
		if m.unit_squad[i] == 0:
			front_y = minf(front_y, m.pos[i].y)
		if m.team[i] == 1:
			zfront = maxf(zfront, m.pos[i].y)
	print("== %s: старт — передний ряд пехоты y=%.0f, передний край зомби y=%.0f (до контакта %.0f px); центр пехоты %s, лучников %s" % [
		label, front_y, zfront, front_y - zfront, m.squad_pos[0].round(), m.squad_pos[1].round()])
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		var a := [0, 0]
		var at_gate := 0
		for i in m.count:
			a[m.team[i]] += 1
			var p: Vector2 = m.pos[i]
			if p.x < 0.0 or p.y < 0.0 or p.x > field.x or p.y > field.y:
				bad += 1
			if p.y > wall + 0.001:
				bad_wall += 1
			if m.team[i] == 1 and p.distance_to(m.GATE_POS) <= 20.0:
				at_gate += 1
		if gate_first < 0.0 and at_gate > 0:
			gate_first = t / 30.0
		if m.count < before:
			if last_death > 0 and t - last_death >= 90 and a[0] > 0 and a[1] > 0:
				freezes.append("%.1f–%.1f с" % [last_death / 30.0, t / 30.0])
			last_death = t
		if t % 150 == 0:
			line += "  %dс %d:%d(у ворот %d)" % [t / 30, a[0], a[1], at_gate]
		if t == 1800:
			print(line)
			print("   вне FIELD: %d юнито-тиков, ниже WALL_Y: %d; первый зомби у ворот (<=20 px): %s; паузы >= 3 с посреди боя: %s; в конце у ворот %d зомби, живых %d:%d; стрел %d/%d" % [
				bad, bad_wall, "%.1f с" % gate_first if gate_first >= 0.0 else "нет", "нет" if freezes.is_empty() else ", ".join(freezes),
				at_gate, a[0], a[1], m.arrows_fired, m.arrows_hit])
	m.free()

func _initialize() -> void:
	# (д) размеры
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	var ok: bool = m.cell_start.size() == m.CELL_COUNT + 1 and m.cursor.size() == m.CELL_COUNT and m.CELL_COUNT == 184 * 88 \
		and m.coarse_zcount.size() == m.COARSE_COUNT and m.coarse_sum.size() == m.COARSE_COUNT and m.coarse_start.size() == m.COARSE_COUNT + 1 \
		and m.coarse_cursor.size() == m.COARSE_COUNT and m.COARSE_W == 46 and m.COARSE_H == 22
	var cover: bool = m.COARSE_W * m.COARSE_SIZE >= m.FIELD.x and m.COARSE_H * m.COARSE_SIZE >= m.FIELD.y
	print("(д) FIELD %s; мелкая сетка %dx%d = %d клеток, cell_start %d, cursor %d; грубая %dx%d = %d, coarse_start %d; покрытие поля грубой сеткой: %s — %s" % [
		m.FIELD, m.GRID_W, m.GRID_H, m.CELL_COUNT, m.cell_start.size(), m.cursor.size(), m.COARSE_W, m.COARSE_H, m.COARSE_COUNT, m.coarse_start.size(), cover, "OK" if ok and cover else "FAIL"])
	m.free()
	# (а) детерминизм
	var a: Node2D = load("res://scripts/main.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a.spawn_seed = 7
	b.spawn_seed = 7
	a._setup_data()
	b._setup_data()
	var first := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp or a.arrows_hit != b.arrows_hit):
			first = t
	print("(а) детерминизм 30 с, seed 7: " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first))
	a.free()
	b.free()
	# (в) дымовой
	smoke("бой 300+100 против 300", false)
	smoke("орда без игрока (дойдут ли до ворот)", true)
	quit()