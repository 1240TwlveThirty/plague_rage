extends SceneTree
# (е) Тик на пике. old: bak22, 3000 юнитов, плотная фаза (живых >= 50%), 60 с.
# new: волна 25, армия ~2950 (2650 пехоты + 300 лучников), ворота неразрушимы; тики, где юнитов >= 3000.
func _initialize() -> void:
	var v := OS.get_cmdline_user_args()[0]
	var times := PackedFloat64Array()
	var maxc := 0
	if v == "old":
		var m: Node2D = load("res://bench/main_bak22_3000.gd").new()
		m.record_path = "user://record_bench.json"
		m._setup_data()
		var n0: int = m.count
		for t in 1800:
			var dense: bool = m.count * 2 >= n0
			var t0 := Time.get_ticks_usec()
			m._physics_process(1.0 / 30.0)
			if dense:
				times.append((Time.get_ticks_usec() - t0) / 1000.0)
			maxc = maxi(maxc, m.count)
		m.free()
	else:
		var m: Node2D = load("res://scripts/main.gd").new()
		m.record_path = "user://record_bench.json"
		m._setup_data()
		m.gold = 1e12
		while m.count < 2650 + 100:
			m._buy(0)
		while m.count < 2650 + 400:
			m._buy(1)
		m.gate_hp = 1e12
		m.gate_hp_max = 1e12
		for t in 300:   # строй успевает собраться
			m._physics_process(1.0 / 30.0)
		m.wave_number = 24
		m._start_wave()
		for t in 30 * 120:
			var big: bool = m.count >= 3000
			var t0 := Time.get_ticks_usec()
			m._physics_process(1.0 / 30.0)
			if big:
				times.append((Time.get_ticks_usec() - t0) / 1000.0)
			maxc = maxi(maxc, m.count)
		m.free()
	var mean := 0.0
	for x in times:
		mean += x
	mean /= maxi(times.size(), 1)
	times.sort()
	var p99 := times[maxi(ceili(times.size() * 0.99) - 1, 0)] if times.size() > 0 else 0.0
	print("%s,%d,%.3f,%.3f,%d" % [v, times.size(), mean, p99, maxc])
	quit()