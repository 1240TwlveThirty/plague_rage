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

	print("громкость")
	st.set_music_volume(0.3)
	st.set_sfx_volume(0.0)
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	check("музыка 0.3: шина Music %.1f dB, не выключена" % AudioServer.get_bus_volume_db(mi), is_equal_approx(AudioServer.get_bus_volume_db(mi), linear_to_db(0.3))
		and not AudioServer.is_bus_mute(mi))
	check("эффекты 0: шина SFX выключена", AudioServer.is_bus_mute(si))
	cfg = ConfigFile.new()
	check("audio/music и audio/sfx в файле", cfg.load(path) == OK and is_equal_approx(cfg.get_value("audio", "music", -1.0), 0.3) and cfg.get_value("audio", "sfx", -1.0) == 0.0)
	st.music_volume = 1.0
	st.sfx_volume = 1.0
	st.load_settings()
	check("«перезапуск»: громкость из файла", is_equal_approx(st.music_volume, 0.3) and st.sfx_volume == 0.0 and AudioServer.is_bus_mute(si))
	st.set_music_volume(st.VOLUME_DEFAULT)
	st.set_sfx_volume(st.VOLUME_DEFAULT)
	check("по умолчанию 0.8: SFX снова включена", not AudioServer.is_bus_mute(si) and is_equal_approx(AudioServer.get_bus_volume_db(si), linear_to_db(0.8)))

	print("главное меню")
	var mn: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(mn)
	await step(2)
	var sm: CanvasLayer = mn.settings_menu
	check("кнопки «Играть», «Настройки», «Выход»; настройки скрыты", mn.settings_button != null and mn.settings_button.is_visible_in_tree() and not sm.visible)
	mn.settings_button.pressed.emit()
	await step(1)
	check("«Настройки» открывают экран, вкладка «Видео», фокус на «Назад»", sm.visible and tr(sm.tabs.get_tab_title(0)) == "Видео" and sm.back_button.has_focus())
	sm.tabs.current_tab = 1
	check("вкладка «Звук»: ползунки «Музыка» и «Эффекты» со значениями Settings", tr(sm.tabs.get_tab_title(1)) == "Звук"
		and is_equal_approx(sm.music_slider.value, st.music_volume) and is_equal_approx(sm.sfx_slider.value, st.sfx_volume))
	sm.music_slider.value = 0.5
	check("ползунок «Музыка» меняет громкость", is_equal_approx(st.music_volume, 0.5))
	st.set_music_volume(st.VOLUME_DEFAULT)
	sm.tabs.current_tab = 0
	sm.fullscreen_check.button_pressed = true
	check("переключатель включает полный экран", st.fullscreen)
	st.set_fullscreen(false)
	check("переключатель следует за F11 и Settings", not sm.fullscreen_check.button_pressed)
	# «Тряска экрана» — уровни (задача 23): выкл / слабая / обычная / сильная, по умолчанию «обычная»; «Жестокость» — выкл / обычная
	var srow: Node = sm.shake_option.get_parent()
	check("«Тряска экрана» на вкладке «Видео» под полным экраном: %d уровня, по умолчанию «%s»" % [sm.shake_option.item_count, tr(sm.shake_option.get_item_text(sm.shake_option.selected))],
		tr(srow.get_child(0).text) == "Тряска экрана" and srow.get_parent() == sm.fullscreen_check.get_parent() and sm.shake_option.item_count == st.SHAKE_LEVELS.size()
		and sm.shake_option.selected == st.SHAKE_NORMAL and st.screen_shake_level == st.SHAKE_NORMAL and st.screen_shake)
	sm.shake_option.select(0)
	sm.shake_option.item_selected.emit(0)
	var sc := ConfigFile.new()
	check("уровень «выкл.» выключает тряску и пишет display/screen_shake_level = 0 (и прежний ключ screen_shake = false)", not st.screen_shake and sc.load(path) == OK
		and sc.get_value("display", "screen_shake_level", -1) == 0 and sc.get_value("display", "screen_shake", true) == false)
	st.screen_shake_level = 3
	st.load_settings()
	check("после «перезапуска» тряска выключена", not st.screen_shake and st.screen_shake_level == 0)
	st.set_screen_shake_level(3)
	check("«Сильная»: уровень 3 в Settings и в списке", st.screen_shake_level == 3 and sm.shake_option.selected == 3)
	var old := ConfigFile.new()   # прежний файл: только display/screen_shake = false — уровень «выкл.»
	old.set_value("display", "screen_shake", false)
	old.save(path)
	st.load_settings()
	check("прежний ключ display/screen_shake = false читается как уровень «выкл.»", st.screen_shake_level == 0)
	st.set_screen_shake_level(st.SHAKE_NORMAL)
	var grow: Node = sm.gore_option.get_parent()
	check("«Жестокость» там же: выкл / обычная, по умолчанию «обычная»", tr(grow.get_child(0).text) == "Жестокость" and sm.gore_option.item_count == st.GORE_LEVELS.size()
		and sm.gore_option.selected == 1 and st.gore == 1)
	sm.gore_option.select(0)
	sm.gore_option.item_selected.emit(0)
	sc = ConfigFile.new()
	check("«Жестокость: выкл.» пишет gameplay/gore = 0", st.gore == 0 and sc.load(path) == OK and sc.get_value("gameplay", "gore", -1) == 0)
	st.set_gore(1)
	TranslationServer.set_locale("en")
	var en := tr(srow.get_child(0).text)
	var en2 := tr(sm.shake_option.get_item_text(3))
	var en3 := tr(grow.get_child(0).text)
	TranslationServer.set_locale("ru")
	check("списки следуют за Settings; en: «%s», «%s», «%s»" % [en, en2, en3], sm.shake_option.selected == st.SHAKE_NORMAL and sm.gore_option.selected == 1
		and en == "Screen shake" and en2 == "Strong" and en3 == "Gore")
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
