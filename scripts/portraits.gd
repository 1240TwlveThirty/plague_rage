extends RefCounted
# Иллюстрации отрядов в кнопках магазина и панели отрядов (задача 15). data/unit_portraits.json: тип юнита -> {"path": исходная
# картинка, "crop": [x, y, w, h]} — полоса исходника. Из полосы берётся середина с пропорциями кнопки (лишнее по краям отрезается)
# и уменьшается до 2x размера кнопки (Lanczos). Готовые уменьшенные копии — art/ui/<тип>_<w>x<h>.png (bench/make_unit_portraits.gd);
# в art/ui/unit_portraits_made.json записано, из каких path и crop они сделаны. Данные поменяли, а копии нет — полоса
# режется из исходника при запуске (с предупреждением). Типа нет в файле — кнопка обычная.
# Вид кнопки: картинка и тёмный градиент слева под текстом (дети кнопки за ней — show_behind_parent), контур текста;
# градиент (задача 16) — в том же файле: gradient_left_alpha у левого края, gradient_right_alpha на доле gradient_width ширины
# кнопки и дальше вправо; общего затемнения картинки нет. Наведение — картинка ярче и тонкая светлая рамка; нажатая или выбранная —
# рамка #feae34 3 px; недоступная — серая и темнее.
const UI := preload("res://scripts/ui.gd")   # рамка вида кнопки (задача 24)
const FONTS := preload("res://scripts/fonts.gd")   # кегли и контуры текста под вариант шрифта (задача 20)
const PATH := "res://data/unit_portraits.json"
const UI_DIR := "res://art/ui/"
const MADE_PATH := "res://art/ui/unit_portraits_made.json"
const GRADIENT_KEYS := {"gradient_left_alpha": 0.45, "gradient_right_alpha": 0.0, "gradient_width": 0.6}   # по умолчанию; доли от 0 до 1
const OUTLINE_PX := 4       # тёмный контур текста
const HOVER_BRIGHT := 1.3
const DISABLED_BRIGHT := 0.55
const SELECT_COLOR := Color("#feae34")
const SELECT_PX := 3
const HOVER_BORDER := Color(1.0, 1.0, 1.0, 0.7)
const SHADER := """
shader_type canvas_item;
uniform float gray = 0.0;
uniform float bright = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c.rgb, vec3(l), gray) * bright, c.a);
}
"""

var defs := {}       # тип -> {"path": String, "crop": Rect2i}
var made := {}       # из art/ui/unit_portraits_made.json
var cache := {}      # "тип WxH" -> Texture2D или null
var shader: Shader
var styles := {}     # состояние кнопки -> StyleBox
var gradient := GRADIENT_KEYS.duplicate()   # параметры градиента из файла
var shade_tex: GradientTexture2D   # общий для всех кнопок: set_gradient меняет все сразу


# Читает data/unit_portraits.json. Нет файла или запись неверна — у этих типов картинки нет (предупреждение), игра идёт.
func load_defs(path := PATH) -> void:
	defs = {}
	if not FileAccess.file_exists(path):
		push_warning("Нет %s: кнопки отрядов без иллюстраций" % path)
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		push_warning("%s: нужен JSON-объект «тип -> {path, crop}»: кнопки без иллюстраций" % path)
		return
	for k in GRADIENT_KEYS:
		var v = d.get(k, GRADIENT_KEYS[k])
		if (v is float or v is int) and v >= 0.0 and v <= 1.0 and (k != "gradient_width" or v > 0.0):
			gradient[k] = float(v)
		else:
			push_warning("%s: %s — число от 0 до 1 (ширина больше 0); остаётся %s" % [path, k, GRADIENT_KEYS[k]])
	set_gradient(gradient.gradient_left_alpha, gradient.gradient_right_alpha, gradient.gradient_width)
	for t in d:
		if t in GRADIENT_KEYS:
			continue
		var e = d[t]
		var c = e.get("crop") if e is Dictionary else null
		if not e is Dictionary or not e.get("path") is String or not c is Array or c.size() != 4 \
				or not c.all(func(v): return (v is float or v is int) and v == floorf(v) and v >= 0) or c[2] < 1 or c[3] < 1:
			push_warning("%s: у «%s» нужны path (строка) и crop [x, y, w, h] (целые, w и h от 1): без иллюстрации" % [path, t])
			continue
		defs[t] = {"path": e.path, "crop": Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))}
	var m = JSON.parse_string(FileAccess.get_file_as_string(MADE_PATH)) if FileAccess.file_exists(MADE_PATH) else null
	made = m if m is Dictionary else {}


