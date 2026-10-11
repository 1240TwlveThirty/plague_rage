extends SceneTree
# Smoke v39, этап 1, со сценой и окном (без --headless): буфер отрисовки на паузе (в), фокус интерфейса (г),
# клавиши, кнопки и ползунок синтетическими событиями (и), R после поражения (б).
var fails := 0
var m: Node2D
var presses := 0       # сигналы pressed всех кнопок
var slides := 0        # сигналы value_changed ползунка

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
		root.push_input(e, true)
	await step(2)

# Клик мышью в координатах экрана (1920 × 1080).
func click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		root.push_input(e, true)
		await step(1)
	await step(1)

func controls(node: Node, out: Array) -> void:
	if node is Control:
		out.append(node)
	for c in node.get_children():
		controls(c, out)

func used() -> int:
	var n := 0
	for s in m.SQUAD_MAX:
		n += m.squad_used[s]
	return n

# Позиция юнита в буфере, какой она должна быть без интерполяции: pos + статичный сдвиг + отдача.
func buf_error(buf: PackedFloat32Array) -> float:
	var worst := 0.0
	for i in m.count:
		var p: Vector2 = m.pos[i] + m.unit_render_off[i]
		if m.unit_anim_t[i] > 0.0 and m.type_recoil[m.unit_type[i]] > 0.0:
			p += m._recoil_offset(i)
		var o: int = i * m.FLOATS_PER_UNIT
		worst = maxf(worst, maxf(absf(buf[o + 3] - p.x), absf(buf[o + 7] - p.y)))
	return worst

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(8)
	var all := []
	controls(m, all)
	var focusable := PackedStringArray()
	for c in all:
		if (c as Control).focus_mode != Control.FOCUS_NONE:
			focusable.append(c.get_class())
		if c is Button:
			(c as Button).pressed.connect(func() -> void: presses += 1)
		if c is Slider:
			(c as Slider).value_changed.connect(func(_v: float) -> void: slides += 1)
	check("(г) у всех Control (%d в дереве) focus_mode = NONE" % all.size(), focusable.is_empty() and all.size() > 10, ", ".join(focusable))
	check("передышка: ползунок доли и кнопка режима видны, надписи «ПАУЗА» нет", m.split_box.is_visible_in_tree() and not m.pause_label.visible and not m.pause_dim.visible,
		"«%s», «%s»" % [m.split_label.text, m.split_mode_button.text])
	# передышка: Space начинает волну
	await key(KEY_SPACE)
	check("(б) Space в передышке начинает волну", m.wave_state == m.WS_BATTLE and not m.paused)
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._place_formation(0, Vector2(700, 250), Vector2(940, 250))   # отряд идёт: позиции меняются каждый тик
	while m.tick_counter < 20:   # панель обновляется раз в 0.25 с
		await process_frame
	check("в бою без паузы кнопки отрядов и ползунок скрыты", not m.squad_actions.is_visible_in_tree() and not m.split_box.is_visible_in_tree())
	# (в) пауза: буфер без интерполяции
	await key(KEY_SPACE)
	var tick0: int = m.tick_counter
	var pos0: PackedVector2Array = m.pos.duplicate()
	var fracs := {}
	var bufs := []
	for f in 12:
		await process_frame
		fracs[snappedf(Engine.get_physics_interpolation_fraction(), 0.0001)] = true
		bufs.append(m.buf.duplicate())
		OS.delay_msec(7)   # кадры разной длины: доля тика заведомо разная
	var same_buf := true
	var worst := 0.0
	for b in bufs:
		same_buf = same_buf and b == bufs[1]
		worst = maxf(worst, buf_error(b))
	check("(в) Space в бою ставит паузу: надпись «ПАУЗА» и затемнение 0.12 видны, тики стоят", m.paused and m.pause_label.visible and m.pause_dim.visible
		and is_equal_approx(m.pause_dim.color.a, 0.12) and m.tick_counter == tick0 and m.pos == pos0, "тик %d" % tick0)
	check("(в) на паузе %d кадров с разной долей тика (%d разных значений): буфер MultiMesh (%d юнитов) один и тот же и равен pos + сдвиг, без lerp" % [bufs.size(), fracs.size(), m.count],
		same_buf and worst < 0.001 and fracs.size() >= 3 and m.count >= 100, "наибольшее отличие от pos %.5f px" % worst)
	var hud := Rect2(m.hud_label.global_position, m.hud_label.size)
	var pl := Rect2(m.pause_label.global_position, m.pause_label.size)
	var sp := Rect2(m.squad_panel.global_position, m.squad_panel.size)
	check("надпись «ПАУЗА» по центру сверху, под HUD, панель отрядов не перекрывает", pl.position.y >= hud.end.y - 1.0 and absf(pl.get_center().x - 960.0) < 2.0 and not pl.intersects(sp),
		"HUD до y = %.0f, «ПАУЗА» %s, панель %s" % [hud.end.y, pl, sp])
	check("на паузе в бою кнопки отрядов, ползунок и кнопка режима видны; «+ Отряд» и «Слить» выключены", m.split_box.is_visible_in_tree() and m.squad_actions.is_visible_in_tree()
		and m.action_buttons[0].disabled and not m.action_buttons[1].disabled and m.action_buttons[2].disabled)
	# (г) клик по «Разделить», затем Space: второго деления нет
	var u0 := used()
	await click(m.action_buttons[1].get_global_rect().get_center())
	var u1 := used()
	var p1 := presses
	var sl0 := slides
	await key(KEY_ENTER)
	await key(KEY_SPACE)
	var unpaused: bool = not m.paused
	await key(KEY_SPACE)
	check("(г) клик мышью по «Разделить» делит (отрядов %d → %d); затем Enter и Space кнопку не нажимают: Space снял паузу, делений больше нет" % [u0, u1],
		u1 == u0 + 1 and presses == p1 and used() == u1 and unpaused and m.paused and root.gui_get_focus_owner() == null, "сигналов pressed %d" % presses)
	# ползунок: клик двигает, стрелки и Space — нет
	var sr: Rect2 = m.split_slider.get_global_rect()
	await click(Vector2(sr.position.x + sr.size.x * 0.25, sr.get_center().y))
	var val: float = m.split_slider.value
	var frac: float = m.split_frac
	sl0 = slides
	p1 = presses
	m.hud_msg = ""
	for c in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER]:
		await key(c)
	check("(г) клик по ползунку меняет долю (%d%%, «%s»); стрелки и Enter его не двигают и кнопок не нажимают" % [roundi(frac * 100.0), m.split_label.text],
		val != 50.0 and is_equal_approx(frac, val / 100.0) and m.split_slider.value == val and slides == sl0 and presses == p1 and m.split_label.text == "Доля ухода: %d%%" % roundi(val))
	# (и) кнопка режима, K, G, P
	var mode0: int = m.split_mode
	await click(m.split_mode_button.get_global_rect().get_center())
	var mode1: int = m.split_mode
	await key(KEY_K)
	check("(и) кнопка режима и K меняют режим по кругу", mode1 == (mode0 + 1) % 4 and m.split_mode == (mode0 + 2) % 4, m.split_mode_button.text)
	await key(KEY_1)
	u0 = used()
	await key(KEY_G)
	check("(и) G на паузе делит выбранный отряд", used() == u0 + 1 and m.selected_squad >= 2, "отряд %d: %d юнитов" % [m.selected_squad + 1, m.squad_n[m.selected_squad]])
	check("(и) за всё время паузы тики и позиции юнитов не менялись", m.tick_counter == tick0 and m.pos == pos0)
	await key(KEY_P)
	var p_off: bool = not m.paused
	# (в) после паузы интерполяция снова работает: буфер меняется между кадрами и не совпадает с pos
	var moved := 0
	var lerped := 0
	var prev: PackedFloat32Array = m.buf.duplicate()
	for f in 40:
		await process_frame
		OS.delay_msec(3)
		if m.buf != prev:
			moved += 1
		if buf_error(m.buf) > 0.01:
			lerped += 1
		prev = m.buf.duplicate()
	check("(в) P снимает паузу: тики идут, буфер меняется между кадрами и интерполируется между тиками", p_off and m.tick_counter > tick0 and moved >= 10 and lerped >= 5 and not m.pause_label.visible,
		"кадров с новым буфером %d из 40, с позицией между тиками %d, тиков прошло %d" % [moved, lerped, m.tick_counter - tick0])
	await key(KEY_G)
	check("(и) G в бою без паузы: сообщение", m.hud_msg == "Поставь паузу (Space)", m.hud_msg)
	# (б) поражение: пауза недоступна, R начинает заново
	await key(KEY_P)
	var was: bool = m.paused
	await key(KEY_P)
	m.gate_hp = 0.0
	var t := 0
	while m.wave_state != m.WS_DEFEAT and t < 300:
		await process_frame
		t += 1
	await key(KEY_SPACE)
	await key(KEY_P)
	check("(б) поражение (wave_state 1): Space и P паузу не ставят", was and m.wave_state == m.WS_DEFEAT and not m.paused and not m.pause_label.visible)
	await key(KEY_R)
	await step(6)
	var fresh: Node2D = current_scene
	check("(б) R после поражения начинает заново: новая сцена, передышка, паузы нет, выбран отряд 1", fresh != m and fresh != null and fresh.wave_state == fresh.WS_RESPITE and not fresh.paused
		and fresh.selected_squad == 0 and fresh.wave_number == 0)
	m = fresh
	m.record_path = "user://record_bench.json"
	# передышка: деление и стрелки работают без паузы, слияние возвращает
	await key(KEY_G)
	var split_ok: bool = used() == 3
	await key(KEY_UP)
	await key(KEY_M)
	check("(и) передышка: G делит, ↑ ставит на пост, M сливает обратно", split_ok and used() == 2 and m.squad_n[0] == m.INFANTRY_COUNT)
	await step(5)
	print("SMOKE: провалов %d" % fails)
	quit()
