extends Node2D
# Видимые стрелы лучников (задача 29). Только отрисовка: читает очередь стрел main (arrow_land, arrow_tick и массивы отрисовки
# arrow_from, arrow_t0, arrow_vid), симуляцию и её ГСЧ не трогает. Время картинки td — в тиках, как у юнитов
# (tick_counter - 1 + доля тика): стрела видна при arrow_t0 <= td < arrow_tick и долетает в точку падения ровно к тику падения.
# Полёт — один MultiMesh (стрелы над слоями) и один MultiMesh теней (на земле, под юнитами); не больше max_visible, лишние —
# выборка каждой N-й по номеру выстрела. Настройки — data/arrows_fx.json.
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
	var nums := ["max_visible", "shaft_px", "arc_height_rel", "launch_height_px", "shadow_alpha", "lod_min_screen_px", "view_margin_px"]
	var colors := ["shaft_color", "head_color", "outline_color", "shadow_color"]
	var sizes := ["art_size_px", "shadow_size_px"]
	var ok: bool = d is Dictionary and d.get("art_path") is String
	for k in nums:
		ok = ok and d.get(k) is float and d[k] >= 0.0
	for k in colors:
		ok = ok and d.get(k) is String and Color.html_is_valid(d[k])
	for k in sizes:
		ok = ok and d.get(k) is Array and d[k].size() == 2 and d[k].all(func(x): return x is float and x > 0.0)
	ok = ok and d.max_visible >= 1.0 and d.shaft_px >= 1.0
	if not ok:
		push_error("%s: нужны числа >= 0 (%s; max_visible и shaft_px >= 1), цвета hex (%s), размеры [ш, в] > 0 (%s), art_path — стрелы не рисуются" % [
			path, ", ".join(nums), ", ".join(colors), ", ".join(sizes)])
		return {}
	for k in colors:
		d[k] = Color(d[k])
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
	return true


# Кадр (из main._process после юнитов): td — время картинки в тиках, dt — время кадра (0 на паузе), view — вид в мире, zoom — px
# экрана на px мира.
func frame(td: float, _dt: float, view: Rect2, zoom: float) -> void:
	air_node.visible = on
	shadow_node.visible = on
	if not on:
		drawn = 0
		in_flight = 0
		return
	lod_skip = maxf(arrow_size.x, arrow_size.y) * zoom < float(cfg.lod_min_screen_px)
	if lod_skip:
		drawn = 0
		air_mm.visible_instance_count = 0
		shadow_mm.visible_instance_count = 0
		return
	_draw_flights(td, view.grow(float(cfg.view_margin_px)))


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