# Градиент под текстом: left — доля чёрного у левого края, right — с доли width ширины кнопки и до правого края (общая текстура).
func set_gradient(left: float, right: float, width: float) -> void:
	gradient = {"gradient_left_alpha": left, "gradient_right_alpha": right, "gradient_width": width}
	if shade_tex == null:
		shade_tex = GradientTexture2D.new()
		shade_tex.width = 256
		shade_tex.height = 4
		shade_tex.gradient = Gradient.new()
	var g := shade_tex.gradient
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0, 0, 0, left))
	g.set_offset(1, width)
	g.set_color(1, Color(0, 0, 0, right))


# Середина crop с пропорциями size (лишнее поровну с двух сторон), в пределах картинки w x h.
static func fit(crop: Rect2i, size: Vector2i, w: int, h: int) -> Rect2i:
	var r := crop.intersection(Rect2i(0, 0, w, h))
	var ar := float(size.x) / size.y
	if r.size.x > r.size.y * ar:
		var nw := maxi(roundi(r.size.y * ar), 1)
		r = Rect2i(r.position.x + (r.size.x - nw) / 2, r.position.y, nw, r.size.y)
	else:
		var nh := maxi(roundi(r.size.x / ar), 1)
		r = Rect2i(r.position.x, r.position.y + (r.size.y - nh) / 2, r.size.x, nh)
	return r


# Полоса для кнопки размера size из исходной картинки (уменьшение Lanczos). null — нет картинки или crop вне её.
static func strip(img: Image, crop: Rect2i, size: Vector2i) -> Image:
	if img == null or img.is_empty():
		return null
	var r := fit(crop, size, img.get_width(), img.get_height())
	if r.size.x < 1 or r.size.y < 1:
		return null
	var out := img.get_region(r)
	out.convert(Image.FORMAT_RGBA8)
	out.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return out


