extends CanvasLayer
# Экран выбора карточки забега: в начале передышки после волн pick_after_waves (data/cards_rules.json) сцена боя показывает тройку.
# У карточки — клавиша, название, цветная метка основного билда, описание одной строкой (издержка — часть после «;» — красным).
# Выбор мышью или клавишами 1, 2, 3 (действия card_pick_1..3 InputMap; нет в проекте — добавляются при первом открытии); пропуска нет.
# Внизу — уже выбранные карточки. Пока экран открыт, клавиши игры (кроме Esc и F11) до боя не доходят.
signal picked(id: String)

const DIM := Color(0.0, 0.0, 0.0, 0.85)
const FONTS := preload("res://scripts/fonts.gd")   # кегли и контуры текста под вариант шрифта (задача 20)
const ICONS := preload("res://scripts/icons.gd")
const CARDS := preload("res://scripts/cards.gd")   # fill_desc: {hero_near_radius} в описании
const FRAME_TIMER := "res://art/card_perk_timer.png"   # рамка временной карточки
const FRAME_META := "res://art/card_meta_perk.png"     # запасная рамка (дар), окрашивается в цвет билда
const SHINE := "res://art/shine.png"
const FRAME_PX := Vector2(32, 48)    # размер рамки в пикселях арта
const SCALE := 10                    # целый масштаб рамки и иконки: 320 x 480 на экране
const ICON_AT := Vector2(8, 5)       # иконка 16 x 16 в окне рамки (окно — x 3..28, y 2..45; ленточки по краям сверху)
const TEXT_RECT := Rect2(7, 22, 21, 23)   # окно под текст в пикселях рамки: правее ленточки-закладки (она слева, x 2..6, до y 30)
const LIFT := 12.0                   # насколько карточка приподнимается при наведении, px
const SHINE_SCALE := 5
const INK := Color(0.22, 0.13, 0.07)      # текст на светлой карточке
const COST_ON_CARD := Color(0.72, 0.1, 0.08)   # издержка на карточке
const COST_COLOR := Color(1.0, 0.35, 0.3)
const BUILD_KEYS := {"shield": "UI_BUILD_SHIELD", "archers": "UI_BUILD_ARCHERS", "gold": "UI_BUILD_GOLD", "risk": "UI_BUILD_RISK", "common": "UI_BUILD_COMMON",
	"hero": "UI_BUILD_HERO"}
const BUILD_COLORS := {"shield": Color(0.35, 0.55, 1.0), "archers": Color(0.35, 0.85, 0.45), "gold": Color(1.0, 0.8, 0.2), "risk": Color(0.9, 0.35, 0.9),
	"common": Color(0.75, 0.75, 0.75), "hero": Color(0.95, 0.45, 0.2)}
const KEYS := [KEY_1, KEY_2, KEY_3]
const SETTINGS := preload("res://scripts/settings.gd")

var row: HBoxContainer
var owned_label: Label
var buttons: Array[Button] = []
var offer: Array = []
var shown_defs := {}   # для пересборки при смене языка
var shown_owned: Array = []


func _ready() -> void:
	layer = 90
	visible = false
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # клики по полю под экраном не проходят
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	center.add_child(box)
	var title := Label.new()
	title.text = "UI_CARDS_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONTS.px(56))
	box.add_child(title)
	row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	box.add_child(row)
	var hint := Label.new()
	hint.text = "UI_CARDS_HINT"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", FONTS.px(24))
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	owned_label = Label.new()
	owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owned_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	owned_label.custom_minimum_size = Vector2(1400, 0)
	owned_label.add_theme_font_size_override("font_size", FONTS.px(22))
	box.add_child(owned_label)


static func ensure_actions() -> void:
	for k in KEYS.size():
		var a := "card_pick_%d" % (k + 1)
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var e := InputEventKey.new()
			e.keycode = KEYS[k]
			InputMap.action_add_event(a, e)


# Показать тройку ids (карточки defs); owned — названия уже выбранных (ключи перевода).
func open(ids: Array, defs: Dictionary, owned: Array) -> void:
	ensure_actions()
	offer = ids.duplicate()
	shown_defs = defs
	shown_owned = owned.duplicate()
	for c in row.get_children():
		c.queue_free()
	buttons.clear()
	for k in ids.size():
		var d: Dictionary = defs[ids[k]]
		var b := _card(k, d)
		row.add_child(b)
		buttons.append(b)
	owned_label.text = tr("UI_CARDS_OWNED") % (", ".join(owned.map(func(key): return tr(key))) if not owned.is_empty() else tr("UI_CARDS_NONE"))
	visible = true


