extends SceneTree
# Смоук задачи 25 (окно): режим скриншотов. Клавиши — из data/screenshot.json.
#   shot_key: кадр size (1920x1080) сохраняется, на нём нет строки FPS (включена флагом отладки), после кадра строка снова видна.
#   record_key: запись кадров в подпапку rec_*, повторное нажатие — стоп; предел длины — запись выключается сама на
#   record_max_frames (для скорости теста предел уменьшен до LIMIT, механизм тот же).
# Аргумент: временная папка (кадры кладутся туда, user://screenshots не трогается).
const LIMIT := 4
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
	var shots: Node = root.get_node("Shots")
	var dir := tmp.path_join("shots_v75")
	shots.shot_dir = dir
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v75sh/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v75sh")
	g._setup()
	g.run_seed = 3
	node_added.connect(func(n): if n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd": n.debug_fps_force = true)
	g.start_run(1)
	await step(10)
	var m: Node2D = current_scene
	check("клавиши из данных: кадр %s, запись %s" % [cfg.shot_key, cfg.record_key], shots.shot_key == OS.find_keycode_from_string(cfg.shot_key)
		and shots.record_key == OS.find_keycode_from_string(cfg.record_key))
	check("строка FPS включена флагом отладки и видна", m.fps_label != null and m.fps_label.visible and m.fps_label.is_in_group(&"shot_hidden"))
	# кадр: строка FPS на кадре скрыта — сравнить с кадром, где она видна
	var got := [""]
	shots.saved.connect(func(p): got[0] = p, CONNECT_ONE_SHOT)
	key(shots.shot_key)
	for i in 30:
		if got[0] != "":
			break
		await process_frame
	var path: String = got[0]
	var img := Image.load_from_file(path) if path != "" else null
	var size: Array = cfg.size
	var fps_r: Rect2 = m.fps_label.get_global_rect()
	await step(2)
	await RenderingServer.frame_post_draw
	var live := root.get_texture().get_image()
	live.resize(int(size[0]), int(size[1]), Image.INTERPOLATE_NEAREST)
	var with_fps := 0
	if img != null:
		var sx := float(size[0]) / root.get_visible_rect().size.x
		var sy := float(size[1]) / root.get_visible_rect().size.y
		var r := Rect2i(int(fps_r.position.x * sx), int(fps_r.position.y * sy), int(fps_r.size.x * sx), int(fps_r.size.y * sy))
		for y in range(r.position.y, r.end.y, 2):
			for x in range(r.position.x, r.end.x, 2):
				if img.get_pixel(x, y).is_equal_approx(live.get_pixel(x, y)) == false:
					with_fps += 1
	check("клавиша кадра: %s сохранён, %dx%d; строки FPS на нём нет (отличается от живого кадра в %d точках её места), после кадра она снова видна" % [path.get_file(),
		img.get_width() if img else 0, img.get_height() if img else 0, with_fps], img != null and img.get_width() == int(size[0]) and img.get_height() == int(size[1])
		and with_fps > 0 and m.fps_label.visible and path.get_base_dir() == dir)
	# запись: старт, кадры, стоп повторным нажатием
	key(shots.record_key)
	await step(2)
	var rec: String = shots.rec_dir
	var hidden_rec: bool = not m.fps_label.visible
	var t0 := Time.get_ticks_msec()
	while shots.rec_n < 2 and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	key(shots.record_key)
	await step(2)
	var n1 := DirAccess.get_files_at(rec).size()
	check("запись: старт клавишей, кадры в %s (%d), строка FPS скрыта во время записи; повторное нажатие — стоп, строка снова видна" % [rec.get_file(), n1],
		n1 >= 2 and hidden_rec and not shots.recording and m.fps_label.visible and rec.get_base_dir() == dir)
	# предел длины: запись выключается сама
	shots.cfg.record_max_frames = LIMIT
	key(shots.record_key)
	t0 = Time.get_ticks_msec()
	while shots.recording and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	var n2 := DirAccess.get_files_at(shots.rec_dir).size()
	check("предел записи (record_max_frames, здесь %d; в данных %d): запись выключилась сама на %d кадрах" % [LIMIT, int(cfg.record_max_frames), n2],
		not shots.recording and n2 == LIMIT)
	shots.cfg.record_max_frames = int(cfg.record_max_frames)
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
