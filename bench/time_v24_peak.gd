extends SceneTree
# (в) Тик на пике: волна 25, армия 2650 пехоты + 300 лучников (в обход магазина и cap), ворота неразрушимы.
# Тики, где юнитов >= 3000: средний, p99, max; фазы — по 60-тиковым окнам профиля, целиком на пике.
func _initialize() -> void:
	var m: Node2D = load("res://scripts/main.gd").new()
	m.record_path = "user://record_bench.json"
	m.profile = true
	m._setup_data()
	var n0 := 0
	var n1 := 0
	for i in m.count:
		if m.unit_squad[i] == 0: n0 += 1
		if m.unit_squad[i] == 1: n1 += 1
	m._squad_add_units(0, m.infantry_type, 2650 - n0)
	m._squad_add_units(1, m.archer_type, 300 - n1)
	m.gate_hp = 1e12
	m.gate_hp_max = 1e12
	for t in 300:
		m._physics_process(1.0 / 30.0)
	m.wave_number = 24
	m._start_wave()
	var times := PackedFloat64Array()
	var maxc := 0
	var win_ok := true
	var phase_sum := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var windows := 0
	for t in 30 * 120:
		var big: bool = m.count >= 3000
		win_ok = win_ok and big
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		if big:
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
		maxc = maxi(maxc, m.count)
		if m.prof_n == 0:   # окно из 60 тиков только что закрылось
			if win_ok:
				for q in 6:
					phase_sum[q] += m.prof_avg[q]
				windows += 1
			win_ok = true
	var mean := 0.0
	for x in times:
		mean += x
	mean /= maxi(times.size(), 1)
	times.sort()
	var ph := []
	for q in 6:
		ph.append("%.3f" % (phase_sum[q] / maxi(windows, 1)))
	print("new,%d,%.3f,%.3f,%.3f,%d,%d,%s" % [times.size(), mean, times[maxi(ceili(times.size() * 0.99) - 1, 0)], times[times.size() - 1], maxc, windows, ",".join(ph)])
	m.free()
	quit()