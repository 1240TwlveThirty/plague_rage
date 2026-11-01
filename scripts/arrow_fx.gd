extends Node2D
# Видимые стрелы лучников (задача 29). Только отрисовка: читает очередь стрел main (arrow_land, arrow_tick и массивы отрисовки
# arrow_from, arrow_t0, arrow_vid), симуляцию и её ГСЧ не трогает. Время картинки td — в тиках, как у юнитов
# (tick_counter - 1 + доля тика): стрела видна при arrow_t0 <= td < arrow_tick и долетает в точку падения ровно к тику падения.
# Полёт — один MultiMesh (стрелы над слоями) и один MultiMesh теней (на земле, под юнитами); не больше max_visible, лишние —
# выборка каждой N-й по номеру выстрела. Падение (событие из main._process_arrows, только при включённой отрисовке): попадание —
# искра на 1–3 кадра, промах — воткнутая стрела, гаснет за stuck_life (кольцевой буфер max_stuck). Эффекты появляются, когда время
# картинки дошло до тика падения. ГСЧ — свой (fx_rng). Настройки — data/arrows_fx.json.
const CFG_PATH := "res://data/arrows_fx.json"
const FPI := 12   # float на инстанс: 8 (трансформ 2D) + 4 (цвет)

var main: Node2D
var cfg := {}
var cfg_path := CFG_PATH
var on := true                 # «Показывать стрелы» (настройки); main ставит каждый кадр
var tex: Texture2D
var arrow_size := Vector2.ONE  # размер стрелы в мире (px)
var from_art := false          # true — картинка art_path, false — нарисована кодом
var air_mm: MultiMesh
var shadow_mm: MultiMesh
var air_node: MultiMeshInstance2D
var shadow_node: MultiMeshInstance2D
var spark_mm: MultiMesh
var stuck_mm: MultiMesh
var spark_node: MultiMeshInstance2D
var stuck_node: MultiMeshInstance2D
var spark_buf := PackedFloat32Array()
var stuck_buf := PackedFloat32Array()
var fx_rng := RandomNumberGenerator.new()   # свой ГСЧ эффектов: ГСЧ симуляции не трогается
# Очередь падений (ждут, пока время картинки дойдёт до тика падения)
var ev_to := PackedVector2Array()
var ev_dir := PackedVector2Array()
var ev_tgt := PackedVector2Array()
var ev_t := PackedInt32Array()
var ev_hit := PackedByteArray()
var ev_n := 0
var ev_dropped := 0
# Искры: позиция, кадров осталось, размер, цвет
var sp_pos := PackedVector2Array()
var sp_left := PackedInt32Array()
var sp_size := PackedFloat32Array()
var sp_col := PackedColorArray()
var spark_n := 0
# Воткнутые: кольцевой буфер (жизнь <= 0 — пусто)
var st_pos := PackedVector2Array()
var st_ang := PackedFloat32Array()
var st_life := PackedFloat32Array()
var st_life0 := PackedFloat32Array()
var st_next := 0
var stuck_n := 0
var hits_shown := 0     # искр-попаданий создано (тесты)
var stuck_shown := 0    # воткнутых создано (тесты)
var air_buf := PackedFloat32Array()
var shadow_buf := PackedFloat32Array()
var shadow_col := Color.BLACK
var drawn := 0        # стрел в полёте на экране в прошлом кадре
var in_flight := 0    # стрел в полёте всего (выпущены, ещё не упали) в прошлом кадре
var stride := 1       # выборка: каждая stride-я по номеру выстрела
var draw_calls := 0   # вызовов отрисовки полёта (тесты: при выключенном флаге не растёт)
var lod_skip := false # прошлый кадр: стрела меньше порога на экране, полёт не рисовался