# Карточка: рамка временной карточки (art/card_perk_timer.png) в масштабе SCALE (32 x 48 -> 320 x 480), иконка карточки в окне рамки
# (16 x 16 в точке ICON_AT рамки — над ленточкой-закладкой), под ней клавиша, название, метка билда и описание (издержка красным) —
# в пределах окна рамки. Нет текстуры рамки — рамка card_meta_perk.png, окрашенная в цвет билда. При наведении «лицо» карточки
# приподнимается на LIFT и в углу появляется блик art/shine.png. Без шейдеров.
func _card(k: int, d: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(FRAME_PX.x * SCALE, FRAME_PX.y * SCALE + LIFT)
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.pressed.connect(_pick.bind(k))
	var face := Control.new()   # всё, что приподнимается при наведении
	face.name = "Face"
	face.position = Vector2(0, LIFT)
	face.size = FRAME_PX * SCALE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	var frame := TextureRect.new()
	frame.name = "Frame"
	var timer_frame := ResourceLoader.exists(FRAME_TIMER)
	frame.texture = load(FRAME_TIMER if timer_frame else FRAME_META)
	if not timer_frame:
		frame.modulate = BUILD_COLORS[d.builds[0]].lerp(Color.WHITE, 0.35)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = FRAME_PX * SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(frame)
	var icon := ICONS.make(ICONS.of_card(d.id), SCALE)
	icon.name = "Icon"
	icon.position = ICON_AT * SCALE
	face.add_child(icon)
	var key := _text(face, "[%s]" % key_text(k), 20, INK.lerp(Color.TRANSPARENT, 0.35))
	key.name = "Key"
	key.autowrap_mode = TextServer.AUTOWRAP_OFF
	key.position = Vector2(24 * SCALE, 3 * SCALE)   # правый верхний угол окна (ленточка слева)
	var col := VBoxContainer.new()
	col.position = TEXT_RECT.position * SCALE + Vector2(6, 0)
	col.size = TEXT_RECT.size * SCALE - Vector2(12, 0)
	col.custom_minimum_size.x = col.size.x
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(col)
	var nm := _text(col, d.name_key, 24, INK)
	nm.name = "Name"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var build: String = d.builds[0]
	var tag := _text(col, BUILD_KEYS[build], 18, BUILD_COLORS[build].darkened(0.45))
	tag.name = "Build"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var desc := RichTextLabel.new()
	desc.name = "Desc"
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.add_theme_font_size_override("normal_font_size", FONTS.px(18))
	desc.add_theme_color_override("default_color", INK)
	desc.custom_minimum_size.x = col.size.x
	desc.text = desc_bbcode(CARDS.fill_desc(tr(d.desc_key)), COST_ON_CARD)
	col.add_child(desc)
	var shine := TextureRect.new()
	shine.name = "Shine"
	if ResourceLoader.exists(SHINE):
		shine.texture = load(SHINE)
	shine.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shine.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shine.stretch_mode = TextureRect.STRETCH_SCALE
	shine.size = Vector2(16, 16) * SHINE_SCALE
	shine.position = Vector2(FRAME_PX.x * SCALE - shine.size.x * 0.6, -shine.size.y * 0.4)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.visible = false
	face.add_child(shine)
	b.mouse_entered.connect(_hover.bind(face, shine, true))
	b.mouse_exited.connect(_hover.bind(face, shine, false))
	return b


func _hover(face: Control, shine: Control, on: bool) -> void:
	face.position.y = 0.0 if on else LIFT
	shine.visible = on


# Описание: часть после «;» (издержка) — красным.
static func desc_bbcode(text: String, cost := COST_COLOR) -> String:
	var at := text.find(";")
	if at < 0:
		return text
	return "%s;[color=#%s]%s[/color]" % [text.left(at), cost.to_html(false), text.substr(at + 1)]


# Подпись клавиши выбора k-й карточки: «1», «2», «3» (или что назначено действию card_pick_N).
static func key_text(k: int) -> String:
	ensure_actions()
	return SETTINGS.key_label("card_pick_%d" % (k + 1))


func _text(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", FONTS.px(size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# Смена языка при открытом экране: описания и список выбранных собраны через tr() — собрать заново.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and visible and not offer.is_empty():
		open(offer, shown_defs, shown_owned)


func _pick(k: int) -> void:
	if not visible or k >= offer.size():
		return
	visible = false
	picked.emit(offer[k])


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_F11:
		return   # меню паузы и полный экран работают и здесь
	for k in offer.size():
		if event.is_action_pressed("card_pick_%d" % (k + 1)):
			_pick(k)
			break
	get_viewport().set_input_as_handled()
