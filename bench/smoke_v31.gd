extends SceneTree
# Smoke UI v31: обычный клик с отказом (блок пересекается) и без, перетаскивание с отказом и без. Синтетические события.
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

func click(world: Vector2) -> void:
	await button(to_screen(world), true)
	await button(to_screen(world + Vector2(3, 2)), false)

func drag(a: Vector2, b: Vector2) -> Dictionary:
	await button(to_screen(a), true)
	await motion(to_screen(b))
	await step(3)
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
	check("по умолчанию залп по старому правилу (ARCHER_OWN_RANGE = false)", not m.archer_own_range)
	await key(KEY_2)   # лучники
	var t0: Vector2 = m.squad_target[1]
	await click(Vector2(1010, 640))   # в середину блока пехоты
	await step(6)
	check("клик лучниками в блок пехоты: отказ, цель не меняется, сообщение в HUD", m.squad_target[1] == t0 and m.hud_msg == "Блок пересекается с отрядом 1"
		and m.hud_label.text.contains(m.hud_msg) and m.hud_msg_t <= 2.0 and m.hud_msg_t > 0.0 and not m.drag_active, m.hud_msg)
	await click(Vector2(1300, 600))   # свободное место
	check("клик лучниками по свободному месту: цель задана", m.squad_target[1].distance_to(Vector2(1300, 600)) < 0.01)
	var t1: Vector2 = m.squad_target[1]
	var g := await drag(Vector2(960, 640), Vector2(1104, 640))   # перетаскивание поверх пехоты
	check("перетаскивание лучников поверх пехоты: отказ, отряд и цель на месте", g.overlap == 0 and m.squad_target[1] == t1)
	g = await drag(Vector2(1200, 700), Vector2(1344, 700))
	check("перетаскивание лучников на свободное место: блок поставлен", g.overlap == -1 and m.squad_target[1] == m.squad_pos[1] and absf(m.squad_pos[1].y - 709.0) < 1.0, "центр %s" % m.squad_pos[1])
	# пехота: клик на лучников — отказ, рядом — принят; то же в бою
	await key(KEY_1)
	var p0: Vector2 = m.squad_target[0]
	await click(m.squad_pos[1])
	check("клик пехотой на блок лучников: отказ", m.squad_target[0] == p0 and m.hud_msg == "Блок пересекается с отрядом 2")
	await key(KEY_SPACE)
	await step(4)
	await click(m.squad_pos[1] + Vector2(10, 0))
	var refused_in_battle: bool = m.squad_target[0] == p0
	await click(Vector2(1010, 560))
	check("в бою: клик на лучников — отказ, клик вперёд по дороге — принят", m.wave_state == m.WS_BATTLE and refused_in_battle and m.squad_target[0].distance_to(Vector2(1010, 560)) < 0.01)
	var tick0: int = m.tick_counter
	while m.tick_counter < tick0 + 90:
		await process_frame
	check("бой идёт, пехота движется к цели", m.squad_pos[0].y < 640.0 and m.wave_number == 1, "центр пехоты %s" % m.squad_pos[0])
	print("SMOKE: провалов %d" % fails)
	quit()
