extends SceneTree
# Задача 28, этапы 1 и 2 (без окна): предел отдаления и перетаскивание камеры зажатым колесом. Настоящий забег (автозагрузка
# Game, своё сохранение), события мыши — через root.push_input. Значения — из data/camera.json.
#   Этап 1: zoom_user_min = 1.0 (не меньше CAMERA_ZOOM_FLOOR); при 1.0 вид внутри поля по обеим осям у любого края (чёрных
#   полос нет), колесо вниз дальше не отдаляет; файл с прежним 0.7 и множитель забега 0.7 зажимаются до 1.0; тряска у края
#   поля не выводит вид за поле, по свободной оси не урезается.
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
	pass
