extends SceneTree
# Время тика на 3000 юнитах: <bak31|v31>. Копии с UNIT_COUNT = 3000, без волн; 600 тиков, плотная фаза = живых >= 50%.
func _initialize() -> void:
	var v := OS.get_cmdline_user_args()[0]
	var m: Node2D = load("res://bench/main_%s_3000.gd" % v).new()
	m.waves_enabled = false
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var n: int = m.count
	var dense := PackedFloat64Array()
	for t in 600:
		var is_dense: bool = m.count * 2 >= n
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		if is_dense:
			dense.append((Time.get_ticks_usec() - t0) / 1000.0)
	var mean := 0.0
	for x in dense:
		mean += x
	print("TIME,%s,%d,%d,%.4f,%d" % [v, n, dense.size(), mean / dense.size(), m.count])
	m.free()
	quit()
