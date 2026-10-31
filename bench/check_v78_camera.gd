extends SceneTree
# Задача 28, этапы 1 и 2 (без окна): предел отдаления и перетаскивание камеры зажатым колесом. Настоящий забег (автозагрузка
# Game, своё сохранение), события мыши — через root.push_input. Значения — из data/camera.json.
#   Этап 1: zoom_user_min = 1.0 (не меньше CAMERA_ZOOM_FLOOR); при 1.0 вид внутри поля по обеим осям у любого края (чёрных
#   полос нет), колесо вниз дальше не отдаляет; файл с прежним 0.7 и множитель забега 0.7 зажимаются до 1.0; тряска у края
#   поля не выводит вид за поле, по свободной оси не урезается.
#   Этап 2: зажатая средняя кнопка — перетаскивание: точка мира под курсором остаётся под ним сразу (без сглаживания, в том же
#   кадре), вид в поле, у края упирается и обратным движением сдвигается сразу; на зуме 1.0 по высоте не двигается; работает на
#   паузе (P), курсор и отпускание над панелью перетаскивание не обрывают / обрывают; движение без зажатой кнопки — конец;
#   зум колесом во время перетаскивания — дальше точка под курсором та же; ЛКМ-рамка и ПКМ не начинаются; средняя кнопка не
#   назначается на действия; подсказка camera в data/hints.json (ru/en); строки «Колесо мыши» и «Зажатое колесо» в группе
#   «Камера» вкладки «Управление»; pan_sensitivity из data.
var fails := 0
var cam: Dictionary
var m: Node2D
var g: Node
const DIR := "user://bench_v78cam"

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func ss() -> Vector2:
	return m.get_viewport_rect().size

func to_world(sp: Vector2) -> Vector2:
	return m.get_viewport().get_canvas_transform().affine_inverse() * sp

