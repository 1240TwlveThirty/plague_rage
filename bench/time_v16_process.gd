extends SceneTree
func med(a: PackedFloat64Array) -> float:
	a.sort()
	return a[a.size() / 2]

func cost(path: String, mode: int) -> float:
	var m: Node2D = load(path).new()
	m._setup_data()
	m._setup_rendering()
	m._setup_fps_label()
	if mode >= 0:
		m.color_mode = mode
	var pt := PackedFloat64Array()
	for t in 300:
		m._physics_process(1.0 / 30.0)
		var t0 := Time.get_ticks_usec()
		m._process(0.004)
		pt.append((Time.get_ticks_usec() - t0) / 1000.0)
	m.free()
	return med(pt)

func _initialize() -> void:
	print("_process, 3000 юнитов, медиана 300 кадров:")
	print("  bak16 (цвет по команде, встроенный): %.3f мс" % cost("res://bench/main_bak16_3000.gd", -1))
	for mode in 4:
		print("  текущий main, режим F%d: %.3f мс" % [mode + 1, cost("res://bench/main_v16_base_3000.gd", mode)])
	quit()