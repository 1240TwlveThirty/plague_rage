extends SceneTree
# Smoke v41 (каркас забега), с окном (без --headless), автозагрузка Game проекта: меню -> хаб -> забег -> поражение -> хаб
# синтетическими событиями через окно (клики по кнопкам, Enter, Space, R, Ctrl+R). «Выход» не нажимается.
# Консоль должна быть без ошибок и предупреждений, кроме известного «Нет звука сигнала» (файла audio/horn.ogg нет).
var fails := 0
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
	await step(4)

# Клик мышью по центру кнопки.
func click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	root.push_input(mv, true)
	await step(1)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		root.push_input(e, true)
		await step(1)
	await step(4)

# Сколько юнитов реально нарисовано: кадр с мультимешем юнитов и без него сравнивается в точках юнитов.
func drawn_units(m: Node2D) -> int:
	var mm: Node = null
	for c in m.get_children():
		if c is MultiMeshInstance2D and c.multimesh == m.multimesh:   # юниты; с задачи 12 есть и MultiMesh эффектов (частицы, пятна)
			mm = c
	await step(3)
	var with: Image = root.get_texture().get_image()
	mm.visible = false
	await step(3)
	var without: Image = root.get_texture().get_image()
	mm.visible = true
	await step(1)
	var xf := m.get_global_transform_with_canvas()
	var n := 0
	for i in m.count:
		var at := Vector2i(xf * m.pos[i])
		var differs := false
		for d in [Vector2i(0, 0), Vector2i(2, 2), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2)]:
			var q: Vector2i = at + d
			if q.x >= 0 and q.y >= 0 and q.x < with.get_width() and q.y < with.get_height() and with.get_pixelv(q) != without.get_pixelv(q):
				differs = true
		if differs:
			n += 1
	return n

func is_scene(scene_name: String) -> bool:
	return current_scene != null and current_scene.name == scene_name

# В сцене боя: Space начинает волну 1, ворота обнуляются, ждём поражения.
func lose() -> Node2D:
	var m := current_scene as Node2D
	await key(KEY_SPACE)
	var started: bool = m.wave_state == m.WS_BATTLE and m.wave_number == 1
	await step(10)
	m.gate_hp = 0.0
	var t := 0
	while m.wave_state != m.WS_DEFEAT and t < 300:
		await process_frame
		t += 1
	await step(3)
	check("  Space начал волну 1, ворота пали: wave_state 1, баннер с «Enter — в хаб», кнопка «В хаб» видна", started and m.wave_state == m.WS_DEFEAT
		and m.banner.visible and m.banner_parts[3].ends_with("Enter — в хаб") and m.hub_button.is_visible_in_tree())
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	g = root.get_node_or_null("Game")
	if g == null:
		print("  автозагрузка Game есть: НЕТ")
		print("SMOKE: провалов 1")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("user://bench_v41s")   # временное сохранение: настоящее не трогается
	g.save_path = "user://bench_v41s/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	check("главная сцена проекта — menu.tscn, автозагрузка Game есть", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/menu.tscn")
	g.go_menu()
	await step(40)   # окно только что открылось: первый клик сразу после старта иногда теряется
	check("меню: заголовок «Plague Wrath», «Играть» в фокусе, «Выход»", is_scene("Menu") and current_scene.play_button.has_focus() and tr(current_scene.quit_button.text) == "Выход")
	await click(current_scene.play_button)
	check("клик «Играть» -> хаб: итог пуст, выбор осады скрыт, «Начать забег» в фокусе", is_scene("Hub") and tr(current_scene.last_label.text) == ""
		and not current_scene.siege_option.visible and current_scene.start_button.has_focus())
	await click(current_scene.start_button)
	var m := current_scene as Node2D
	var hv: Dictionary = m.top_hud.get_values()
	check("клик «Начать забег» -> бой: передышка, волна 0, панель «Волна 0/10», осада 1", is_scene("Main") and m.wave_state == m.WS_RESPITE and m.wave_number == 0
		and hv.wave == 0 and hv.wave_max == 10 and g.siege == 1 and g.run_index == 1, str(hv))
	var drawn := await drawn_units(m)
	check("юниты нарисованы после смены сцены (не меньше 300 из 400 видны на кадре)", drawn >= 300, "видно %d" % drawn)
	await key(KEY_R)
	check("R в передышке сцену не перезапускает", current_scene == m and is_instance_valid(m))
	m = await lose()
	await key(KEY_P)
	check("пауза на экране поражения недоступна", not m.paused and not m.pause_label.visible)
	check("баннер: «Лучшая волна осады I: 1. Enter — в хаб»", m.banner_parts[3] == "Лучшая волна осады I: 1. Enter — в хаб", m.banner_parts[3])
	await key(KEY_ENTER)
	check("Enter -> хаб: «Последний забег: поражение на волне 1», забегов 1", is_scene("Hub") and tr(current_scene.last_label.text) == "Последний забег: поражение на волне 1"
		and tr(current_scene.record_labels[0].text) == "Осада I: лучшая волна 1, побед 0, забегов 1")
	await key(KEY_ENTER)
	check("Enter в хабе нажимает «Начать забег»: новый бой с волны 0", is_scene("Main") and current_scene != m and current_scene.wave_number == 0 and g.run_index == 2)
	m = await lose()
	await click(m.hub_button)
	check("клик «В хаб» -> хаб, забегов 2", is_scene("Hub") and g.records[1].runs == 2 and tr(current_scene.record_labels[0].text) == "Осада I: лучшая волна 1, побед 0, забегов 2")
	await click(current_scene.start_button)
	m = current_scene as Node2D
	await key(KEY_R, true)
	check("Ctrl+R (отладка) перезапускает бой: новая сцена, забег тот же", is_scene("Main") and current_scene != m and current_scene.wave_number == 0 and g.run_index == 3 and g.records[1].runs == 2)
	m = await lose()
	await key(KEY_R)
	check("R на экране поражения -> хаб, забегов 3", is_scene("Hub") and g.records[1].runs == 3)
	await click(current_scene.start_button)
	m = await lose()
	await key(KEY_SPACE)
	check("Space на экране поражения -> хаб, забегов 4, новый забег не начат", is_scene("Hub") and g.records[1].runs == 4 and g.run_index == 4)
	await click(current_scene.menu_button)
	check("клик «В меню» -> меню, «Выход» на месте и не нажат, Game цел (забегов 4)", is_scene("Menu") and current_scene.quit_button.is_visible_in_tree() and g.records[1].runs == 4)
	await key(KEY_ENTER)
	check("Enter в меню нажимает «Играть» -> хаб с итогом", is_scene("Hub") and tr(current_scene.last_label.text) == "Последний забег: поражение на волне 1")
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v41s")
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
