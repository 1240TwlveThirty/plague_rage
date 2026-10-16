extends CanvasLayer
# Экран «Настройки» поверх того, откуда открыт (главное меню, меню паузы): вкладки, «Назад». Esc тоже закрывает
# и дальше не идёт — меню под ним остаётся открытым. Значения читает и пишет автозагрузка Settings.
const UI := preload("res://scripts/ui.gd")
const BG := Color(0.0, 0.0, 0.0, 1.0)   # непрозрачный: меню под экраном не просвечивает
const FONT := 30

signal closed

var settings: Node
var tabs: TabContainer
var fullscreen_check: CheckButton
var back_button: Button


func _ready() -> void:
	layer = 110   # выше меню паузы (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	settings = get_node("/root/Settings")
	var dim := ColorRect.new()
	dim.color = BG
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # клики под экран не проходят
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	var title := Label.new()
	title.text = "Настройки"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)
	tabs = TabContainer.new()
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.custom_minimum_size = Vector2(900, 480)
	tabs.add_theme_font_size_override("font_size", FONT)
	box.add_child(tabs)
	_setup_video()
	back_button = Button.new()
	back_button.text = "Назад"
	back_button.add_theme_font_size_override("font_size", 36)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.gold_button(back_button)
	back_button.pressed.connect(close)
	box.add_child(back_button)
	settings.changed.connect(_on_changed)
	_set_focusable(self, false)


# Вкладка: колонка с отступами; title — заголовок вкладки.
func _tab(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	tabs.add_child(margin)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	margin.add_child(col)
	return col


func _setup_video() -> void:
	var col := _tab("Видео")
	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "Полный экран (F11)"
	fullscreen_check.add_theme_font_size_override("font_size", FONT)
	fullscreen_check.button_pressed = settings.fullscreen
	fullscreen_check.toggled.connect(settings.set_fullscreen)
	col.add_child(fullscreen_check)


func _on_changed(_key: String) -> void:
	fullscreen_check.set_pressed_no_signal(settings.fullscreen)


# Пока экран закрыт, его элементы фокус не берут (Space и Enter в бою их не нажимают), как в меню паузы.
func _set_focusable(node: Node, on: bool) -> void:
	if node is Control:
		var c := node as Control
		if not c.has_meta("focus_on"):
			c.set_meta("focus_on", c.focus_mode)   # исходный режим фокуса
		c.focus_mode = c.get_meta("focus_on") if on else Control.FOCUS_NONE
	for ch in node.get_children():
		_set_focusable(ch, on)


func open() -> void:
	_on_changed("")
	_set_focusable(self, true)
	visible = true
	tabs.current_tab = 0
	back_button.grab_focus()


func close() -> void:
	_set_focusable(self, false)
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
