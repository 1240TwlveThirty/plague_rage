extends SceneTree
# Задача 28, этап 3 (без окна): сброс прогресса. Тестовый профиль — во временной папке системы (не в user://): сохранение,
# настройки и журнал забегов там; настоящие user://save.json, settings.cfg и runs.csv разработчика тест не трогает (сверка
# содержимого и времени изменения до и после).
#   Game.reset_progress: в памяти и в файле — как новый профиль (то же, что _setup без файла); показанные подсказки пусты;
#   настройки (звук, клавиши, язык, вкл. подсказок) и runs.csv — прежние.
#   Настройки, вкладка «Игра»: «Сбросить прогресс» — окно подтверждения (что сбрасывается, необратимо), в фокусе «Отмена»;
#   «Отмена» и Esc ничего не сбрасывают (Esc экран настроек не закрывает); «Сбросить» — сброс и сообщение; из боя — в главное
#   меню, дерево не на паузе. Тексты ru/en.
const MENU := "res://scenes/menu.tscn"
var fails := 0
var tmp := ""

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

# Содержимое и время изменения файла (нет файла — "нет").
func stamp(p: String) -> String:
	if not FileAccess.file_exists(p):
		return "нет"
	return "%s@%d" % [FileAccess.get_md5(p), FileAccess.get_modified_time(p)]

# Состояние прогресса Game (без play_time: идёт каждый кадр).
func progress(g: Node) -> Dictionary:
	return {"siege": g.siege, "unlocked": g.unlocked_siege, "last": g.last_siege, "records": g.records.duplicate(true), "diary": g.diary_seen.duplicate(),
		"completed": g.completed, "runs": g.runs_total, "radiance": g.radiance, "gifts": g.gift_levels.duplicate(), "last_run": g.last_run.duplicate()}

func fill_progress(g: Node) -> void:
	g.radiance = 77
	for id in g.gift_levels:
		g.gift_levels[id] = 1
	g.records[1] = {"best_wave": 7, "wins": 1, "runs": 3}
	g.unlocked_siege = mini(2, g.siege_count)
	g.last_siege = g.unlocked_siege
	g.diary_seen = [g.INTRO_ID, "s1_w5"]
	g.completed = true
	g.runs_total = 3
	g.play_time = 1234.0
	g.last_run = {"siege": 1, "result": "loss", "wave": 7, "kills": 99, "radiance": 10}
	g.save()

