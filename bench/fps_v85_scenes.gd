extends SceneTree
# Замер задачи 31 (окно): FPS сцен режима съёмки (data/cine_scenes.json). Сцена собирается как в Shots (--cine-scene), режим
# съёмки включён, бой идёт сам SECONDS с реального времени; FPS — кадров за последние MEASURE с (после разгона), вертикальная
# синхронизация выключена (как в бою). Печатает FPS85|сцена|юнитов в начале / в конце|FPS средний|худшая секунда.
const SECONDS := 6.0
const MEASURE := 4.0
const CINE_SCENES := preload("res://scripts/cine_scenes.gd")

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)
	_run.call_deferred()

func _run() -> void:
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v85fps/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v85fps")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	for sc in CINE_SCENES.all():
		g.run_seed = int(sc.seed)
		var prep := func(n: Node) -> void:
			if n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
				CINE_SCENES.prepare(n, sc)
		node_added.connect(prep)
		g.start_run(1)
		for i in 4:
			await process_frame
		node_added.disconnect(prep)
		var m: Node2D = current_scene
		CINE_SCENES.build(m, sc)
		m.cine.set_on(true)
		CINE_SCENES.camera(m, sc)
		var n0: int = m.count
		var t0 := Time.get_ticks_msec()
		var frames := 0
		var sec_frames := 0
		var sec_t := 0
		var worst := 1e9
		while Time.get_ticks_msec() - t0 < SECONDS * 1000.0:
			await process_frame
			var el := Time.get_ticks_msec() - t0
			if el >= (SECONDS - MEASURE) * 1000.0:
				frames += 1
				sec_frames += 1
				if sec_t == 0:
					sec_t = el
				elif el - sec_t >= 1000:
					worst = minf(worst, sec_frames * 1000.0 / (el - sec_t))
					sec_frames = 0
					sec_t = el
		print("FPS85|%s|юнитов %d / %d|FPS %.0f|худшая секунда %.0f" % [sc.id, n0, m.count, frames / MEASURE, worst])
		m.cine.set_on(false)
		g.go_menu()
		for i in 3:
			await process_frame
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v85fps")
	quit(0)
