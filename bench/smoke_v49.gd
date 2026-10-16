extends SceneTree
# Смоук v49 с окном: F11 включает и выключает полный экран (настоящий режим окна), скриншоты меню и экрана настроек.
# Аргумент: папка для PNG (по умолчанию user://). Файл настроек — временный, настоящий user://settings.cfg не трогается.
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func f11() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_F11
	e.pressed = true
	root.push_input(e)
	await step(10)

func shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join(name))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	print("SMOKE v49: F11, экран настроек")
	var st: Node = root.get_node("Settings")
	DirAccess.make_dir_recursive_absolute("user://bench_v49")
	st.path = "user://bench_v49/smoke_settings.cfg"
	st.persist = true
	var mn: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(mn)
	current_scene = mn
	await step(5)
	check("старт: окно", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED)
	await shot(dir, "v49_menu.png")
	await f11()
	check("F11: полный экран", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN and st.fullscreen, str(DisplayServer.window_get_mode()))
	mn.settings_button.pressed.emit()
	await step(5)
	await shot(dir, "v49_settings_fullscreen.png")
	await f11()
	check("F11 ещё раз: окно", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and not st.fullscreen, str(DisplayServer.window_get_mode()))
	await step(5)
	await shot(dir, "v49_settings_window.png")
	var cfg := ConfigFile.new()
	check("значение сохранено (false)", cfg.load(st.path) == OK and cfg.get_value("display", "fullscreen", true) == false)
	DirAccess.remove_absolute(st.path)
	print("SMOKE: провалов %d" % fails)
	quit()
