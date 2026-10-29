extends Control
# Хаб-заглушка между забегами, две вкладки. «Осада»: осада, итог последнего забега, рекорды, «Начать забег», «Дневник» и «В меню».
# «Дары»: магазин даров за Сияние (правила покупки — в Game). Интерфейс строится кодом. Выбор осады виден, только когда открыто больше одной.
# Тексты — ключи перевода: постоянные метки и кнопки переводятся сами, собранные строки пересобираются при смене языка.
const FONTS := preload("res://scripts/fonts.gd")   # кегли и контуры текста под вариант шрифта (задача 20)
const UI := preload("res://scripts/ui.gd")
const ESC_MENU := preload("res://scripts/esc_menu.gd")
const WARN_COLOR := Color(1.0, 0.75, 0.35)
const STORY_COLOR := Color(1.0, 0.88, 0.6)   # как у дневника в баннере боя
const DIARY_SIZE := Vector2(0.5, 0.7)        # панель дневника: доля экрана
const DIARY_EMPTY := "HUB_DIARY_EMPTY"
const RADIANCE_COLOR := Color(0.6, 0.9, 1.0)
const RADIANCE_ICON := "res://art/shine.png"
const ICONS := preload("res://scripts/icons.gd")
const TOP_HUD := preload("res://scripts/top_hud.gd")   # окошко «Сияние» справа сверху — тот же компонент, что у панели боя (задача 19)
const HUD_SLOT := preload("res://scripts/hud_slot.gd")
const GIFT_ICON_AT := Vector2(8, 5)   # иконка 16 x 16 в окне рамки 32 x 48 (масштаб 1, как у рамки в строке)
const GIFT_ICON := "res://art/card_meta_perk.png"   # общая заглушка; своя иконка дара — art/gift_<id>.png, если есть
const GIFT_ICON_SIZE := Vector2(32.0, 48.0)   # 12 строк даров помещаются на экран 1080
const GIFT_FONT := 24   # задача 22: 26 в fusion10 давало 30 — таблица даров не помещалась по высоте
const GIFT_MAX := "—"
const ROW_FRAME_PAD := 8.0   # рамка строки дара шире таблицы на столько с каждой стороны (задача 24)
const REASON_MARGIN := 16.0   # вкладка «Дары» с причинами отказа — не ближе к краю экрана

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
var gifts_panel: PanelContainer   # вкладка «Дары»: универсальная панель
var radiance_label: Label      # баланс Сияния на вкладке «Дары»
var radiance_slot: HUD_SLOT        # окошко «Сияние» в правом верхнем углу (на обеих вкладках)
var gift_grid: GridContainer    # таблица даров
var row_frames_box: Control     # рамки ui_slot за строками таблицы (_place_row_frames)
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
	tabs.add_theme_font_size_override("font_size", FONTS.px(30))
	UI.frame_panel_dark(tabs)   # задача 24: тёмный экран — подложка вкладок на тёмной панели (обе вкладки)
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
	siege_option.add_theme_font_size_override("font_size", FONTS.px(30))
	for s in range(1, open + 1):
		siege_option.add_item(game.siege_name(s), s)
	siege_option.select(siege_option.get_item_index(chosen))
	siege_option.visible = game.unlocked_siege >= 2
	siege_option.item_selected.connect(_on_siege_selected)
	box.add_child(siege_option)
	start_button = _button(box, "HUB_START_RUN")
	start_button.pressed.connect(_on_start)
	start_button.set_meta("sfx", "click_play")   # начало забега звучит как «Играть» (Audio)
	diary_button = _button(box, "HUB_DIARY")
	diary_button.pressed.connect(_open_diary)
	diary_button.disabled = game.story.is_empty()   # story.json не загрузился: ошибка уже выведена
	menu_button = _button(box, "HUB_TO_MENU")
	menu_button.pressed.connect(_on_menu)
	_setup_gifts()
	tabs.tab_changed.connect(_on_tab_changed)
	top.move_child(tabs, top.get_child_count() - 1)
	radiance_slot = TOP_HUD.corner_slot()
	add_child(radiance_slot)
	radiance_slot.set_value(game.radiance)
	_setup_diary()
	esc_menu = ESC_MENU.new()
	add_child(esc_menu)
	_refresh()
	start_button.grab_focus()   # Enter начинает забег


