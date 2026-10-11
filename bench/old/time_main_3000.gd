extends SceneTree
# Время тика main.gd на 3000 юнитах: <old|new>. 60 с, плотная фаза = живых >= 50%.
func _initialize() -> void:
	var v := OS.get_cmdline_user_args()[0]
	var m: Node2D = load("res://bench/main_%s_3000.gd" % v).new()
	m._setup_data()
	var n: int = m.count
	var dense := PackedFloat64Array()
	var all_ms := 0.0
	for t in 1800:
		var is_dense: bool = m.count * 2 >= n
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		all_ms += ms
		if is_dense:
			dense.append(ms)
	var mean := 0.0
	for x in dense:
		mean += x
	mean /= dense.size()
	dense.sort()
	print("%s,%d,%.3f,%.3f,%.3f,%.3f,%d" % [v, dense.size(), mean, dense[ceili(dense.size() * 0.99) - 1], dense[dense.size() - 1], all_ms / 1800.0, m.count])
	m.free()
	quit()