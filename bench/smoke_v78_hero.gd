extends SceneTree
# Смоук задачи 28, этап 4 (окно): герой под слоями замка и леса, силуэт поверх — только там, где слой его закрывает.
# Бой волны 1 без эффектов карты (fx_enabled false: кадры неподвижны — вода, листва и факелы не мешают сравнению), симуляция
# стоит, герой ставится в точку. Точки ищутся по прозрачности слоёв (текстуры и прямоугольники спрайтов на экране):
#   за воротами — квадрат героя целиком под замком; за деревом — целиком под лесом (замка нет); частично — замок закрывает
#   часть; открыто — ни один слой. В каждой точке три кадра: A — как в игре, B — силуэт скрыт, C — скрыт и герой.
#   Открыто: A = B (силуэта нет), C ≠ B (герой виден). Целиком закрыт: C = B (герой под слоем), A ≠ B (силуэт), цвет
#   отличий — смесь слоя с hero_occlusion_color при hero_occlusion_alpha (data/hero.json). Частично: силуэт меньше полного.
#   hero_occlusion_enabled false — силуэта нет. Шейдер силуэта и с эффектами (запечённые слои): за воротами A ≠ B.
const TOL := 0.05   # отличие точки кадров — больше 5% по каналу (кроны и края стен с альфой 0.9–0.99 пропускают героя на несколько уровней)
var fails := 0
var m: Node2D
var layers := []   # [[спрайт, Image], ...] — лес, замок

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	_run.call_deferred()

func alpha_at(k: int, w: Vector2) -> float:
	var sp: Sprite2D = layers[k][0]
	var img: Image = layers[k][1]
	if sp == null or img == null:
		return 0.0
	var uv := (w - sp.position) / (Vector2(img.get_size()) * sp.scale)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return 0.0
	return img.get_pixel(int(uv.x * img.get_width()), int(uv.y * img.get_height())).a

# Доля точек квадрата героя (±r px мира) под слоем k.
func cover(k: int, p: Vector2, r := 13.0) -> float:
	var n := 0
	for iy in 7:
		for ix in 7:
			if alpha_at(k, p + Vector2(-r + ix * r / 3.0, -r + iy * r / 3.0)) >= 0.5:
				n += 1
	return n / 49.0

# Непрозрачные точки текущего кадра героя относительно его позиции, px мира (спрайт: смещение, поворот, масштаб).
var hero_pts: Array[Vector2] = []
func hero_points() -> void:
	var s: Sprite2D = m.hero_sprite
	var img: Image = s.texture.get_image()
	if img.is_compressed():
		img.decompress()
	var fs := Vector2(img.get_width() / s.hframes, img.get_height() / s.vframes)
	var fx0 := (s.frame % s.hframes) * int(fs.x)
	var fy0 := (s.frame / s.hframes) * int(fs.y)
	hero_pts.clear()
	for v in int(fs.y):
		for u in int(fs.x):
			if img.get_pixel(fx0 + u, fy0 + v).a >= 0.5:
				var lp := s.offset + Vector2(u + 0.5, v + 0.5) - fs * 0.5
				if s.flip_h:
					lp.x = -lp.x
				hero_pts.append(s.transform * lp)

# Доли непрозрачных точек героя в p под лесом и под замком.
func exact(p: Vector2) -> Vector2:
	var t := 0
	var c := 0
	for q in hero_pts:
		if alpha_at(0, p + q) >= 0.5:
			t += 1
		if alpha_at(1, p + q) >= 0.5:
			c += 1
	return Vector2(t, c) / maxf(hero_pts.size(), 1)