# data/arrows_fx.json. Не читается или неверный — {} и одна ошибка в лог: стрел на экране нет, игра идёт.
static func load_cfg(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Нет %s: стрелы не рисуются" % path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var nums := ["max_visible", "shaft_px", "arc_height_rel", "launch_height_px", "shadow_alpha", "lod_min_screen_px", "view_margin_px",
		"spark_jitter_px", "max_sparks", "stuck_fade", "stuck_len_rel", "stuck_angle_jitter_deg", "max_stuck", "max_events"]
	var colors := ["shaft_color", "head_color", "outline_color", "shadow_color"]
	var sizes := ["art_size_px", "shadow_size_px"]
	var pairs := ["spark_count", "spark_frames", "spark_size_px", "stuck_life"]
	var ok: bool = d is Dictionary and d.get("art_path") is String
	for k in pairs:
		ok = ok and d.get(k) is Array and d[k].size() == 2 and d[k].all(func(x): return x is float and x >= 0.0) and d[k][0] <= d[k][1]
	ok = ok and d.get("spark_colors") is Array and not d.spark_colors.is_empty() and d.spark_colors.all(func(c): return c is String and Color.html_is_valid(c))
	for k in nums:
		ok = ok and d.get(k) is float and d[k] >= 0.0
	for k in colors:
		ok = ok and d.get(k) is String and Color.html_is_valid(d[k])
	for k in sizes:
		ok = ok and d.get(k) is Array and d[k].size() == 2 and d[k].all(func(x): return x is float and x > 0.0)
	ok = ok and d.max_visible >= 1.0 and d.shaft_px >= 1.0 and d.max_sparks >= 1.0 and d.max_stuck >= 1.0 and d.max_events >= 1.0
	ok = ok and d.stuck_fade > 0.0 and d.stuck_fade <= 1.0 and d.spark_frames[0] >= 1.0 and d.stuck_life[0] > 0.0
	if not ok:
		push_error("%s: нужны числа >= 0 (%s; max_visible, shaft_px, max_sparks, max_stuck, max_events >= 1; stuck_fade в (0, 1]), цвета hex (%s, spark_colors), размеры [ш, в] > 0 (%s), пары [от, до] (%s; spark_frames от 1, stuck_life от > 0), art_path — стрелы не рисуются" % [
			path, ", ".join(nums), ", ".join(colors), ", ".join(sizes), ", ".join(pairs)])
		return {}
	for k in colors:
		d[k] = Color(d[k])
	d.spark_colors = d.spark_colors.map(func(c): return Color(c))
	return d


# Стрела кодом: древко shaft_px светлым, наконечник на конце, тёмный контур 1 px вокруг; остриём вправо.
static func make_arrow_image(c: Dictionary) -> Image:
	var n := int(c.shaft_px)
	var img := Image.create(n + 2, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(1, n + 1):
		img.set_pixel(x, 0, c.outline_color)
		img.set_pixel(x, 2, c.outline_color)
		img.set_pixel(x, 1, c.head_color if x == n else c.shaft_color)
	img.set_pixel(0, 1, c.outline_color)
	img.set_pixel(n + 1, 1, c.outline_color)
	return img


# Единичный квадрат (центр в 0) с UV: размер, поворот и цвет — у инстанса.
static func quad_mm(n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mm.mesh = quad
	mm.instance_count = maxi(n, 1)
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-1e5, -1e5, 0.0), Vector3(2e5, 2e5, 0.0))
	return mm


