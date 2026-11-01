extends Control
# Хаб-заглушка между забегами, две вкладки. «Осада»: осада, итог последнего забега, рекорды, «Начать забег», «Дневник» и «В меню».
# «Дары»: магазин даров за Сияние (правила покупки — в Game). Интерфейс строится кодом. Выбор осады виден, только когда открыто больше одной.
# Тексты — ключи перевода: постоянные метки и кнопки переводятся сами, собранные строки пересобираются при смене языка.
const FONTS := preload("res://scripts/fonts.gd")   # кегли и контуры текста под вариант шрифта (задача 20)
const UI := preload("res://scripts/ui.gd")
const ESC_MENU := preload("res://scripts/esc_menu.gd")
const WARN_COLOR := Color(1.0, 0.75, 0.35)
const DIARY_SIZE := Vector2(0.5, 0.7)        # панель дневника: доля экрана
const DIARY_EMPTY := "HUB_DIARY_EMPTY"
const RADIANCE_COLOR := Color(0.6, 0.9, 1.0)
const RADIANCE_ICON := "res://art/shine.png"
const ICONS := preload("res://scripts/icons.gd")
const TOP_HUD := preload("res://scripts/top_hud.gd")   # окошко «Сияние» справа сверху — тот же компонент, что у панели боя (задача 19)
const HUD_SLOT := preload("res://scripts/hud_slot.gd")
const GIFT_ICON_AT := Vector2(8, 5)   # иконка 16 x 16 в окне рамки 32 x 48 (масштаб 1, как у рамки в строке)
const GIFT_ICON := "res://art/card_meta_perk.png"   # общая заглушка; своя иконка дара — art/gift_<id>.png, если есть
const GIFT_ICON_SIZE := Vector2(32.0, 48.0)   # иконка дара в рамке карточки (масштаб 1)
const GIFT_MAX := "—"
const LAYOUT := "res://data/ui_layout.json"
# Вкладка «Дары» (задача 28в), data/ui_layout.json — значения по умолчанию, если ключа нет: кегль строк, высота строки (не меньше;
# по факту — две строки текста), промежуток между строками, поля строки [слева/справа, сверху/снизу], между колонками, ширины колонок,
# размер «Купить», промежуток между Сиянием, шапкой и списком, поля до краёв экрана сверху и снизу.
const GIFTS_DEFAULT := {"hub_row_font": 30, "hub_row_height": 56, "hub_row_gap": 8, "hub_row_pad": [12, 6], "hub_col_gap": 16,
	"hub_columns": {"icon": 32, "name": 260, "level": 110, "next": 620, "price": 100, "buy": 160, "reason": 300},
	"hub_buy_size": [160, 48], "hub_section_gap": 12, "hub_screen_margin": 24}

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
var gcfg := {}                  # раскладка вкладки «Дары» (_gifts_cfg)
var hub_box: VBoxContainer      # весь хаб: заголовок, предупреждение, вкладки (высота прокрутки — по нему)
var gift_head: HBoxContainer    # шапка таблицы даров: над прокруткой, не прокручивается
var gift_scroll: ScrollContainer   # прокрутка со строками даров
var gift_list: VBoxContainer    # строки даров (рамка ui_slot на строку)
var gift_row_h := 0.0          # высота строки дара (gift_row_height при сборке вкладки)
var gift_rows := {}            # id дара -> {frame, icon, name, level, effect, price, button, reason}: строка магазина


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
	hub_box = box
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
	var f := get_node_or_null("/root/Focus")
	if f != null:
		f.hide_focus()   # задача 26: подсветка фокуса — только после клавиши


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