func wheel(sp: Vector2, up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.factor = 1.0
	e.position = sp
	e.global_position = sp
	root.push_input(e, true)   # координаты вьюпорта (px интерфейса), не окна
	var r := e.duplicate()
	r.pressed = false
	root.push_input(r, true)

func mmb(sp: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_MIDDLE
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_MIDDLE if pressed else 0
	e.position = sp
	e.global_position = sp
	root.push_input(e, true)

func move(sp: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = sp
	e.global_position = sp
	e.button_mask = MOUSE_BUTTON_MASK_MIDDLE if held else 0
	root.push_input(e, true)

func settle() -> void:
	var t_end := Time.get_ticks_msec() + 3000   # сглаживание — по реальному времени, не по кадрам
	while m.zoom_user != m.zoom_user_target and Time.get_ticks_msec() < t_end:
		await process_frame
	await process_frame

# Вид (со смещением тряски, если off) внутри поля по обеим осям: за краем карты ничего не видно.
func inside(vr: Rect2) -> bool:
	return vr.position.x >= -0.01 and vr.position.y >= -0.01 and vr.end.x <= m.FIELD.x + 0.01 and vr.end.y <= m.FIELD.y + 0.01

func view_with_offset() -> Rect2:
	var vr: Rect2 = m.view_rect()
	vr.position += m.camera.offset
	return vr

func set_zoom(mult: float, sp: Vector2, world: Vector2) -> void:
	m.zoom_user_target = mult
	m.zoom_anchor_screen = sp
	m.zoom_anchor_world = world
	m._store_zoom()
	await settle()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	cam = JSON.parse_string(FileAccess.get_file_as_string("res://data/camera.json"))
	g = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(8)
	m = current_scene
	m.banner_hidden = true
	m.banner.visible = false
	await t_limit()
	await t_pan()
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR + "/camera.json")
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_limit() -> void:
	print("этап 1: предел отдаления")
	var zmin := float(cam.zoom_user_min)
	check("data/camera.json: zoom_user_min = 1.0, не меньше CAMERA_ZOOM_FLOOR (%s), в коде по умолчанию тоже" % m.CAMERA_ZOOM_FLOOR,
		zmin == 1.0 and zmin >= m.CAMERA_ZOOM_FLOOR and float(m.CAMERA_DEFAULTS.zoom_user_min) >= m.CAMERA_ZOOM_FLOOR and float(m.cam_cfg.zoom_user_min) == zmin)
	var base: float = m.camera_min_zoom()
	var vs := ss()
	check("базовый зум = max(vs.y/FIELD.y, vs.x/FIELD.x)", is_equal_approx(base, maxf(vs.y / m.FIELD.y, vs.x / m.FIELD.x)), str(base))
	check("в начале забега множитель 1, вид внутри поля", m.zoom_user == 1.0 and inside(m.view_rect()), str(m.view_rect()))
	var sp := Vector2(700, 600)
	for i in 30:
		wheel(sp, false)
	await settle()
	check("колесо вниз 30 раз: множитель 1, зум базовый — дальше не отдаляет", m.zoom_user == 1.0 and m.zoom_user_target == 1.0
		and is_equal_approx(m.camera.zoom.x, base), "%s %s" % [m.zoom_user, m.camera.zoom.x])
	var bad := []
	for anchor in [Vector2(-500, -500), Vector2(m.FIELD.x + 500, -500), Vector2(-500, m.FIELD.y + 500), m.FIELD + Vector2(500, 500), m.FIELD * 0.5]:
		await set_zoom(2.0, vs * 0.5, m.FIELD * 0.5)
		await set_zoom(1.0, vs * 0.5, anchor)
		var vr: Rect2 = m.view_rect()
		var c00 := to_world(Vector2.ZERO)
		var c11 := to_world(vs)
		if not inside(vr) or not inside(Rect2(c00, c11 - c00)):
			bad.append("%s: %s" % [anchor, vr])
	check("зум 1.0 к якорю за каждым углом поля и в центре: вид и углы экрана (преобразование холста) внутри поля — чёрных полос нет",
		bad.is_empty(), "; ".join(bad))
	# прежний предел 0.7: в файле данных и в множителе забега
	var f := FileAccess.open(DIR + "/camera.json", FileAccess.WRITE)
	var old := cam.duplicate()
	old.zoom_user_min = 0.7
	f.store_string(JSON.stringify(old))
	f.close()
	var c: Dictionary = m._load_camera_cfg(DIR + "/camera.json")
	check("файл с прежним zoom_user_min 0.7 при загрузке зажат до 1.0 (с предупреждением), остальное из файла",
		c.zoom_user_min == 1.0 and c.zoom_user_max == float(cam.zoom_user_max) and c.zoom_step == float(cam.zoom_step), str(c))
	g.camera_zoom_user = 0.7
	reload_current_scene()
	await step(8)
	m = current_scene
	check("множитель забега 0.7 (сохранён до задачи 28): новая сцена боя берёт 1.0, вид внутри поля", m.zoom_user == 1.0 and inside(m.view_rect()), str(m.zoom_user))
	m.banner_hidden = true
	m.banner.visible = false
	# тряска у края поля
	var cap_was: float = m.shake_cap
	m.shake_cap = 6.0
	await set_zoom(1.0, vs * 0.5, Vector2(0, 0))
	var out := 0
	var y_cut := 0
	for i in 200:
		var off: Vector2 = m._shake_offset(6.0)
		m.camera.offset = m._shake_in_field(off)
		var px: Vector2 = m.camera.offset * m.camera.zoom.x
		if not inside(view_with_offset()) or not px.is_equal_approx(px.round()) or px.length() > off.length() * m.camera.zoom.x + 0.01:
			out += 1
		if absf(m.camera.offset.y) < 0.001:
			y_cut += 1
	m.camera.offset = Vector2.ZERO
	check("тряска у левого верхнего края при зуме 1.0: вид со смещением всегда в поле, смещение — целые px экрана, не больше исходного (%d из 200 нет)" % out, out == 0)
	check("по высоте при зуме 1.0 вид равен полю — вертикальная тряска урезана до 0", y_cut == 200, str(y_cut))
	await set_zoom(2.0, vs * 0.5, m.FIELD * 0.5)
	var same := 0
	for i in 100:
		var off: Vector2 = m._shake_offset(6.0)
		if m._shake_in_field(off).is_equal_approx(off):
			same += 1
	check("в середине поля при ×2 тряска не урезается (%d из 100 без изменений)" % same, same == 100)
	m.shake_cap = cap_was
	await set_zoom(1.0, vs * 0.5, m.FIELD * 0.5)

func t_pan() -> void:
	print("этап 2: перетаскивание зажатым колесом")
	var vs := ss()
	check("data/camera.json: pan_sensitivity = 1.0 (1:1), в main из data", float(cam.pan_sensitivity) == 1.0 and float(m.cam_cfg.pan_sensitivity) == float(cam.pan_sensitivity))
	# зум 1.0: по высоте вид равен полю, по ширине есть запас
	await set_zoom(1.0, vs * 0.5, m.FIELD * 0.5)
	var a := Vector2(900, 500)
	var wa := to_world(a)
	var c0: Vector2 = m.camera.position
	mmb(a, true)
	move(a + Vector2(-100, -80))
	await step(1)   # преобразование холста Camera2D обновляет в кадре (до отрисовки)
	check("зум 1.0: сдвиг курсора на (-100, -80) — вид по ширине за курсором (точка под ним), по высоте на месте (вид = поле)",
		m.pan_active and absf(to_world(a + Vector2(-100, -80)).x - wa.x) < 0.5 and m.camera.position.y == c0.y and inside(m.view_rect()),
		"%s -> %s" % [c0, m.camera.position])
	mmb(a + Vector2(-100, -80), false)
	check("отпускание — конец перетаскивания", not m.pan_active)
	# ×2: точка под курсором в том же кадре
	await set_zoom(2.0, vs * 0.5, m.FIELD * 0.5)
	var bad := []
	var lag := []
	for d in [Vector2(-300, 120), Vector2(250, -200), Vector2(37, 11)]:
		a = vs * 0.5 + Vector2(40, 30)
		wa = to_world(a)
		mmb(a, true)
		move(a + d * 0.5)
		move(a + d)
		var w: Vector2 = m.screen_to_world(a + d)   # без кадра: камера уже там (сдвиг 1:1, без сглаживания)
		if w.distance_to(wa) > 0.5:
			lag.append("%s: %s против %s" % [d, w, wa])
		await step(1)
		if to_world(a + d).distance_to(wa) > 0.5 or not inside(m.view_rect()):
			bad.append("%s: %s" % [d, to_world(a + d)])
		mmb(a + d, false)
	check("×2: перетаскивание — точка мира под курсором остаётся под ним (преобразование холста), вид в поле", bad.is_empty(), "; ".join(bad))
	check("×2: без лага — камера сдвинута в том же событии, до кадра", lag.is_empty(), "; ".join(lag))
	# край поля: упирается, обратное движение — сразу
	a = vs * 0.5
	mmb(a, true)
	move(a + Vector2(3000, 3000))
	var vr: Rect2 = m.view_rect()
	check("протяжка далеко вправо-вниз: вид прижат к левому верхнему краю поля, не за ним", inside(vr) and vr.position.length() < 0.5, str(vr))
	var p_edge: Vector2 = m.camera.position
	move(a + Vector2(2900, 2900))
	check("обратно на 100 px: вид сдвинулся сразу (на 100 px экрана)", m.camera.position.distance_to(p_edge + Vector2(100, 100) / m.camera.zoom.x) < 0.5, "%s -> %s" % [p_edge, m.camera.position])
	mmb(a, false)
	# пауза, панель, кнопка отпущена вне события
	m.paused = true
	a = vs * 0.5
	var cp: Vector2 = m.camera.position
	mmb(a, true)
	move(a + Vector2(-50, 0))
	check("на паузе (P) перетаскивание работает", m.pan_active and m.camera.position.x > cp.x, "%s -> %s" % [cp, m.camera.position])
	var hud: Rect2 = m.top_hud.get_global_rect()
	var over := hud.get_center()
	move(over)
	check("курсор над верхней панелью: перетаскивание идёт (движение ловит _input до интерфейса)", m.pan_active and to_world(over).distance_to(to_world(a)) > 1.0 or m.pan_active)
	mmb(over, false)
	check("отпускание над панелью: перетаскивание кончилось", not m.pan_active)
	m.paused = false
	mmb(a, true)
	move(a + Vector2(10, 0), false)
	check("движение без зажатой средней кнопки (отпускание не дошло): перетаскивание кончилось", not m.pan_active)
	# зум колесом во время перетаскивания
	await set_zoom(1.5, vs * 0.5, m.FIELD * 0.5)
	a = Vector2(800, 450)
	mmb(a, true)
	move(a + Vector2(60, 40))
	var b := a + Vector2(60, 40)
	await step(1)
	var wb := to_world(b)
	wheel(b, true)
	await settle()
	var wz := to_world(b)
	move(b + Vector2(-120, -30))
	await step(1)
	check("зум колесом во время перетаскивания: точка под курсором та же после зума и после дальнейшего движения",
		wz.distance_to(wb) < 0.5 and to_world(b + Vector2(-120, -30)).distance_to(wb) < 0.5 and inside(m.view_rect()), "%s %s %s" % [wb, wz, to_world(b + Vector2(-120, -30))])
	check("зум сглаживается по-прежнему (zoom_smooth), перетаскивание — нет", float(cam.zoom_smooth) > 0.0)
	mmb(b + Vector2(-120, -30), false)
	check("средняя кнопка не начинает рамку ЛКМ и приказ ПКМ", not m.box_active and not m.drag_active)
	# действия и подсказки
	var S: GDScript = load("res://scripts/settings.gd")
	check("средняя кнопка не назначается на действия (MOUSE_BINDABLE), подпись есть", not S.MOUSE_BINDABLE.has(MOUSE_BUTTON_MIDDLE) and S.MOUSE_LABELS.has(MOUSE_BUTTON_MIDDLE))
	var hj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hints.json"))
	var hc := {}
	for e in hj.hints:
		if e.id == "camera":
			hc = e
	var texts := []
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		texts.append(load("res://scripts/hints.gd").text_of(str(hc.get("text", ""))))
	TranslationServer.set_locale("ru")
	check("подсказка camera в data/hints.json: done_on camera, текст ru/en с клавишей сброса: %s" % str(texts), hc.get("done_on", "") == "camera"
		and texts[0] != hc.get("text") and texts[1] != hc.get("text") and not "{" in texts[0] and S.key_label("camera_zoom_reset") in texts[1])
	var sm: CanvasLayer = load("res://scripts/settings_menu.gd").new()
	root.add_child(sm)
	await step(1)
	sm.open()
	var rows := []
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		for r in sm.info_rows:
			rows.append("%s=%s" % [tr(r[0].text), tr(r[1].text)])
	TranslationServer.set_locale("ru")
	check("«Управление», группа «Камера»: строки «колесо — зум», «зажатое колесо — перемещение» (ru/en), не переназначаются: %s" % str(rows),
		sm.info_rows.size() == 2 and sm.info_rows.all(func(r): return r[1].disabled and r[0].get_parent() == sm.key_titles["camera_zoom_reset"].get_parent())
		and not "UI_" in "".join(rows))
	sm.queue_free()
	await step(1)
