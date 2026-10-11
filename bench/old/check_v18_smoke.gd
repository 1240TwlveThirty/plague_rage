extends SceneTree
func _initialize() -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	# перекрытие строёв на старте: минимальное расстояние лучник — пехотинец
	var dmin := INF
	var amin_x := INF
	var imax_x := -INF
	for i in m.count:
		if m.unit_squad[i] == 1:
			amin_x = minf(amin_x, m.pos[i].x)
			for j in m.count:
				if m.unit_squad[j] == 0:
					dmin = minf(dmin, m.pos[i].distance_to(m.pos[j]))
		if m.unit_squad[i] == 0:
			imax_x = maxf(imax_x, -m.pos[i].x)
	var inf_back := INF
	var arc_front := -INF
	for i in m.count:
		if m.unit_squad[i] == 0:
			inf_back = minf(inf_back, m.pos[i].x)
		if m.unit_squad[i] == 1:
			arc_front = maxf(arc_front, m.pos[i].x)
	print("старт: пехота %s (задний ряд x=%.0f), лучники %s (передний ряд x=%.0f), отряд лучников %dx%d; min расстояние лучник–пехотинец %.1f px" % [
		m.squad_pos[0].round(), inf_back, m.squad_pos[1].round(), arc_front, m.squad_width[1], m.squad_rows[1], dmin])
	for t in range(1, 60 * 30 + 1):
		m._physics_process(1.0 / 30.0)
		if t % 90 == 0:
			var c := [0, 0, 0]
			for i in m.count:
				c[2 if m.team[i] == 1 else m.unit_squad[i]] += 1
			print("t=%2d с  пехота %3d  лучники %3d  зомби %3d | режим %s, стрел %d, попаданий %d, в полёте %d, смен режима %d" % [
				t / 30, c[0], c[1], c[2], "одиночный" if m.squad_volley_mode[1] == 1 else "залп", m.arrows_fired, m.arrows_hit, m.arrow_count, m.mode_switches])
			if c[2] == 0 or c[0] + c[1] == 0:
				break
	m.free()
	quit()