func _label(box: Container, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", FONTS.px(size))
	box.add_child(l)
	return l


func _button(box: Container, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FONTS.px(36))
	UI.frame_button(b)
	box.add_child(b)
	return b


# Вкладка «Дары» на универсальной панели: баланс Сияния и таблица — иконка, название, уровень, эффект следующего уровня, цена,
# «Купить», причина отказа.
func _setup_gifts() -> void:
	gifts_panel = PanelContainer.new()   # подложка — тёмная панель вкладок (задача 24); своей рамки нет, чтобы не было двух рамок
	gifts_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	tabs.add_child(gifts_panel)
	tabs.set_tab_title(1, "HUB_TAB_GIFTS")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	gifts_panel.add_child(col)
	var bal := HBoxContainer.new()
	bal.alignment = BoxContainer.ALIGNMENT_CENTER
	bal.add_theme_constant_override("separation", 12)
	col.add_child(bal)
	bal.add_child(_icon(RADIANCE_ICON, Vector2(40.0, 40.0)))
	radiance_label = _label(bal, "", 40)
	UI.frame_label(radiance_label)
	radiance_label.add_theme_color_override("font_color", RADIANCE_COLOR)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 2)   # 15 строк даров на экран 1080
	# строки даров на рамке ui_slot (задача 24): рамки — за таблицей, по строкам, после каждой раскладки таблицы
	var stack := MarginContainer.new()
	col.add_child(stack)
	row_frames_box = Control.new()
	row_frames_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(row_frames_box)
	stack.add_child(grid)
	gift_grid = grid
	grid.sort_children.connect(_place_row_frames)
	for head in ["", "HUB_GIFTS_HEAD_GIFT", "HUB_GIFTS_HEAD_LEVEL", "HUB_GIFTS_HEAD_NEXT", "HUB_GIFTS_HEAD_PRICE", "", ""]:
		_cell(grid, head, Color(1.0, 1.0, 1.0, 0.6))
	for id in game.gift_defs:
		if game.gift_defs[id].hidden:
			continue   # скрытый дар (hidden в gifts.json) в магазине не показывается
		var own := "res://art/gift_%s.png" % id
		var cell_icon := _icon(own if ResourceLoader.exists(own) else GIFT_ICON, GIFT_ICON_SIZE)
		if not ResourceLoader.exists(own):   # своей картинки дара нет: рамка карточки дара и иконка из общего набора в её окне
			var ic := ICONS.make(ICONS.of_gift(id), 1)
			ic.position = GIFT_ICON_AT
			cell_icon.add_child(ic)
		grid.add_child(cell_icon)
		var ink := UI.slot_text_color()   # текст на светлой рамке слота — тёмный (контраст — check_v74_ui)
		_cell(grid, game.gift_defs[id].name_key, ink)
		var row := {"level": _cell(grid, "", ink), "effect": _cell(grid, "", ink), "price": _cell(grid, "", ink)}
		var b := Button.new()
		b.text = "HUB_GIFT_BUY"
		b.add_theme_font_size_override("font_size", FONTS.px(GIFT_FONT))
		UI.frame_button(b, false)   # строка таблицы: высота по тексту, как у строки дара
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_buy.bind(id))
		grid.add_child(b)
		row["button"] = b
		row["reason"] = _cell(grid, "", ink)
		row.reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # ширину задаёт _fit_reasons: таблица не шире экрана
		row.reason.mouse_filter = Control.MOUSE_FILTER_PASS   # полный текст — во всплывающей подсказке
		gift_rows[id] = row
	if game.gift_defs.is_empty():
		UI.frame_label(_label(col, "HUB_GIFTS_LOAD_FAILED", 28))   # gifts.json с ошибкой: она уже выведена
	_refresh_gifts()


