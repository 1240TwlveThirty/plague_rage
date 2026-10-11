extends SceneTree
# Время тика (плотная фаза) и разбивка лучников, 3000 юнитов, 60 с. Аргумент: <old|new>.
func _initialize() -> void:
	var v := OS.get_cmdline_user_args()[0]
	var m: Node2D = load("res://bench/old/main_bak18_3000.gd" if v == "old" else "res://bench/old/main_v18_3000.gd").new()
	m._setup_data()
	var n0: int = m.count
	var dense := PackedFloat64Array()
	var all_ms := 0.0
	for t in 1800:
		var is_dense: bool = m.count * 2 >= n0
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
	var extra := ""
	if v == "new":
		extra = ",%.4f,%.4f,%.4f,%d,%d" % [m.bench_coarse_us / 1800000.0, m.bench_archers_us / 1800000.0, m.bench_arrows_us / 1800000.0, m.arrows_fired, m.arrows_hit]
	print("%s,%.3f,%.3f,%.3f,%.3f,%d%s" % [v, mean, dense[ceili(dense.size() * 0.99) - 1], dense[dense.size() - 1], all_ms / 1800.0, m.count, extra])
	m.free()
	quit()