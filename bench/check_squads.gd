extends SceneTree
# Headless-РїСЂРѕРіРѕРЅ main.gd: 20 СЃ СЃРёРјСѓР»СЏС†РёРё Р±РµР· РєР»РёРєР°, РѕС‚С‡С‘С‚ РєР°Р¶РґС‹Рµ 2 СЃ.
func _initialize() -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	var field: Vector2 = m.FIELD
	var out_total := 0
	for t in range(1, int(OS.get_cmdline_user_args()[0]) * 30 + 1 if OS.get_cmdline_user_args().size() > 0 else 601):
		m._physics_process(1.0 / 30.0)
		var out := 0
		for i in m.count:
			var p: Vector2 = m.pos[i]
			if p.x < 0.0 or p.y < 0.0 or p.x > field.x or p.y > field.y:
				out += 1
		out_total += out
		if t % 60 == 0:
			var a := [0, 0]
			for i in m.count:
				a[m.team[i]] += 1
			var gap: float = m.squad_pos[0].distance_to(m.squad_pos[1])
			print("t=%2d s  team0=%d team1=%d  out_of_field=%d  squad0=%s squad1=%s  squad_dist=%.1f" % [t / 30, a[0], a[1], out, m.squad_pos[0].round(), m.squad_pos[1].round(), gap])
	print("out_of_field (СЃСѓРјРјР° РїРѕ РІСЃРµРј С‚РёРєР°Рј) = %d" % out_total)
	m.free()
	quit()