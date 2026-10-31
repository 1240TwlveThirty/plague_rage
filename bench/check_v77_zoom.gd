extends SceneTree
# Задача 27, этап 2 (без окна): ручной зум камеры. Настоящий забег (автозагрузка Game, своё сохранение), события мыши и
# клавиш — через root.push_input (как от системы: интерфейс, затем _unhandled_input сцены). Пределы, шаг — из data/camera.json.
#   Колесо без Shift: множитель × zoom_step (вверх) / ÷ (вниз), в пределах zoom_user_min..max; точка мира под курсором
#   остаётся под ним (сверено обратным преобразованием холста); Shift + колесо зум не меняет.
#   Камера не выходит за поле: вид меньше поля по оси — внутри поля, больше — поле по центру; у края поля центр упирается.
#   Сброс — действие camera_zoom_reset (по умолчанию из ui_layout.json keys), в группе «Камера» вкладки «Управление»,
#   переназначается; множитель 1, центр поля.
#   Множитель живёт в забеге (перезапуск сцены боя — тот же), новый забег — 1.
#   Интерфейс не масштабируется: слой HUD без преобразования, верхняя панель на том же месте.
#   Приказы мышью при зуме ×2 и ×0,7: рамка ЛКМ выбирает отряд по мировым координатам, ПКМ-клик — цель в мировой точке.
#   Тряска при любом зуме — в px экрана (не больше shake_cap).
#   Симуляция: зум — только отрисовка (поля камеры и зума не трогают тики; регрессия — отдельным шагом run_all).
var fails := 0
var cam: Dictionary
var m: Node2D
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func ss() -> Vector2:
	return m.get_viewport_rect().size

# Мир -> экран и обратно независимо от main: преобразование холста вьюпорта (камера с зумом и смещением).
func to_screen(w: Vector2) -> Vector2:
	return m.get_viewport().get_canvas_transform() * w

func to_world(sp: Vector2) -> Vector2:
	return m.get_viewport().get_canvas_transform().affine_inverse() * sp