# Ближайшая к near точка поля (шаг 4 px, не дальше 500 px), где want(доля под лесом, доля под замком) по точкам героя.
func find(want: Callable, near: Vector2) -> Vector2:
	var cand := []
	for y in range(int(maxf(near.y - 500.0, 24.0)), int(minf(near.y + 500.0, m.FIELD.y - 24.0)), 4):
		for x in range(int(maxf(near.x - 500.0, 24.0)), int(minf(near.x + 500.0, m.FIELD.x - 24.0)), 4):
			cand.append(Vector2(x, y))
	cand.sort_custom(func(a, b): return a.distance_squared_to(near) < b.distance_squared_to(near))
	for p in cand:
		var e := exact(p)
		if want.call(e.x, e.y):
			return p
	return Vector2(-1, -1)

# Слои интерфейса (CanvasLayer сцены) скрыты: панели не закрывают точки сравнения.
func hide_ui() -> void:
	for c in m.get_children():
		if c is CanvasLayer:
			c.visible = false

func place(p: Vector2) -> void:
	var h: int = m.hero_idx
	m.pos[h] = p
	m.prev_pos[h] = p

func frame() -> Image:
	await step(2)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

# Точки квадрата героя на экране, где кадры различаются.
func diff(a: Image, b: Image, p: Vector2) -> Array:
	var c: Vector2 = m.get_viewport().get_canvas_transform() * p
	var k: float = Vector2(a.get_size()).x / m.get_viewport_rect().size.x
	var r := int(16.0 * m.camera.zoom.x * k)   # квадрат спрайта; кольцо (радиус 20 px экрана) — снаружи
	var out := []
	for y in range(int(c.y * k) - r, int(c.y * k) + r):
		for x in range(int(c.x * k) - r, int(c.x * k) + r):
			if x < 0 or y < 0 or x >= a.get_width() or y >= a.get_height():
				continue
			var p0 := a.get_pixel(x, y)
			var p1 := b.get_pixel(x, y)
			if maxf(maxf(absf(p0.r - p1.r), absf(p0.g - p1.g)), absf(p0.b - p1.b)) > TOL:
				out.append(Vector2i(x, y))
	return out

# A, B, C в точке p (см. заголовок).
func abc(p: Vector2) -> Array:
	place(p)
	m.hero_view.visible = true
	m.hero_occ.visible = true
	var a := await frame()
	m.hero_occ.visible = false
	var b := await frame()
	m.hero_sprite.visible = false
	var c := await frame()
	m.hero_sprite.visible = true
	m.hero_occ.visible = true
	return [a, b, c]

