extends SceneTree
# Тик волны по слоям (v35: путь к main шестым аргументом). Аргументы: <слой> <волна> <зомби в волне, 0 = как в игре> <армия: start | caps> <seed> <main.gd>.
# Бой идёт, пока все не появятся и ещё 10 с (или волна не кончится). Считаются все тики: медиана, максимум,
# максимум среди тиков с появлением куска; PROFILE по фазам — среднее закрывшихся окон по 60 тиков.
func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var args := OS.get_cmdline_user_args()
	var m: Node2D = load(args[5]).new()
	m.spawn_seed = int(args[4])
	m.debug_layer = int(args[0])
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var w := int(args[1])
	if int(args[2]) > 0:
		m.wave_cfg.count_base = int(args[2]) - m.wave_cfg.count_step * (w - 1)
	if args[3] == "caps":
		m._squad_add_units(0, m.infantry_type, 900)
		m._squad_add_units(1, m.archer_type, 200)
		for i in m.count:
			if m.unit_squad[i] >= 0:
				m.pos[i] = m.squad_pos[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])
				m.prev_pos[i] = m.pos[i]
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m.profile = true
	m.wave_number = w - 1
	m.wave_plan_for = -1
	m._start_wave()
	var total: int = m.wave_remaining
	var bursts: int = m.wave_bursts.size()
	var ms := PackedFloat64Array()
	var spawn_max := 0.0
	var phases := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var windows := 0
	var max_count := 0
	var after := 0
	var arrivals := 0
	while m.wave_state == m.WS_BATTLE and after < 300 and ms.size() < 6000:
		var rem0: int = m.wave_remaining
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		ms.append(dt)
		if m.wave_remaining < rem0:
			spawn_max = maxf(spawn_max, dt)
		if m.wave_state == m.WS_BATTLE:
			arrivals = m.arrivals_10s_max
		max_count = maxi(max_count, m.count)
		if m.prof_n == 0:
			for q in 6:
				phases[q] += m.prof_avg[q]
			windows += 1
		if m.wave_remaining == 0:
			after += 1
	var sorted := ms.duplicate()
	sorted.sort()
	var ph := []
	for q in 6:
		ph.append("%.2f" % (phases[q] / maxi(windows, 1)))
	print("TIME|%s|%d|%d|%d|%d|%.3f|%.3f|%.3f|%d|%s|%.0f" % [args[0], w, total, bursts, max_count, sorted[sorted.size() / 2], sorted[sorted.size() - 1], spawn_max, arrivals, " ".join(ph), ms.size() / 30.0])
	m.free()
	quit()
