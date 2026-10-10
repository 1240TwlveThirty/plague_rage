extends SceneTree
# Headless-прогон main.gd. Аргументы: <секунд> [секунда_клика x y]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 40
	var click_tick := int(args[1]) * 30 if args.size() > 3 else -1
	var click_pos := Vector2(float(args[2]), float(args[3])) if args.size() > 3 else Vector2.ZERO
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	var field: Vector2 = m.FIELD
	var max_ms := 0.0
	var edge_max := 0
	var first_death := -1.0
	for t in range(1, secs * 30 + 1):
		if t == click_tick:
			m.squad_target[0] = click_pos
			print("  -- t=%.1f s: отряд 0 получил цель %s" % [t / 30.0, click_pos])
		var before: int = m.count
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		max_ms = maxf(max_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		if first_death < 0.0 and m.count < before:
			first_death = t / 30.0
		var edge := 0
		for i in m.count:
			var p: Vector2 = m.pos[i]
			if p.x <= 0.0 or p.y <= 0.0 or p.x >= field.x or p.y >= field.y:
				edge += 1
		edge_max = maxi(edge_max, edge)
		if t % 60 == 0:
			var a := [0, 0]
			for i in m.count:
				a[m.team[i]] += 1
			print("t=%2d s  team0=%3d team1=%3d  у края=%d  squad0=%s squad1=%s" % [t / 30, a[0], a[1], edge, m.squad_pos[0].round(), m.squad_pos[1].round()])
	print("first_death=%.2f s  max_tick=%.2f ms  max_units_at_edge=%d" % [first_death, max_ms, edge_max])
	m.free()
	quit()