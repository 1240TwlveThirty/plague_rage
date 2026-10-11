extends Control
# Хаб-заглушка между забегами: осада, итог последнего забега, рекорды, «Начать забег» и «В меню».
# Интерфейс строится кодом. Выбор осады виден, только когда открыто больше одной.
const BG_COLOR := Color(0.08, 0.08, 0.1)

var game: Node
var chosen := 1                # осада, с которой начнётся забег
var siege_label: Label
var last_label: Label
var record_labels: Array[Label] = []
var siege_option: OptionButton
var start_button: Button
var menu_button: Button


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
	siege_label = _label(box, "", 40)
	last_label = _label(box, "", 30)
	for s in range(1, game.siege_count + 1):
		record_labels.append(_label(box, "", 26))
	# по умолчанию — последняя сыгранная осада, иначе первая
	var open: int = maxi(game.unlocked_siege, 1)
	chosen = clampi(game.siege, 1, open) if game.run_index > 0 else 1
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
	menu_button = _button(box, "В меню")
	menu_button.pressed.connect(_on_menu)
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
