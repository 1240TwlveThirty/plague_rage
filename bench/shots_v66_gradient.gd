extends SceneTree
# Скриншоты для выбора градиента кнопок (задача 16, с окном): магазин и панель отрядов (выбран отряд 1) при трёх вариантах
# gradient_left_alpha / gradient_right_alpha (ширина — gradient_width из data/unit_portraits.json). Только снимки, файлы данных не меняются.
# Аргумент: папка для PNG (gradient_<лево>_<право>.png — панель отрядов слева, магазин справа, 1:1).
const DIR := "user://bench_v66g"
const VARIANTS := [[0.45, 0.0], [0.55, 0.1], [0.35, 0.0]]

func step(n: int) -> void:
	for i in n:
		await process_frame

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var g: Node = root.get_node_or_null("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	m.banner.visible = false
	m.gold = 100000
	m._select_only(0)
	var width: float = m.portraits.gradient.gradient_width
	for v in VARIANTS:
		m.portraits.set_gradient(v[0], v[1], width)
		m._process(1.0 / 60.0)
		m._update_ui()
		m._update_squad_panel()
		await step(3)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var sq := Rect2i(m.squad_panel.get_global_rect().grow(8))
		var sh := Rect2i(m.shop_panel.get_global_rect().grow(8))
		var a := img.get_region(sq)
		var b := img.get_region(sh)
		var o := Image.create(a.get_width() + b.get_width() + 16, maxi(a.get_height(), b.get_height()), false, img.get_format())
		o.fill(Color(1, 1, 1))
		o.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
		o.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width() + 16, 0))
		var name := "gradient_%03d_%03d.png" % [roundi(v[0] * 100), roundi(v[1] * 100)]
		o.save_png(out_dir.path_join(name))
		print("  %s: слева %.2f, справа %.2f, ширина %.2f" % [name, v[0], v[1], width])
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("SHOTS: готово")
	quit(0)