# Исходник как Image: файл с диска (редактор, тесты), иначе из импортированной текстуры (экспорт).
static func source_image(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
	if img == null and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		img = tex.get_image() if tex != null else null
	return img


static func copy_path(type_name: String, size: Vector2i) -> String:
	return UI_DIR + "%s_%dx%d.png" % [type_name, size.x, size.y]


# Уменьшенная копия актуальна: сделана из тех же path и crop, что в данных.
func copy_fresh(type_name: String) -> bool:
	var m = made.get(type_name)
	var d: Dictionary = defs[type_name]
	return m is Dictionary and m.get("path") == d.path and m.get("crop") is Array and m.crop.size() == 4 \
		and Rect2i(int(m.crop[0]), int(m.crop[1]), int(m.crop[2]), int(m.crop[3])) == d.crop


# Текстура иллюстрации типа для кнопки button_size (полоса 2x размера кнопки); null — у типа картинки нет.
func texture(type_name: String, button_size: Vector2i) -> Texture2D:
	if not defs.has(type_name):
		return null
	var size := button_size * 2
	var key := "%s %dx%d" % [type_name, size.x, size.y]
	if cache.has(key):
		return cache[key]
	var tex: Texture2D = null
	var cp := copy_path(type_name, size)
	if copy_fresh(type_name) and ResourceLoader.exists(cp):
		tex = load(cp) as Texture2D
	if tex == null:
		var img := strip(source_image(defs[type_name].path), defs[type_name].crop, size)
		if img == null:
			push_warning("%s: иллюстрация «%s» (%s) не загрузилась или crop вне картинки: кнопка без неё" % [PATH, type_name, defs[type_name].path])
		else:
			push_warning("%s: копия %s не совпадает с данными (path, crop) — полоса вырезана при запуске; обновить: bench/make_unit_portraits.gd" % [PATH, cp])
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	cache[key] = tex
	return tex


func _style(border: Color, px: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = border
	s.set_border_width_all(px)
	s.content_margin_left = 10.0
	s.content_margin_right = 8.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


func _styles() -> Dictionary:
	if styles.is_empty():
		var plain := _style(Color(0, 0, 0, 0), 0)
		var sel := _style(SELECT_COLOR, SELECT_PX)
		styles = {"normal": plain, "disabled": plain, "hover": _style(HOVER_BORDER, 1), "pressed": sel, "hover_pressed": sel, "focus": StyleBoxEmpty.new()}
	return styles


# Иллюстрация типа на кнопке b (type_name "" или без картинки — обычная кнопка). Повторный вызов с тем же типом ничего не делает.
# Кнопка с рамкой вида (UI.frame_kind, мета frame_kind) остаётся в своей рамке: с иллюстрацией — без середины рамки (картинка
# видна, рамка поверх), без иллюстрации — с серединой; свои StyleBox иллюстрации тогда не ставятся.
func apply(b: Button, type_name: String) -> void:
	if b.has_meta("portrait") and b.get_meta("portrait") == type_name:
		return
	b.set_meta("portrait", type_name)
	var tex := texture(type_name, Vector2i(b.custom_minimum_size)) if type_name != "" else null
	var pic := b.get_node_or_null("Portrait") as TextureRect
	var kind: String = b.get_meta("frame_kind", "")
	if tex == null:   # обычная кнопка: картинка и градиент скрыты, оформление по умолчанию
		if pic != null:
			pic.visible = false
			b.get_node("Shade").visible = false
			if kind != "":
				UI.frame_kind(b, kind, true)
			else:
				for st in _styles():
					b.remove_theme_stylebox_override(st)
			b.remove_theme_color_override("font_outline_color")
			b.remove_theme_constant_override("outline_size")
		return
	if pic == null:
		if shader == null:
			shader = Shader.new()
			shader.code = SHADER
		pic = TextureRect.new()
		pic.name = "Portrait"
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pic.material = ShaderMaterial.new()
		pic.material.shader = shader
		var shade := TextureRect.new()
		shade.name = "Shade"
		if shade_tex == null:
			set_gradient(gradient.gradient_left_alpha, gradient.gradient_right_alpha, gradient.gradient_width)
		shade.texture = shade_tex
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		for c in [pic, shade]:   # за текстом и рамкой кнопки, на всю кнопку
			c.show_behind_parent = true
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.set_anchors_preset(Control.PRESET_FULL_RECT)
			b.add_child(c, false, Node.INTERNAL_MODE_FRONT)
		b.draw.connect(_on_draw.bind(b))
	if kind != "":
		UI.frame_kind(b, kind, false)
	else:
		for st in _styles():
			b.add_theme_stylebox_override(st, styles[st])
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", FONTS.outline(OUTLINE_PX))
	pic.texture = tex
	pic.visible = true
	b.get_node("Shade").visible = true
	b.queue_redraw()


# Состояние кнопки при каждой её перерисовке (наведение, нажатие, выбор, недоступность меняют вид и перерисовывают кнопку).
func _on_draw(b: Button) -> void:
	var pic := b.get_node_or_null("Portrait") as TextureRect
	if pic == null or not pic.visible:
		return
	var mode := b.get_draw_mode()
	var m := pic.material as ShaderMaterial
	m.set_shader_parameter("gray", 1.0 if mode == BaseButton.DRAW_DISABLED else 0.0)
	m.set_shader_parameter("bright", DISABLED_BRIGHT if mode == BaseButton.DRAW_DISABLED else (HOVER_BRIGHT if mode in [BaseButton.DRAW_HOVER, BaseButton.DRAW_HOVER_PRESSED] else 1.0))
