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
var key_buttons := {}           # действие -> кнопка с клавишей на вкладке «Управление»
var key_msg: Label              # итог последнего назначения (обмен, отказ) или пусто
var reset_keys_button: Button
var waiting_action := ""        # ждём клавишу для этого действия; "" — не ждём


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
	tabs.custom_minimum_size = Vector2(960, 600)
	tabs.add_theme_font_size_override("font_size", FONT)
	box.add_child(tabs)
	_setup_video()
	_setup_controls()
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


# Вкладка «Управление»: «действие — клавиша»; клик по клавише и нажатие новой назначает её (Esc — отмена).
func _setup_controls() -> void:
	var col := _tab("Управление")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for r in settings.REBINDABLE:
		var l := Label.new()
		l.text = r[1]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 26)
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(320, 0)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(_wait_key.bind(r[0]))
		grid.add_child(b)
		key_buttons[r[0]] = b
	key_msg = Label.new()
	key_msg.add_theme_font_size_override("font_size", 24)
	key_msg.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	key_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(key_msg)
	reset_keys_button = Button.new()
	reset_keys_button.text = "Сбросить по умолчанию"
	reset_keys_button.add_theme_font_size_override("font_size", 26)
	reset_keys_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset_keys_button.pressed.connect(_reset_keys)
	col.add_child(reset_keys_button)
	_refresh_keys()


func _refresh_keys() -> void:
	for a in key_buttons:
		key_buttons[a].text = "Нажмите клавишу… (Esc — отмена)" if a == waiting_action else settings.key_label(a)


func _wait_key(action: String) -> void:
	waiting_action = action
	key_msg.text = ""
	_refresh_keys()


func _reset_keys() -> void:
	waiting_action = ""
	settings.reset_keys()
	key_msg.text = "Клавиши по умолчанию"
	_refresh_keys()


# Нажатая клавиша для ждущего действия: Esc — отмена, иначе Settings.rebind (обмен или отказ — сообщение).
func assign_key(event: InputEventKey) -> void:
	var action := waiting_action
	waiting_action = ""
	if event.keycode == KEY_ESCAPE:
		key_msg.text = ""
	else:
		key_msg.text = settings.rebind(action, event.keycode).msg
	_refresh_keys()


func _on_changed(_key: String) -> void:
	fullscreen_check.set_pressed_no_signal(settings.fullscreen)
	_refresh_keys()


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
	waiting_action = ""
	if key_msg != null:
		key_msg.text = ""
	_set_focusable(self, false)
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and waiting_action != "" and event is InputEventKey and event.pressed and not event.echo:
		assign_key(event)   # клавиша уходит в назначение, Esc экран не закрывает
		get_viewport().set_input_as_handled()
		return
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