# Вкладка «Дары» на универсальной панели (задача 28в): баланс Сияния, шапка таблицы (закреплена) и прокрутка со строками даров —
# иконка, название, уровень, эффект следующего уровня, цена, «Купить», причина отказа. Кегль, высота строки, промежутки и ширины
# колонок — data/ui_layout.json hub_gifts; длинный эффект и причина переносятся на вторую строку внутри ячейки.
func _setup_gifts() -> void:
	gcfg = _gifts_cfg()
	gifts_panel = PanelContainer.new()   # подложка — тёмная панель вкладок (задача 24); своей рамки нет, чтобы не было двух рамок
	gifts_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	tabs.add_child(gifts_panel)
	tabs.set_tab_title(1, "HUB_TAB_GIFTS")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(gcfg.hub_section_gap))
	gifts_panel.add_child(col)
	var bal := HBoxContainer.new()
	bal.alignment = BoxContainer.ALIGNMENT_CENTER
	bal.add_theme_constant_override("separation", 12)
	col.add_child(bal)
	bal.add_child(_icon(RADIANCE_ICON, Vector2(40.0, 40.0)))
	radiance_label = _label(bal, "", 40)
	UI.frame_label(radiance_label)
	radiance_label.add_theme_color_override("font_color", RADIANCE_COLOR)
	# шапка: те же колонки и поля, что у строки, без рамки; над прокруткой — не прокручивается
	gift_head = _gift_row_box()
	var head_pad := MarginContainer.new()
	_row_margins(head_pad, true)
	head_pad.add_child(gift_head)
	col.add_child(head_pad)
	var cols: Dictionary = gcfg.hub_columns
	gift_head.add_child(_spacer(cols.icon))
	for k in [["HUB_GIFTS_HEAD_GIFT", "name"], ["HUB_GIFTS_HEAD_LEVEL", "level"], ["HUB_GIFTS_HEAD_NEXT", "next"], ["HUB_GIFTS_HEAD_PRICE", "price"]]:
		var l := _cell(gift_head, k[1], k[0], Color(1.0, 1.0, 1.0, 0.6))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gift_head.add_child(_spacer(cols.buy))
	gift_head.add_child(_spacer(cols.reason))
	gift_scroll = ScrollContainer.new()
	gift_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # переносы внутри ячеек, вбок не прокручивается
	gift_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO         # полоса — когда список длиннее области
	gift_scroll.follow_focus = true    # стрелки по кнопкам «Купить» — список едет за фокусом
	gift_scroll.focus_mode = Control.FOCUS_ALL   # клик по списку — фокус на нём: PageUp/PageDown и стрелки листают
	gift_scroll.gui_input.connect(_on_gift_scroll_input)
	UI.style_scrollbar(gift_scroll.get_v_scroll_bar())
	col.add_child(gift_scroll)
	gift_list = VBoxContainer.new()
	gift_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gift_list.add_theme_constant_override("separation", int(gcfg.hub_row_gap))
	gift_scroll.add_child(gift_list)
	var ink := UI.slot_text_color()   # текст на светлой рамке слота — тёмный (контраст — check_v74_ui)
	gift_row_h = gift_row_height()
	var row_h := gift_row_h
	for id in game.gift_defs:
		if game.gift_defs[id].hidden:
			continue   # скрытый дар (hidden в gifts.json) в магазине не показывается
		var frame := UI.slot_frame()   # рамка ui_slot строки (задача 24), как есть
		frame.custom_minimum_size.y = row_h
		gift_list.add_child(frame)
		var pad := MarginContainer.new()
		_row_margins(pad)
		frame.add_child(pad)
		var box := _gift_row_box()
		pad.add_child(box)
		var own := "res://art/gift_%s.png" % id
		var cell_icon := _icon(own if ResourceLoader.exists(own) else GIFT_ICON, GIFT_ICON_SIZE)
		cell_icon.custom_minimum_size.x = maxf(GIFT_ICON_SIZE.x, float(cols.icon))
		if not ResourceLoader.exists(own):   # своей картинки дара нет: рамка карточки дара и иконка из общего набора в её окне
			var ic := ICONS.make(ICONS.of_gift(id), 1)
			ic.position = GIFT_ICON_AT
			cell_icon.add_child(ic)
		box.add_child(cell_icon)
		var name_l := _cell(box, "name", game.gift_defs[id].name_key, ink)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var row := {"frame": frame, "icon": cell_icon, "name": name_l, "level": _cell(box, "level", "", ink), "effect": _cell(box, "next", "", ink),
			"price": _cell(box, "price", "", ink)}
		row.effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # длинный эффект — на вторую строку
		var b := Button.new()
		b.text = "HUB_GIFT_BUY"
		b.add_theme_font_size_override("font_size", FONTS.px(int(gcfg.hub_row_font)))
		UI.frame_button(b, false)   # строка таблицы: размер — hub_buy_size
		b.custom_minimum_size = Vector2(gcfg.hub_buy_size[0], gcfg.hub_buy_size[1])
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_buy.bind(id))
		b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, float(cols.buy))   # колонка «Купить» — по кнопке
		box.add_child(b)
		row["button"] = b
		row["reason"] = _cell(box, "reason", "", ink)
		row.reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # «Откроется после осады II» целиком, с переносом
		row.reason.mouse_filter = Control.MOUSE_FILTER_PASS   # полный текст — и во всплывающей подсказке
		gift_rows[id] = row
	if game.gift_defs.is_empty():
		UI.frame_label(_label(col, "HUB_GIFTS_LOAD_FAILED", 28))   # gifts.json с ошибкой: она уже выведена
	_refresh_gifts()
	_fit_gift_list.call_deferred()


