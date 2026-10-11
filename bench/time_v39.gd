extends SceneTree
# Тик на 3000 юнитов, синтетика (v39): <main_*_3000.gd>. Без волн, 600 тиков; медиана и среднее тика, мс.
func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var m: Node2D = load(OS.get_cmdline_user_args()[0]).new()
	m.spawn_seed = 1
	m.waves_enabled = false
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var n: int = m.count
	var ms := PackedFloat64Array()
	var sum := 0.0
	for t in 600:
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		sum += ms[t]
	ms.sort()
	print("SYN|%d|%d|%.3f|%.3f" % [n, m.count, ms[300], sum / 600.0])
	m.free()
	quit()
