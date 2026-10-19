extends SceneTree
# Тик на 3000 юнитов, синтетика (v39): <main_*_3000.gd> [spear]. Без волн, 600 тиков; медиана и среднее тика, мс.
# spear (задача 8) — пехотный отряд 0 превращается в копейщиков той же численности (дальность удара больше).
# hero (задача 10) — с героем (hero_mode 1): ввод — круг радиусом ~130 px у ворот (cos, sin от тика), без клавиатуры.
func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var m: Node2D = load(OS.get_cmdline_user_args()[0]).new()
	m.spawn_seed = 1
	m.waves_enabled = false
	m.record_path = "user://record_bench.json"
	var hero := OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "hero"
	if hero:
		m.hero_mode = 1
		m.hero_feed = func(t: int) -> Vector2: return Vector2(cos(t * 0.03), sin(t * 0.03))
	m._setup_data()
	var spear := OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "spear"
	if spear:
		m.squad_type[0] = m.spearman_type
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.unit_type[i] = m.spearman_type
	var n: int = m.count
	var ms := PackedFloat64Array()
	var sum := 0.0
	for t in 600:
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		sum += ms[t]
	ms.sort()
	print("SYN|%d|%d|%.3f|%.3f%s" % [n, m.count, ms[300], sum / 600.0, "|spear" if spear else ("|hero" if hero else "")])
	m.free()
	quit()
