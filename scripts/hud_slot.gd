extends PanelContainer
# Окошко верхней панели боя и Сияния (задача 19): рамка ui_slot ×2 (вариация темы FrameSlot), иконка из атласа, число.
# С полосой (ворота) — рамка и заливка полосы из темы (FrameBar), число «текущее/максимум» поверх полосы.
# Подпись и полоса меняются, только когда значение изменилось (set_value): строка не собирается каждый кадр.
# Числа от 1000 — с пробелом между тысячами; не помещается при font_size — кегль меньше, но не ниже font_min, дальше
# сокращение «12.3к» (HUD_THOUSANDS).
const UI := preload("res://scripts/ui.gd")
const ICONS := preload("res://scripts/icons.gd")

var id := ""
var label: Label
var bar: Control        # полоса: рамка снизу, обрезка заливки сверху (clip_contents), число поверх; null — окошко без полосы
var bar_clip: Control   # ширина — доля HP, заливка внутри не масштабируется, а обрезается
var value := 0
var value_max := -1     # -1 — без максимума (число без «/M»)
var font_size := 18
var font_min := 16
var text_width := 0.0   # ширина под число: окошко без полей и иконки, у полосы — её ширина
var fill_left := 0      # окно заливки на экране (из темы, FrameBar)
var fill_right := 0
var fill_step := 1
var _shown := false     # set_value ещё не вызывали: первое значение показывается всегда


# Окошко id: ширина width, высота height, иконка icon (id из data/icon_atlas.json) ×icon_scale, зазор icon_gap; with_bar — полоса.
func setup(slot_id: String, icon: String, width: float, height: float, icon_scale: int, icon_gap: float, size_px: int, size_min: int, with_bar := false) -> void:
	id = slot_id
	name = "Slot_" + slot_id
	font_size = size_px
	font_min = size_min
	UI.frame_slot(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(width, height)
	size = custom_minimum_size
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(icon_gap))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var ic := ICONS.make(icon, icon_scale)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	label = Label.new()
	UI.frame_label(label)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # числа, перевод не нужен
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	var inner := width - UI.slot_margins().x
	if with_bar:
		var t := ThemeDB.get_project_theme()
		var frame: Texture2D = t.get_icon("frame", UI.BAR)
		var fill: Texture2D = t.get_icon("fill", UI.BAR)
		fill_left = t.get_constant("fill_left", UI.BAR)
		fill_right = t.get_constant("fill_right", UI.BAR)
		fill_step = maxi(t.get_constant("step", UI.BAR), 1)
		bar = Control.new()
		bar.custom_minimum_size = frame.get_size()
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER   # по центру места справа от иконки
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(_tex_rect(frame))
		bar_clip = Control.new()
		bar_clip.clip_contents = true
		bar_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_clip.size = Vector2(0.0, frame.get_height())
		bar_clip.add_child(_tex_rect(fill))
		bar.add_child(bar_clip)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar.add_child(label)
		row.add_child(bar)
		text_width = frame.get_width()
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		text_width = inner - ic.custom_minimum_size.x - icon_gap


func _tex_rect(t: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP   # 1:1, без растяжения
	r.size = t.get_size()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# Показать v (и максимум vmax: «v/vmax», у полосы — доля). Значение то же — ничего не делает.
func set_value(v: int, vmax := -1) -> void:
	if _shown and v == value and vmax == value_max:
		return
	_shown = true
	value = v
	value_max = vmax
	var full := group(v) if vmax < 0 else group(v) + "/" + group(vmax)
	_fit(full)
	if bar_clip != null:
		var frac := clampf(float(v) / float(vmax), 0.0, 1.0) if vmax > 0 else 0.0
		var window := bar.custom_minimum_size.x - fill_left - fill_right
		# пустая — ничего; иначе левый край (как у рамки) и доля окна, по целым пикселям арта
		bar_clip.size.x = 0.0 if frac <= 0.0 else fill_left + floorf(frac * window / fill_step) * fill_step


# Кегль от font_size вниз до font_min, пока текст не влезет в text_width; не влез и при font_min — сокращение тысяч.
func _fit(full: String) -> void:
	var font := label.get_theme_font("font")
	var outline := label.get_theme_constant("outline_size")
	var text := full
	var px := font_size
	while px > font_min and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + outline > text_width:
		px -= 1
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + outline > text_width:
		text = short(value) if value_max < 0 else short(value) + "/" + short(value_max)
	if label.get_theme_font_size("font_size") != px:
		label.add_theme_font_size_override("font_size", px)
	label.text = text


# Заново подобрать текст (смена языка: сокращение «к» / «k»).
func refresh() -> void:
	if _shown:
		_shown = false
		set_value(value, value_max)


# Пиксели, которые текст при текущем кегле займёт (для тестов и отчёта).
func text_px() -> float:
	return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x \
		+ label.get_theme_constant("outline_size")


# 12345 -> «12 345»; отрицательные — со знаком.
static func group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# 12345 -> «12.3к» (до 1000 — как есть).
static func short(n: int) -> String:
	if absi(n) < 1000:
		return str(n)
	return TranslationServer.translate("HUD_THOUSANDS") % ("%.1f" % (n / 1000.0))
