extends SceneTree
# Тесты задачи 24 (без окна): интерфейс. Все размеры, клавиши и длительности — из data/ui_layout.json и data/ui_theme.json.
#   Кнопки действий отряда: размер action_button_size, тексты ru и en с клавишами по умолчанию входят целиком (без многоточия
#   и без уменьшения кегля); переназначенная длинная клавиша — многоточие, целиком в подсказке, кнопка не растёт.
#   Строка FPS: флаг debug_fps выключен по умолчанию — строки нет; в релизной сборке нет и с флагом; с флагом — внизу слева,
#   не пересекает окошки верхней панели и панель отрядов.
# Временное сохранение user://bench_v74 (user://save.json не трогается).
const FONTS := preload("res://scripts/fonts.gd")
const DIR := "user://bench_v74"
var fails := 0
var lay: Dictionary
var theme_cfg: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	lay = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	theme_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_theme.json"))
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	node_added.connect(_on_node_added)
	for l in ["ru", "en"]:
		TranslationServer.set_locale(l)
		g.start_run(1)
		await step(3)
		var m := current_scene as Node2D
		await t_actions(m, l)
		if l == "ru":
			await t_fps(m, g)
		m.queue_free()
		await step(2)
	TranslationServer.set_locale("ru")
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Ширина строки text кнопки b при её кегле и место под текст (размер минус поля рамки).
func text_w(b: Button, text: String) -> float:
	return b.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x

func room_w(b: Button) -> float:
	return b.size.x - b.get_theme_stylebox("normal").get_minimum_size().x

func t_actions(m: Node2D, l: String) -> void:
	print("кнопки действий отряда, %s" % l)
	var want := Vector2(lay.action_button_size[0], lay.action_button_size[1])
	m._update_squad_panel()
	await step(2)
	var base := FONTS.px(FONTS.DEFAULT_SIZE)
	for b: Button in m.action_buttons:
		var w := text_w(b, b.text)
		print("ACTION|%s|%s|%.0f из %.0f px|кегль %d" % [l, b.text, w, room_w(b), b.get_theme_font_size("font_size")])
		check("%s: «%s» — размер %s, текст %.0f <= %.0f px целиком, кегль темы %d" % [l, b.text, str(want), w, room_w(b), base],
			b.size == want and w <= room_w(b) + 0.5 and b.get_theme_font_size("font_size") == base)
	# переназначенная длинная клавиша: кнопка того же размера, многоточие, целиком в подсказке
	var saved: Array = InputMap.action_get_events("squad_split")
	InputMap.action_erase_events("squad_split")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("squad_split", e)
	m._update_squad_panel()
	await step(2)
	var b: Button = m.action_buttons[1]
	check("%s: длинная клавиша «%s» — кнопка %s, многоточие, целиком в подсказке" % [l, b.text, str(b.size)], b.size == want
		and b.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and b.autowrap_mode == TextServer.AUTOWRAP_OFF and b.tooltip_text == b.text)
	InputMap.action_erase_events("squad_split")
	for ev in saved:
		InputMap.action_add_event("squad_split", ev)
	m._update_squad_panel()

func t_fps(m: Node2D, g: Node) -> void:
	print("строка FPS")
	var script: GDScript = load("res://scripts/main.gd")
	check("debug_fps в ui_layout.json выключен (%s), строки FPS нет" % str(lay.get("debug_fps")), lay.get("debug_fps") == false and m.fps_label == null
		and not m.debug_fps_on())
	check("релизная сборка: строки нет и с флагом, и с --debug-fps", not script.fps_wanted(false, true, PackedStringArray(["--debug-fps"])))
	check("отладочная сборка: флаг или --debug-fps включают строку", script.fps_wanted(true, true, PackedStringArray())
		and script.fps_wanted(true, false, PackedStringArray(["--debug-fps"])) and not script.fps_wanted(true, false, PackedStringArray()))
	# с флагом: новая сцена, строка внизу слева вне окошек и панели отрядов
	var m2: Node2D = load("res://scenes/main.tscn").instantiate()
	m2.debug_fps_force = true
	m2.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m2)
	await step(2)
	var ok: bool = m2.fps_label != null
	if ok:
		m2.fps_label.text = tr("DEBUG_FPS_LINE") % [999, 700, 1.0, 2.0, 0.5, 1, 1000.0, 99, 99]
		await step(2)
		var r: Rect2 = m2.fps_label.get_global_rect()
		var vp := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
		var clear: bool = not r.intersects(m2.top_hud.get_global_rect()) and not r.intersects(m2.squad_panel.get_global_rect())
		check("с флагом: строка %s внизу слева, на экране, не на окошках %s и не на панели отрядов %s" % [str(r), str(m2.top_hud.get_global_rect()),
			str(m2.squad_panel.get_global_rect())], clear and r.position.x < vp.x * 0.5 and r.end.y <= vp.y and r.position.y > vp.y * 0.5)
	else:
		check("с флагом строка FPS создана", false)
	m2.queue_free()
	await step(1)
