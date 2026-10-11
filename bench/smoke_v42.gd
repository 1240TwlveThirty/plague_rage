extends SceneTree
# Smoke v42 (каркас забега, часть 2), с окном (без --headless), автозагрузка Game проекта с временным сохранением
# (user://bench_v42s; настоящий user://save.json не трогается): меню -> хаб -> забег до поражения на волне 2 -> хаб,
# «Дневник» открывается и закрывается кнопкой и Esc. События синтетические, через окно.
# Консоль должна быть без ошибок и предупреждений, кроме известного «Нет звука сигнала» (файла audio/horn.ogg нет).
const DIR := "user://bench_v42s"
var fails := 0
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		root.push_input(e, true)
	await step(4)

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

func is_scene(scene_name: String) -> bool:
	return current_scene != null and current_scene.name == scene_name

func diary_texts(h: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in h.diary_box.get_children():
		out.append(c.text)
	return out

func real_stamp() -> String:
	return "%d/%d" % [FileAccess.get_modified_time("user://save.json"), FileAccess.get_file_as_bytes("user://save.json").size()] if FileAccess.file_exists("user://save.json") else "нет"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	g = root.get_node_or_null("Game")
	if g == null:
		print("  автозагрузка Game есть: НЕТ")
		print("SMOKE: провалов 1")
		quit(1)
		return
	var real := real_stamp()
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.go_menu()
	await step(40)   # окно только что открылось: первый клик сразу после старта иногда теряется
	await click(current_scene.play_button)
	var h := current_scene
	check("меню -> хаб: кнопка «Дневник» есть, предупреждения о сохранении нет, панель дневника скрыта", is_scene("Hub") and h.diary_button.text == "Дневник"
		and not h.diary_button.disabled and not h.warning_label.visible and not h.diary_panel.visible)
	await click(h.diary_button)
	check("клик «Дневник»: панель открыта, в ней «Записей пока нет.»", h.diary_panel.visible and diary_texts(h) == PackedStringArray(["Записей пока нет."]))
	await key(KEY_ENTER)
	check("Enter при открытом дневнике нажимает «Закрыть», забег не начинается", is_scene("Hub") and not h.diary_panel.visible and g.run_index == 0)
	await click(h.start_button)
	var m := current_scene as Node2D
	check("«Начать забег»: стартовый баннер со вступлением дневника", is_scene("Main") and m.banner.visible and m.banner_parts[0] == "Дневник военачальника"
		and m.banner_parts[2] == g.story.intro and m.banner_labels[2].is_visible_in_tree())
	# волна 1 проходится быстро: зомби снимаются по мере появления (только в смоуке)
	await key(KEY_SPACE)
	var t := 0
	Engine.time_scale = 8.0
	while m.wave_state == m.WS_BATTLE and t < 3000:
		for i in m.count:
			if m.team[i] == 1:
				m.hp[i] = 0.0
		await process_frame
		t += 1
	Engine.time_scale = 1.0
	await step(8)
	var entry := ""
	for e in g.story.entries:
		if e.id == "s1w1":
			entry = e.text
	check("волна 1 пройдена: в баннере итога запись дневника s1w1, она сохранена", m.wave_state == m.WS_RESPITE and m.wave_number == 1 and entry != "" and m.banner_parts[2] == entry
		and m.banner_labels[2].is_visible_in_tree() and g.diary_seen == ["intro", "s1w1"], "кадров %d" % t)
	await key(KEY_SPACE)
	await step(10)
	m.gate_hp = 0.0
	t = 0
	while m.wave_state != m.WS_DEFEAT and t < 300:
		await process_frame
		t += 1
	await step(3)
	check("поражение на волне 2: концовка «День 2. ...», «Лучшая волна осады I: 2. Enter — в хаб»", m.wave_state == m.WS_DEFEAT and m.wave_number == 2 and "День 2." in m.banner_parts[2]
		and m.banner_parts[3] == "Лучшая волна осады I: 2. Enter — в хаб", m.banner_parts[3])
	await key(KEY_ENTER)
	h = current_scene
	check("Enter -> хаб: «Последний забег: поражение на волне 2», рекорд из сохранения", is_scene("Hub") and h.last_label.text == "Последний забег: поражение на волне 2"
		and h.record_labels[0].text == "Осада I: лучшая волна 2, побед 0, забегов 1")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(g.save_path))
	check("сохранение на диске: забегов 1, лучшая волна 2, дневник intro и s1w1; временного файла нет", saved is Dictionary and saved.runs_total == 1.0 and saved.records["1"].best_wave == 2.0
		and saved.diary_seen == ["intro", "s1w1"] and DirAccess.get_files_at(DIR).size() == 1)
	await click(h.diary_button)
	check("«Дневник»: вступление и запись «Осада I, волна 1», больше ничего", h.diary_panel.visible and h.diary_panel.is_visible_in_tree()
		and diary_texts(h) == PackedStringArray([g.story.intro, "Осада I, волна 1", entry]), str(diary_texts(h).size()))
	await key(KEY_ESCAPE)
	check("Esc закрывает дневник, хаб на месте", is_scene("Hub") and not h.diary_panel.visible and h.start_button.has_focus())
	await click(h.diary_button)
	var opened: bool = h.diary_panel.visible
	await click(h.diary_close)
	check("дневник открывается снова и закрывается кликом по «Закрыть»", opened and not h.diary_panel.visible)
	await click(h.start_button)
	m = current_scene as Node2D
	check("второй забег: стартовый баннер без дневника — только подсказка", is_scene("Main") and m.banner.visible and m.banner_parts[0] == "" and m.banner_parts[2] == ""
		and m.banner_parts[3] == "Расставь отряды. Space — начать волну 1" and not m.banner_labels[2].is_visible_in_tree())
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)
	check("настоящий user://save.json не тронут", real_stamp() == real, real)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
