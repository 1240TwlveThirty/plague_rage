extends Control
# Хаб-заглушка между забегами, две вкладки. «Осада»: осада, итог последнего забега, рекорды, «Начать забег», «Дневник» и «В меню».
# «Дары»: магазин даров за Сияние (правила покупки — в Game). Интерфейс строится кодом. Выбор осады виден, только когда открыто больше одной.
# Тексты — ключи перевода: постоянные метки и кнопки переводятся сами, собранные строки пересобираются при смене языка.
const UI := preload("res://scripts/ui.gd")
const ESC_MENU := preload("res://scripts/esc_menu.gd")
const WARN_COLOR := Color(1.0, 0.75, 0.35)
const STORY_COLOR := Color(1.0, 0.88, 0.6)   # как у дневника в баннере боя
const DIARY_SIZE := Vector2(0.5, 0.7)        # панель дневника: доля экрана
const DIARY_EMPTY := "HUB_DIARY_EMPTY"
const RADIANCE_COLOR := Color(0.6, 0.9, 1.0)
const RADIANCE_ICON := "res://art/shine.png"
const GIFT_ICON := "res://art/card_meta_perk.png"   # общая заглушка; своя иконка дара — art/gift_<id>.png, если есть
const GIFT_ICON_SIZE := Vector2(40.0, 60.0)
const GIFT_FONT := 26
const GIFT_MAX := "—"

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
var esc_menu: CanvasLayer      # меню паузы по Esc: «Продолжить», «Выйти в меню», «Выход из игры»
var tabs: TabContainer         # «Осада» и «Дары»
var radiance_label: Label      # баланс Сияния на вкладке «Дары»
var gift_rows := {}            # id дара -> {level, effect, price, button, reason}: подписи и кнопка строки магазина


func _ready() -> void:
	game = get_node("/root/Game")
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
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	_label(box, "HUB_TITLE", 64)
	warning_label = _label(box, game.save_warning, 26)
	warning_label.add_theme_color_override("font_color", WARN_COLOR)
	warning_label.visible = game.save_warning != ""
	tabs = TabContainer.new()
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.add_theme_font_size_override("font_size", 30)
	box.add_child(tabs)
	var top := box
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	tabs.add_child(box)
	tabs.set_tab_title(0, "HUB_TAB_SIEGE")
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
	start_button = _button(box, "HUB_START_RUN")
	start_button.pressed.connect(_on_start)
	diary_button = _button(box, "HUB_DIARY")
	diary_button.pressed.connect(_open_diary)
	diary_button.disabled = game.story.is_empty()   # story.json не загрузился: ошибка уже выведена
	menu_button = _button(box, "HUB_TO_MENU")
	menu_button.pressed.connect(_on_menu)
	_setup_gifts()
	tabs.tab_changed.connect(_on_tab_changed)
	top.move_child(tabs, top.get_child_count() - 1)
	_setup_diary()
	esc_menu = ESC_MENU.new()
	add_child(esc_menu)
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
	UI.gold_button(b)
	box.add_child(b)
	return b


# Вкладка «Дары»: баланс Сияния и таблица — иконка, название, уровень, эффект следующего уровня, цена, «Купить», причина отказа.
func _setup_gifts() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	tabs.add_child(col)
	tabs.set_tab_title(1, "HUB_TAB_GIFTS")
	var bal := HBoxContainer.new()
	bal.alignment = BoxContainer.ALIGNMENT_CENTER
	bal.add_theme_constant_override("separation", 12)
	col.add_child(bal)
	bal.add_child(_icon(RADIANCE_ICON, Vector2(40.0, 40.0)))
	radiance_label = _label(bal, "", 40)
	radiance_label.add_theme_color_override("font_color", RADIANCE_COLOR)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for head in ["", "HUB_GIFTS_HEAD_GIFT", "HUB_GIFTS_HEAD_LEVEL", "HUB_GIFTS_HEAD_NEXT", "HUB_GIFTS_HEAD_PRICE", "", ""]:
		_cell(grid, head, Color(1.0, 1.0, 1.0, 0.6))
	for id in game.gift_defs:
		var own := "res://art/gift_%s.png" % id
		grid.add_child(_icon(own if ResourceLoader.exists(own) else GIFT_ICON, GIFT_ICON_SIZE))
		_cell(grid, game.gift_defs[id].name_key)
		var row := {"level": _cell(grid), "effect": _cell(grid), "price": _cell(grid, "", RADIANCE_COLOR)}
		var b := Button.new()
		b.text = "HUB_GIFT_BUY"
		b.add_theme_font_size_override("font_size", GIFT_FONT)
		UI.gold_button(b)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_buy.bind(id))
		grid.add_child(b)
		row["button"] = b
		row["reason"] = _cell(grid, "", WARN_COLOR)
		gift_rows[id] = row
	if game.gift_defs.is_empty():
		_label(col, "HUB_GIFTS_LOAD_FAILED", 28)   # gifts.json с ошибкой: она уже выведена
	_refresh_gifts()