func wheel(sp: Vector2, up: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.factor = 1.0
	e.shift_pressed = shift
	e.position = sp
	e.global_position = sp
	root.push_input(e, true)   # координаты вьюпорта (px интерфейса), не окна
	var r := e.duplicate()
	r.pressed = false
	root.push_input(r, true)

func button(btn: MouseButton, sp: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = sp
	e.global_position = sp
	root.push_input(e, true)   # координаты вьюпорта (px интерфейса), не окна

func motion(sp: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = sp
	e.global_position = sp
	root.push_input(e, true)   # координаты вьюпорта (px интерфейса), не окна

func key(code: Key) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = p
		root.push_input(e, true)   # координаты вьюпорта (px интерфейса), не окна

func settle() -> void:
	var t_end := Time.get_ticks_msec() + 3000   # сглаживание — по реальному времени, не по кадрам
	while m.zoom_user != m.zoom_user_target and Time.get_ticks_msec() < t_end:
		await process_frame
	await process_frame

# Вид в поле: по оси, где вид меньше поля, — внутри; где больше — по центру поля.
func view_ok() -> bool:
	var vr: Rect2 = m.view_rect()
	for a in 2:
		if vr.size[a] <= m.FIELD[a] + 0.01:
			if vr.position[a] < -0.01 or vr.end[a] > m.FIELD[a] + 0.01:
				return false
		elif absf(vr.get_center()[a] - m.FIELD[a] * 0.5) > 0.01:
			return false
	return true

func set_zoom(mult: float, sp: Vector2) -> void:
	m.zoom_user_target = mult
	m.zoom_anchor_screen = sp
	m.zoom_anchor_world = m.screen_to_world(sp)
	m._store_zoom()
	await settle()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	cam = JSON.parse_string(FileAccess.get_file_as_string("res://data/camera.json"))
	var lay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	var zmin := float(cam.zoom_user_min)
	var zmax := float(cam.zoom_user_max)
	var zstep := float(cam.zoom_step)
	g = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute("user://bench_v77z")
	g.save_path = "user://bench_v77z/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(8)
	m = current_scene
	m.banner_hidden = true
	m.banner.visible = false
	check("data/camera.json: пределы и шаг — числа, min < 1 < max, шаг > 1", zmin < 1.0 and zmax > 1.0 and zstep > 1.0 and zmin <= 0.7 and zmax >= 2.0, "%s..%s шаг %s" % [zmin, zmax, zstep])
	check("в начале забега множитель 1, зум базовый (поле вписано)", m.zoom_user == 1.0 and is_equal_approx(m.camera.zoom.x, m.camera_min_zoom()) and view_ok())
	var hud_rect: Rect2 = m.top_hud.get_global_rect()
	var hud_xf: Transform2D = m.top_hud.get_global_transform_with_canvas()

	# колесо к точке под курсором
	var sp := Vector2(700, 600)
	var w0 := to_world(sp)
	wheel(sp, true)
	await settle()
	var w1 := to_world(sp)
	check("колесо вверх: множитель × шаг (%s)" % zstep, is_equal_approx(m.zoom_user, zstep), str(m.zoom_user))
	check("зум = базовый × множитель", is_equal_approx(m.camera.zoom.x, m.camera_min_zoom() * m.zoom_user))
	check("точка мира под курсором осталась под ним", w0.distance_to(w1) < 0.5, "%s -> %s" % [w0, w1])
	check("вид в поле", view_ok(), str(m.view_rect()))
	wheel(sp, true, true)
	await settle()
	check("Shift + колесо зум не меняет (поворот отряда)", is_equal_approx(m.zoom_user, zstep))
	for i in 40:
		wheel(sp, true)
	await settle()
	check("много щелчков вверх — не больше zoom_user_max", is_equal_approx(m.zoom_user, zmax), str(m.zoom_user))
	check("у максимума вид в поле", view_ok(), str(m.view_rect()))
	check("интерфейс не масштабируется: верхняя панель на месте, без преобразования камеры",
		m.top_hud.get_global_rect() == hud_rect and m.top_hud.get_global_transform_with_canvas() == hud_xf)
	check("подписи у курсора в px экрана: ui_k × зум = базовый", is_equal_approx(m.ui_k() * m.camera.zoom.x, m.camera_min_zoom()))
	for i in 60:
		wheel(sp, false)
	await settle()
	check("много щелчков вниз — не меньше zoom_user_min", is_equal_approx(m.zoom_user, zmin), str(m.zoom_user))
	check("у минимума поле по центру (вид шире поля), вид в поле по остальным осям", view_ok(), str(m.view_rect()))

	# у края поля: зум к точке у угла экрана — точка под курсором на месте, вид в поле; якорь за краем поля — вид упирается в край
	key(KEY_HOME)
	await settle()
	for corner in [Vector2(20, 20), ss() - Vector2(20, 20)]:
		await set_zoom(1.0, ss() * 0.5)
		var wc := to_world(corner)
		for i in 40:
			wheel(corner, true)
		await settle()
		check("зум к углу экрана %s: точка под курсором на месте, вид в поле" % corner, to_world(corner).distance_to(wc) < 0.5 and view_ok(), str(m.view_rect()))
	m.zoom_anchor_screen = ss() * 0.5
	m.zoom_anchor_world = Vector2(-400, -400)
	m.zoom_user_target = zmax * 0.99
	await settle()
	var vr: Rect2 = m.view_rect()
	check("якорь левее и выше поля: вид прижат к левому верхнему краю поля, не за ним", view_ok() and vr.position.length() < 0.5, str(vr))
	m.zoom_anchor_world = m.FIELD + Vector2(400, 400)
	m.zoom_user_target = zmax
	await settle()
	vr = m.view_rect()
	check("якорь правее и ниже поля: вид прижат к правому нижнему краю", view_ok() and vr.end.distance_to(m.FIELD) < 0.5, str(vr))

	# сброс: действие, клавиша по умолчанию, группа «Камера», переназначение
	var S: GDScript = load("res://scripts/settings.gd")
	check("действие camera_zoom_reset есть, клавиша по умолчанию из ui_layout.json keys (%s)" % lay.keys.camera_zoom_reset,
		InputMap.has_action("camera_zoom_reset") and OS.get_keycode_string(S.action_key("camera_zoom_reset")) == lay.keys.camera_zoom_reset)
	var cam_group := []
	for gr in lay.controls_groups:
		if gr.title == "UI_SETTINGS_GROUP_CAMERA":
			cam_group = gr.actions
	check("в группе «Камера» вкладки «Управление» — сброс зума, действие переназначаемое", "camera_zoom_reset" in cam_group and "camera_zoom_reset" in S.REBINDABLE)
	var SM := load("res://scripts/settings_menu.gd")
	var groups: Array = SM.key_groups_for(lay.controls_groups, S.REBINDABLE, S.hidden_actions())
	var shown := false
	for gr in groups:
		if gr[0] == "UI_SETTINGS_GROUP_CAMERA" and "camera_zoom_reset" in gr[1]:
			shown = true
	check("группа «Камера» показывается (не пуста)", shown)
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		var t: String = S.action_title("camera_zoom_reset")
		check("подпись действия (%s): «%s»" % [loc, t], t != "" and t != "ACTION_CAMERA_ZOOM_RESET")
	TranslationServer.set_locale("ru")
	key(KEY_HOME)
	await settle()
	check("Home: множитель 1, центр поля", m.zoom_user == 1.0 and m.camera.position.distance_to(m._camera_clamp(m.FIELD * 0.5, m.camera.zoom.x)) < 0.01 and view_ok())
	var st: Node = root.get_node("Settings")
	var r: Dictionary = st.rebind("camera_zoom_reset", KEY_K)
	check("переназначение на K принято", S.action_key("camera_zoom_reset") == KEY_K, str(r))
	wheel(sp, true)
	await settle()
	key(KEY_K)
	await settle()
	check("K сбрасывает зум", m.zoom_user == 1.0)
	st.reset_keys()
	check("сброс клавиш: снова %s" % lay.keys.camera_zoom_reset, OS.get_keycode_string(S.action_key("camera_zoom_reset")) == lay.keys.camera_zoom_reset)

	# тряска при любом зуме — в px экрана
	var cap_was: float = m.shake_cap
	m.shake_cap = 6.0   # предел тряски в px экрана (в игре — из data/fx.json и настройки; здесь — заметный)
	for mult in [zmin, 1.0, zmax]:
		await set_zoom(mult, ss() * 0.5)
		var worst := 0.0
		var least := INF
		for i in 50:
			var px: float = (m._shake_offset(100.0) * m.camera.zoom.x).length()
			worst = maxf(worst, px)
			least = minf(least, px)
		check("тряска ×%s: смещение на экране 1..shake_cap px, как при любом зуме" % mult, worst <= 6.01 and least >= 0.99 and worst >= 5.0, "%.2f..%.2f" % [least, worst])
	m.shake_cap = cap_was

	# приказы мышью при ×2 и ×0,7
	for mult in [2.0, 0.7]:
		await set_zoom(1.0, ss() * 0.5)
		var s0 := 0
		var c: Vector2 = m.squad_pos[s0]
		await set_zoom(mult, to_screen(c))   # отряд под точкой зума — на экране
		m.sel_mask = 0
		var a := to_screen(c + Vector2(-90, -60))
		var b := to_screen(c + Vector2(90, 60))
		button(MOUSE_BUTTON_LEFT, a, true)
		motion((a + b) * 0.5)
		motion(b)
		await step(1)
		check("×%s: во время рамки её углы в мире там, где курсор" % mult, m.box_active and m.box_start.distance_to(c + Vector2(-90, -60)) < 0.5 and m.box_cur.distance_to(c + Vector2(90, 60)) < 0.5,
			"%s %s" % [m.box_start, m.box_cur])
		button(MOUSE_BUTTON_LEFT, b, false)
		await step(1)
		check("×%s: рамка ЛКМ вокруг отряда в мире выбрала его" % mult, (m.sel_mask >> s0) & 1 == 1, "sel %d" % m.sel_mask)
		var target: Vector2 = c + Vector2(0, -160)
		var tp := to_screen(target)
		button(MOUSE_BUTTON_RIGHT, tp, true)
		await step(1)
		check("×%s: ПКМ нажата — точка приказа в мире под курсором" % mult, m.drag_active and m.drag_start.distance_to(target) < 0.5, str(m.drag_start))
		button(MOUSE_BUTTON_RIGHT, tp, false)
		await step(1)
		var only_one: bool = m._order_list().size() == 1
		check("×%s: ПКМ-клик — цель отряда в этой мировой точке" % mult, only_one and m.squad_target[s0].distance_to(target) < 0.5, "%s против %s" % [m.squad_target[s0], target])

	# множитель в забеге и новый забег
	await set_zoom(2.0, ss() * 0.5)
	reload_current_scene()
	await step(8)
	m = current_scene
	check("перезапуск сцены боя в том же забеге: множитель тот же (2)", is_equal_approx(m.zoom_user, 2.0) and is_equal_approx(m.camera.zoom.x, m.camera_min_zoom() * 2.0) and view_ok(), str(m.zoom_user))
	g.start_run(1)
	await step(8)
	m = current_scene
	check("новый забег: множитель 1", m.zoom_user == 1.0 and g.camera_zoom_user == 1.0)

	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v77z")
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
