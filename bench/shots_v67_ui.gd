extends SceneTree
# Снимки интерфейса для отчёта (задача 17, с окном 1920x1080): ui_respite.png — передышка (магазин справа, панель отрядов слева,
# выбран отряд 1, кнопка Клича); ui_battle.png — бой через 5 с после начала волны 1 (магазин в бою скрыт, панель отрядов и Клич).
# Только снимки; файлы данных не меняются. Аргумент: папка для PNG.
const DIR := "user://bench_v67s"
const DT := 1.0 / 30.0

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(m: Node2D, path: String) -> void:
	m._process(1.0 / 60.0)
	m._update_ui()
	await step(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("  %s" % path)

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
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
	m.war_cry_level = 1   # кнопка Клича (дар) — чтобы она была на снимке
	m._setup_war_cry_ui(m.squad_panel.get_parent())
	m._select_only(0)
	m.squad_panel_sig = -1
	m._update_squad_panel()
	await shot(m, out_dir.path_join("ui_respite.png"))
	m._start_wave()
	for t in 150:
		m._physics_process(DT)
	print("  бой: %s, зомби %d" % [m.wave_state == m.WS_BATTLE, m.count])
	m.banner.visible = false
	m.squad_panel_sig = -1
	m._update_squad_panel()
	await shot(m, out_dir.path_join("ui_battle.png"))
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("SHOTS: готово")
	quit(0)
