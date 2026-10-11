extends SceneTree
# Только _build_grid: та же раскладка юнитов, разный размер сетки. Медиана 300 вызовов.
func cost(path: String) -> float:
	var m: Node2D = load(path).new()
	m._setup_data()
	var a := PackedFloat64Array()
	for r in 300:
		var t0 := Time.get_ticks_usec()
		m._build_grid()
		a.append((Time.get_ticks_usec() - t0) / 1000.0)
	m.free()
	a.sort()
	return a[150]

func _initialize() -> void:
	print("_build_grid, 3000 юнитов: bak20 (14620 клеток) %.3f мс; новая (16192 клетки) %.3f мс" % [cost("res://bench/old/main_bak20_3000.gd"), cost("res://bench/old/main_v20_3000.gd")])
	quit()