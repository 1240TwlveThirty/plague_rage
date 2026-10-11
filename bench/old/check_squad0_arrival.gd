extends SceneTree
# Отряд 0 получает цель как от клика; смотрим, не крутится ли он после прибытия (stop_dist = 0).
func _initialize() -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	m.squad_target[0] = Vector2(450.0, 380.0)
	var flips := 0
	var prev_angle: float = m.squad_angle[0]
	for t in range(1, 451):
		m._physics_process(1.0 / 30.0)
		var a: float = m.squad_angle[0]
		if absf(angle_difference(prev_angle, a)) > 1.0:
			flips += 1
		prev_angle = a
		if t % 60 == 0 or t > 440:
			print("t=%5.2f s squad0=%s angle=%.4f dist_to_target=%.6f" % [t / 30.0, m.squad_pos[0], a, m.squad_pos[0].distance_to(m.squad_target[0])])
	print("разворотов «кругом» (скачок угла > 1 рад): %d" % flips)
	m.free()
	quit()