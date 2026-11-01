extends SceneTree
# Задача 34, разведка (без окна): что с бойцом в сцене lone_soldier. Сцена собирается как в Shots (--cine-scene), тики — как
# --cine-ticks. Печатает по тикам: жив ли боец (team 0), HP, позиция, зомби в радиусе 24/48 px, ближайший зомби, и где камера.
const CINE_SCENES := preload("res://scripts/cine_scenes.gd")
const SCENE := "lone_soldier"

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)
	_run.call_deferred()

func _run() -> void:
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v87p/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v87p")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	var sc := CINE_SCENES.find(SCENE)
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
	m.set_physics_process(false)
	var vis: Rect2 = Rect2(m.camera.position - m.get_viewport_rect().size * 0.5 / m.camera.zoom, m.get_viewport_rect().size / m.camera.zoom)
	print("LONE87|камера %s, видно мира %s" % [str(m.camera.position), str(vis)])
	var died := -1
	for t in 401:
		var me := -1
		for i in m.count:
			if m.team[i] == 0:
				me = i
		if me < 0:
			if died < 0:
				died = t
				print("LONE87|t %d: бойца нет (погиб)" % t)
			if t % 50 != 0:
				m._physics_process(1.0 / Engine.physics_ticks_per_second)
				continue
		if t % 5 == 0 or (me >= 0 and m.hp[me] < 1e9 and t < 120 and t % 5 == 0):
			var n24 := 0
			var n48 := 0
			var best := 1e9
			var p: Vector2 = m.pos[me] if me >= 0 else Vector2.ZERO
			for i in m.count:
				if m.team[i] == 1:
					var d: float = m.pos[i].distance_to(p)
					best = minf(best, d)
					n24 += int(d < 24.0)
					n48 += int(d < 48.0)
			if me >= 0:
				print("LONE87|t %d|HP %.2f|поз %s|в кадре %s|зомби <24px %d, <48px %d|ближайший %.0f px|всего %d" % [t, m.hp[me], str(p.round()),
					vis.has_point(p), n24, n48, best, m.count])
		m._physics_process(1.0 / Engine.physics_ticks_per_second)
	print("LONE87|погиб на тике %d" % died)
	m.cine.set_on(false)
	g.go_menu()
	for i in 3:
		await process_frame
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v87p")
	quit(0)
