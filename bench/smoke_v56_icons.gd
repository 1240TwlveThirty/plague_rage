extends SceneTree
# Смоук v56 с окном (задача 6c): вкладка «Дары» в хабе с иконками в рамке карточки дара — скриншот hub_gifts_icons.png;
# все строки даров (14 видимых) целиком на экране 1920 x 1080, у каждой — рамка и иконка в ней. Аргумент: папка для PNG.
const DIR := "user://bench_v56s"
const SCREEN := Rect2(0, 0, 1920, 1080)
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var g: Node = root.get_node_or_null("Game")
	if g == null:
		print("SMOKE: нет автозагрузки Game")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.radiance = 300
	g.go_hub()
	await step(5)
	var h := current_scene
	h.tabs.current_tab = 1
	await step(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("hub_gifts_icons.png"))
	var grid: GridContainer = h.gift_rows["mine"].button.get_parent()
	var frames := grid.get_children().filter(func(c): return c is TextureRect)
	var with_icon := frames.filter(func(c): return c.get_child_count() == 1 and c.get_global_rect().encloses(c.get_child(0).get_global_rect()))
	check("строк даров %d, у каждой рамка с иконкой внутри" % h.gift_rows.size(), frames.size() == h.gift_rows.size() and with_icon.size() == frames.size())
	check("таблица даров целиком на экране", SCREEN.encloses(grid.get_global_rect()), str(grid.get_global_rect()))
	h.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