# Рамка ui_slot за каждой строкой даров (кроме заголовка): по высоте строки, на всю ширину таблицы и ROW_FRAME_PAD за край.
func _place_row_frames() -> void:
	var cols := gift_grid.columns
	var n := gift_grid.get_child_count() / cols
	while row_frames_box.get_child_count() < n - 1:
		row_frames_box.add_child(UI.slot_frame())
	for r in range(1, n):
		var top := INF
		var bottom := -INF
		for k in cols:
			var c := gift_grid.get_child(r * cols + k) as Control
			top = minf(top, c.position.y)
			bottom = maxf(bottom, c.position.y + c.size.y)
		var f := row_frames_box.get_child(r - 1) as Control
		f.position = Vector2(-ROW_FRAME_PAD, top)
		f.size = Vector2(gift_grid.size.x + ROW_FRAME_PAD * 2.0, bottom - top)


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
	l.add_theme_font_size_override("font_size", FONTS.px(GIFT_FONT))
	l.add_theme_color_override("font_color", color)
	UI.frame_label(l)
	grid.add_child(l)
	return l


# Эффект уровня дара одной строкой по desc_key дара: «+6% к урону пехоты», «+5% воинов в каждом стартовом отряде (не меньше +1)».
static func effect_text(def: Dictionary, level: int) -> String:
	if def.get("type", "mods") == "ability":   # способность: бонус, длительность и перезарядка уровня
		var lv: Dictionary = def.levels[level - 1]
		return String(TranslationServer.translate(def.desc_key)) % [_num(lv.bonus_pct), _num(lv.duration_s), _num(lv.cooldown_s)]
	var v: float = def.levels[level - 1]
	if def.get("stat", "") == "block":   # шанс блока хранится долей (0.05), в тексте — процентные пункты (5)
		v *= 100.0
	return String(TranslationServer.translate(def.desc_key)) % _num(snappedf(v, 0.01))


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else String.num(v)   # 8, а не 8.0


# Баланс и строки магазина по состоянию Game: уровень, эффект и цена следующего уровня, кнопка и причина, если купить нельзя.
func _refresh_gifts() -> void:
	radiance_label.text = tr("HUB_RADIANCE") % game.radiance
	if radiance_slot != null:
		radiance_slot.set_value(game.radiance)
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
		row.reason.tooltip_text = block
	_fit_reasons()


# Столбец причины («Откроется после осады II», «Не хватает Сияния») — по самой длинной причине, но не больше, чем осталось
# до краёв экрана (по REASON_MARGIN с каждой стороны); длиннее — с многоточием: вкладка «Дары» не выходит за экран
# при любом шрифте и языке.
func _fit_reasons() -> void:
	for id in gift_rows:
		gift_rows[id].reason.custom_minimum_size.x = 0.0
	var room := get_viewport_rect().size.x - REASON_MARGIN * 2.0 - tabs.get_combined_minimum_size().x
	var need := 0.0   # самая длинная причина целиком
	for id in gift_rows:
		var l: Label = gift_rows[id].reason
		if l.text != "":
			need = maxf(need, l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
				+ l.get_theme_constant("outline_size"))
	for id in gift_rows:
		gift_rows[id].reason.custom_minimum_size.x = clampf(need, 0.0, maxf(room, 0.0))


func _on_buy(id: String) -> void:
	if game.buy_gift(id):
		_refresh_gifts()


func _on_tab_changed(tab: int) -> void:
	if tab == 0:
		start_button.grab_focus()   # Enter снова начинает забег
	else:
		_refresh_gifts()


# Панель дневника поверх хаба (универсальная панель): заголовок, прокрутка со строками, «Закрыть». Скрыта, пока не открыта кнопкой.
func _setup_diary() -> void:
	diary_panel = PanelContainer.new()
	diary_panel.anchor_left = 0.5 - DIARY_SIZE.x * 0.5
	diary_panel.anchor_right = 0.5 + DIARY_SIZE.x * 0.5
	diary_panel.anchor_top = 0.5 - DIARY_SIZE.y * 0.5
	diary_panel.anchor_bottom = 0.5 + DIARY_SIZE.y * 0.5
	UI.frame_panel(diary_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	diary_panel.add_child(col)
	UI.frame_label(_label(col, "UI_DIARY_TITLE", 40))
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
	l.add_theme_font_size_override("font_size", FONTS.px(size))
	l.add_theme_color_override("font_color", color)
	UI.frame_label(l)
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
		radiance_slot.refresh()
		if diary_panel.visible:
			_open_diary()


func _on_siege_selected(index: int) -> void:
	chosen = siege_option.get_item_id(index)
	_refresh()


func _on_start() -> void:
	game.start_run(chosen)


func _on_menu() -> void:
	game.go_menu()