func _run() -> void:
	var fx := [false]   # лямбда держит массив: значение меняется перед перезагрузкой сцены
	node_added.connect(func(n): if n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd": n.fx_enabled = fx[0])
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v78h/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v78h")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(10)
	m = current_scene
	m.banner_hidden = true
	m.banner.visible = false
	m.set_physics_process(false)
	m._clear_sel()
	hide_ui()
	check("герой есть, силуэт — ребёнок спрайта героя на z %d (выше листвы %d), герой и дуга удара на z %d (ниже слоёв %d)" % [m.HERO_OCC_Z, m.LEAF_Z, m.HERO_Z, m.FG_Z],
		m.hero_idx >= 0 and m.hero_occ != null and m.hero_occ.get_parent() == m.hero_sprite and m.hero_occ.z_index == m.HERO_OCC_Z and not m.hero_occ.z_as_relative
		and m.HERO_OCC_Z > m.LEAF_Z and m.hero_view.z_index == m.HERO_Z and m.hero_fx.z_index == m.HERO_Z and m.HERO_Z < m.FG_Z)
	var hc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	var oc := Color(hc.hero_occlusion_color)
	var oa := float(hc.hero_occlusion_alpha)
	var mc: Color = m.hero_occ_mat.get_shader_parameter("occ_color")
	check("цвет и прозрачность силуэта из data/hero.json (%s, %s), включён флагом hero_occlusion_enabled" % [hc.hero_occlusion_color, oa],
		hc.hero_occlusion_enabled == true and mc.is_equal_approx(Color(oc.r, oc.g, oc.b, oa)))
	for sp in [m.trees_sprite, m.castle_sprite]:
		var img: Image = sp.texture.get_image() if sp != null else null
		if img != null and img.is_compressed():
			img.decompress()
		layers.append([sp, img])
	place(m.HERO_SPAWN)
	await step(2)
	hero_points()
	var spots := {
		"за воротами": find(func(t, c): return c == 1.0 and t == 0.0, m.GATE_POS),
		"за деревом": find(func(t, c): return t == 1.0 and c == 0.0, Vector2(300, m.FIELD.y * 0.45)),
		"частично за стеной": find(func(t, c): return c >= 0.35 and c <= 0.65 and t == 0.0, m.GATE_POS),
		"открыто": find(func(t, c): return t == 0.0 and c == 0.0, m.HERO_SPAWN + Vector2(0, -150)),
	}
	print("  точки: %s" % str(spots))
	check("точки найдены в поле", spots.values().all(func(p): return p.x >= 0.0))
	var full := {}
	for name in spots:
		var p: Vector2 = spots[name]
		var r: Array = await abc(p)
		if OS.get_cmdline_user_args().size() > 0:   # отладка: кадры A, B, C вокруг точки
			var c: Vector2 = m.get_viewport().get_canvas_transform() * p * (Vector2(r[0].get_size()).x / m.get_viewport_rect().size.x)
			for k in 3:
				(r[k] as Image).get_region(Rect2i(int(c.x) - 60, int(c.y) - 60, 120, 120)).save_png(OS.get_cmdline_user_args()[0].path_join("%s_%s.png" % [name, "ABC"[k]]))
		var ab := diff(r[0], r[1], p)
		var bc := diff(r[1], r[2], p)
		full[name] = ab.size()
		if name == "открыто":
			check("%s %s: силуэта нет (A = B), герой виден (C ≠ B: %d точек)" % [name, p, bc.size()], ab.is_empty() and bc.size() >= 50, "A≠B %d" % ab.size())
		elif name == "частично за стеной":
			check("%s %s: силуэт только на закрытой части (%d точек, меньше, чем за воротами: %d), открытая часть героя видна (%d)" % [name, p, ab.size(), full.get("за воротами", 0), bc.size()],
				ab.size() > 0 and ab.size() < full.get("за воротами", 0) and bc.size() > 0)
		else:
			var mixed := 0
			for q in ab:
				var want: Color = (r[1] as Image).get_pixelv(q).lerp(oc, oa)
				var got: Color = (r[0] as Image).get_pixelv(q)
				if absf(want.r - got.r) < 0.04 and absf(want.g - got.g) < 0.04 and absf(want.b - got.b) < 0.04:
					mixed += 1
			check("%s %s: герой под слоем (C = B: %d точек отличий), силуэт поверх (%d точек), %d%% — смесь слоя и цвета силуэта" % [name, p, bc.size(), ab.size(),
				int(100.0 * mixed / maxf(ab.size(), 1))], bc.is_empty() and ab.size() >= 50 and mixed >= ab.size() * 0.9)
	# выключатель
	m.hero_occ.queue_free()
	m.hero_occ = null
	m.hero_cfg.hero_occlusion_enabled = false
	m._setup_hero_occlusion()
	check("hero_occlusion_enabled false: силуэта нет", m.hero_occ == null)
	m.hero_cfg.hero_occlusion_enabled = true
	m._setup_hero_occlusion()
	# с эффектами карты (запечённые слои — текстуры вьюпортов)
	fx[0] = true
	reload_current_scene()
	await step(12)
	m = current_scene
	m.banner_hidden = true
	m.banner.visible = false
	m.set_physics_process(false)
	m._clear_sel()
	hide_ui()
	var pg: Vector2 = spots["за воротами"]
	var r2: Array = await abc(pg)
	var d2 := diff(r2[0], r2[1], pg)
	check("с эффектами карты (слои — текстуры вьюпортов): за воротами силуэт есть (%d точек)" % d2.size(), m.fx_enabled and d2.size() >= 50)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v78h")
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
