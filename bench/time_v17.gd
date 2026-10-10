extends SceneTree
# Время физического тика (плотная фаза: живых >= 50%) и _process на кадр, 3000 юнитов, 60 с.
# Аргумент: <old|new>. Вывод: variant,dense_mean,dense_p99,dense_max,all_mean,process_median,process_p99
func _initialize() -> void:
	var v := OS.get_cmdline_user_args()[0]
	var path := "res://bench/main_bak17_3000.gd" if v == "old" else "res://bench/main_v17_3000.gd"
	var m: Node2D = load(path).new()
	m._setup_data()
	m._setup_rendering()
	m._setup_fps_label()
	var n0: int = m.count
	var dense := PackedFloat64Array()
	var proc := PackedFloat64Array()
	var all_ms := 0.0
	for t in 1800:
		var is_dense: bool = m.count * 2 >= n0
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		all_ms += ms
		if is_dense:
			dense.append(ms)
		var t1 := Time.get_ticks_usec()
		m._process(0.004)
		proc.append((Time.get_ticks_usec() - t1) / 1000.0)
	var mean := 0.0
	for x in dense:
		mean += x
	mean /= dense.size()
	dense.sort()
	proc.sort()
	print("%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [v, mean, dense[ceili(dense.size() * 0.99) - 1], dense[dense.size() - 1], all_ms / 1800.0, proc[proc.size() / 2], proc[ceili(proc.size() * 0.99) - 1]])
	m.free()
	quit()