extends SceneTree
# Smoke v40, этап 2, со сценой и окном (без --headless): ЛКМ клик, двойной клик, рамка, ПКМ клик и протяжка,
# Shift, Ctrl+A, Esc, цифры, строки панели — синтетическими событиями через окно (интерфейс получает их первым).
# Перед каждым нажатием мыши курсор ОС переносится в ту же точку окна (Viewport.warp_mouse) и окно — на передний план, если
# фокус потерян (задача 20: настоящая мышь вне окна, например на другом мониторе, давала событиям ОС сбивать наведение GUI).
# Аргумент other_screen: окно — на другой монитор, курсор ОС — в середину прежнего (проверка, что тест от этого не зависит).
var fails := 0
var m: Node2D
var refocus := 0   # сколько раз окно пришлось возвращать на передний план

var os_moves := 0   # движения мыши, пришедшие от ОС (не синтетические)

func _on_window_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		os_moves += 1

# Окно в фокусе (иначе — на передний план); курсор ОС — в точку at окна. Если курсор ОС сдвинулся, ждём его событие движения
# (до 30 кадров): пришедшее позже синтетических, оно сбило бы рамку и протяжку (box_cur, drag_cur).
func aim(at: Vector2) -> void:
	if not DisplayServer.window_is_focused():
		refocus += 1
		DisplayServer.window_move_to_foreground()
		await process_frame
		await process_frame
	var was := DisplayServer.mouse_get_position()
	var n := os_moves
	root.warp_mouse(at)
	if DisplayServer.mouse_get_position() == was:
		return
	for i in 30:
		await process_frame
		if os_moves > n:
			break
	await process_frame

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key, shift := false, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
	await step(2)

# Точка мира на экране.
func scr(w: Vector2) -> Vector2:
	return m.get_global_transform_with_canvas() * w

func button(btn: MouseButton, at: Vector2, pressed: bool, shift := false, dbl := false) -> void:
	if pressed:
		await aim(at)   # отпускание — без переноса: протяжка идёт синтетическими событиями
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.shift_pressed = shift
	e.double_click = dbl
	e.position = at
	e.global_position = at
	root.push_input(e, true)
	await step(1)

func move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	root.push_input(e, true)
	await step(2)

func click(btn: MouseButton, at: Vector2, shift := false, dbl := false) -> void:
	await button(btn, at, true, shift, dbl)
	await button(btn, at, false, shift)
	await step(1)

# Клик по кнопке интерфейса: нажатие и отпускание в одном кадре. Между кадрами окно может получить события ОС (потеря фокуса
# окна, движение настоящей мыши) — GUI тогда сбрасывает фокус мыши (Viewport на NOTIFICATION_WM_WINDOW_FOCUS_OUT) и отпускание
# уже не нажимает кнопку. Так падал пункт «б» в run_all (задачи 8–10); внутри одного кадра события ОС не обрабатываются.
func tap(btn: MouseButton, at: Vector2, shift := false) -> void:
	await aim(at)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = btn
		e.pressed = pressed
		e.shift_pressed = shift
		e.position = at
		e.global_position = at
		root.push_input(e, true)
	await step(2)

func drag(btn: MouseButton, a: Vector2, b: Vector2, shift := false) -> void:
	await button(btn, a, true, shift)
	await move(a.lerp(b, 0.5))
	await move(b)
	await button(btn, b, false, shift)
	await step(1)

func teleport() -> void:
	for i in m.count:
		if m.unit_squad[i] >= 0:
			m.pos[i] = m.squad_pos[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])
			m.prev_pos[i] = m.pos[i]

func mask_of(list: Array) -> int:
	var k := 0
	for s in list:
		k |= 1 << s
	return k

func rows_match() -> bool:
	for s in m.SQUAD_MAX:
		if m.squad_used[s] == 1 and m.squad_buttons[s].button_pressed != m._is_sel(s):
			return false
	return true

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	_run.call_deferred()

