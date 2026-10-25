extends SceneTree
# Снимки универсальных рамок (задача 18, с окном 1920x1080): главное меню, настройки, хаб (вкладки «Осада» и «Дары», дневник),
# баннер передышки, передышка с кнопками действий и Кличем, карточки выбора, бой с «Командир пал», меню паузы, итог забега.
# Печатает «RECT|имя|x,y,w,h» кнопок магазина, отрядов и карточек — для сравнения с теми же снимками до задачи (они без рамки темы).
# Временное сохранение user://bench_v68s (настоящий user://save.json не трогается); файлы данных не меняются. Аргумент: папка для PNG.
const DIR := "user://bench_v68s"
const DT := 1.0 / 30.0
var out_dir := ""

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(file: String) -> void:
	await step(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file))
	print("  %s" % file)

func refresh(m: Node2D) -> void:
	m._process(1.0 / 60.0)
	m._update_ui()

func rects(prefix: String, list: Array) -> void:
	for k in list.size():
		var r: Rect2 = list[k].get_global_rect()
		print("RECT|%s%d|%d,%d,%d,%d" % [prefix, k, r.position.x, r.position.y, r.size.x, r.size.y])

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var g: Node = root.get_node_or_null("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.radiance = 120
	g.go_menu()
	await step(10)
	var mn := current_scene
	await shot("menu.png")
	mn.settings_menu.open()
	await shot("settings.png")
	mn.settings_menu.tabs.current_tab = 2
	await shot("settings_keys.png")
	mn.settings_menu.close()
	g.go_hub()
	await step(5)
	var h := current_scene
	await shot("hub_siege.png")
	h.tabs.current_tab = 1
	await shot("hub_gifts.png")
	h.tabs.current_tab = 0
	h._open_diary()
	await shot("hub_diary.png")
	h._close_diary()
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	m.war_cry_level = 1   # кнопка Клича (дар) — чтобы она была на снимке
	m._setup_war_cry_ui(m.squad_panel.get_parent())
	m._select_only(0)
	m.squad_panel_sig = -1
	m._update_squad_panel()
	refresh(m)
	await shot("banner_respite.png")
	m.banner.visible = false
	await shot("respite_actions.png")
	rects("shop", m.shop_buttons)
	rects("squad", m.squad_buttons.filter(func(b): return b.is_visible_in_tree()))
	m.card_screen.open(m.card_defs.keys().slice(0, 3), m.card_defs, [])
	await shot("cards.png")
	rects("card", m.card_screen.buttons)
	m.card_screen.visible = false
	m._start_wave()
	for t in 60:
		m._physics_process(DT)
	if m.hero_on and m.hero_idx >= 0:
		m.hp[m.hero_idx] = 0.0   # «Командир пал»
	m._physics_process(DT)
	m.banner.visible = false
	m.squad_panel_sig = -1
	m._update_squad_panel()
	refresh(m)
	print("  бой: %s, герой пал: %s" % [m.wave_state == m.WS_BATTLE, m.hero_fallen_label.visible])
	await shot("battle_fallen.png")
	m.esc_menu.open(m.ESC_NOTE)
	await shot("pause.png")
	m.esc_menu.close()
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 900:
		m._physics_process(DT)
		t += 1
	refresh(m)
	await shot("banner_wave_cleared.png")
	m._on_defeat()
	refresh(m)
	await shot("result.png")
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("SHOTS: готово")
	quit(0)
