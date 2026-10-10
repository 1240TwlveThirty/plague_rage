extends SceneTree
# Тик на пике, волна 40 (1805 зомби), армия на пределах магазина (пехота 1200, лучники 300). Аргументы: <режим> <seed>.
#   bak33 — прежние подволны, все за 3 с (subwave_size 600, интервал 1 с, в памяти);
#   v33   — всплески, все сразу (t_start = 0, burst_chunk 600, в памяти): тот же пик ~3300 юнитов;
#   v33spawn — всплески с рабочими настройками, 60 с: время тиков, в которых появился кусок, против остальных.
# Считаются тики, где юнитов >= 3000; PROFILE по фазам — среднее окон по 60 тиков, закрывшихся на пике.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var v := args[0]
	var m: Node2D = load("res://bench/main_bak33.gd" if v == "bak33" else "res://scripts/main.gd").new()
	m.spawn_seed = int(args[1])
	m.record_path = "user://record_bench.json"
	m._setup_data()
	m._squad_add_units(0, m.infantry_type, 900)
	m._squad_add_units(1, m.archer_type, 200)
	for i in m.count:
		if m.unit_squad[i] >= 0:
			m.pos[i] = m.squad_pos[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])
			m.prev_pos[i] = m.pos[i]
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	if v == "bak33":
		m.wave_cfg.subwave_size = 600
		m.wave_cfg.subwave_interval = 1.0
	elif v == "v33":
		m.wave_cfg.burst_chunk = 600
	m.profile = true
	m.wave_number = 39
	m._start_wave()
	if v == "v33":
		for b in m.wave_bursts:
			b.t_start = 0.0
	if v == "v33spawn":
		var spawn_ms := PackedFloat64Array()
		var other_ms := PackedFloat64Array()
		for t in 1800:
			var c0: int = m.wave_remaining
			var t0 := Time.get_ticks_usec()
			m._physics_process(1.0 / 30.0)
			var dt := (Time.get_ticks_usec() - t0) / 1000.0
			if m.wave_remaining < c0:
				spawn_ms.append(dt)
			else:
				other_ms.append(dt)
		spawn_ms.sort()
		other_ms.sort()
		print("SPAWN|%d|%.3f|%.3f|%.3f|%.3f|%d" % [spawn_ms.size(), spawn_ms[spawn_ms.size() / 2], spawn_ms[spawn_ms.size() - 1], other_ms[other_ms.size() / 2], other_ms[other_ms.size() - 1], m.count])
		m.free()
		quit()
		return
	var ms := PackedFloat64Array()
	var phases := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var windows := 0
	var max_count := 0
	var seen_peak := false
	for t in 900:
		var on_peak: bool = m.count >= 3000
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		max_count = maxi(max_count, m.count)
		if on_peak:
			seen_peak = true
			ms.append(dt)
			if m.prof_n == 0:
				for q in 6:
					phases[q] += m.prof_avg[q]
				windows += 1
		elif seen_peak:
			break
	var mean := 0.0
	for x in ms:
		mean += x
	var ph := []
	for q in 6:
		ph.append("%.2f" % (phases[q] / maxi(windows, 1)))
	print("TIME|%s|%s|%d|%d|%.3f|%s" % [v, args[1], max_count, ms.size(), mean / maxi(ms.size(), 1), " ".join(ph)])
	m.free()
	quit()
