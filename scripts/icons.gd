extends RefCounted
# Иконки карточек и даров: общий набор, атлас art/icons.png (автор кладёт свой файл), порядок ячеек — data/icon_atlas.json
# (id иконки -> индекс ячейки, cell x cell пикселей, per_row в ряду), какая иконка у карточки или дара — data/icon_map.json.
# Ячейка берётся из art/icons.png; файла нет или ячейка полностью прозрачна — из заглушки art/icons_placeholder.png; нет и её —
# рамка с буквой (первая буква id), нарисованная кодом. Атласы читаются один раз (первый вызов), фильтр nearest, масштаб — целый.
const ATLAS_PATH := "res://art/icons.png"
const PLACEHOLDER_PATH := "res://art/icons_placeholder.png"
const ATLAS_JSON := "res://data/icon_atlas.json"
const MAP_JSON := "res://data/icon_map.json"
const FRAME_COLOR := Color(0.78, 0.67, 0.43)
const FILL_COLOR := Color(0.27, 0.2, 0.16)
const LETTER_COLOR := Color(0.94, 0.86, 0.67)

static var atlas_path := ATLAS_PATH          # тесты подменяют (загрузка без атласа)
static var placeholder_path := PLACEHOLDER_PATH
static var _loaded := false
static var cell := 16
static var per_row := 8
static var order := {}       # id иконки -> индекс ячейки
static var card_icon := {}   # id карточки -> id иконки
static var gift_icon := {}   # id дара -> id иконки
static var _tex := {}        # id иконки -> Texture2D ячейки или null (тогда рамка с буквой)
static var source := {}      # id иконки -> "atlas" | "placeholder" | "code" (для отчёта и тестов)


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: %s" % path)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# Сбросить загруженное (тесты: другой путь атласа).
static func reset() -> void:
	_loaded = false
	order = {}
	card_icon = {}
	gift_icon = {}
	_tex = {}
	source = {}


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var a = _json(ATLAS_JSON)
	if a is Dictionary and a.get("icons") is Dictionary:
		cell = int(a.get("cell", 16))
		per_row = int(a.get("per_row", 8))
		for k in a.icons:
			order[k] = int(a.icons[k])
	else:
		push_error("%s: нет объекта icons" % ATLAS_JSON)
	var m = _json(MAP_JSON)
	if m is Dictionary:
		card_icon = m.get("cards", {})
		gift_icon = m.get("gifts", {})
	var images := [_image(atlas_path), _image(placeholder_path)]
	for id in order:
		_tex[id] = null
		source[id] = "code"
		for q in 2:
			var img: Image = images[q]
			if img == null:
				continue
			var idx: int = order[id]
			var r := Rect2i((idx % per_row) * cell, (idx / per_row) * cell, cell, cell)
			if r.end.x > img.get_width() or r.end.y > img.get_height() or img.get_region(r).is_invisible():
				continue
			_tex[id] = ImageTexture.create_from_image(img.get_region(r))
			source[id] = ["atlas", "placeholder"][q]
			break


static func _image(path: String) -> Image:
	if path.begins_with("user://"):   # тесты: свой атлас без импорта
		return Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if not ResourceLoader.exists(path):
		return null
	var t = load(path)
	return (t as Texture2D).get_image() if t is Texture2D else null


static func of_card(card_id: String) -> String:
	load_all()
	return card_icon.get(card_id, "")


static func of_gift(gift_id: String) -> String:
	load_all()
	return gift_icon.get(gift_id, "")


# Иконка id размером cell * scale (scale — целое): TextureRect (nearest) из атласа или заглушки, иначе рамка с буквой.
static func make(icon_id: String, scale: int) -> Control:
	load_all()
	var size := Vector2(cell * scale, cell * scale)
	var t: Texture2D = _tex.get(icon_id, null)
	if t != null:
		var r := TextureRect.new()
		r.texture = t
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.custom_minimum_size = size
		r.size = size
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var box := Panel.new()   # рамка с буквой — пока нет ни атласа, ни заглушки
	var st := StyleBoxFlat.new()
	st.bg_color = FILL_COLOR
	st.border_color = FRAME_COLOR
	st.set_border_width_all(maxi(scale, 1))
	box.add_theme_stylebox_override("panel", st)
	box.custom_minimum_size = size
	box.size = size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = icon_id.left(1).to_upper() if icon_id != "" else "?"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", maxi(int(cell * scale * 0.6), 8))
	l.add_theme_color_override("font_color", LETTER_COLOR)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return box
