extends SceneTree
# Смоук задачи 27 (окно): режим скриншотов при любом зуме камеры. На каждом множителе (zoom_user_min, 1, zoom_user_max из
# data/camera.json; у max — у края поля): клавиша кадра (data/screenshot.json) — кадр size, строки FPS (отладка) на нём нет,
# после кадра она видна; запись — кадры size / record_downscale, строка FPS скрыта на время записи.
# Аргумент: временная папка (кадры кладутся туда, user://screenshots не трогается).
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	root.push_input(e)
	var r := e.duplicate() as InputEventKey
	r.pressed = false
	root.push_input(r)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var tmp: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/screenshot.json"))
	var cam: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/camera.json"))
	var shots: Node = root.get_node("Shots")
	var dir := tmp.path_join("shots_v77")
	shots.shot_dir = dir
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v77sh/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v77sh")
	g._setup()
	g.run_seed = 3
	node_added.connect(func(n): if n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd": n.debug_fps_force = true)
	g.start_run(1)
	await step(10)
	var m: Node2D = current_scene
	var size: Array = cfg.size
	var vs: Vector2 = m.get_viewport_rect().size
	for z in [[float(cam.zoom_user_min), vs * 0.5, "min"], [1.0, vs * 0.5, "1"], [float(cam.zoom_user_max), Vector2(20, vs.y * 0.5), "max, у левого края поля"]]:
		m.zoom_user_target = z[0]
		m.zoom_anchor_screen = z[1]
		m.zoom_anchor_world = m.screen_to_world(z[1]) if z[2] != "max, у левого края поля" else Vector2(-200, m.FIELD.y * 0.5)
		var t_end := Time.get_ticks_msec() + 3000   # сглаживание — по реальному времени, не по кадрам
		while m.zoom_user != m.zoom_user_target and Time.get_ticks_msec() < t_end:
			await process_frame
		await step(2)
		var tag := "зум ×%s (%s)" % [z[0], z[2]]
		var got := [""]
		shots.saved.connect(func(p): got[0] = p, CONNECT_ONE_SHOT)
		key(shots.shot_key)
		for i in 30:
			if got[0] != "":
				break
			await process_frame
		var path: String = got[0]
		var img := Image.load_from_file(path) if path != "" else null
		var fps_r: Rect2 = m.fps_label.get_global_rect()
		await step(2)
		await RenderingServer.frame_post_draw
		var live := root.get_texture().get_image()
		live.resize(int(size[0]), int(size[1]), Image.INTERPOLATE_NEAREST)
		var differ := 0
		if img != null:
			var sx := float(size[0]) / root.get_visible_rect().size.x
			var sy := float(size[1]) / root.get_visible_rect().size.y
			var r := Rect2i(int(fps_r.position.x * sx), int(fps_r.position.y * sy), int(fps_r.size.x * sx), int(fps_r.size.y * sy))
			for y in range(r.position.y, r.end.y, 2):
				for x in range(r.position.x, r.end.x, 2):
					if not img.get_pixel(x, y).is_equal_approx(live.get_pixel(x, y)):
						differ += 1
		check("%s: кадр %dx%d, строки FPS на нём нет (%d точек её места отличаются от живого кадра), после кадра она видна" % [tag,
			img.get_width() if img else 0, img.get_height() if img else 0, differ], img != null and img.get_width() == int(size[0])
			and img.get_height() == int(size[1]) and differ > 0 and m.fps_label.visible)
		check("%s: зум не сбился кадром" % tag, m.zoom_user == z[0])
		key(shots.record_key)
		await step(2)
		var hidden_rec: bool = not m.fps_label.visible
		var t0 := Time.get_ticks_msec()
		while shots.rec_n < 2 and Time.get_ticks_msec() - t0 < 3000:
			await process_frame
		key(shots.record_key)
		await step(2)
		var files := DirAccess.get_files_at(shots.rec_dir)
		var f0 := Image.load_from_file(shots.rec_dir.path_join(files[0])) if files.size() > 0 else null
		var dw := int(size[0]) / int(cfg.record_downscale)
		check("%s: запись — %d кадров %dx%d, строка FPS скрыта на время записи и видна после" % [tag, files.size(), f0.get_width() if f0 else 0, f0.get_height() if f0 else 0],
			files.size() >= 2 and f0 != null and f0.get_width() == dw and hidden_rec and m.fps_label.visible)
	for d in DirAccess.get_directories_at(dir):
		for f in DirAccess.get_files_at(dir.path_join(d)):
			DirAccess.remove_absolute(dir.path_join(d).path_join(f))
		DirAccess.remove_absolute(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(g.save_path)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
