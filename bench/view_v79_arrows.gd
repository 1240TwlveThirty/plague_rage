extends SceneTree
# Замер FPS задачи 29 (с окном): бой копии main (bench/make_v79.py: N юнитов, лучников N / 5) без волн; зомби ставятся полосой перед
# лучниками в их дальности (свой ГСЧ скрипта, seed 7) — отряд лучников стреляет залпами весь замер. WARM тиков разгона, затем TICKS
# тиков: на каждый — тик симуляции, кадр main (_process: юниты, эффекты, стрелы) и кадр движка (рендер), время отдельно; FPS без
# тика = 1000 / (медиана кадра main + медиана рендера). Аргументы: путь к копии, [show_arrows 1/0 — только для копии «после»;
# ab — A/B в одном процессе: «Показывать стрелы» переключается каждые AB_EVERY тиков, AB_SKIP кадров после переключения не считаются,
# AB_TICKS тиков; печатает ARROWS79AB со стрелами и без — та же сцена, тот же прогрев, без шума между процессами].
# Печатает ARROWS79|копия|юнитов|FPS без тика|FPS с тиком (1000 / (тик + кадр main + рендер))|кадр main мс|рендер мс|стрел в полёте (сред.)|на экране пик|тик мс|кадр стрел мс (arrow_fx.cost_us).
const DT := 1.0 / 30.0
const WARM := 40
const TICKS := 150
const AB_TICKS := 480
const AB_EVERY := 8
const AB_SKIP := 2

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	if root.has_node("Game"):
		root.get_node("Game").free()
	_run.call_deferred()

func med(a: PackedFloat32Array, q := 0.5) -> float:
	var s := a.duplicate()
	s.sort()
	return s[mini(int(s.size() * q), s.size() - 1)]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	var show := args.size() < 2 or args[1] != "0"
	var ab := args.size() >= 2 and args[1] == "ab"
	var st: Node = root.get_node_or_null("Settings")
	if st != null:
		st.persist = false
		st.set("show_arrows", show)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var m: Node2D = Node2D.new()
	m.set_script(load(path))
	m.record_path = "user://record_bench.json"
	m.spawn_seed = 3
	m.waves_enabled = false
	m.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m)
	current_scene = m
	for i in 8:
		await process_frame
	m.banner.visible = false
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	# центр лучников; зомби — полосой перед ними (вверх по экрану), в 0.55–0.95 дальности стрелка
	var ca := Vector2.ZERO
	var na := 0
	for i in m.count:
		if m.team[i] == 0 and m.unit_type[i] == m.archer_type:
			ca += m.pos[i]
			na += 1
	ca /= maxf(na, 1)
	var rf: float = m.type_range_far[m.archer_type]
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in m.count:
		if m.team[i] == 1:
			var p: Vector2 = ca + Vector2.from_angle(-PI * 0.5 + r.randf_range(-0.9, 0.9)) * r.randf_range(0.55, 0.95) * rf
			p = p.clamp(Vector2(8, 8), m.FIELD - Vector2(8, 8))
			m.pos[i] = p
			m.prev_pos[i] = p
	if m.camera != null:
		m.camera.position = m._camera_clamp(ca + Vector2(0, -rf * 0.5), m.camera.zoom.x)
	var n0: int = m.count
	var tick_ms := PackedFloat32Array()
	var proc_ms := PackedFloat32Array()
	var rend_ms := PackedFloat32Array()
	var fl_sum := 0
	var drawn_peak := 0
	var fx_ms := PackedFloat32Array()
	var fx = m.get("arrow_fx")
	if ab:
		await _ab(m, st, path, n0)
		return
	for t in WARM + TICKS:
		var a := Time.get_ticks_usec()
		m._physics_process(DT)
		var b := Time.get_ticks_usec()
		m._process(DT)
		var e := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		var f := Time.get_ticks_usec()
		if t < WARM:
			continue
		tick_ms.append((b - a) / 1000.0)
		proc_ms.append((e - b) / 1000.0)
		rend_ms.append((f - e) / 1000.0)
		var inflight := 0
		for q in m.arrow_count:
			if m.arrow_tick[q] > m.tick_counter:
				inflight += 1
		fl_sum += inflight
		if fx != null:
			drawn_peak = maxi(drawn_peak, fx.count_in_flight(m.tick_counter) if fx.has_method("count_in_flight") else fx.drawn)
			var cu = fx.get("cost_us")
			fx_ms.append(float(cu) / 1000.0 if cu != null else 0.0)
	var fps := 1000.0 / maxf(med(proc_ms) + med(rend_ms), 0.001)
	var fps_tick := 1000.0 / maxf(med(tick_ms) + med(proc_ms) + med(rend_ms), 0.001)
	print("ARROWS79|%s%s|юнитов %d|FPS без тика %.1f|с тиком %.1f|кадр main %.2f / %.2f мс|рендер %.2f / %.2f мс|стрел в полёте сред. %.0f|на экране пик %d|тик %.2f мс|стрелы в кадре %.3f / %.3f мс" % [
		path.get_file(), "" if show else " (стрелы выкл)", n0, fps, fps_tick, med(proc_ms), med(proc_ms, 0.95), med(rend_ms), med(rend_ms, 0.95),
		float(fl_sum) / TICKS, drawn_peak, med(tick_ms), med(fx_ms) if not fx_ms.is_empty() else 0.0, med(fx_ms, 0.95) if not fx_ms.is_empty() else 0.0])
	m.queue_free()
	for i in 2:
		await process_frame
	quit(0)


