extends Control
# Хаб-заглушка между забегами: осада, итог последнего забега, рекорды, «Начать забег», «Дневник» и «В меню».
# Интерфейс строится кодом. Выбор осады виден, только когда открыто больше одной.
const BG_COLOR := Color(0.08, 0.08, 0.1)
const WARN_COLOR := Color(1.0, 0.75, 0.35)
const STORY_COLOR := Color(1.0, 0.88, 0.6)   # как у дневника в баннере боя
const DIARY_SIZE := Vector2(0.5, 0.7)        # панель дневника: доля экрана
const DIARY_EMPTY := "Записей пока нет."

var game: Node
var chosen := 1                # осада, с которой начнётся забег
var siege_label: Label
var last_label: Label
var warning_label: Label       # предупреждение о сохранении; скрыта, если его нет
var record_labels: Array[Label] = []
var siege_option: OptionButton
var start_button: Button
var diary_button: Button
var menu_button: Button
var diary_panel: PanelContainer
var diary_box: VBoxContainer   # строки дневника внутри прокрутки
var diary_close: Button


func _ready() -> void:
	game = get_node("/root/Game")
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
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	_label(box, "Хаб", 64)
	warning_label = _label(box, game.save_warning, 26)
	warning_label.add_theme_color_override("font_color", WARN_COLOR)
	warning_label.visible = game.save_warning != ""
	siege_label = _label(box, "", 40)
	last_label = _label(box, "", 30)
	for s in range(1, game.siege_count + 1):
		record_labels.append(_label(box, "", 26))
	# по умолчанию — последняя выбранная осада (из сохранения), иначе первая
	var open: int = maxi(game.unlocked_siege, 1)
	chosen = clampi(game.last_siege, 1, open)
	siege_option = OptionButton.new()
	siege_option.add_theme_font_size_override("font_size", 30)
	for s in range(1, open + 1):
		siege_option.add_item(game.siege_name(s), s)
	siege_option.select(siege_option.get_item_index(chosen))
	siege_option.visible = game.unlocked_siege >= 2
	siege_option.item_selected.connect(_on_siege_selected)
	box.add_child(siege_option)
	start_button = _button(box, "Начать забег")
	start_button.pressed.connect(_on_start)
	diary_button = _button(box, "Дневник")
	diary_button.pressed.connect(_open_diary)
	diary_button.disabled = game.story.is_empty()   # story.json не загрузился: ошибка уже выведена
	menu_button = _button(box, "В меню")
	menu_button.pressed.connect(_on_menu)
	_setup_diary()
	_refresh()
	start_button.grab_focus()   # Enter начинает забег


func _label(box: Container, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	box.add_child(l)
	return l


func _button(box: Container, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 36)
	box.add_child(b)
	return b


# Панель дневника поверх хаба: заголовок, прокрутка со строками, «Закрыть». Скрыта, пока не открыта кнопкой.
func _setup_diary() -> void:
	diary_panel = PanelContainer.new()
	diary_panel.anchor_left = 0.5 - DIARY_SIZE.x * 0.5
	diary_panel.anchor_right = 0.5 + DIARY_SIZE.x * 0.5
	diary_panel.anchor_top = 0.5 - DIARY_SIZE.y * 0.5
	diary_panel.anchor_bottom = 0.5 + DIARY_SIZE.y * 0.5
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.03, 0.03, 0.04)
	panel_bg.set_content_margin_all(24.0)
	diary_panel.add_theme_stylebox_override("panel", panel_bg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	diary_panel.add_child(col)
	_label(col, "Дневник военачальника", 40)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	diary_box = VBoxContainer.new()
	diary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diary_box.add_theme_constant_override("separation", 20)
	scroll.add_child(diary_box)
	diary_close = _button(col, "Закрыть")
	diary_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	diary_close.pressed.connect(_close_diary)
	diary_panel.visible = false
	add_child(diary_panel)


# Прочитанное: вступление, затем записи в порядке (осада, волна). Непрочитанное не показывается никак.
# Результат: [[заголовок, текст], ...].
func _diary_lines() -> Array:
	var out := []
	if game.story.is_empty():
		return out
	if game.diary_read(game.INTRO_ID):
		out.append(["", game.story.intro])
	for e in game.story.entries:
		if game.diary_read(e.id):
			out.append(["%s, волна %d" % [game.siege_name(e.siege), e.wave], e.text])
	return out


func _open_diary() -> void:
	for c in diary_box.get_children():
		diary_box.remove_child(c)
		c.queue_free()
	var lines := _diary_lines()
	if lines.is_empty():
		_diary_text(DIARY_EMPTY, 28, Color.WHITE)
	for line in lines:
		if line[0] != "":
			_diary_text(line[0], 22, Color(1.0, 1.0, 1.0, 0.6))
		_diary_text(line[1], 28, STORY_COLOR)
	diary_panel.visible = true
	diary_close.grab_focus()


func _diary_text(text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	diary_box.add_child(l)


func _close_diary() -> void:
	diary_panel.visible = false
	start_button.grab_focus()


# Esc закрывает дневник.
func _unhandled_input(event: InputEvent) -> void:
	if diary_panel.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close_diary()
		get_viewport().set_input_as_handled()


# Итог последнего забега одной строкой; забегов не было — пусто.
func _last_text() -> String:
	match game.last_run.result:
		"win":
			return "Последний забег: победа на %d-й волне" % game.last_run.wave
		"loss":
			return "Последний забег: поражение на волне %d" % game.last_run.wave
	return ""


func _refresh() -> void:
	siege_label.text = game.siege_name(chosen)
	last_label.text = _last_text()
	for k in record_labels.size():
		var r: Dictionary = game.records[k + 1]
		record_labels[k].text = "%s: лучшая волна %d, побед %d, забегов %d" % [game.siege_name(k + 1), r.best_wave, r.wins, r.runs]


func _on_siege_selected(index: int) -> void:
	chosen = siege_option.get_item_id(index)
	_refresh()


func _on_start() -> void:
	game.start_run(chosen)


func _on_menu() -> void:
	game.go_menu()
