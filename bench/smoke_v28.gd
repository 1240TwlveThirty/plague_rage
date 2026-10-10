extends SceneTree
# Smoke UI v28: несколько отрядов — клавиши 1-8, N, G, M, кнопки панели, 8 строк, блокировка в бою.
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

func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await button(MOUSE_BUTTON_LEFT, p, true)
	await button(MOUSE_BUTTON_LEFT, p, false)
	await step(2)

func used() -> Array:
	var r := []
	for s in m.SQUAD_MAX:
		if m.squad_used[s] == 1:
			r.append(s)
	return r

func rows_shown() -> Array:
	var r := []
	for s in m.SQUAD_MAX:
		if m.squad_rows_ui[s].visible:
			r.append(s)
	return r

func wait_ticks(n: int) -> void:
	var t0: int = m.tick_counter
	while m.tick_counter < t0 + n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(5)
	m.gold = 5000.0
	check("старт: 2 строки панели, кнопки отрядов видны, подписи без номеров", rows_shown() == [0, 1] and m.squad_actions.visible
		and m.squad_buttons[0].text == "1  Пехота — 300 — атака" and m.squad_buttons[1].text == "2  Лучники — 100 — атака", m.squad_buttons[0].text)
	await step(8)
	check("магазин: подпись цели покупки", m.shop_buttons[0].text.ends_with("→ Отряд 1 (Пехота)") and m.shop_buttons[1].text.ends_with("→ Отряд 2 (Лучники)"), m.shop_buttons[0].text.replace("\n", " / "))
	# N: новый отряд пехоты, покупка идёт в него
	await key(KEY_N)
	await step(8)
	check("N: отряд 3 создан и выбран, строка видна, названия с номерами", used() == [0, 1, 2] and m.selected_squad == 2 and rows_shown() == [0, 1, 2]
		and m.squad_buttons[0].text.begins_with("1  Пехота 1 — 300") and m.squad_buttons[2].text == "3  Пехота 2 — 0 — атака"
		and m.shop_buttons[0].text.ends_with("→ Отряд 3 (Пехота 2)"), m.squad_buttons[2].text)
	await key(KEY_Z)
	check("Z: пехота куплена в выбранный отряд 3", m.squad_n[2] == 50 and m.squad_n[0] == 300)
	# G: разделение отряда 1, затем лучников
	await key(KEY_1)
	await key(KEY_G)
	check("G: отряд 1 разделён пополам, выбран новый отряд 4", m.squad_n[0] == 150 and m.squad_n[3] == 150 and m.selected_squad == 3 and rows_shown() == [0, 1, 2, 3])
	await key(KEY_2)
	await key(KEY_G)
	check("G у лучников: 50 + 50, новый отряд — лучники", m.squad_n[1] == 50 and m.squad_n[4] == 50 and m.squad_type[4] == m.archer_type and m.squad_buttons[4].text.begins_with("5  Лучники 2 — 50"))
	# до 8 отрядов кнопкой «+ Отряд»
	for q in 3:
		await click(m.squad_actions.get_child(0))
	await step(20)
	var panel: Rect2 = m.squad_panel.get_global_rect()
	var free_of_banner: bool = not m.banner.visible or not panel.intersects(m.banner.get_global_rect())
	check("кнопка «+ Отряд» ×3: заняты все 8, панель из 8 строк в экране и не пересекает баннер и магазин", used().size() == 8 and rows_shown().size() == 8
		and panel.position.y >= 0.0 and panel.end.y <= 1080.0 and free_of_banner and not panel.intersects(m.shop_panel.get_global_rect()),
		"панель %s, баннер %s" % [panel, m.banner.get_global_rect()])
	await key(KEY_N)
	await step(8)
	check("N при 8 занятых: отказ с сообщением в HUD", used().size() == 8 and m.hud_msg != "" and m.hud_label.text.contains(m.hud_msg), m.hud_msg)
	var sel_ok := true
	for k in 8:
		await key(KEY_1 + k)
		sel_ok = sel_ok and m.selected_squad == k and m.squad_buttons[k].button_pressed
	check("клавиши 1-8 выбирают отряды", sel_ok)
	# M и кнопки «Слить», «Разделить»
	await key(KEY_8)
	await key(KEY_M)
	check("M: пустой отряд 8 слит и освобождён, строка скрыта, выбор на целевом", m.squad_used[7] == 0 and not m.squad_rows_ui[7].visible and m.squad_used[m.selected_squad] == 1 and used().size() == 7)
	await key(KEY_8)
	check("клавиша свободного индекса игнорируется", m.selected_squad != 7)
	await key(KEY_4)
	await click(m.squad_actions.get_child(2))
	check("кнопка «Слить»: отряд 4 (150) влит в отряд 1", m.squad_used[3] == 0 and m.squad_n[0] == 300 and m.selected_squad == 0)
	await click(m.squad_actions.get_child(1))
	var parts := []
	for s in used():
		if m.squad_type[s] == m.infantry_type and m.squad_n[s] == 150:
			parts.append(s)
	check("кнопка «Разделить»: отряд 1 снова 150 + 150", parts.size() == 2 and m.squad_n[0] == 150, "отряды %s" % [parts])
	# перетаскивание для отряда с индексом >= 2
	var s3: int = m.selected_squad
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1100, 560)), true)
	await motion(to_screen(Vector2(1250, 560)))
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1250, 560)), false)
	check("перетаскивание работает для отряда %d" % (s3 + 1), s3 >= 2 and m.squad_user_width[s3] == roundi(150.0 / m.SLOT_SPACING) + 1 and m.squad_target[s3] == m.squad_pos[s3])
	# бой: кнопки скрыты, N/G/M не действуют
	var before := used()
	var sizes: PackedInt32Array = m.squad_n.duplicate()
	await key(KEY_SPACE)
	await wait_ticks(10)
	await step(20)
	m.hud_msg = ""
	await key(KEY_N)
	await key(KEY_1)
	await key(KEY_G)
	await key(KEY_M)
	check("в бою: кнопки отрядов скрыты, N, G, M не действуют, сообщений нет", m.wave_state == m.WS_BATTLE and not m.squad_actions.visible and used() == before and m.squad_n == sizes and m.hud_msg == "",
		"отряды %s" % [before])
	await key(KEY_3)
	check("в бою выбор клавишами работает", m.selected_squad == 2)
	# конец волны: пустые отряды освобождаются
	var frames := 0
	while m.wave_state == m.WS_BATTLE and frames < 40000:
		await process_frame
		frames += 1
	await step(20)
	var empty_left := 0
	for s in range(2, m.SQUAD_MAX):
		if m.squad_used[s] == 1 and m.squad_n[s] == 0:
			empty_left += 1
	check("передышка после волны 1: пустые отряды освобождены, строк столько же, сколько отрядов, кнопки снова видны", m.wave_state == m.WS_RESPITE and empty_left == 0
		and rows_shown() == used() and m.squad_actions.visible and m.squad_used[m.selected_squad] == 1, "отряды %s, тиков %d" % [used(), m.tick_counter])
	print("SMOKE: провалов %d" % fails)
	quit()