# Установка (main._setup_arrow_fx): ноды полёта (z air_z) и теней (перед ground_before в дереве main — под юнитами).
func setup(m: Node2D, air_z: int, ground_before: Node) -> bool:
	main = m
	cfg = load_cfg(cfg_path)
	if cfg.is_empty():
		return false
	var art: String = cfg.art_path
	if art != "" and ResourceLoader.exists(art):
		tex = load(art) as Texture2D
	from_art = tex != null
	if from_art:
		arrow_size = Vector2(cfg.art_size_px[0], cfg.art_size_px[1])
	else:
		var img := make_arrow_image(cfg)
		tex = ImageTexture.create_from_image(img)
		arrow_size = Vector2(img.get_size())   # 1 тексель = 1 px мира
	var n := int(cfg.max_visible)
	shadow_col = Color(cfg.shadow_color, cfg.shadow_alpha)
	air_buf.resize(n * FPI)
	shadow_buf.resize(n * FPI)
	air_mm = quad_mm(n)
	shadow_mm = quad_mm(n)
	shadow_node = MultiMeshInstance2D.new()
	shadow_node.multimesh = shadow_mm
	shadow_node.name = "ArrowShadows"
	m.add_child(shadow_node)
	if ground_before != null and ground_before.get_parent() == m:
		m.move_child(shadow_node, ground_before.get_index())
	air_node = MultiMeshInstance2D.new()
	air_node.multimesh = air_mm
	air_node.texture = tex
	air_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	air_node.z_index = air_z
	air_node.name = "ArrowsAir"
	m.add_child(air_node)
	# воткнутые — на земле, над тенями, под юнитами; искры — над стрелами
	var ns := int(cfg.max_stuck)
	stuck_mm = quad_mm(ns)
	stuck_buf.resize(ns * FPI)
	st_pos.resize(ns)
	st_ang.resize(ns)
	st_life.resize(ns)
	st_life0.resize(ns)
	stuck_node = MultiMeshInstance2D.new()
	stuck_node.multimesh = stuck_mm
	stuck_node.texture = tex
	stuck_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stuck_node.name = "ArrowsStuck"
	m.add_child(stuck_node)
	m.move_child(stuck_node, shadow_node.get_index() + 1)
	var nk := int(cfg.max_sparks)
	spark_mm = quad_mm(nk)
	spark_buf.resize(nk * FPI)
	sp_pos.resize(nk)
	sp_left.resize(nk)
	sp_size.resize(nk)
	sp_col.resize(nk)
	spark_node = MultiMeshInstance2D.new()
	spark_node.multimesh = spark_mm
	spark_node.z_index = air_z
	spark_node.name = "ArrowSparks"
	m.add_child(spark_node)
	var ne := int(cfg.max_events)
	ev_to.resize(ne)
	ev_dir.resize(ne)
	ev_tgt.resize(ne)
	ev_t.resize(ne)
	ev_hit.resize(ne)
	fx_rng.seed = 2909
	return true


# Падение стрелы (main._process_arrows, тик падения t1; только при включённой отрисовке): откуда летела, точка падения, попала ли,
# позиция цели. Эффект появится, когда время картинки дойдёт до t1.
func land(from: Vector2, to: Vector2, t1: int, hit: bool, target: Vector2) -> void:
	if ev_n >= ev_t.size():
		ev_dropped += 1
		return
	ev_to[ev_n] = to
	ev_dir[ev_n] = (to - from).normalized()
	ev_tgt[ev_n] = target
	ev_t[ev_n] = t1
	ev_hit[ev_n] = 1 if hit else 0
	ev_n += 1


# Всё убрать (отрисовка выключена): очередь, искры, воткнутые.
func clear() -> void:
	ev_n = 0
	spark_n = 0
	stuck_n = 0
	st_life.fill(0.0)
	spark_mm.visible_instance_count = 0
	stuck_mm.visible_instance_count = 0


# Кадр (из main._process после юнитов): td — время картинки в тиках, dt — время кадра (0 на паузе), view — вид в мире, zoom — px
# экрана на px мира.
func frame(td: float, dt: float, view: Rect2, zoom: float) -> void:
	for n in [air_node, shadow_node, spark_node, stuck_node]:
		n.visible = on
	if not on:
		drawn = 0
		in_flight = 0
		if ev_n > 0 or spark_n > 0 or stuck_n > 0:
			clear()
		return
	_land_effects(td, dt)
	_draw_sparks()
	_draw_stuck(dt)
	lod_skip = maxf(arrow_size.x, arrow_size.y) * zoom < float(cfg.lod_min_screen_px)
	if lod_skip:
		drawn = 0
		air_mm.visible_instance_count = 0
		shadow_mm.visible_instance_count = 0
		return
	_draw_flights(td, view.grow(float(cfg.view_margin_px)))


