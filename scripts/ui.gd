extends RefCounted
# Общий вид меню, хаба и меню паузы: чёрный фон, золотые кнопки.
const BG_COLOR := Color.BLACK
const GOLD := Color(0.85, 0.65, 0.13)
const GOLD_HOVER := Color(1.0, 0.8, 0.25)
const GOLD_PRESSED := Color(0.65, 0.5, 0.1)
const GOLD_DISABLED := Color(0.3, 0.24, 0.1)
const BUTTON_TEXT := Color(0.08, 0.06, 0.02)
const BUTTON_TEXT_DISABLED := Color(0.08, 0.06, 0.02, 0.7)


static func _box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(6)
	s.content_margin_left = 20.0
	s.content_margin_right = 20.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


# Золотая кнопка с тёмным текстом; фокус — белая рамка.
static func gold_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(GOLD))
	b.add_theme_stylebox_override("hover", _box(GOLD_HOVER))
	b.add_theme_stylebox_override("pressed", _box(GOLD_PRESSED))
	b.add_theme_stylebox_override("disabled", _box(GOLD_DISABLED))
	var focus := _box(Color(0.0, 0.0, 0.0, 0.0))
	focus.set_border_width_all(3)
	focus.border_color = Color.WHITE
	b.add_theme_stylebox_override("focus", focus)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, BUTTON_TEXT)
	b.add_theme_color_override("font_disabled_color", BUTTON_TEXT_DISABLED)
