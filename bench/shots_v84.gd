extends SceneTree
# Кадры задачи 30 (с окном): баннер скрыт, на его месте «Журнал (H)», ru и en. Кнопка в группе shot_hidden — режим съёмки (F12,
# Shots.capture) её прячет, поэтому кадр — прямо из окна (root.get_texture), как видит игрок. Сцена — как --scene=respite (seed
# screenshot.json scene_seed, своё временное сохранение). Баннер с «×» снимает режим съёмки: --scene=respite --banner=show.
# Аргумент — папка для кадров. Печатает SHOT84|файл|что.
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
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v84shots/save.json"   # временное сохранение: настоящее не трогается
	DirAccess.make_dir_recursive_absolute("user://bench_v84shots")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = int(cfg.scene_seed)
	for l in ["ru", "en"]:
		TranslationServer.set_locale(l)
		g.start_run(1)
		await _frames(int(cfg.scene_settle_frames))
		var m: Node2D = current_scene
		m.close_banner()
		await _frames(4)
		await RenderingServer.frame_post_draw
		var dst := out.path_join("banner_log_%s.png" % l)
		root.get_texture().get_image().save_png(dst)
		print("SHOT84|%s|баннер скрыт, «%s»" % [dst.get_file(), m.banner_log.text])
	g.go_menu()
	await _frames(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v84shots")
	quit(0)
