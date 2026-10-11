extends SceneTree
# Тик на пике: волна 40 (1805 зомби), армия на пределах магазина (пехота 1200, лучники 300), все подволны за 3 с
# (subwave_size 600, интервал 1 с — только в памяти). Аргументы: <bak32|v32> <seed> или find.
# Считаются тики, где юнитов >= 3000; PROFILE по фазам — среднее окон по 60 тиков, закрывшихся на пике.
func make(v: String, seed: int) -> Node2D:
	var m: Node2D = load("res://bench/old/main_bak32.gd" if v == "bak32" else "res://scripts/main.gd").new()
	m.spawn_seed = seed
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args[0] == "find":
		for seed in range(1, 200):
			var f := make("v32", seed)
			var sides := {}
			for r in f._plan_wave(40):
				sides[r.side] = true
			f.free()
			if sides.size() == 3:
				print("SEED,%d" % seed)
				break
		quit()
		return
	var v := args[0]
	var m := make(v, int(args[1]))
	m._squad_add_units(0, m.infantry_type, 900)
	m._squad_add_units(1, m.archer_type, 200)
	for i in m.count:
		if m.unit_squad[i] >= 0:
			m.pos[i] = m.squad_pos[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])
			m.prev_pos[i] = m.pos[i]
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m.wave_cfg.subwave_size = 600
	m.wave_cfg.subwave_interval = 1.0
	m.profile = true
	m.wave_number = 39
	m._start_wave()
	var sides := "верх"
	if v != "bak32":
		var by_side := [0, 0, 0]
		for r in m.wave_plan:
			by_side[r.side] += r.count
		sides = "верх %d, лево %d, право %d" % by_side
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
			if m.prof_n == 0:   # окно профиля только что закрылось
				for q in 6:
					phases[q] += m.prof_avg[q]
				windows += 1
		elif seen_peak:
			break
	var mean := 0.0
	for x in ms:
		mean += x
	ms.sort()
	var ph := []
	for q in 6:
		ph.append("%.2f" % (phases[q] / maxi(windows, 1)))
	print("TIME|%s|%s|%d|%d|%.3f|%.3f|%s|%s" % [v, args[1], max_count, ms.size(), mean / maxi(ms.size(), 1), ms[ms.size() / 2] if ms.size() > 0 else 0.0, " ".join(ph), sides])
	m.free()
	quit()
