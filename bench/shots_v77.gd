extends SceneTree
# Снимки задачи 27 (окно): зум камеры в бою волны 10 (как --scene=battle: seed и тики из data/screenshot.json), ru и en.
# zoom_min — множитель zoom_user_min (поле по центру), zoom_max — zoom_user_max у ворот, zoom_edge — zoom_user_max у левого
# края поля (вид упёрся в край). Кадр — как клавиша кадра (без отладочных надписей), size из data/screenshot.json.
# Аргумент: папка для PNG (bench/report_27). Файлы: zoom_<вид>_<язык>.png.
const DT := 1.0 / 30.0

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/screenshot.json"))
	var cam: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/camera.json"))
	var shots: Node = root.get_node("Shots")
	var st: Node = root.get_node("Settings")
	var lang_was: String = st.language
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v77shots/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v77shots")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = int(cfg.scene_seed)
	g.start_run(1)
	await _frames(6)
	var m: Node2D = current_scene
	m.banner_hidden = true
	m.banner.visible = false
	m.wave_number = int(cfg.battle_wave) - 1
	m.wave_plan_for = -1
	m._start_wave()
	m.set_physics_process(false)
	for t in int(cfg.battle_ticks):
		if m.wave_state != m.WS_BATTLE:
			break
		m._physics_process(DT)
	m.banner.visible = false
	m._select_only(0)   # контур выбранного отряда — масштабируется с миром, подписи интерфейса — нет
	var vs: Vector2 = m.get_viewport_rect().size
	for lang in ["ru", "en"]:
		st.set_language(lang)
		await _frames(4)
		for v in [["min", float(cam.zoom_user_min), m.FIELD * 0.5], ["max", float(cam.zoom_user_max), m.GATE_POS + Vector2(0, -120)],
				["edge", float(cam.zoom_user_max), Vector2(-400, m.FIELD.y * 0.5)]]:
			m.zoom_user = v[1] * 0.97   # цель равна текущему множителю — камера не двигается (у предела колесо вид не дёргает); снимку нужен сдвиг
			m.zoom_user_target = v[1]
			m.zoom_anchor_screen = vs * 0.5
			m.zoom_anchor_world = v[2]
			var t_end := Time.get_ticks_msec() + 3000   # сглаживание — по реальному времени, не по кадрам
			while m.zoom_user != m.zoom_user_target and Time.get_ticks_msec() < t_end:
				await process_frame
			m._update_ui()
			await _frames(int(cfg.scene_settle_frames))
			var p: String = await shots.capture()
			var dst := out.path_join("zoom_%s_%s.png" % [v[0], lang])
			DirAccess.copy_absolute(p, dst)
			DirAccess.remove_absolute(p)
			print("SHOT77|%s|×%s|вид %s" % [dst.get_file(), v[1], str(m.view_rect())])
	st.set_language(lang_was)
	DirAccess.remove_absolute(g.save_path)
	quit(0)
