extends SceneTree
# Тесты v50: клавиши — действия InputMap, переназначение (обмен, отказ, сброс), сохранение в settings.cfg (секция input),
# подписи с актуальной клавишей (Settings.key_label), вкладка «Управление». Файл настроек временный (user://bench_v50).
const DIR := "user://bench_v50"
const ST := preload("res://scripts/settings.gd")
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func ev(code: Key, shift := false, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	return e

func mb(button: MouseButton, pressed := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	return e

func used_squads(m: Node2D) -> int:
	var n := 0
	for s in m.SQUAD_MAX:
		n += m.squad_used[s]
	return n

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	print("CHECK v50: клавиши, переназначение")
	var st: Node = root.get_node("Settings")
	DirAccess.make_dir_recursive_absolute(DIR)
	st.path = DIR + "/settings.cfg"
	if FileAccess.file_exists(st.path):
		DirAccess.remove_absolute(st.path)
	st.persist = true
	st.load_settings()
	var defaults := {"squad_select_1": "1", "squad_select_8": "8", "squad_new": "N", "squad_split": "G", "squad_merge": "M",
		"split_side": "K", "wave_start": "Space", "buy_1": "Z", "buy_2": "X", "buy_3": "C", "buy_4": "V", "order_attack": "Q",
		"pause": "P", "select_all": "Ctrl+A", "to_hub": "Enter", "post_left": "Left"}
	var bad := []
	for a in defaults:
		if ST.key_label(a) != defaults[a]:
			bad.append("%s=%s" % [a, ST.key_label(a)])
	check("клавиши по умолчанию прежние (InputMap из project.godot)", bad.is_empty(), ", ".join(bad))
	check("переназначаемых действий 27 (с buy_spear, war_cry, движением героя move_*, ударом hero_attack, сворачиванием магазина и панели отрядов, задача 24, и сбросом зума, задача 27), у всех есть клавиша", ST.REBINDABLE.size() == 27 and ST.REBINDABLE.all(func(r): return ST.action_key(r) != KEY_NONE))

	print("игра по действиям")
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = 1
	root.add_child(m)
	m.set_physics_process(false)
	await step(2)
	m._unhandled_input(ev(KEY_1))
	var n0 := used_squads(m)
	m._unhandled_input(ev(KEY_N))
	check("N (по умолчанию) создаёт отряд", used_squads(m) == n0 + 1, "%d -> %d" % [n0, used_squads(m)])
	m._unhandled_input(ev(KEY_1))
	m._unhandled_input(ev(KEY_2, true))
	check("1 и Shift+2: выбор и добавление", m.sel_mask == 3)
	m._unhandled_input(ev(KEY_A, false, true))
	var all_sel: int = m.sel_mask
	m._unhandled_input(ev(KEY_1))
	m._unhandled_input(ev(KEY_A))
	check("Ctrl+A выбирает все, A без Ctrl — ничего", all_sel != 1 and m.sel_mask == 1, "%d %d" % [all_sel, m.sel_mask])

	print("переназначение")
	var r: Dictionary = st.rebind("squad_new", KEY_O)
	check("N -> O: назначено без сообщения", r.ok and r.msg == "" and ST.key_label("squad_new") == "O")
	await step(1)
	m._update_squad_panel()
	check("кнопка «+ Отряд (O)» показывает новую клавишу", tr(m.action_buttons[0].text) == "+ Отряд (O)", m.action_buttons[0].text)
	n0 = used_squads(m)
	m._unhandled_input(ev(KEY_N))
	check("N больше не создаёт отряд", used_squads(m) == n0)
	m._unhandled_input(ev(KEY_1))
	m._unhandled_input(ev(KEY_O))
	check("O создаёт отряд", used_squads(m) == n0 + 1)
	r = st.rebind("squad_new", KEY_G)
	check("O -> G (занята «Разделить»): обмен, сообщение", r.ok and r.msg != "" and ST.key_label("squad_new") == "G" and ST.key_label("squad_split") == "O", r.msg)
	r = st.rebind("buy_1", KEY_Q)
	check("Q (постоянный приказ «атака»): отказ, клавиша прежняя", not r.ok and r.msg != "" and ST.key_label("buy_1") == "Z", r.msg)
	r = st.rebind("buy_1", KEY_ESCAPE)
	var r2: Dictionary = st.rebind("buy_1", KEY_F5)
	check("Esc и F5: отказ", not r.ok and not r2.ok and ST.key_label("buy_1") == "Z")
	r = st.rebind("buy_1", KEY_B)
	m.wave_state = m.WS_RESPITE
	m._update_ui()
	check("магазин: подпись первой кнопки начинается с «B»", m.shop_buttons[0].text.begins_with("B  "), m.shop_buttons[0].text.get_slice("\n", 0))
	st.rebind("wave_start", KEY_ENTER)
	check("Enter занят переходом в хаб: отказ", ST.key_label("wave_start") == "Space")
	st.rebind("wave_start", KEY_L)
	m.wave_state = m.WS_BATTLE
	m.paused = false
	m._unhandled_input(ev(KEY_1))
	m._cmd_split()
	check("подсказка «Поставь паузу (L)» с новой клавишей", "(L)" in m.hud_msg, m.hud_msg)
	m.wave_state = m.WS_RESPITE
	var cfg := ConfigFile.new()
	check("файл: секция input с новыми клавишами", cfg.load(st.path) == OK and cfg.get_value("input", "squad_new", "") == "G"
		and cfg.get_value("input", "squad_split", "") == "O" and cfg.get_value("input", "buy_1", "") == "B" and cfg.get_value("input", "wave_start", "") == "L")
	InputMap.load_from_project_settings()
	st.load_settings()
	check("«перезапуск»: клавиши из файла", ST.key_label("squad_new") == "G" and ST.key_label("squad_split") == "O" and ST.key_label("buy_1") == "B" and ST.key_label("wave_start") == "L")
	print("кнопки мыши")
	r = st.rebind_event("squad_new", mb(MOUSE_BUTTON_XBUTTON1))
	check("«Новый отряд» -> Мышь 4", r.ok and ST.key_label("squad_new") == "Мышь 4", ST.key_label("squad_new"))
	m._unhandled_input(ev(KEY_1))
	n0 = used_squads(m)
	m._unhandled_input(mb(MOUSE_BUTTON_XBUTTON1, true))
	check("Мышь 4 создаёт отряд", used_squads(m) == n0 + 1, "%d -> %d" % [n0, used_squads(m)])
	m._unhandled_input(ev(KEY_1))
	m._unhandled_input(mb(MOUSE_BUTTON_XBUTTON2, true))
	check("Мышь 5 без привязки: ничего", used_squads(m) == n0 + 1)
	r = st.rebind_event("squad_split", mb(MOUSE_BUTTON_XBUTTON1))
	check("Мышь 4 у «Разделить»: обмен с «Новый отряд» (получает O)", r.ok and r.msg != "" and ST.key_label("squad_split") == "Мышь 4" and ST.key_label("squad_new") == "O", r.msg)
	r = st.rebind_event("buy_1", mb(MOUSE_BUTTON_LEFT))
	r2 = st.rebind_event("buy_1", mb(MOUSE_BUTTON_RIGHT))
	check("ЛКМ и ПКМ: отказ", not r.ok and not r2.ok and ST.key_label("buy_1") == "B")
	st.rebind_event("buy_1", mb(MOUSE_BUTTON_MIDDLE))
	cfg = ConfigFile.new()
	check("файл: кнопки мыши как Mouse8 / Mouse3", cfg.load(st.path) == OK and cfg.get_value("input", "squad_split", "") == "Mouse8" and cfg.get_value("input", "buy_1", "") == "Mouse3")
	InputMap.load_from_project_settings()
	st.load_settings()
	TranslationServer.set_locale("en")
	check("«перезапуск»: мышь из файла, подпись по-английски", ST.key_label("squad_split") == "Mouse 4" and ST.key_label("buy_1") == "Middle mouse button", ST.key_label("buy_1"))
	TranslationServer.set_locale("ru")
	st.reset_keys()
	cfg = ConfigFile.new()
	cfg.load(st.path)
	check("сброс: клавиши по умолчанию и в файле", ST.key_label("squad_new") == "N" and ST.key_label("squad_split") == "G" and ST.key_label("buy_1") == "Z"
		and ST.key_label("wave_start") == "Space" and cfg.get_value("input", "squad_new", "") == "N")
	m.queue_free()
	await step(1)

	print("вкладка «Управление»")
	var sm: CanvasLayer = load("res://scripts/settings_menu.gd").new()
	root.add_child(sm)
	await step(1)
	sm.open()
	var titles := []
	for t in sm.tabs.get_tab_count():
		titles.append(tr(sm.tabs.get_tab_title(t)))
	check("вкладки «Видео», «Звук», «Управление», «Игра» (задача 26), «Язык»; строк — переназначаемые без скрытых данными (buy_spear: копейщики выключены, задача 9; задача 27 — +сброс зума), кнопка «Сбросить»", titles == ["Видео", "Звук", "Управление", "Игра", "Язык"]
		and sm.key_buttons.size() == ST.REBINDABLE.filter(func(r): return not r in ST.hidden_actions()).size() and sm.key_buttons.has("camera_zoom_reset") and not sm.key_buttons.has("buy_spear") and sm.reset_keys_button != null, str(titles))
	sm.key_buttons["buy_2"].pressed.emit()
	check("клик по строке: ждёт клавишу", sm.waiting_action == "buy_2" and sm.key_buttons["buy_2"].text.begins_with("Нажмите"))
	root.push_input(ev(KEY_ESCAPE))
	await step(1)
	check("Esc отменяет ожидание, экран не закрывается, клавиша прежняя", sm.visible and sm.waiting_action == "" and tr(sm.key_buttons["buy_2"].text) == "X")
	sm.key_buttons["buy_2"].pressed.emit()
	root.push_input(ev(KEY_C))
	await step(1)
	check("C (занята «Купить: оружие»): обмен и сообщение", ST.key_label("buy_2") == "C" and ST.key_label("buy_3") == "X" and tr(sm.key_buttons["buy_3"].text) == "X" and sm.key_msg.text != "", sm.key_msg.text)
	sm.key_buttons["buy_2"].pressed.emit()
	root.push_input(mb(MOUSE_BUTTON_LEFT, true))
	await step(1)
	check("ЛКМ во время ожидания не назначается", sm.waiting_action == "buy_2" and ST.key_label("buy_2") == "C")
	root.push_input(mb(MOUSE_BUTTON_XBUTTON2, true))
	await step(1)
	check("Мышь 5 назначена из «Управления»", sm.waiting_action == "" and ST.key_label("buy_2") == "Мышь 5" and sm.key_buttons["buy_2"].text == "Мышь 5", sm.key_buttons["buy_2"].text)
	sm.reset_keys_button.pressed.emit()
	check("«Сбросить по умолчанию»", ST.key_label("buy_2") == "X" and tr(sm.key_buttons["buy_2"].text) == "X")
	sm.queue_free()
	await step(1)
	st.persist = false
	DirAccess.remove_absolute(st.path)
	print("CHECK: провалов %d" % fails)
	quit()
