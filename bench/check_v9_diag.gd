extends SceneTree
# Диагностика: развороты и угол обоих отрядов; (в) с целью строго от противника; форма через 1 с после 80 живых.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0]
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	var prev := [m.squad_angle[0], m.squad_angle[1]]
	var flips := [0, 0]
	var flip_log := []
	var ref1 := 0.0
	var turns := 0
	var max_dev := 0.0
	var over := false
	var ev := 25 * 30
	var flips1_after := 0
	for t in range(1, 60 * 30 + 1):
		if mode == "away" and t == ev:
			var away: Vector2 = (m.squad_pos[0] - m.squad_pos[1]).normalized()
			m.squad_target[0] = m.squad_pos[0] + away * 150.0
			ref1 = m.squad_angle[1]
			print("t=25 с: угол отряда 0 = %.2f, цель отряда 0 = %s (от зомби), живых в отряде 1 = %d" % [m.squad_angle[0], m.squad_target[0].round(), m.alive_count(1) if m.has_method("alive_count") else -1])
		m._physics_process(1.0 / 30.0)
		for s in 2:
			if absf(angle_difference(prev[s], m.squad_angle[s])) > 2.0:
				flips[s] += 1
				if flip_log.size() < 8:
					flip_log.append("отряд %d на %.1f с" % [s, t / 30.0])
				if s == 1 and mode == "away" and t > ev and t <= ev + 150:
					flips1_after += 1
			prev[s] = m.squad_angle[s]
		if mode == "away" and t > ev and t <= ev + 150:
			var dev := absf(angle_difference(ref1, m.squad_angle[1]))
			max_dev = maxf(max_dev, dev)
			if dev > 0.3 and not over:
				turns += 1
			over = dev > 0.3
		if t % 300 == 0:
			print("t=%2d с  угол отряда 0 = %.2f, |squad_pos[0] - squad_target[0]| = %.1f px" % [t / 30, m.squad_angle[0], m.squad_pos[0].distance_to(m.squad_target[0])])
	print("разворотов «кругом» за 60 с: отряд 0 = %d, отряд 1 = %d; первые: %s" % [flips[0], flips[1], flip_log])
	if mode == "away":
		print("(в) отряд 1 за 5 с после приказа: отклонений угла > 0.3 рад: %d (max %.3f рад), разворотов: %d" % [turns, max_dev, flips1_after])
	m.free()
	quit()