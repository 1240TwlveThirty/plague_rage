extends SceneTree
# Задача 34, разведка (окно): фильтрация фона боя. Бой seed 3, кадры окна (без приведения к 1920x1080) при множителе зума
# 1.0, 2.5 и 4.0 с центром на открытой земле; печатает фильтры спрайтов фона, леса, замка, юнитов и фильтр по умолчанию.
# Аргументы после «--»: папка кадров [, суффикс имени].
func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)
	_run.call_deferred()

func step(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else OS.get_temp_dir()
	var suf: String = args[1] if args.size() > 1 else ""
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v87/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v87")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(12)
	var m: Node2D = current_scene
	m.set_physics_process(false)
	print("FILTER87|окно %s|по умолчанию (проект) %s|вьюпорт %s" % [str(DisplayServer.window_get_size()),
		str(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")), str(root.canvas_item_default_texture_filter)])
	for n in m.find_children("*", "CanvasItem", true, false):
		if n is Sprite2D or n is MultiMeshInstance2D:
			var t: Texture2D = n.texture
			print("FILTER87|%s|%s|текстура %s|фильтр %d|материал %s|z %d" % [n.get_class(), n.name, t.resource_path if t != null else "-",
				n.texture_filter, n.material.get_class() if n.material != null else "-", n.z_index])
	m.cam_cfg.zoom_user_max = 4.0
	for z in [1.0, 2.5, 4.0]:
		m.zoom_user = z
		m.zoom_user_target = z
		var zz: float = m.camera_min_zoom() * z
		m.camera.zoom = Vector2.ONE * zz
		m.camera.position = m._camera_clamp(Vector2(1010, 330), zz)
		await step(4)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var p := out.path_join("zoom_%s%s.png" % [str(z), suf])
		img.save_png(p)
		print("FILTER87|кадр %s|%s" % [p, str(img.get_size())])
	g.go_menu()
	await step(3)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v87")
	quit(0)
