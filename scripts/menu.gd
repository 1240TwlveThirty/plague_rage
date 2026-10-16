extends Control
# Главное меню: заголовок, «Играть» (в хаб), «Настройки» и «Выход». Интерфейс строится кодом, по центру экрана;
# тексты — ключи перевода (Label и Button переводятся сами).
const UI := preload("res://scripts/ui.gd")
const SETTINGS_MENU := preload("res://scripts/settings_menu.gd")

var play_button: Button
var settings_button: Button
var quit_button: Button
var settings_menu: CanvasLayer   # экран «Настройки» поверх меню


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG_COLOR
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
	title.text = "UI_MENU_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	box.add_child(title)
	play_button = _button(box, "UI_MENU_PLAY")
	play_button.pressed.connect(_on_play)
	settings_button = _button(box, "UI_MENU_SETTINGS")
	settings_button.pressed.connect(_open_settings)
	quit_button = _button(box, "UI_MENU_QUIT")
	quit_button.pressed.connect(_on_quit)
	settings_menu = SETTINGS_MENU.new()
	settings_menu.closed.connect(func(): settings_button.grab_focus())
	add_child(settings_menu)
	play_button.grab_focus()   # Enter нажимает «Играть»


func _button(box: Container, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 36)
	UI.gold_button(b)
	box.add_child(b)
	return b


func _on_play() -> void:
	get_node("/root/Game").go_hub()


func _open_settings() -> void:
	settings_menu.open()


func _on_quit() -> void:
	get_node("/root/Game").quit_game()   # сохранить и выйти
