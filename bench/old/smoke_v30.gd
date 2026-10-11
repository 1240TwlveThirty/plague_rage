extends SceneTree
# Smoke UI v30: перетаскивание с пересечением (отказ, сообщение в HUD, отряд на месте) и без. Синтетические события.
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

func button(screen: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
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

func drag(a: Vector2, b: Vector2) -> Dictionary:
	await button(to_screen(a), true)
	await motion(to_screen(b))
	await step(3)   # кадры с предпросмотром
	var g: Dictionary = m._formation_geometry(m.selected_squad, m.drag_start, m.drag_cur, m.drag_flip)
	await button(to_screen(b), false)
	return g

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(6)
	await key(KEY_2)   # лучники
	var before := [m.squad_pos[1], m.squad_target[1], m.squad_angle[1], m.squad_width[1], m.squad_user_width[1]]
	var g := await drag(Vector2(960, 640), Vector2(1104, 640))   # поверх блока пехоты
	await step(6)
	check("лучники поверх пехоты: предпросмотр красный (пересечение с отрядом 1), блок не поставлен, отряд на месте", g.overlap == 0
		and before == [m.squad_pos[1], m.squad_target[1], m.squad_angle[1], m.squad_width[1], m.squad_user_width[1]] and not m.drag_active)
	check("сообщение в HUD на 2 с", m.hud_msg == "Блок пересекается с отрядом 1" and m.hud_label.text.contains(m.hud_msg) and m.hud_msg_t <= 2.0 and m.hud_msg_t > 0.0, m.hud_msg)
	g = await drag(Vector2(1200, 640), Vector2(1344, 640))   # рядом, без пересечения
	check("лучники рядом с пехотой: блок поставлен", g.overlap == -1 and m.squad_pos[1] != before[0] and m.squad_width[1] == 25 and m.squad_target[1] == m.squad_pos[1])
	g = await drag(Vector2(1071, 598), Vector2(1215, 598))   # вплотную к правому краю пехоты
	check("вплотную к блоку пехоты (касание): блок поставлен", g.overlap == -1 and absf(m.squad_pos[1].x - 1143.0) < 1.0, "центр %s" % m.squad_pos[1])
	# то же в бою
	await key(KEY_SPACE)
	await step(5)
	var p1: Vector2 = m.squad_pos[1]
	g = await drag(Vector2(960, 640), Vector2(1104, 640))
	check("в бою пересечение тоже отклоняется", m.wave_state == m.WS_BATTLE and g.overlap == 0 and m.squad_pos[1] == p1)
	await key(KEY_1)
	g = await drag(Vector2(953, 500), Vector2(1067, 500))
	check("пехота на свободное место: блок поставлен", g.overlap == -1 and absf(m.squad_pos[0].y - 542.0) < 1.0, "центр %s" % m.squad_pos[0])
	var t0: int = m.tick_counter
	while m.tick_counter < t0 + 60:
		await process_frame
	check("бой идёт дальше", m.tick_counter >= t0 + 60 and m.wave_number == 1)
	print("SMOKE: провалов %d" % fails)
	quit()