# Ключи hub_* из data/ui_layout.json поверх значений по умолчанию.
func _gifts_cfg() -> Dictionary:
	var out := GIFTS_DEFAULT.duplicate(true)
	var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT)) if FileAccess.file_exists(LAYOUT) else null
	if d is Dictionary:
		for k in out:
			if d.has(k):
				out[k] = d[k]
	return out


# Высота строки дара: не меньше hub_row_height и вмещает две строки текста кегля hub_row_font (эффект с переносом), иконку
# и кнопку «Купить» — с полями hub_row_pad сверху и снизу.
func gift_row_height() -> float:
	var probe := Label.new()   # две строки текста — как их выложит метка ячейки (шрифт, контур, межстрочный интервал темы)
	probe.text = "A
A"
	probe.add_theme_font_size_override("font_size", FONTS.px(int(gcfg.hub_row_font)))
	UI.frame_label(probe)
	add_child(probe)
	var two := probe.get_minimum_size().y
	probe.free()
	var inner := maxf(two, maxf(GIFT_ICON_SIZE.y, float(gcfg.hub_buy_size[1])))
	return maxf(float(gcfg.hub_row_height), inner + float(gcfg.hub_row_pad[1]) * 2.0 + UI.slot_margins().y)


func _gift_row_box() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", int(gcfg.hub_col_gap))
	return box


# Поля строки hub_row_pad; head — шапка без рамки: плюс поля рамки слота слева и справа, чтобы колонки шапки шли над колонками строк.
func _row_margins(m: MarginContainer, head := false) -> void:
	var side := int(gcfg.hub_row_pad[0]) + (int(UI.slot_margins().x * 0.5) if head else 0)
	m.add_theme_constant_override("margin_left", side)
	m.add_theme_constant_override("margin_right", side)
	m.add_theme_constant_override("margin_top", int(gcfg.hub_row_pad[1]))
	m.add_theme_constant_override("margin_bottom", int(gcfg.hub_row_pad[1]))


