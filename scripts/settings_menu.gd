extends CanvasLayer
# Экран «Настройки» поверх того, откуда открыт (главное меню, меню паузы): вкладки, «Назад». Esc тоже закрывает
# и дальше не идёт — меню под ним остаётся открытым. Значения читает и пишет автозагрузка Settings.
# Тексты — ключи перевода: метки и кнопки переводятся сами, собранные строки обновляются при смене языка.
const UI := preload("res://scripts/ui.gd")
const BG := Color(0.0, 0.0, 0.0, 1.0)   # непрозрачный: меню под экраном не просвечивает
const FONT := 30

signal closed

var settings: Node
var tabs: TabContainer
var fullscreen_check: CheckButton
var shake_check: CheckButton   # «Тряска экрана» (задача 12)
var back_button: Button
var key_titles := {}            # действие -> подпись строки на вкладке «Управление»
var key_buttons := {}           # действие -> кнопка с клавишей на вкладке «Управление»
var key_msg: Label              # итог последнего назначения (обмен, отказ) или пусто
var reset_keys_button: Button
var waiting_action := ""        # ждём клавишу для этого действия; "" — не ждём
var lang_buttons := {}          # "ru" / "en" -> кнопка выбора языка
var music_slider: HSlider
var sfx_slider: HSlider


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
	title.text = "UI_SETTINGS_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)
	tabs = TabContainer.new()
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.custom_minimum_size = Vector2(960, 600)
	tabs.add_theme_font_size_override("font_size", FONT)
	box.add_child(tabs)
	_setup_video()
	_setup_audio()
	_setup_controls()
	_setup_language()
	back_button = Button.new()
	back_button.text = "UI_SETTINGS_BACK"
	back_button.add_theme_font_size_override("font_size", 36)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.gold_button(back_button)
	back_button.pressed.connect(close)
	box.add_child(back_button)
	settings.changed.connect(_on_changed)
	_set_focusable(self, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and tabs != null:
		_refresh_keys()


# Вкладка: колонка с отступами; title — ключ заголовка вкладки (TabBar переводит сам).
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
	var col := _tab("UI_SETTINGS_TAB_VIDEO")
	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "UI_SETTINGS_FULLSCREEN"
	fullscreen_check.add_theme_font_size_override("font_size", FONT)
	fullscreen_check.button_pressed = settings.fullscreen
	fullscreen_check.toggled.connect(settings.set_fullscreen)
	col.add_child(fullscreen_check)
	shake_check = CheckButton.new()
	shake_check.text = "UI_SETTINGS_SCREEN_SHAKE"
	shake_check.add_theme_font_size_override("font_size", FONT)
	shake_check.button_pressed = settings.screen_shake
	shake_check.toggled.connect(settings.set_screen_shake)
	col.add_child(shake_check)


# Вкладка «Звук»: ползунки «Музыка» и «Эффекты» (линейная громкость 0..1, Settings переводит в dB).
func _setup_audio() -> void:
	var col := _tab("UI_SETTINGS_TAB_AUDIO")
	music_slider = _volume_row(col, "UI_SETTINGS_MUSIC", settings.music_volume, settings.set_music_volume)
	sfx_slider = _volume_row(col, "UI_SETTINGS_SFX", settings.sfx_volume, settings.set_sfx_volume)


func _volume_row(col: Container, title: String, value: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 300.0
	l.add_theme_font_size_override("font_size", FONT)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(480, 32)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(on_change)
	row.add_child(sl)
	return sl


# Вкладка «Управление»: «действие — клавиша»; клик по клавише и нажатие новой клавиши или средней/боковой кнопки мыши
# назначает её (Esc — отмена).
func _setup_controls() -> void:
	var col := _tab("UI_SETTINGS_TAB_CONTROLS")
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
	var hidden: Array = settings.hidden_actions()
	for a in settings.REBINDABLE:
		if a in hidden:   # покупка выключенного товара (копейщики в v1) не показывается
			continue
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 26)
		grid.add_child(l)
		key_titles[a] = l
		var b := Button.new()
		b.custom_minimum_size = Vector2(320, 0)
		b.add_theme_font_size_override("font_size", 26)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # названия клавиш не переводятся
		b.pressed.connect(_wait_key.bind(a))
		grid.add_child(b)
		key_buttons[a] = b
	key_msg = Label.new()
	key_msg.add_theme_font_size_override("font_size", 24)
	key_msg.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	key_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(key_msg)
	reset_keys_button = Button.new()
	reset_keys_button.text = "UI_SETTINGS_KEYS_RESET"
	reset_keys_button.add_theme_font_size_override("font_size", 26)
	reset_keys_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset_keys_button.pressed.connect(_reset_keys)
	col.add_child(reset_keys_button)
	_refresh_keys()


# Вкладка «Язык»: «Русский» и «English», переключение сразу.
func _setup_language() -> void:
	var col := _tab("UI_SETTINGS_TAB_LANGUAGE")
	var group := ButtonGroup.new()
	for l in settings.LANGUAGES:
		var b := CheckBox.new()
		b.text = "UI_SETTINGS_LANG_" + l.to_upper()
		b.button_group = group
		b.add_theme_font_size_override("font_size", FONT)
		b.button_pressed = settings.language == l
		b.pressed.connect(settings.set_language.bind(l))
		col.add_child(b)
		lang_buttons[l] = b


func _refresh_keys() -> void:
	for a in key_buttons:
		key_titles[a].text = settings.action_title(a)
		key_buttons[a].text = tr("UI_SETTINGS_KEY_WAIT") if a == waiting_action else settings.key_label(a)


func _wait_key(action: String) -> void:
	waiting_action = action
	key_msg.text = ""
	_refresh_keys()


func _reset_keys() -> void:
	waiting_action = ""
	settings.reset_keys()
	key_msg.text = "MSG_KEYS_RESET_DONE"
	_refresh_keys()


# Нажатая клавиша или кнопка мыши для ждущего действия: Esc — отмена, иначе Settings.rebind_event (обмен или отказ —
# сообщение).
func assign_key(event: InputEvent) -> void:
	var action := waiting_action
	waiting_action = ""
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		key_msg.text = ""
	else:
		key_msg.text = settings.rebind_event(action, event).msg
	_refresh_keys()


func _on_changed(_key: String) -> void:
	fullscreen_check.set_pressed_no_signal(settings.fullscreen)
	shake_check.set_pressed_no_signal(settings.screen_shake)
	music_slider.set_value_no_signal(settings.music_volume)
	sfx_slider.set_value_no_signal(settings.sfx_volume)
	for l in lang_buttons:
		lang_buttons[l].set_pressed_no_signal(settings.language == l)
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
	if visible and waiting_action != "" and event is InputEventMouseButton and event.pressed and settings.MOUSE_BINDABLE.has(event.button_index):
		assign_key(event)   # средняя и боковые кнопки мыши; ЛКМ и ПКМ работают с интерфейсом как обычно
		get_viewport().set_input_as_handled()
		return
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
