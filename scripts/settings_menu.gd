extends CanvasLayer
# Экран «Настройки» поверх того, откуда открыт (главное меню, меню паузы): вкладки, «Назад». Esc тоже закрывает
# и дальше не идёт — меню под ним остаётся открытым. Значения читает и пишет автозагрузка Settings.
# Тексты — ключи перевода: метки и кнопки переводятся сами, собранные строки обновляются при смене языка.
const FONTS := preload("res://scripts/fonts.gd")   # кегли и контуры текста под вариант шрифта (задача 20)
const UI := preload("res://scripts/ui.gd")
const BG := Color(0.0, 0.0, 0.0, 1.0)   # непрозрачный: меню под экраном не просвечивает
const FONT := 30
const UI_LAYOUT := "res://data/ui_layout.json"
# Задача 26: окно одного размера на всех вкладках (settings_size), лишнее прокручивается внутри вкладки; на «Управлении»
# действия по группам с заголовками (controls_groups), высота строки — settings_key_row_height. Нет поля — значения ниже.
const LAYOUT_DEFAULTS := {"settings_size": [1100, 640], "settings_key_row_height": 56, "controls_groups": []}
const GROUP_COLOR := Color("#feae34")   # заголовок группы (Endesga 32)

signal closed

var settings: Node
var tabs: TabContainer
var fullscreen_check: CheckButton
var shake_option: OptionButton   # «Тряска экрана»: выкл / слабая / обычная / сильная (задача 23)
var gore_option: OptionButton    # «Жестокость»: выкл / обычная (задача 23)
var card_anim_option: OptionButton   # «Анимация выбора карточки»: выкл / короткая / полная (задача 25)
var hints_check: CheckButton     # «Подсказки» вкл/выкл (задача 26)
var hints_reset_button: Button   # «Сбросить подсказки»
var data_folder_button: Button   # «Открыть папку данных» (user://: настройки, сохранение, журнал забегов runs.csv)
var game_msg: Label              # итог «Сбросить подсказки»
var back_button: Button
var key_titles := {}            # действие -> подпись строки на вкладке «Управление»
var key_buttons := {}           # действие -> кнопка с клавишей на вкладке «Управление»
var key_msg: Label              # итог последнего назначения (обмен, отказ) или пусто
var reset_keys_button: Button
var waiting_action := ""        # ждём клавишу для этого действия; "" — не ждём
var lang_buttons := {}          # "ru" / "en" -> кнопка выбора языка
var music_slider: HSlider
var sfx_slider: HSlider
var layout := {}                # LAYOUT_DEFAULTS поверх data/ui_layout.json
var key_groups := []            # [[заголовок, [действия]], ...] — как показаны на «Управлении»
var group_heads: Array[Label] = []


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
	title.add_theme_font_size_override("font_size", FONTS.px(64))
	box.add_child(title)
	layout = load_layout()
	tabs = TabContainer.new()
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.custom_minimum_size = Vector2(layout.settings_size[0], layout.settings_size[1])   # и не больше: содержимое вкладок прокручивается
	tabs.clip_contents = true
	tabs.add_theme_font_size_override("font_size", FONTS.px(FONT))
	UI.frame_panel_dark(tabs)   # задача 24: тёмный экран — вкладки на тёмной панели
	box.add_child(tabs)
	_setup_video()
	_setup_audio()
	_setup_controls()
	_setup_game()
	_setup_language()
	back_button = Button.new()
	back_button.text = "UI_SETTINGS_BACK"
	back_button.add_theme_font_size_override("font_size", FONTS.px(36))
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.frame_button(back_button)
	back_button.pressed.connect(close)
	box.add_child(back_button)
	settings.changed.connect(_on_changed)
	_set_focusable(self, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and tabs != null:
		_refresh_keys()


# data/ui_layout.json: размер окна, высота строки клавиши, группы действий. Поле неверно — значение по умолчанию.
static func load_layout() -> Dictionary:
	var out := LAYOUT_DEFAULTS.duplicate(true)
	var d = JSON.parse_string(FileAccess.get_file_as_string(UI_LAYOUT)) if FileAccess.file_exists(UI_LAYOUT) else null
	if not d is Dictionary:
		return out
	var sz = d.get("settings_size")
	if sz is Array and sz.size() == 2 and sz.all(func(x): return (x is float or x is int) and x > 0):
		out.settings_size = sz
	var rh = d.get("settings_key_row_height")
	if (rh is float or rh is int) and rh > 0:
		out.settings_key_row_height = rh
	if d.get("controls_groups") is Array:
		out.controls_groups = d.controls_groups
	return out


# Вкладка: колонка с отступами; title — ключ заголовка вкладки (TabBar переводит сам). scroll — колонка в прокрутке
# (содержимое не раздвигает окно); без неё вкладка сама прокручивает свою часть («Управление»).
func _tab(title: String, scroll := true) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	tabs.add_child(margin)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if scroll:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(sc)
		sc.add_child(col)
	else:
		margin.add_child(col)
	return col


func _setup_video() -> void:
	var col := _tab("UI_SETTINGS_TAB_VIDEO")
	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "UI_SETTINGS_FULLSCREEN"
	fullscreen_check.add_theme_font_size_override("font_size", FONTS.px(FONT))
	fullscreen_check.button_pressed = settings.fullscreen
	fullscreen_check.toggled.connect(settings.set_fullscreen)
	col.add_child(fullscreen_check)
	shake_option = _option_row(col, "UI_SETTINGS_SCREEN_SHAKE", settings.SHAKE_LEVELS, settings.screen_shake_level, settings.set_screen_shake_level)
	gore_option = _option_row(col, "UI_SETTINGS_GORE", settings.GORE_LEVELS, settings.gore, settings.set_gore)
	card_anim_option = _option_row(col, "UI_SETTINGS_CARD_ANIM", settings.CARD_ANIM_LEVELS, settings.card_pick_anim, settings.set_card_pick_anim)


# Строка «подпись — выбор из списка» (ключи перевода items, индекс — значение).
func _option_row(col: Container, title: String, items: Array, value: int, on_change: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 300.0
	l.add_theme_font_size_override("font_size", FONTS.px(FONT))
	row.add_child(l)
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", FONTS.px(FONT))
	for k in items.size():
		o.add_item(items[k], k)
	o.select(value)
	o.item_selected.connect(on_change)
	row.add_child(o)
	return o


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
	l.add_theme_font_size_override("font_size", FONTS.px(FONT))
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


# Группы «Управления»: controls_groups из data (заголовок — ключ перевода, действия) в порядке файла; действие, которого нет
# ни в одной группе, — в последнюю (с предупреждением); скрытые действия и пустые группы не показываются.
static func key_groups_for(groups: Array, rebindable: Array, hidden: Array) -> Array:
	var out := []
	var placed := {}
	for g in groups:
		if not (g is Dictionary and g.get("title") is String and g.get("actions") is Array):
			continue
		var acts := []
		for a in g.actions:
			if a in rebindable and not placed.has(a):
				placed[a] = true
				if not a in hidden:
					acts.append(a)
		out.append([g.title, acts])
	var rest := []
	for a in rebindable:
		if not placed.has(a) and not a in hidden:
			rest.append(a)
	if not rest.is_empty():
		push_warning("%s: controls_groups без действий %s — они в последней группе" % [UI_LAYOUT, str(rest)])
		if out.is_empty():
			out.append(["UI_SETTINGS_TAB_CONTROLS", []])
		out[-1][1].append_array(rest)
	return out.filter(func(g): return not g[1].is_empty())


# Вкладка «Управление»: «действие — клавиша» по группам (отряды, герой, камера, интерфейс) с заголовками; клик по клавише
# и нажатие новой клавиши или средней/боковой кнопки мыши назначает её (Esc — отмена).
func _setup_controls() -> void:
	var col := _tab("UI_SETTINGS_TAB_CONTROLS", false)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var row_h := float(layout.settings_key_row_height)
	key_groups = key_groups_for(layout.controls_groups, settings.REBINDABLE, settings.hidden_actions())
	for g in key_groups:
		var head := Label.new()
		head.text = g[0]
		head.add_theme_font_size_override("font_size", FONTS.px(28))
		head.add_theme_color_override("font_color", GROUP_COLOR)
		if not group_heads.is_empty():
			head.custom_minimum_size.y = row_h   # отступ над заголовком следующей группы
			head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		list.add_child(head)
		group_heads.append(head)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 32)
		grid.add_theme_constant_override("v_separation", 8)
		list.add_child(grid)
		for a in g[1]:
			var l := Label.new()
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size.y = row_h
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.add_theme_font_size_override("font_size", FONTS.px(26))
			grid.add_child(l)
			key_titles[a] = l
			var b := Button.new()
			b.custom_minimum_size = Vector2(320, row_h)
			b.add_theme_font_size_override("font_size", FONTS.px(26))
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # названия клавиш не переводятся
			UI.frame_button(b, false)   # строка таблицы: ширина 320, высота settings_key_row_height
			b.pressed.connect(_wait_key.bind(a))
			grid.add_child(b)
			key_buttons[a] = b
	key_msg = Label.new()
	key_msg.add_theme_font_size_override("font_size", FONTS.px(24))
	key_msg.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	key_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(key_msg)
	reset_keys_button = Button.new()
	reset_keys_button.text = "UI_SETTINGS_KEYS_RESET"
	reset_keys_button.add_theme_font_size_override("font_size", FONTS.px(26))
	reset_keys_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UI.frame_button(reset_keys_button)
	reset_keys_button.pressed.connect(_reset_keys)
	col.add_child(reset_keys_button)
	_refresh_keys()


# Вкладка «Игра» (задача 26): подсказки первой минуты (вкл/выкл, сбросить) и папка данных игры.
func _setup_game() -> void:
	var col := _tab("UI_SETTINGS_TAB_GAME")
	hints_check = CheckButton.new()
	hints_check.text = "UI_SETTINGS_HINTS"
	hints_check.add_theme_font_size_override("font_size", FONTS.px(FONT))
	hints_check.button_pressed = settings.hints_enabled
	hints_check.toggled.connect(settings.set_hints_enabled)
	col.add_child(hints_check)
	hints_reset_button = Button.new()
	hints_reset_button.text = "UI_SETTINGS_HINTS_RESET"
	hints_reset_button.add_theme_font_size_override("font_size", FONTS.px(26))
	hints_reset_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UI.frame_button(hints_reset_button)
	hints_reset_button.pressed.connect(_reset_hints)
	col.add_child(hints_reset_button)
	game_msg = Label.new()
	game_msg.add_theme_font_size_override("font_size", FONTS.px(24))
	game_msg.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	col.add_child(game_msg)
	data_folder_button = Button.new()
	data_folder_button.text = "UI_SETTINGS_DATA_FOLDER"
	data_folder_button.add_theme_font_size_override("font_size", FONTS.px(26))
	data_folder_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UI.frame_button(data_folder_button)
	data_folder_button.pressed.connect(open_data_folder)
	col.add_child(data_folder_button)


func _reset_hints() -> void:
	settings.reset_hints()
	game_msg.text = "MSG_HINTS_RESET_DONE"


# Папка user:// в проводнике системы (там settings.cfg, save.json и журнал забегов runs.csv). Возвращает путь (тесты).
var shell_open := func(path: String) -> Error: return OS.shell_open(path)   # тесты подменяют: окно проводника не открывается
func open_data_folder() -> String:
	var path := ProjectSettings.globalize_path("user://")
	shell_open.call(path)
	return path


# Вкладка «Язык»: «Русский» и «English», переключение сразу.
func _setup_language() -> void:
	var col := _tab("UI_SETTINGS_TAB_LANGUAGE")
	var group := ButtonGroup.new()
	for l in settings.LANGUAGES:
		var b := CheckBox.new()
		b.text = "UI_SETTINGS_LANG_" + l.to_upper()
		b.button_group = group
		b.add_theme_font_size_override("font_size", FONTS.px(FONT))
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
	shake_option.select(settings.screen_shake_level)
	gore_option.select(settings.gore)
	card_anim_option.select(settings.card_pick_anim)
	hints_check.set_pressed_no_signal(settings.hints_enabled)
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
	var f := get_node_or_null("/root/Focus")
	if f != null:
		f.hide_focus()   # задача 26: при открытии ни одна кнопка не подсвечена, пока не нажата клавиша


func close() -> void:
	waiting_action = ""
	if key_msg != null:
		key_msg.text = ""
	if game_msg != null:
		game_msg.text = ""
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
