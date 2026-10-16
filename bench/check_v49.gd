extends SceneTree
# Тесты v49: автозагрузка Settings (user://settings.cfg), экран «Настройки» из главного меню и меню паузы, F11.
# Файл настроек — временный user://bench_v49/settings.cfg; настоящий user://settings.cfg не трогается.
const DIR := "user://bench_v49"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("CHECK v49: настройки, полный экран")
	var st: Node = root.get_node_or_null("Settings")
	check("автозагрузка Settings есть, под тестом файл игрока не пишется", st != null and not st.persist)
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "/settings.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	st.path = path
	st.persist = true
	st.load_settings()
	check("нет файла: окно (не полный экран)", not st.fullscreen)
	st.set_fullscreen(true)
	var cfg := ConfigFile.new()
	check("set_fullscreen(true) пишет display/fullscreen = true", cfg.load(path) == OK and cfg.get_value("display", "fullscreen", false) == true)
	st.fullscreen = false
	st.load_settings()
	check("после «перезапуска» (load_settings) снова полный экран", st.fullscreen)
	st._input(key(KEY_F11))
	cfg = ConfigFile.new()
	check("F11 выключает и сохраняет", not st.fullscreen and cfg.load(path) == OK and cfg.get_value("display", "fullscreen", true) == false)
	st._input(key(KEY_F11))
	check("F11 ещё раз включает", st.fullscreen)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[display\nfullscreen=")
	f.close()
	st.load_settings()
	check("битый файл: значения по умолчанию", not st.fullscreen)
	st.set_fullscreen(false)

	print("главное меню")
	var mn: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(mn)
	await step(2)
	var sm: CanvasLayer = mn.settings_menu
	check("кнопки «Играть», «Настройки», «Выход»; настройки скрыты", mn.settings_button != null and mn.settings_button.is_visible_in_tree() and not sm.visible)
	mn.settings_button.pressed.emit()
	await step(1)
	check("«Настройки» открывают экран, вкладка «Видео», фокус на «Назад»", sm.visible and sm.tabs.get_tab_title(0) == "Видео" and sm.back_button.has_focus())
	sm.fullscreen_check.button_pressed = true
	check("переключатель включает полный экран", st.fullscreen)
	st.set_fullscreen(false)
	check("переключатель следует за F11 и Settings", not sm.fullscreen_check.button_pressed)
	sm._input(key(KEY_ESCAPE))
	await step(1)
	check("Esc закрывает настройки, меню на месте, фокус на «Настройки»", not sm.visible and mn.is_inside_tree() and mn.settings_button.has_focus())
	mn.settings_button.pressed.emit()
	sm.back_button.pressed.emit()
	check("«Назад» закрывает", not sm.visible)
	mn.queue_free()
	await step(1)

	print("меню паузы")
	var host := Node.new()
	root.add_child(host)
	var em: CanvasLayer = load("res://scripts/esc_menu.gd").new()
	host.add_child(em)
	await step(1)
	em.open()
	check("пауза: кнопка «Настройки» между «Продолжить» и «Выйти в меню»", em.settings_button.get_index() == em.continue_button.get_index() + 1
		and em.menu_button.get_index() == em.settings_button.get_index() + 1)
	em.settings_button.pressed.emit()
	await step(1)
	check("из паузы открываются настройки, пауза остаётся", em.settings_menu.visible and em.visible and paused)
	# Esc идёт через окно: сначала экран настроек (дочерний, получает раньше), меню паузы остаётся открытым
	root.push_input(key(KEY_ESCAPE))
	await step(1)
	check("Esc закрывает только настройки: меню паузы открыто, дерево на паузе", not em.settings_menu.visible and em.visible and paused)
	root.push_input(key(KEY_ESCAPE))
	await step(1)
	check("Esc ещё раз закрывает меню паузы", not em.visible and not paused)
	host.queue_free()
	await step(1)
	DirAccess.remove_absolute(path)
	print("CHECK: провалов %d" % fails)
	quit()