func _icon(path: String, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # пиксельный арт
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = size
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


func _cell(grid: GridContainer, text := "", color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", GIFT_FONT)
	l.add_theme_color_override("font_color", color)
	grid.add_child(l)
	return l


# Эффект уровня дара одной строкой по desc_key дара: «+8% к урону всех воинов», «+40 воинов в каждом стартовом отряде».
static func effect_text(def: Dictionary, level: int) -> String:
	var v: float = def.levels[level - 1]
	var num := str(int(v)) if v == floorf(v) else String.num(v)   # 8, а не 8.0
	return String(TranslationServer.translate(def.desc_key)) % num


# Баланс и строки магазина по состоянию Game: уровень, эффект и цена следующего уровня, кнопка и причина, если купить нельзя.
func _refresh_gifts() -> void:
	radiance_label.text = tr("HUB_RADIANCE") % game.radiance
	for id in gift_rows:
		var row: Dictionary = gift_rows[id]
		var def: Dictionary = game.gift_defs[id]
		var lvl: int = game.gift_levels.get(id, 0)
		var top: bool = lvl >= def.levels.size()
		var price: int = game.gift_price(id, lvl + 1)
		var block: String = game.buy_block(id)
		row.level.text = "%d / %d" % [lvl, def.levels.size()]
		row.effect.text = GIFT_MAX if top else effect_text(def, lvl + 1)
		row.price.text = GIFT_MAX if top or price < 0 else str(price)
		row.button.disabled = block != ""
		row.reason.text = block


func _on_buy(id: String) -> void:
	if game.buy_gift(id):
		_refresh_gifts()


func _on_tab_changed(tab: int) -> void:
	if tab == 0:
		start_button.grab_focus()   # Enter снова начинает забег
	else:
		_refresh_gifts()


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
	_label(col, "UI_DIARY_TITLE", 40)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	diary_box = VBoxContainer.new()
	diary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diary_box.add_theme_constant_override("separation", 20)
	scroll.add_child(diary_box)
	diary_close = _button(col, "HUB_DIARY_CLOSE")
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
		out.append(["", tr(game.story.intro)])
	for e in game.story.entries:
		if game.diary_read(e.id):
			out.append([tr("HUB_DIARY_ENTRY_HEAD") % [game.siege_name(e.siege), e.wave], tr(e.text)])
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


# Esc закрывает дневник; дневник закрыт — открывает меню паузы.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if diary_panel.visible:
			_close_diary()
		else:
			esc_menu.open()
		get_viewport().set_input_as_handled()


# Итог последнего забега одной строкой; забегов не было — пусто.
func _last_text() -> String:
	match game.last_run.result:
		"win":
			return tr("HUB_LAST_WIN") % game.last_run.wave
		"loss":
			return tr("HUB_LAST_LOSS") % game.last_run.wave
	return ""


func _refresh() -> void:
	siege_label.text = game.siege_name(chosen)
	last_label.text = _last_text()
	for k in record_labels.size():
		var r: Dictionary = game.records[k + 1]
		record_labels[k].text = tr("HUB_RECORD") % [game.siege_name(k + 1), r.best_wave, r.wins, r.runs]
	for i in siege_option.item_count:
		siege_option.set_item_text(i, game.siege_name(siege_option.get_item_id(i)))


# Смена языка: собранные строки (осада, итог, рекорды, магазин, открытый дневник) пересобрать.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
		_refresh_gifts()
		if diary_panel.visible:
			_open_diary()


func _on_siege_selected(index: int) -> void:
	chosen = siege_option.get_item_id(index)
	_refresh()


func _on_start() -> void:
	game.start_run(chosen)


func _on_menu() -> void:
	game.go_menu()
