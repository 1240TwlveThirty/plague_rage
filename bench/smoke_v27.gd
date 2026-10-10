extends SceneTree
# Smoke UI v27: расстановка перетаскиванием синтетическими событиями мыши (push_input, in_local_coords) и клавишами.
var fails := 0
var m: Node2D

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await step(3)

func to_screen(world: Vector2) -> Vector2:
	return m.get_viewport().get_canvas_transform() * world

func button(index: MouseButton, screen: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = screen
	e.global_position = screen
	root.push_input(e, true)
	await step(2)

func motion(screen: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = screen
	e.global_position = screen
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await step(2)

func snapshot() -> Array:
	# без squad_pos и squad_angle: после клика отряд марширует к цели, они меняются сами
	return [m.squad_target[0], m.squad_width[0], m.squad_rows[0], m.squad_user_width[0], m.squad_target[1], m.squad_width[1], m.squad_user_width[1]]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(5)
	# 1. перетаскивание (сквозь стартовый баннер): линия 250 px выше отряда -> лицом вверх
	var w1 := Vector2(900, 450)
	var w2 := Vector2(1150, 450)
	await button(MOUSE_BUTTON_LEFT, to_screen(w1), true)
	check("ЛКМ по карте начинает перетаскивание", m.drag_active and m.drag_start.distance_to(w1) < 0.01, "баннер виден: %s" % m.banner.visible)
	await motion(to_screen(Vector2(1000, 450)))
	check("движение обновляет drag_cur (предпросмотр)", m.drag_active and m.drag_cur.distance_to(Vector2(1000, 450)) < 0.01)
	await motion(to_screen(w2))
	await step(3)
	await button(MOUSE_BUTTON_LEFT, to_screen(w2), false)
	var want := roundi(250.0 / m.SLOT_SPACING) + 1
	var front: Vector2 = m.squad_pos[0] - m.squad_center_off[0].rotated(m.squad_angle[0])
	check("отпускание ставит строй на линию", not m.drag_active and m.squad_user_width[0] == want and m.squad_width[0] == want
		and absf(angle_difference(m.squad_angle[0], -PI / 2.0)) < 0.001 and front.distance_to(Vector2(1025, 450)) < 0.01 and m.squad_target[0] == m.squad_pos[0],
		"ширина %d, рядов %d, середина переднего ряда %s" % [m.squad_width[0], m.squad_rows[0], front])
	# 2. короткий клик: прежнее поведение — только цель отряда
	var before := snapshot()
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(700, 300)), true)
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(705, 303)), false)
	var after := snapshot()
	check("короткий клик (5 px): только цель отряда, строй не меняется", not m.drag_active and m.squad_target[0].distance_to(Vector2(700, 300)) < 0.01
		and after.slice(1) == before.slice(1), "цель %s" % m.squad_target[0])
	# 3. клик по панели отрядов не начинает перетаскивание
	var panel_pos: Vector2 = m.squad_buttons[1].get_global_rect().get_center()
	before = snapshot()
	await button(MOUSE_BUTTON_LEFT, panel_pos, true)
	var started: bool = m.drag_active
	await button(MOUSE_BUTTON_LEFT, panel_pos, false)
	check("клик по панели: перетаскивание не начато, выбран отряд 2, цели и строй те же", not started and not m.drag_active and m.selected_squad == 1 and snapshot() == before, "%s -> %s" % [before, snapshot()])
	await key(KEY_1)
	# 4. ПКМ отменяет
	before = snapshot()
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(800, 500)), true)
	await motion(to_screen(Vector2(1000, 520)))
	var was: bool = m.drag_active
	await button(MOUSE_BUTTON_RIGHT, to_screen(Vector2(1000, 520)), true)
	var cancelled: bool = not m.drag_active
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1000, 520)), false)
	check("ПКМ отменяет перетаскивание, ничего не меняется", was and cancelled and snapshot() == before)
	# 5. Esc отменяет
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(800, 500)), true)
	await motion(to_screen(Vector2(1000, 520)))
	was = m.drag_active
	await key(KEY_ESCAPE)
	cancelled = not m.drag_active
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1000, 520)), false)
	check("Esc отменяет перетаскивание, ничего не меняется", was and cancelled and snapshot() == before)
	# 6. T сбрасывает ширину выбранного отряда
	await key(KEY_T)
	check("T: ширина отряда снова авто", m.squad_user_width[0] == 0 and m.selected_squad == 0)
	# 7. лучники: выбрать клавишей 2 и перетащить; затем волна 1 и перетаскивание в бою
	await key(KEY_2)
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(950, 620)), true)
	await motion(to_screen(Vector2(1100, 620)))
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1100, 620)), false)
	check("отряд 2 (лучники) расставлен, отряд 1 не тронут", m.squad_user_width[1] == roundi(150.0 / m.SLOT_SPACING) + 1 and m.squad_user_width[0] == 0)
	await key(KEY_1)
	await key(KEY_SPACE)
	await step(30)
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(880, 520)), true)
	await motion(to_screen(Vector2(1140, 540)))
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1140, 540)), false)
	var t0: int = m.tick_counter
	while m.tick_counter < t0 + 90:   # кадры без окна идут быстрее тиков: ждём по тикам
		await process_frame
	check("в бою: волна 1 идёт, строй пехоты расставлен", m.wave_number == 1 and m.squad_user_width[0] > 0 and m.tick_counter > 60, "тиков %d, юнитов %d" % [m.tick_counter, m.count])
	print("SMOKE: провалов %d" % fails)
	quit()
