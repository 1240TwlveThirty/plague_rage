extends SceneTree
# Замеры времени: (1) H1 — копия prev_pos за тик и _process с lerp; (2) время одного назначения слотов при 1500 юнитах.
func med(a: PackedFloat64Array) -> float:
	a.sort()
	return a[a.size() / 2]

func process_cost(path: String, ticks: int) -> Array:
	var m: Node2D = load(path).new()
	m._setup_data()
	m._setup_rendering()
	m._setup_fps_label()
	var pt := PackedFloat64Array()
	for t in ticks:
		m._physics_process(1.0 / 30.0)
		var t0 := Time.get_ticks_usec()
		m._process(0.004)
		pt.append((Time.get_ticks_usec() - t0) / 1000.0)
	var copy_ms: float = (m.bench_copy_us / 1000.0 / ticks) if "bench_copy_us" in m else 0.0
	var n: int = m.count
	m.free()
	return [med(pt), copy_ms, n]

func assign_cost(path: String, fn: String) -> float:
	var res := PackedFloat64Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for r in 7:
		var m: Node2D = load(path).new()
		m._setup_data()
		var killed := 0
		while killed < 150:   # 10% потерь: перестройке есть что делать
			var i := rng.randi_range(0, m.count - 1)
			if m.unit_squad[i] == 0:
				m.hp[i] = 0.0
				m._remove_dead()
				killed += 1
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.pos[i] += Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var t0 := Time.get_ticks_usec()
		m.call(fn, 0)
		res.append((Time.get_ticks_usec() - t0) / 1000.0)
		m.free()
	return med(res)

func _initialize() -> void:
	for n in ["", "_3000"]:
		var b := process_cost("res://bench/main_v16_base%s.gd" % n, 300)
		var h := process_cost("res://bench/main_h1%s.gd" % n, 300)
		print("H1, %d юнитов: _process медиана %.3f мс (база) → %.3f мс (lerp); копия prev_pos %.3f мс за физический тик" % [h[2] if n == "" else 3000, b[0], h[0], h[1]])
	print("назначение слотов, отряд 1350 юнитов (1500 − 10%%), медиана 7 замеров:")
	print("  база _compact_squad: %.2f мс" % assign_cost("res://bench/old/main_v16_base_3000.gd", "_compact_squad"))
	print("  база _reflow_squad:  %.2f мс" % assign_cost("res://bench/old/main_v16_base_3000.gd", "_reflow_squad"))
	print("  H2' _assign_slots:   %.2f мс" % assign_cost("res://bench/old/main_h2_3000.gd", "_assign_slots"))
	quit()