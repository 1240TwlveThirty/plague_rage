extends SceneTree
# Smoke UI v29: перетаскивание с якорем, короткий клик, ПКМ и Esc, F, Shift+колесо, H, баннер сверху,
# счётчик стрел в отладочной строке на волнах 1-3. Синтетические события мыши (push_input) и клавиши.
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

func button(index: MouseButton, screen: Vector2, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.shift_pressed = shift
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

func slot_world(i: int) -> Vector2:
	var s: int = m.unit_squad[i]
	return m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])

# Мировая позиция слота 0 (ряд 0, колонка 0) отряда s.
func slot0(s: int) -> Vector2:
	for i in m.count:
		if m.unit_squad[i] == s and m.unit_slot_idx[i] == 0:
			return slot_world(i)
	return Vector2.INF

func arrows_in_label() -> Array:
	var re := RegEx.new()
	re.compile("стрелы за волну: (\\d+)/(\\d+)")
	var r := re.search(m.fps_label.text)
	return [-1, -1] if r == null else [int(r.get_string(1)), int(r.get_string(2))]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(6)
	# баннер: сверху по центру, y = 120, ширина 700, полупрозрачный фон, панели не перекрыты
	var r: Rect2 = m.banner.get_global_rect()
	var bg: StyleBoxFlat = m.banner.get_theme_stylebox("panel")
	check("баннер старта: верх y = 120, по центру, ширина ≤ 700, фон с альфой 0.55, панели не перекрыты", m.banner.visible and absf(r.position.y - 120.0) <= 0.5
		and absf(r.get_center().x - 960.0) <= 1.0 and r.size.x <= 700.0 and is_equal_approx(bg.bg_color.a, 0.55)
		and not r.intersects(m.squad_panel.get_global_rect()) and not r.intersects(m.shop_panel.get_global_rect()) and r.end.y <= 1080.0,
		"баннер %s, отряды %s, магазин %s" % [r, m.squad_panel.get_global_rect(), m.shop_panel.get_global_rect()])
	await key(KEY_H)
	var hidden: bool = not m.banner.visible
	await key(KEY_H)
	check("H в передышке скрывает и снова показывает баннер", hidden and m.banner.visible)
	# 1. перетаскивание слева направо сквозь баннер: лицо вверх, якорь A на месте
	var a := Vector2(900, 450)
	var b := Vector2(1150, 450)
	await button(MOUSE_BUTTON_LEFT, to_screen(a), true)
	await motion(to_screen(Vector2(1000, 450)))
	check("ЛКМ по карте начинает перетаскивание, движение обновляет предпросмотр", m.drag_active and m.drag_cur.distance_to(Vector2(1000, 450)) < 0.01, "баннер виден: %s" % m.banner.visible)
	await motion(to_screen(b))
	await step(3)
	await button(MOUSE_BUTTON_LEFT, to_screen(b), false)
	var want := roundi(250.0 / m.SLOT_SPACING) + 1
	check("слева направо: лицо вверх, колонка 0 в точке A (0.5 px), ширина по длине", not m.drag_active and m.squad_width[0] == want
		and absf(angle_difference(m.squad_angle[0], -PI / 2.0)) < 0.001 and slot0(0).distance_to(a) <= 0.5 and m.squad_target[0] == m.squad_pos[0],
		"ширина %d, слот 0 в %s" % [m.squad_width[0], slot0(0)])
	# 2. справа налево: лицо вниз
	await button(MOUSE_BUTTON_LEFT, to_screen(b), true)
	await motion(to_screen(a))
	await button(MOUSE_BUTTON_LEFT, to_screen(a), false)
	check("справа налево: лицо вниз, колонка 0 в точке нажатия", absf(angle_difference(m.squad_angle[0], PI / 2.0)) < 0.001 and slot0(0).distance_to(b) <= 0.5)
	# 3. F во время протяжки инвертирует лицо
	await button(MOUSE_BUTTON_LEFT, to_screen(a), true)
	await motion(to_screen(b))
	await key(KEY_F)
	var flipped: bool = m.drag_flip and m.drag_active
	await step(3)
	await button(MOUSE_BUTTON_LEFT, to_screen(b), false)
	check("F во время протяжки слева направо: лицо вниз, линия та же", flipped and absf(angle_difference(m.squad_angle[0], PI / 2.0)) < 0.001 and m.squad_width[0] == want and not m.drag_active)
	# 4. F вне протяжки: разворот кругом на месте
	var before := {}
	for i in m.count:
		if m.unit_squad[i] == 0:
			before[i] = slot_world(i)
	m.squad_compact_t = 0.0   # ближайшее сжатие строя не раньше чем через 0.5 с: замер сразу после F
	await key(KEY_F)
	var worst := 0.0
	for i in before:
		worst = maxf(worst, slot_world(i).distance_to(before[i]))
	check("F вне протяжки: лицо вверх, слоты в мире на месте", absf(angle_difference(m.squad_angle[0], -PI / 2.0)) < 0.001 and worst <= 0.01, "макс. сдвиг %.4f px" % worst)
	# 5. Shift + колесо поворачивает, колесо без Shift — нет
	var ang: float = m.squad_angle[0]
	var target: Vector2 = m.squad_target[0]
	await button(MOUSE_BUTTON_WHEEL_UP, to_screen(Vector2(1000, 300)), true)
	var no_shift: bool = m.squad_angle[0] == ang
	await button(MOUSE_BUTTON_WHEEL_UP, to_screen(Vector2(1000, 300)), true, true)
	var up: float = angle_difference(ang, m.squad_angle[0])
	await button(MOUSE_BUTTON_WHEEL_DOWN, to_screen(Vector2(1000, 300)), true, true)
	await button(MOUSE_BUTTON_WHEEL_DOWN, to_screen(Vector2(1000, 300)), true, true)
	var down: float = angle_difference(ang, m.squad_angle[0])
	check("Shift+колесо: вверх −15°, вниз +15°, цель не меняется; без Shift колесо не действует", no_shift and absf(up + deg_to_rad(15.0)) < 0.001 and absf(down - deg_to_rad(15.0)) < 0.001 and m.squad_target[0] == target,
		"%.1f° / %.1f°" % [rad_to_deg(up), rad_to_deg(down)])
	# 6. короткий клик, ПКМ, Esc
	var w0: int = m.squad_width[0]
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(700, 300)), true)
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(705, 303)), false)
	check("короткий клик: только цель отряда", m.squad_target[0].distance_to(Vector2(700, 300)) < 0.01 and m.squad_width[0] == w0 and not m.drag_active)
	m.squad_target[0] = m.squad_pos[0]   # отряд остаётся на месте для следующих шагов
	var ang0: float = m.squad_angle[0]
	var snap := [m.squad_target[0], m.squad_width[0], m.squad_user_width[0]]
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(800, 500)), true)
	await motion(to_screen(Vector2(1000, 520)))
	await button(MOUSE_BUTTON_RIGHT, to_screen(Vector2(1000, 520)), true)
	var c1: bool = not m.drag_active
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1000, 520)), false)
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(800, 500)), true)
	await motion(to_screen(Vector2(1000, 520)))
	await key(KEY_ESCAPE)
	var c2: bool = not m.drag_active
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1000, 520)), false)
	check("ПКМ и Esc отменяют перетаскивание, ничего не меняется", c1 and c2 and snap == [m.squad_target[0], m.squad_width[0], m.squad_user_width[0]] and m.squad_angle[0] == ang0)
	# 7. не помещается: якорь у стены, блок сдвигается вдоль лица
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(900, 728)), true)
	await motion(to_screen(Vector2(1000, 728)))
	await button(MOUSE_BUTTON_LEFT, to_screen(Vector2(1000, 728)), false)
	var low := 0.0
	for i in m.count:
		if m.unit_squad[i] == 0:
			low = maxf(low, slot_world(i).y)
	check("у стены: строй не ниже WALL_Y - 12", low <= m.WALL_Y - 12.0 + 0.02, "нижний слот y = %.1f, слот 0 в %s" % [low, slot0(0)])
	# 8. волны 1-3: баннер скрывается, счётчик стрел в отладочной строке растёт и сбрасывается
	await key(KEY_2)
	var ring_arch: float = m._range_ring_radius(m.selected_squad)
	await key(KEY_1)
	var ring_inf: float = m._range_ring_radius(m.selected_squad)
	check("кольцо дальности: у выбранных лучников есть (%.0f px), у пехоты нет" % ring_arch, ring_arch > 0.0 and ring_inf == 0.0)
	m._place_formation(0, Vector2(953, 598), Vector2(1067, 598))   # пехота обратно на дорогу, лицом вверх
	var rows := []
	var grew := true
	for wave in 3:
		await key(KEY_SPACE)
		await step(3)
		var at_start := arrows_in_label()
		var hidden_now: bool = not m.banner.visible
		var t := 0
		while m.wave_state == m.WS_BATTLE and t < 3600:
			m._physics_process(1.0 / 30.0)   # ускоренно: тики вручную
			t += 1
			if t % 300 == 0:
				await process_frame
		await step(4)
		var at_end := arrows_in_label()
		grew = grew and hidden_now and at_start[0] == 0 and at_end[0] > 0 and at_end[1] > 0 and at_end[1] <= at_end[0] and at_end[0] == m.arrows_fired and m.wave_state == m.WS_RESPITE
		rows.append("волна %d: %d/%d" % [m.wave_number, at_end[0], at_end[1]])
	check("волны 1-3: баннер скрыт в бою, «стрелы за волну» с нуля растут (выпущено/попало)", grew, ", ".join(rows))
	check("после волны баннер снова показан сверху", m.banner.visible and absf(m.banner.get_global_rect().position.y - 120.0) <= 0.5)
	await key(KEY_SPACE)
	await key(KEY_H)
	check("в бою H не действует (баннер скрыт)", m.wave_state == m.WS_BATTLE and not m.banner.visible and not m.banner_hidden)
	print("SMOKE: провалов %d" % fails)
	quit()
