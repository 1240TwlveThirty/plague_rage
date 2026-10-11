extends SceneTree
func _initialize() -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	var s: RefCounted = load("res://bench/old/sim_c.gd").new()
	s.setup(m.UNIT_COUNT, 1)
	s.pos = m.pos.duplicate()   # одинаковый старт без случайного сдвига
	for t in 600:
		m._physics_process(1.0 / 30.0)
		s.tick(1.0 / 30.0)
	print("count main=%d bench=%d same_pos=%s same_hp=%s" % [m.count, s.count, m.pos == s.pos, m.hp == s.hp])
	m.free()
	quit()