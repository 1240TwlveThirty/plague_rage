extends CanvasLayer
# Экран выбора карточки забега: в начале передышки после волн pick_after_waves (data/cards_rules.json) сцена боя показывает тройку.
# У карточки — клавиша, название, цветная метка основного билда, описание одной строкой (издержка — часть после «;» — красным).
# Выбор мышью или клавишами 1, 2, 3 (действия card_pick_1..3 InputMap; нет в проекте — добавляются при первом открытии); пропуска нет.
# Внизу — уже выбранные карточки. Пока экран открыт, клавиши игры (кроме Esc и F11) до боя не доходят.
signal picked(id: String)

const DIM := Color(0.0, 0.0, 0.0, 0.85)
const CARD_SIZE := Vector2(560, 230)
const CARD_BG := Color(0.1, 0.09, 0.08)
const CARD_BG_HOVER := Color(0.17, 0.15, 0.12)
const COST_COLOR := Color(1.0, 0.35, 0.3)
const BUILD_KEYS := {"shield": "UI_BUILD_SHIELD", "archers": "UI_BUILD_ARCHERS", "gold": "UI_BUILD_GOLD", "risk": "UI_BUILD_RISK", "common": "UI_BUILD_COMMON"}
const BUILD_COLORS := {"shield": Color(0.35, 0.55, 1.0), "archers": Color(0.35, 0.85, 0.45), "gold": Color(1.0, 0.8, 0.2), "risk": Color(0.9, 0.35, 0.9),
	"common": Color(0.75, 0.75, 0.75)}
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
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)
	row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	box.add_child(row)
	var hint := Label.new()
	hint.text = "UI_CARDS_HINT"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 24)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	owned_label = Label.new()
	owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owned_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	owned_label.custom_minimum_size = Vector2(1400, 0)
	owned_label.add_theme_font_size_override("font_size", 22)
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


func _card(k: int, d: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:   # непрозрачная карточка с рамкой цвета билда
		var box := StyleBoxFlat.new()
		box.bg_color = CARD_BG_HOVER if st != "normal" else CARD_BG
		box.set_corner_radius_all(8)
		box.set_border_width_all(3)
		box.border_color = BUILD_COLORS[d.builds[0]]
		b.add_theme_stylebox_override(st, box)
	b.pressed.connect(_pick.bind(k))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	_text(col, "[%s]" % key_text(k), 22, Color(1, 1, 1, 0.6)).name = "Key"
	_text(col, d.name_key, 32, Color.WHITE).name = "Name"
	var build: String = d.builds[0]
	var tag := _text(col, BUILD_KEYS[build], 22, BUILD_COLORS[build])
	tag.name = "Build"
	var desc := RichTextLabel.new()
	desc.name = "Desc"
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.add_theme_font_size_override("normal_font_size", 22)
	desc.text = desc_bbcode(tr(d.desc_key))
	col.add_child(desc)
	return b


# Описание: часть после «;» (издержка) — красным.
static func desc_bbcode(text: String) -> String:
	var at := text.find(";")
	if at < 0:
		return text
	return "%s;[color=#%s]%s[/color]" % [text.left(at), COST_COLOR.to_html(false), text.substr(at + 1)]


# Подпись клавиши выбора k-й карточки: «1», «2», «3» (или что назначено действию card_pick_N).
static func key_text(k: int) -> String:
	ensure_actions()
	return SETTINGS.key_label("card_pick_%d" % (k + 1))


func _text(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
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