func _run() -> void:
	print("CHECK v78: сброс прогресса")
	var real := {}
	for p in ["user://save.json", "user://settings.cfg", "user://runs.csv"]:
		real[p] = stamp(p)
	tmp = OS.get_temp_dir().path_join("plague_v78_reset_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(tmp)
	var st: Node = root.get_node("Settings")
	var S: GDScript = load("res://scripts/settings.gd")
	st.path = tmp.path_join("settings.cfg")
	st.persist = true
	st.load_settings()
	var g: Node = root.get_node("Game")
	g.save_path = tmp.path_join("save.json")
	g.runs_log_path = tmp.path_join("runs.csv")
	g._setup()
	var fresh := progress(g)   # новый профиль: файла нет
	# тестовый профиль: прогресс, подсказки, настройки, журнал
	fill_progress(g)
	st.mark_hint_seen("select_order")
	st.mark_hint_seen("shop")
	st.set_music_volume(0.3)
	st.set_sfx_volume(0.4)
	st.rebind("squad_new", KEY_O)
	st.set_hints_enabled(false)
	st.set_language("en")
	var run_log: GDScript = load("res://scripts/run_log.gd")
	run_log.append(g.runs_log_path, {"date": "2026-10-31", "run": 3, "siege": 1, "result": "loss", "wave": 7})
	var runs_before := FileAccess.get_file_as_string(g.runs_log_path)
	var cfg_before := ConfigFile.new()
	cfg_before.load(st.path)
	check("тестовый профиль во временной папке системы, не в user://", not g.save_path.begins_with("user://") and not st.path.begins_with("user://")
		and not g.runs_log_path.begins_with("user://") and FileAccess.file_exists(g.save_path) and g.radiance == 77, tmp)
	var ok: bool = g.reset_progress()
	check("reset_progress: сохранение записано", ok)
	check("в памяти — как новый профиль (осады, рекорды, дневник, Сияние, дары, последний забег)", progress(g) == fresh and g.play_time < 1.0,
		"%s против %s" % [progress(g), fresh])
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(g.save_path))
	check("файл: Сияние 0, даров нет, рекордов нет, дневник пуст, открыта осада 1, забегов 0",
		d.radiance == 0 and d.gift_levels.values().all(func(v): return v == 0) and d.records.values().all(func(r): return r.best_wave == 0 and r.wins == 0 and r.runs == 0)
		and d.diary_seen.is_empty() and d.unlocked_siege == 1 and d.runs_total == 0 and d.completed == false and d.play_time < 1.0, str(d))
	g._setup()   # «перезапуск»: из файла
	check("после «перезапуска» из файла — тоже новый профиль", progress(g) == fresh)
	var cfg := ConfigFile.new()
	cfg.load(st.path)
	check("показанные подсказки сброшены (Settings и файл)", st.hints_seen.is_empty() and Array(cfg.get_value("hints", "seen", ["x"])).is_empty())
	check("настройки на месте: громкость 0.3 / 0.4, язык en, клавиша «Новый отряд» O, подсказки выкл — в памяти и в файле",
		is_equal_approx(st.music_volume, 0.3) and is_equal_approx(st.sfx_volume, 0.4) and st.language == "en" and S.key_label("squad_new") == "O" and not st.hints_enabled
		and cfg.get_value("general", "language") == "en" and cfg.get_value("input", "squad_new") == "O" and is_equal_approx(float(cfg.get_value("audio", "music")), 0.3)
		and cfg.get_value("hints", "enabled") == false and Array(cfg.get_value("hints", "seen", ["x"])).is_empty())
	var same_cfg := true
	for sec in cfg_before.get_sections():
		for k in cfg_before.get_section_keys(sec):
			if not (sec == "hints" and k == "seen") and str(cfg_before.get_value(sec, k)) != str(cfg.get_value(sec, k, null)):
				same_cfg = false
	check("settings.cfg: всё, кроме [hints] seen, как до сброса", same_cfg)
	check("runs.csv не изменился", FileAccess.get_file_as_string(g.runs_log_path) == runs_before and runs_before.count("\n") == 2)
	st.set_language("ru")

	print("настройки: «Сбросить прогресс», подтверждение")
	fill_progress(g)
	var sm: CanvasLayer = load("res://scripts/settings_menu.gd").new()
	root.add_child(sm)
	await step(1)
	sm.open()
	var game_tab := -1
	for t in sm.tabs.get_tab_count():
		if tr(sm.tabs.get_tab_title(t)) == "Игра":
			game_tab = t
	sm.tabs.current_tab = game_tab
	await step(1)
	check("кнопка «Сбросить прогресс» на вкладке «Игра»", sm.progress_reset_button != null and tr(sm.progress_reset_button.text) == "Сбросить прогресс"
		and sm.tabs.get_tab_control(game_tab).is_ancestor_of(sm.progress_reset_button) and sm.progress_reset_button.is_visible_in_tree())
	sm.progress_reset_button.pressed.emit()
	await step(1)
	var focus: Control = sm.confirm_box.get_viewport().gui_get_focus_owner()
	check("нажатие — окно подтверждения, в фокусе «Отмена»", sm.confirm_box.visible and focus == sm.confirm_no, str(focus))
	var texts := []
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		for k in ["UI_RESET_PROGRESS_TITLE", "UI_RESET_PROGRESS_TEXT", "UI_RESET_PROGRESS_CONFIRM", "UI_RESET_PROGRESS_CANCEL", "UI_SETTINGS_PROGRESS_RESET", "MSG_PROGRESS_RESET_DONE"]:
			texts.append(tr(k))
	TranslationServer.set_locale("ru")
	check("тексты ru/en переведены; в тексте — что сбрасывается, что остаётся и что необратимо",
		texts.all(func(t): return not t.begins_with("UI_") and not t.begins_with("MSG_")) and "нельзя" in texts[1] and "Сияние" in texts[1]
		and "Настройки" in texts[1] and "cannot be undone" in texts[7], str(texts.slice(0, 2)))
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	root.push_input(e)
	await step(1)
	check("Esc — «Отмена»: окно закрыто, экран настроек открыт, прогресс прежний", not sm.confirm_box.visible and sm.visible and g.radiance == 77)
	sm.progress_reset_button.pressed.emit()
	sm.confirm_no.pressed.emit()
	await step(1)
	check("«Отмена»: окно закрыто, прогресс прежний", not sm.confirm_box.visible and g.radiance == 77 and g.runs_total == 3)
	sm.progress_reset_button.pressed.emit()
	sm.confirm_yes.pressed.emit()
	await step(1)
	check("«Сбросить» (вне боя): прогресс сброшен, сообщение, экран настроек открыт", progress(g) == fresh and tr(sm.game_msg.text) == tr("MSG_PROGRESS_RESET_DONE")
		and sm.visible and not sm.confirm_box.visible)
	sm.queue_free()
	await step(1)

	print("из паузы боя — в главное меню")
	fill_progress(g)
	g.run_seed = 3
	g.start_run(1)
	await step(8)
	var m: Node = current_scene
	m._open_esc_menu()
	await step(1)
	var esc: CanvasLayer = m.esc_menu
	esc.settings_button.pressed.emit()
	await step(1)
	var sm2: CanvasLayer = esc.settings_menu
	sm2.progress_reset_button.pressed.emit()
	sm2.confirm_yes.pressed.emit()
	await step(10)
	check("сброс из меню паузы боя: главное меню, дерево не на паузе, прогресс новый", current_scene != null and current_scene.scene_file_path == MENU
		and not paused and progress(g) == fresh, str(current_scene.scene_file_path if current_scene else null))

	var same := []
	for p in real:
		if stamp(p) != real[p]:
			same.append(p)
	check("настоящие user://save.json, settings.cfg, runs.csv не тронуты", same.is_empty(), str(same))
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp.path_join(f))
	DirAccess.remove_absolute(tmp)
	st.persist = false
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
