extends SceneTree
# Время тика на 3000 юнитах: <bak28|v28|v28x6>. Копии с UNIT_COUNT = 3000, без волн; 600 тиков.
# v28x6: те же юниты в 6 отрядах (пехота 4 × 75, лучники 2 × 50). Плюс стоимость одного вызова _update_squads.
func _initialize() -> void:
	var v := OS.get_cmdline_user_args()[0]
	var m: Node2D = load("res://bench/main_%s_3000.gd" % ("bak28" if v == "bak28" else "v28")).new()
	m.waves_enabled = false
	m.record_path = "user://record_bench.json"
	m._setup_data()
	if v == "v28x6":
		m.wave_state = m.WS_RESPITE   # разделение разрешено только в передышке
		for s in [0, 0, 2, 1]:        # 300 -> 150+150 -> 75+75+150 -> 75×4; лучники 50+50
			m._select_squad(s)
			m._cmd_split()
		m._select_squad(0)
		m.wave_state = m.WS_BATTLE
	var squads := 0
	if v == "bak28":
		squads = m.squad_count
	else:
		for s in m.SQUAD_MAX:
			squads += m.squad_used[s]
	# стоимость _update_squads: 3000 вызовов на стартовом состоянии (отряды стоят, раз в 15 вызовов — проверка сжатия)
	var t1 := Time.get_ticks_usec()
	for q in 3000:
		m._update_squads(1.0 / 30.0)
	var us := (Time.get_ticks_usec() - t1) / 3000.0
	m.squad_compact_t = 0.0
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
	print("TIME,%s,%d,%d,%.4f,%.2f,%d" % [v, n, squads, mean / dense.size(), us, m.count])
	m.free()
	quit()