# Искры старше на кадр (только не на паузе), затем эффекты падений, чей тик картинка уже показала.
func _land_effects(td: float, dt: float) -> void:
	if dt > 0.0:
		var i := 0
		while i < spark_n:
			sp_left[i] -= 1
			if sp_left[i] <= 0:
				spark_n -= 1
				sp_pos[i] = sp_pos[spark_n]
				sp_left[i] = sp_left[spark_n]
				sp_size[i] = sp_size[spark_n]
				sp_col[i] = sp_col[spark_n]
				continue
			i += 1
	var e := 0
	while e < ev_n:
		if float(ev_t[e]) > td:
			e += 1
			continue
		if ev_hit[e] == 1:
			_spawn_spark(ev_tgt[e])
		else:
			_spawn_stuck(ev_to[e], ev_dir[e])
		ev_n -= 1
		ev_to[e] = ev_to[ev_n]
		ev_dir[e] = ev_dir[ev_n]
		ev_tgt[e] = ev_tgt[ev_n]
		ev_t[e] = ev_t[ev_n]
		ev_hit[e] = ev_hit[ev_n]


func _spawn_spark(p: Vector2) -> void:
	hits_shown += 1
	var cols: Array = cfg.spark_colors
	var j := float(cfg.spark_jitter_px)
	for q in fx_rng.randi_range(int(cfg.spark_count[0]), int(cfg.spark_count[1])):
		if spark_n >= sp_pos.size():
			return
		sp_pos[spark_n] = p + Vector2(fx_rng.randf_range(-j, j), fx_rng.randf_range(-j, j))
		sp_left[spark_n] = fx_rng.randi_range(int(cfg.spark_frames[0]), int(cfg.spark_frames[1]))
		sp_size[spark_n] = roundf(fx_rng.randf_range(cfg.spark_size_px[0], cfg.spark_size_px[1]))
		sp_col[spark_n] = cols[fx_rng.randi() % cols.size()]
		spark_n += 1


# Воткнутая: остриё в точке падения, древко назад к лучнику; новая занимает место самой старой.
func _spawn_stuck(p: Vector2, dir: Vector2) -> void:
	stuck_shown += 1
	var k := st_next
	st_next = (st_next + 1) % st_pos.size()
	var ln := arrow_size.x * float(cfg.stuck_len_rel)
	st_pos[k] = p - dir * (ln * 0.5)
	st_ang[k] = dir.angle() + deg_to_rad(fx_rng.randf_range(-cfg.stuck_angle_jitter_deg, cfg.stuck_angle_jitter_deg))
	st_life0[k] = fx_rng.randf_range(cfg.stuck_life[0], cfg.stuck_life[1])
	st_life[k] = st_life0[k]


func _draw_sparks() -> void:
	for i in spark_n:
		var o := i * FPI
		var s := sp_size[i]
		var c := sp_col[i]
		spark_buf[o + 0] = s
		spark_buf[o + 1] = 0.0
		spark_buf[o + 3] = sp_pos[i].x
		spark_buf[o + 4] = 0.0
		spark_buf[o + 5] = s
		spark_buf[o + 7] = sp_pos[i].y
		spark_buf[o + 8] = c.r
		spark_buf[o + 9] = c.g
		spark_buf[o + 10] = c.b
		spark_buf[o + 11] = 1.0
	if spark_n > 0:
		spark_mm.buffer = spark_buf
	spark_mm.visible_instance_count = spark_n


# Воткнутые: жизнь убывает (не на паузе), последние stuck_fade жизни — прозрачность к 0.
func _draw_stuck(dt: float) -> void:
	var k := 0
	var ln := arrow_size.x * float(cfg.stuck_len_rel)
	var h := arrow_size.y
	var fade := float(cfg.stuck_fade)
	for i in st_life.size():
		if st_life[i] <= 0.0:
			continue
		st_life[i] -= dt
		if st_life[i] <= 0.0:
			continue
		var a := minf(st_life[i] / (st_life0[i] * fade), 1.0)
		var c := cos(st_ang[i])
		var s := sin(st_ang[i])
		var o := k * FPI
		stuck_buf[o + 0] = c * ln
		stuck_buf[o + 1] = -s * h
		stuck_buf[o + 3] = st_pos[i].x
		stuck_buf[o + 4] = s * ln
		stuck_buf[o + 5] = c * h
		stuck_buf[o + 7] = st_pos[i].y
		stuck_buf[o + 8] = 1.0
		stuck_buf[o + 9] = 1.0
		stuck_buf[o + 10] = 1.0
		stuck_buf[o + 11] = a
		k += 1
	stuck_n = k
	if k > 0:
		stuck_mm.buffer = stuck_buf
	stuck_mm.visible_instance_count = k


