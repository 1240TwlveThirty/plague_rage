extends Control
# Главное меню: заголовок, «Играть» (в хаб) и «Выход». Интерфейс строится кодом.
const BG_COLOR := Color(0.08, 0.08, 0.1)

var play_button: Button
var quit_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	var title := Label.new()
	title.text = "Plague Wrath"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	box.add_child(title)
	play_button = _button(box, "Играть")
	play_button.pressed.connect(_on_play)
	quit_button = _button(box, "Выход")
	quit_button.pressed.connect(_on_quit)
	play_button.grab_focus()   # Enter нажимает «Играть»


func _button(box: Container, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 36)
	box.add_child(b)
	return b


func _on_play() -> void:
	get_node("/root/Game").go_hub()


func _on_quit() -> void:
	get_node("/root/Game").quit_game()   # сохранить и выйти
