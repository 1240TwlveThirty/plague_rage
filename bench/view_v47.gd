extends SceneTree
# Вид поля (v47), с окном: волна 10 (seed 3, ворота бессмертны), FPS и время кадра, скриншоты.
# Аргументы: <папка для PNG> [fx 1|0] [debug 1|0] [фильтр замка nearest|linear_mipmap] [warcry 1|0].
# warcry 1 — дар «Клич Благодати» 3 и клич действует весь замер (кнопка и подсветка краёв на экране), суффикс _warcry.
# [spear 1] (задача 8) — до волны 10 куплено 300 копейщиков (отряд у ворот, «держать»), снимок строя view_<тег>_spear_squad.png, суффикс _spear. fx задаёт fx_enabled до _ready;
# debug — отладка масок эффектов (как F2), тогда PNG с суффиксом _debug; фильтр (castle_filter) не nearest — суффикс с его именем. PNG: весь кадр, у ворот, края и замок у ворот крупнее (_castle); печатает TORCHES|число факелов.
# Печатает VIEW|fx|юнитов|тик|кадров|FPS|медиана кадра мс|95-й перцентиль мс; PNG: весь кадр, у ворот, левый и правый край.
const WARM_TICKS := 480    # 16 с (ускоренно): орда подходит к строю, бой идёт во время замера
const FRAMES := 2000

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var fx := args.size() < 2 or args[1] != "0"
	var debug := args.size() >= 3 and args[2] == "1"
	var filter: String = args[3] if args.size() >= 4 else "nearest"
	var warcry := args.size() >= 5 and args[4] == "1"
	var spear := args.size() >= 6 and args[5] == "1"
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = 3
	if warcry:
		m.active_gifts = {"war_cry": 3}
	if "fx_enabled" in m:
		m.fx_enabled = fx
	if "castle_filter" in m:
		m.castle_filter = filter
	root.add_child(m)
	current_scene = m
	for i in 8:
		await process_frame
	if spear:
		m.gold = 1e6
		for k in 10:
			m._buy(m.SHOP_ITEMS.find("spear_pack"))
		m.squad_order[2] = m.ORDER_HOLD
		m.squad_target[2] = Vector2(1330, 520)   # для снимка — в поле справа от пехоты
		m.banner.visible = false
		var t0: int = m.tick_counter
		while m.tick_counter < t0 + 300:   # отряд выходит из ворот и собирает строй (по тикам симуляции, не по кадрам)
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var px: Vector2 = Vector2(shot.get_size()) / m.get_viewport_rect().size
		var c: Vector2 = (m.get_viewport().get_canvas_transform() * m.squad_pos[2]) * px
		shot.get_region(Rect2i(int(c.x) - 240, int(c.y) - 135, 480, 270)).save_png(out_dir.path_join("view_spear_squad.png"))
		shot.save_png(out_dir.path_join("view_spear_squad_full.png"))
	m.wave_number = 9
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	Engine.time_scale = 4.0
	while m.tick_counter < WARM_TICKS and m.wave_state == m.WS_BATTLE:
		await process_frame
	Engine.time_scale = 1.0
	if warcry:
		m.war_cry_dur = 1000000   # для замера: клич действует до конца
		m.request_war_cry()
		await process_frame
		await process_frame
	if debug:
		m.color_mode = 1
		m._sync_fx_debug()
	var dts := PackedFloat64Array()
	var t_prev := Time.get_ticks_usec()
	var t0 := t_prev
	for i in FRAMES:
		await process_frame
		var t := Time.get_ticks_usec()
		dts.append((t - t_prev) / 1000.0)
		t_prev = t
	var fps := FRAMES / ((t_prev - t0) / 1e6)
	var sorted := dts.duplicate()
	sorted.sort()
	print("VIEW|%s|%d|%d|%d|%.1f|%.3f|%.3f" % [("fx" if fx else "nofx") + ("_warcry" if warcry else "") + ("_spear" if spear else ""), m.count, m.tick_counter, FRAMES, fps, sorted[FRAMES / 2], sorted[FRAMES * 95 / 100]])
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var tag: String = ("fx" if fx else "nofx") + ("_debug" if debug else "") + ("" if filter == "nearest" else "_" + filter) + ("_warcry" if warcry else "") + ("_spear" if spear else "")
	img.save_png(out_dir.path_join("view_%s_full.png" % tag))
	# Точка поля p — пиксель кадра: преобразование холста (камера с зумом camera_min_zoom), затем масштаб окна к базе
	var to_px: Vector2 = Vector2(img.get_size()) / m.get_viewport_rect().size
	var gate: Vector2 = (m.get_viewport().get_canvas_transform() * m.GATE_POS) * to_px
	img.get_region(Rect2i(int(gate.x) - 480, int(gate.y) - 300, 960, 540)).save_png(out_dir.path_join("view_%s_gate.png" % tag))
	img.get_region(Rect2i(0, 300, 640, 560)).save_png(out_dir.path_join("view_%s_left.png" % tag))
	img.get_region(Rect2i(img.get_width() - 640, 300, 640, 560)).save_png(out_dir.path_join("view_%s_right.png" % tag))
	img.get_region(Rect2i(int(gate.x) - 240, int(gate.y) - 80, 480, 270)).save_png(out_dir.path_join("view_%s_castle.png" % tag))
	print("TORCHES|%d" % m.fx_torches)
	quit()
