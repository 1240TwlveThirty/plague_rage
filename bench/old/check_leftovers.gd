extends SceneTree
func _initialize() -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	for t in 60 * 30:
		m._physics_process(1.0 / 30.0)
	# колонка в мировых координатах: у отряда 1 (угол PI) колонки зеркальны
	for s in 2:
		var cols := []
		for i in m.count:
			if m.unit_squad[i] == s:
				var k: int = m.unit_slot_idx[i]
				var c: int = k % 20
				cols.append(c if s == 0 else 19 - c)
		cols.sort()
		print("отряд %d, колонки выживших (в одной системе, сверху вниз): %s" % [s, cols])
	var best := INF
	for i in m.count:
		for j in m.count:
			if m.team[i] != m.team[j]:
				best = minf(best, m.pos[i].distance_to(m.pos[j]))
	print("минимальное расстояние между врагами: %.1f px (VIEW_RANGE = %.0f)" % [best, m.VIEW_RANGE])
	m.free()
	quit()