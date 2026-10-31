extends SceneTree
# Смоук задачи 10 с окном: забег через Game — герой включён по данным (игровой режим). Скриншоты в папку из аргумента:
# hero_start.png — герой у ворот на старте; hero_moved.png — после движения вправо (взгляд), при единственном (минимальном) зуме
# камеры кольцо-маркер видно (пиксели цвета маркера вокруг героя); hero_dead.png — в бою после смерти: метка «Командир пал»,
# героя нет, клавиша приказа не действует; hero_revived.png — передышка: герой снова у ворот, метки нет, приказы работают.
const DIR := "user://bench_v60"
const DT := 1.0 / 30.0
var fails := 0
var out_dir := ""

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(m: Node2D, name: String) -> Image:
	m._process(1.0 / 60.0)   # main без собственного процесса: кадр отрисовки вручную
	m._update_ui()
	await step(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	return img

# Задача 28: кольцо героя — под слоями замка и леса. Точка мира w под непрозрачным слоем (кольцо там закрыто законно)?
var layer_imgs := {}
func under_layer(m: Node2D, w: Vector2) -> bool:
	for sp in [m.trees_sprite, m.castle_sprite]:
		if sp == null:
			continue
		if not layer_imgs.has(sp):
			var im: Image = sp.texture.get_image()
			if im != null and im.is_compressed():
				im.decompress()
			layer_imgs[sp] = im
		var im: Image = layer_imgs[sp]
		var uv: Vector2 = (w - sp.position) / (Vector2(im.get_size()) * sp.scale)
		if uv.x >= 0.0 and uv.y >= 0.0 and uv.x < 1.0 and uv.y < 1.0 and im.get_pixel(int(uv.x * im.get_width()), int(uv.y * im.get_height())).a >= 0.5:
			return true
	return false

# Пикселей цвета маркера (с допуском) на окружности кольца вокруг героя на скриншоте; точки под слоем замка или леса (кольцо
# под ними, задача 28) пропускаются и засчитываются — порог «30 из 72» прежний.
func ring_pixels(m: Node2D, img: Image) -> int:
	var px: Vector2 = Vector2(img.get_size()) / m.get_viewport_rect().size
	var c: Vector2 = (m.get_viewport().get_canvas_transform() * m.hero_view.position) * px
	var col := Color(m.hero_cfg.marker_color)
	var inv: Transform2D = m.get_viewport().get_canvas_transform().affine_inverse()
	var n := 0
	for a in 72:
		var p: Vector2 = c + Vector2.from_angle(a * TAU / 72.0) * m.HERO_RING_PX * px.x
		var q := Vector2i(roundi(p.x), roundi(p.y))
		if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
			continue
		if under_layer(m, inv * (p / px)):
			n += 1
			continue
		var g := img.get_pixelv(q)
		if absf(g.r - col.r) < 0.12 and absf(g.g - col.g) < 0.12 and absf(g.b - col.b) < 0.12:
			n += 1
	return n

# Высота кадра героя и спрайта павшего рыцаря на экране, px окна (с зумом камеры).
func hero_screen_h(m: Node2D) -> float:
	var s: Sprite2D = m.hero_sprite
	return s.texture.get_height() / float(s.vframes) * s.get_global_transform_with_canvas().get_scale().y

func knight_screen_h(m: Node2D) -> float:
	return m.KNIGHT_SPRITE_SCALE * m.SPRITE_PX * m.get_global_transform_with_canvas().get_scale().y

# Спрайт смотрит в сторону dir по x: отражение (прежний вид) или поворот (спрайтшит с orient rotate, задача 15).
func faces(m: Node2D, dir: float) -> bool:
	if m.hero_rotate:
		return not m.hero_sprite.flip_h and signf(cos(m.hero_sprite.rotation)) == dir
	return m.hero_sprite.flip_h == (dir < 0.0)

func key(m: Node2D, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	m._unhandled_input(e)

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var g: Node = root.get_node_or_null("Game")
	if g == null:
		print("SMOKE: нет автозагрузки Game")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	m.banner.visible = false   # дневник на старте закрывает ворота
	var img := await shot(m, "hero_start.png")
	check("игровой режим: герой включён по данным, стоит у ворот, нода видна, спрайт nearest, на экране %.1f px — рыцарь %.1f px x %s" % [hero_screen_h(m),
		knight_screen_h(m), m.hero_cfg.get("hero_screen_scale_rel", 1.0)], m.hero_on and m.hero_idx >= 0
		and m.pos[m.hero_idx] == m.HERO_SPAWN and m.hero_view != null and m.hero_view.visible and m.hero_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and is_equal_approx(hero_screen_h(m), knight_screen_h(m) * m.hero_cfg.get("hero_screen_scale_rel", 1.0)))
	check("камера — единственный (минимальный) зум: %.3f" % m.camera.zoom.x, is_equal_approx(m.camera.zoom.x, m.camera_min_zoom()))
	var rp := ring_pixels(m, img)
	check("кольцо-маркер видно при минимальном зуме: %d из 72 точек окружности цвета маркера" % rp, rp >= 30)
	m.hero_feed = func(_t): return Vector2(1, 0)
	for t in 20:
		m._physics_process(DT)
	img = await shot(m, "hero_moved.png")
	check("движение вправо: герой сместился, спрайт смотрит вправо; кольцо следует за героем (%d точек)" % ring_pixels(m, img), m.pos[m.hero_idx].x > m.HERO_SPAWN.x + 50.0
		and faces(m, 1.0) and ring_pixels(m, img) >= 30)
	m.hero_feed = func(_t): return Vector2(-1, 0)
	for t in 2:
		m._physics_process(DT)
	m._process(1.0 / 60.0)
	check("движение влево: спрайт смотрит влево (отражение или поворот)", faces(m, -1.0))
	m.hero_feed = func(_t): return Vector2.ZERO
	m._select_only(0)
	m._start_wave()
	for t in 60:
		m._physics_process(DT)
	m.hp[m.hero_idx] = 0.0
	m._physics_process(DT)
	var order0: int = m.squad_order[0]
	key(m, KEY_Y if order0 != m.ORDER_HOLD else KEY_Q)
	m.banner.visible = false
	img = await shot(m, "hero_dead.png")
	check("бой, герой пал: нода скрыта, метка «%s» видна, клавиша приказа не действует" % tr(m.hero_fallen_label.text), not m.hero_view.visible
		and m.hero_fallen_label.visible and m.squad_order[0] == order0)
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 900:
		m._physics_process(DT)
		t += 1
	m.banner.visible = false   # итог волны закрывает ворота
	img = await shot(m, "hero_revived.png")
	check("волна 1 побеждена без героя; передышка: герой у ворот с полным HP, метки нет", m.wave_state == m.WS_RESPITE and m.hero_idx >= 0 and m.hero_view.visible
		and not m.hero_fallen_label.visible and is_equal_approx(m.hp[m.hero_idx], m.type_hp[m.hero_type]) and ring_pixels(m, img) >= 30)
	key(m, KEY_Y)
	check("приказ снова работает (Y — «Держать»)", m.squad_order[0] == m.ORDER_HOLD)
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