func _spacer(width) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = float(width)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# Ячейка колонки col (ширина — hub_columns), текст по центру по вертикали.
func _cell(box: HBoxContainer, col: String, text := "", color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = float(gcfg.hub_columns[col])
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	l.add_theme_font_size_override("font_size", FONTS.px(int(gcfg.hub_row_font)))
	l.add_theme_color_override("font_color", color)
	UI.frame_label(l)
	box.add_child(l)
	return l


# Высота прокрутки: хаб (с пустой прокруткой) и список строк по высоте экрана с полями hub_screen_margin сверху и снизу.
# Список короче — прокрутка по нему, полосы нет.
func _fit_gift_list() -> void:
	if gift_scroll == null:
		return
	gift_scroll.custom_minimum_size.y = 0.0
	var room := get_viewport_rect().size.y - float(gcfg.hub_screen_margin) * 2.0 - hub_box.get_combined_minimum_size().y
	gift_scroll.custom_minimum_size.y = clampf(gift_list.get_combined_minimum_size().y, 0.0, maxf(room, 0.0))


# Список в фокусе: PageUp/PageDown — на высоту области, стрелки — на строку (колесо и полоса — сами ScrollContainer).
func _on_gift_scroll_input(event: InputEvent) -> void:
	if _scroll_key(event, true):
		gift_scroll.accept_event()


# Листание списка клавишей: PageUp/PageDown — всегда (фокус в списке или на нём); стрелки — только когда фокус на самой прокрутке
# (на кнопке «Купить» стрелки переводят фокус, список едет за ним).
func _scroll_key(event: InputEvent, arrows: bool) -> bool:
	if not (event is InputEventKey and event.pressed):
		return false
	var page := gift_scroll.size.y
	var step := gift_row_h + float(gcfg.hub_row_gap)
	var d := 0.0
	match event.keycode:
		KEY_PAGEUP:
			d = -page
		KEY_PAGEDOWN:
			d = page
		KEY_UP:
			d = -step if arrows else 0.0
		KEY_DOWN:
			d = step if arrows else 0.0
	if d == 0.0:
		return false
	gift_scroll.scroll_vertical = int(gift_scroll.scroll_vertical + d)
	return true


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


func _on_buy(id: String) -> void:
	if game.buy_gift(id):
		_refresh_gifts()


func _on_tab_changed(tab: int) -> void:
	if tab == 0:
		start_button.grab_focus()   # Enter снова начинает забег
	else:
		_refresh_gifts()
		_fit_gift_list()


# Панель дневника поверх хаба (универсальная панель): заголовок, прокрутка со строками, «Закрыть». Скрыта, пока не открыта кнопкой.
func _setup_diary() -> void:
	diary_panel = PanelContainer.new()
	diary_panel.anchor_left = 0.5 - DIARY_SIZE.x * 0.5
	diary_panel.anchor_right = 0.5 + DIARY_SIZE.x * 0.5
	diary_panel.anchor_top = 0.5 - DIARY_SIZE.y * 0.5
	diary_panel.anchor_bottom = 0.5 + DIARY_SIZE.y * 0.5
	UI.frame_panel(diary_panel)
	# задача 28в: текст дневника тёмный (diary_text_color); панель светлая — как есть, иначе (контраст ниже contrast_min) — заливка
	# diary_panel_color с теми же полями
	if UI.contrast(UI.diary_text_color(), UI.panel_center_color()) < float(UI.theme_cfg().get("contrast_min", 4.5)):
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(str(UI.theme_cfg().get("diary_panel_color", "#e8d5a8")))
		var m := UI.panel_margins() * 0.5
		fill.content_margin_left = m.x
		fill.content_margin_right = m.x
		fill.content_margin_top = m.y
		fill.content_margin_bottom = m.y
		diary_panel.add_theme_stylebox_override("panel", fill)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	diary_panel.add_child(col)
	_diary_ink(_label(col, "UI_DIARY_TITLE", 40))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.style_scrollbar(scroll.get_v_scroll_bar())   # полоса — как у списка даров (ui_theme.json scrollbar)
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
		_diary_text(DIARY_EMPTY, 28)
	for line in lines:
		if line[0] != "":
			_diary_text(line[0], 22)   # заголовок записи — мельче
		_diary_text(line[1], 28)
	diary_panel.visible = true
	diary_close.grab_focus()


func _diary_text(text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", FONTS.px(size))
	_diary_ink(l)
	diary_box.add_child(l)


# Текст дневника: тёмный diary_text_color на светлой панели, без контура (тёмный контур тёмного текста только утолщает буквы).
func _diary_ink(l: Label) -> void:
	l.add_theme_color_override("font_color", UI.diary_text_color())
	l.add_theme_constant_override("outline_size", 0)


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
	elif tabs.current_tab == 1 and _focus_in_gifts() and _scroll_key(event, false):   # PageUp/PageDown с фокусом на «Купить»
		get_viewport().set_input_as_handled()


func _focus_in_gifts() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and gift_scroll != null and (f == gift_scroll or gift_scroll.is_ancestor_of(f))


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