func _run() -> void:
	root.window_input.connect(_on_window_input)
	if "other_screen" in OS.get_cmdline_user_args():
		var n := DisplayServer.get_screen_count()
		var was := DisplayServer.window_get_current_screen()
		if n < 2:
			print("  другой монитор: экран один — проверка с курсором ОС вне окна (в углу экрана)")
			Input.warp_mouse(Vector2(-DisplayServer.window_get_position()) + Vector2(4, 4))
		else:
			DisplayServer.window_set_current_screen((was + 1) % n)
			await step(5)
			var mid := DisplayServer.screen_get_position(was) + DisplayServer.screen_get_size(was) / 2
			Input.warp_mouse(Vector2(mid - DisplayServer.window_get_position()))   # курсор ОС — на прежний монитор
			await step(2)
			print("  другой монитор: окно на экране %d из %d, курсор ОС на экране %d (%s)" % [DisplayServer.window_get_current_screen(), n, was,
				str(DisplayServer.mouse_get_position())])
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(8)
	await key(KEY_H)   # баннер дневника скрыт: не мешает кликам по карте
	# армия: пехота 1 (150), 3 (75), 4 (75) в ряд, лучники 2 на старте
	await key(KEY_G)
	await key(KEY_G)
	m._place_formation(0, Vector2(500, 250), Vector2(700, 250))
	m._place_formation(2, Vector2(940, 250), Vector2(1060, 250))
	m._place_formation(3, Vector2(1300, 250), Vector2(1420, 250))
	teleport()
	await step(3)
	var hint: Rect2 = m.hint_label.get_global_rect()
	var panel: Rect2 = m.squad_panel.get_global_rect()
	var overlap := false
	for c in m.squad_panel.get_children():
		if c != m.hint_label and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().grow(-1.0).intersects(hint):
			overlap = true
	check("подсказка внизу левой панели мелким шрифтом, ничего не перекрывает", m.hint_label.is_visible_in_tree() and panel.encloses(hint) and not overlap
		and tr(m.hint_label.text) == "ЛКМ выбор · ПКМ приказ · Shift добавить" and Rect2(0, 0, 1920, 1080).encloses(panel), "подсказка %s, панель %s" % [hint, panel])
	var t0: PackedVector2Array = m.squad_target.duplicate()
	# ЛКМ
	await click(MOUSE_BUTTON_LEFT, scr(m.squad_pos[2]))
	var c1: bool = m.sel_mask == 4 and m.sel_primary == 2
	await click(MOUSE_BUTTON_LEFT, scr(m.squad_pos[0]), true)
	var c2: bool = m.sel_mask == 5 and m.sel_primary == 0
	check("(л) ЛКМ-клик выбирает отряд, Shift+клик добавляет; цели не меняются; строки панели подсвечивают все выбранные", c1 and c2 and m.squad_target == t0 and rows_match())
	await click(MOUSE_BUTTON_LEFT, scr(m.squad_pos[3]))
	await click(MOUSE_BUTTON_LEFT, scr(m.squad_pos[3]), false, true)
	check("(л) двойной клик: все отряды пехоты", m.sel_mask == mask_of([0, 2, 3]) and m.sel_primary == 3 and rows_match())
	await click(MOUSE_BUTTON_LEFT, scr(Vector2(800, 520)))
	var empty: bool = m.sel_mask == 0 and m.sel_primary == -1
	await click(MOUSE_BUTTON_RIGHT, scr(Vector2(800, 520)))
	await drag(MOUSE_BUTTON_RIGHT, scr(Vector2(700, 520)), scr(Vector2(900, 520)))
	check("(л) клик в пустоту очищает выбор; ПКМ без выбранных игнорируется", empty and m.squad_target == t0 and rows_match())
	# рамка
	await button(MOUSE_BUTTON_LEFT, scr(Vector2(850, 200)), true)
	await move(scr(Vector2(1200, 300)))
	await move(scr(Vector2(1500, 400)))
	var drawn: bool = m.box_active and m.box_cur.distance_to(Vector2(1500, 400)) < 0.01
	await button(MOUSE_BUTTON_LEFT, scr(Vector2(1500, 400)), false)
	var boxed: bool = m.sel_mask == mask_of([2, 3])
	await button(MOUSE_BUTTON_LEFT, scr(Vector2(400, 200)), true)
	await move(scr(Vector2(750, 400)))
	await key(KEY_ESCAPE)
	await button(MOUSE_BUTTON_LEFT, scr(Vector2(750, 400)), false)
	check("(л) рамка выбирает два отряда; Esc во время рамки отменяет её", drawn and boxed and m.sel_mask == mask_of([2, 3]) and not m.box_active)
	# ПКМ: один отряд
	await key(KEY_1)
	await click(MOUSE_BUTTON_RIGHT, scr(Vector2(560, 480)))
	var one_move: bool = m.squad_target[0].distance_to(Vector2(560, 480)) < 0.01 and m.squad_target[2] == t0[2]
	# протяжка 550 -> 850: при зуме камеры camera_min_zoom точка x 450 на экране уже под левой панелью отрядов
	await button(MOUSE_BUTTON_RIGHT, scr(Vector2(550, 520)), true)
	await move(scr(Vector2(700, 520)))
	await move(scr(Vector2(850, 520)))
	var preview: bool = m.drag_active and m.drag_cur.distance_to(Vector2(850, 520)) < 0.01
	await step(3)
	await button(MOUSE_BUTTON_RIGHT, scr(Vector2(850, 520)), false)
	check("(л) один отряд: ПКМ-клик задаёт цель, ПКМ-протяжка ставит строй (предпросмотр рисуется)", one_move and preview and absf(m._front_centre(0).x - 700.0) < 7.0 and absf(m._front_centre(0).y - 520.0) < 0.01
		and m.squad_user_width[0] == 26, "середина переднего ряда %s, ширина %d" % [m._front_centre(0).round(), m.squad_width[0]])
	teleport()
	# ПКМ: набор
	await key(KEY_3)
	await key(KEY_4, true)
	var sel_keys: bool = m.sel_mask == mask_of([2, 3]) and m.sel_primary == 3
	var rel: Vector2 = m.squad_pos[3] - m.squad_pos[2]
	var mid: Vector2 = (m.squad_pos[2] + m.squad_pos[3]) * 0.5
	await click(MOUSE_BUTTON_RIGHT, scr(mid + Vector2(30, 60)))
	var group_move: bool = (m.squad_target[3] - m.squad_target[2]).distance_to(rel) < 0.01 and ((m.squad_target[2] + m.squad_target[3]) * 0.5).distance_to(mid + Vector2(30, 60)) < 0.01
	await button(MOUSE_BUTTON_RIGHT, scr(Vector2(1000, 420)), true)
	await move(scr(Vector2(1200, 420)))
	await move(scr(Vector2(1400, 420)))
	await step(3)
	await key(KEY_F)
	var flipped: bool = m.drag_flip and m.drag_active
	await step(3)
	await key(KEY_F)
	await button(MOUSE_BUTTON_RIGHT, scr(Vector2(1400, 420)), false)
	var face_up: bool = Vector2.from_angle(m.squad_angle[2]).dot(Vector2.UP) > 0.99 and Vector2.from_angle(m.squad_angle[3]).dot(Vector2.UP) > 0.99
	check("(л) цифры и Shift+цифра; набор: ПКМ-клик сдвигает группу, ПКМ-протяжка ставит отряды в линию (предпросмотр группы, F инвертирует лицо)",
		sel_keys and group_move and flipped and face_up and absf(m.squad_pos[2].y - m.squad_pos[3].y) < 0.01 and m.squad_pos[2].x < m.squad_pos[3].x and m.squad_target[2] == m.squad_pos[2],
		"отряды %s и %s" % [m.squad_pos[2].round(), m.squad_pos[3].round()])
	teleport()
	# Esc во время ПКМ-протяжки. Физика стоит: отряды не доезжают до целей прошлого пункта (сколько тиков проходит за кадр —
	# зависит от частоты монитора), squad_pos меняет только сама протяжка
	m.set_physics_process(false)
	var p_before: PackedVector2Array = m.squad_pos.duplicate()
	var t_before: PackedVector2Array = m.squad_target.duplicate()
	await button(MOUSE_BUTTON_RIGHT, scr(Vector2(700, 600)), true)
	await move(scr(Vector2(1000, 600)))
	var dragging: bool = m.drag_active
	await key(KEY_ESCAPE)
	await button(MOUSE_BUTTON_RIGHT, scr(Vector2(1000, 600)), false)
	check("(л) Esc во время ПКМ-протяжки отменяет её", dragging and m.squad_pos == p_before and m.squad_target == t_before and not m.drag_active,
		"протяжка шла: %s" % dragging)
	m.set_physics_process(true)
	# Ctrl+A и строки панели. Физика стоит: цели меняют только клики (отряды «атака» сами берут цели, а сколько тиков пройдёт,
	# пока курсор ОС переносится в окно, зависит от монитора)
	m.set_physics_process(false)
	await key(KEY_A, false, true)
	var all: bool = m.sel_mask == mask_of([0, 1, 2, 3])
	var t1: PackedVector2Array = m.squad_target.duplicate()
	await tap(MOUSE_BUTTON_LEFT, m.squad_buttons[2].get_global_rect().get_center())
	var row_one: bool = m.sel_mask == 4 and m.sel_primary == 2 and rows_match()
	await tap(MOUSE_BUTTON_LEFT, m.squad_buttons[0].get_global_rect().get_center(), true)
	var row_add: bool = m.sel_mask == 5 and m.sel_primary == 0 and rows_match()
	await tap(MOUSE_BUTTON_LEFT, m.squad_buttons[2].get_global_rect().get_center(), true)
	var row_off: bool = m.sel_mask == 1 and rows_match()
	await tap(MOUSE_BUTTON_RIGHT, m.squad_buttons[1].get_global_rect().get_center())
	check("(б) Ctrl+A выбирает все; клик по строке панели выбирает отряд, Shift+клик добавляет и убирает; цели отрядов не меняются (и ПКМ по панели карту не трогает)",
		all and row_one and row_add and row_off and m.squad_target == t1 and not m.box_active and not m.drag_active,
		"все %s, строка %s, добавить %s, убрать %s, цели %s, рамка %s, протяжка %s, маска %d, мышь ОС %s, фокус окна %s" % [all, row_one, row_add, row_off,
		m.squad_target == t1, m.box_active, m.drag_active, m.sel_mask, root.get_mouse_position(), DisplayServer.window_is_focused()])
	m.set_physics_process(true)
	# команды набора клавишами и бой с паузой
	await key(KEY_A, false, true)
	await key(KEY_Y)
	var held := true
	for s in 4:
		held = held and m.squad_order[s] == m.ORDER_HOLD
	await key(KEY_G)
	var one_only: bool = m.hud_msg == "Выбери один отряд"
	await key(KEY_Q)
	await key(KEY_SPACE)
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	while m.tick_counter < 30:
		await process_frame
	await key(KEY_SPACE)
	var tick: int = m.tick_counter
	var at: PackedVector2Array = m.pos.duplicate()
	await drag(MOUSE_BUTTON_LEFT, scr(Vector2(350, 150)), scr(Vector2(1650, 700)))
	var boxed_all: bool = m.sel_mask & mask_of([0, 2, 3]) == mask_of([0, 2, 3])
	await drag(MOUSE_BUTTON_RIGHT, scr(Vector2(600, 330)), scr(Vector2(1400, 330)))
	await key(KEY_UP)
	await click(MOUSE_BUTTON_LEFT, scr(m.squad_pos[1]))
	await click(MOUSE_BUTTON_RIGHT, scr(Vector2(1000, 600)))
	await step(10)
	var frozen: bool = m.paused and m.tick_counter == tick and m.pos == at
	await key(KEY_SPACE)
	while m.tick_counter < tick + 30:
		await process_frame
	check("(л) Q/W/E всем выбранным; G при нескольких выбранных — сообщение; бой: на паузе рамка, расстановка группы, стрелка, клик меняют данные, юниты стоят; после паузы бой идёт",
		held and one_only and boxed_all and frozen and not m.paused and m.pos != at, "%s %s %s %s маска %d" % [held, one_only, boxed_all, frozen, m.sel_mask])
	await key(KEY_P)
	await key(KEY_A, false, true)
	await step(5)
	await key(KEY_P)
	await step(5)
	print("  окно возвращалось на передний план: %d раз" % refocus)
	print("SMOKE: провалов %d" % fails)
	quit()