# A/B: флаг переключается каждые AB_EVERY тиков; по каждому состоянию — медианы тика, кадра main и рендера.
func _ab(m: Node2D, st: Node, path: String, n0: int) -> void:
	var t_ms := [PackedFloat32Array(), PackedFloat32Array()]   # [выкл, вкл]
	var p_ms := [PackedFloat32Array(), PackedFloat32Array()]
	var r_ms := [PackedFloat32Array(), PackedFloat32Array()]
	var on := true
	var since := 0
	for t in WARM + AB_TICKS:
		if t >= WARM and (t - WARM) % AB_EVERY == 0:
			on = not on
			st.set_show_arrows(on)
			since = 0
		var a := Time.get_ticks_usec()
		m._physics_process(DT)
		var b := Time.get_ticks_usec()
		m._process(DT)
		var e := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		var f := Time.get_ticks_usec()
		since += 1
		if t < WARM or since <= AB_SKIP:
			continue
		var k := 1 if on else 0
		t_ms[k].append((b - a) / 1000.0)
		p_ms[k].append((e - b) / 1000.0)
		r_ms[k].append((f - e) / 1000.0)
	var fps := []
	var fps_t := []
	for k in 2:
		fps.append(1000.0 / maxf(med(p_ms[k]) + med(r_ms[k]), 0.001))
		fps_t.append(1000.0 / maxf(med(t_ms[k]) + med(p_ms[k]) + med(r_ms[k]), 0.001))
	print("ARROWS79AB|%s|юнитов %d|кадров %d / %d|FPS без тика: без стрел %.1f, со стрелами %.1f (%+.1f%%)|с тиком: %.1f, %.1f (%+.1f%%)|кадр main %.3f / %.3f мс|рендер %.3f / %.3f мс|тик %.2f / %.2f мс" % [
		path.get_file(), n0, p_ms[0].size(), p_ms[1].size(), fps[0], fps[1], (fps[1] / fps[0] - 1.0) * 100.0, fps_t[0], fps_t[1], (fps_t[1] / fps_t[0] - 1.0) * 100.0,
		med(p_ms[0]), med(p_ms[1]), med(r_ms[0]), med(r_ms[1]), med(t_ms[0]), med(t_ms[1])])
	m.queue_free()
	for i in 2:
		await process_frame
	quit(0)
