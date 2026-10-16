extends CanvasLayer
# Меню паузы по Esc (бой и хаб): «Продолжить», «Настройки», «Выйти в меню», «Выход из игры». Esc ещё раз — продолжить
# (при открытых настройках Esc сначала закрывает их).
# Пока открыто, дерево сцен на паузе: стоят симуляция боя, окно сигнала всплеска (оно идёт по времени волны) и Game.play_time.
# Открывает сцена-хозяин вызовом open(note); закрывается само. Перед уходом в меню вызывается before_menu хозяина:
# бой засчитывает брошенный забег поражением (с начислением Сияния).
const UI := preload("res://scripts/ui.gd")
const SETTINGS_MENU := preload("res://scripts/settings_menu.gd")
const DIM := Color(0.0, 0.0, 0.0, 0.7)

var continue_button: Button
var settings_button: Button
var settings_menu: CanvasLayer  # экран «Настройки» поверх меню паузы
var menu_button: Button
var quit_button: Button
var note_label: Label           # предупреждение хозяина под заголовком (ключ перевода; в бою — о поражении) или скрыта
var before_menu := Callable()   # хозяин задаёт: что сделать перед уходом в меню


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS   # работает при паузе дерева
	visible = false
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # клики под меню не проходят
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	var title := Label.new()
	title.text = "UI_PAUSE_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)
	note_label = Label.new()
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.add_theme_font_size_override("font_size", 26)
	note_label.visible = false
	box.add_child(note_label)
	continue_button = _button(box, "UI_PAUSE_RESUME")
	continue_button.pressed.connect(close)
	settings_button = _button(box, "UI_PAUSE_SETTINGS")
	settings_button.pressed.connect(_open_settings)
	menu_button = _button(box, "UI_PAUSE_TO_MENU")
	menu_button.pressed.connect(_on_menu)
	quit_button = _button(box, "UI_PAUSE_QUIT")
	quit_button.pressed.connect(_on_quit)
	settings_menu = SETTINGS_MENU.new()
	settings_menu.closed.connect(func(): settings_button.grab_focus())
	add_child(settings_menu)


func _button(box: Container, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 36)
	UI.gold_button(b)
	b.focus_mode = Control.FOCUS_NONE   # пока меню закрыто, кнопки фокус не берут: Space и Enter в бою их не нажимают
	box.add_child(b)
	return b


func open(note := "") -> void:
	note_label.text = note
	note_label.visible = note != ""
	visible = true
	get_tree().paused = true
	_set_focusable(true)
	continue_button.grab_focus()   # Enter продолжает


func close() -> void:
	if settings_menu.visible:
		settings_menu.close()
	_set_focusable(false)
	visible = false
	get_tree().paused = false


func _set_focusable(on: bool) -> void:
	for b in [continue_button, settings_button, menu_button, quit_button]:
		b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


# Esc при открытом меню — продолжить; до сцены-хозяина клавиша не доходит.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _open_settings() -> void:
	settings_menu.open()


func _on_menu() -> void:
	close()
	if before_menu.is_valid():
		before_menu.call()
	get_node("/root/Game").go_menu()


func _on_quit() -> void:
	get_node("/root/Game").quit_game()   # сохранить и выйти