# Середины искр и воткнутых (кадры отчёта).
func spark_center() -> Vector2:
	var c := Vector2.ZERO
	for i in spark_n:
		c += sp_pos[i]
	return c / maxf(spark_n, 1)


func stuck_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for i in st_life.size():
		if st_life[i] > 0.0:
			c += st_pos[i]
			n += 1
	return c / maxf(n, 1)


# Полёт: доля пути u = (td - t0) / (t1 - t0); земля — прямая от лучника к точке падения (по ней тень), стрела выше неё на
# launch_height * (1 - u) + 4 * arc * u * (1 - u), повёрнута по касательной к этой дуге на экране.
func _draw_flights(td: float, view: Rect2) -> void:
	draw_calls += 1
	var n: int = main.arrow_count
	var cap := int(cfg.max_visible)
	stride = maxi(ceili(float(n) / cap), 1)
	var land: PackedVector2Array = main.arrow_land
	var t1s: PackedInt32Array = main.arrow_tick
	var from: PackedVector2Array = main.arrow_from
	var t0s: PackedFloat64Array = main.arrow_t0
	var vids: PackedInt32Array = main.arrow_vid
	var arc_k := float(cfg.arc_height_rel)
	var h0 := float(cfg.launch_height_px)
	var sw := float(cfg.shadow_size_px[0])
	var sh := float(cfg.shadow_size_px[1])
	var aw := arrow_size.x
	var ah := arrow_size.y
	var k := 0
	var fl := 0
	for a in n:
		var t1 := float(t1s[a])
		var t0 := t0s[a]
		if td < t0 or td >= t1:
			continue
		fl += 1
		if k >= cap or vids[a] % stride != 0:
			continue
		var u := (td - t0) / (t1 - t0)
		var p0 := from[a]
		var d := land[a] - p0
		var g := p0 + d * u
		var dist := d.length()
		var arc := arc_k * dist
		var h := h0 * (1.0 - u) + 4.0 * arc * u * (1.0 - u)
		var sp := Vector2(g.x, g.y - h)
		if not view.has_point(g) and not view.has_point(sp):
			continue
		# касательная на экране: d/du (g - (0, h))
		var tan := Vector2(d.x, d.y + h0 - 4.0 * arc * (1.0 - 2.0 * u))
		var ang := tan.angle() if tan.length_squared() > 1e-6 else d.angle()
		var c := cos(ang)
		var s := sin(ang)
		var o := k * FPI
		air_buf[o + 0] = c * aw
		air_buf[o + 1] = -s * ah
		air_buf[o + 3] = sp.x
		air_buf[o + 4] = s * aw
		air_buf[o + 5] = c * ah
		air_buf[o + 7] = sp.y
		air_buf[o + 8] = 1.0
		air_buf[o + 9] = 1.0
		air_buf[o + 10] = 1.0
		air_buf[o + 11] = 1.0
		var gc := cos(d.angle())
		var gs := sin(d.angle())
		shadow_buf[o + 0] = gc * sw
		shadow_buf[o + 1] = -gs * sh
		shadow_buf[o + 3] = g.x
		shadow_buf[o + 4] = gs * sw
		shadow_buf[o + 5] = gc * sh
		shadow_buf[o + 7] = g.y
		shadow_buf[o + 8] = shadow_col.r
		shadow_buf[o + 9] = shadow_col.g
		shadow_buf[o + 10] = shadow_col.b
		shadow_buf[o + 11] = shadow_col.a
		k += 1
	drawn = k
	in_flight = fl
	if k > 0:
		air_mm.buffer = air_buf   # буфер целиком (размер = instance_count); рисуются первые k
		shadow_mm.buffer = shadow_buf
	air_mm.visible_instance_count = k
	shadow_mm.visible_instance_count = k
