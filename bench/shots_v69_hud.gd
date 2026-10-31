extends SceneTree
# Снимки верхней панели боя (задача 19, окно 1920x1080): бой с малыми числами (ru, en), с 4- и 5-значными, ворота 100 / 40 / 0 %,
# хаб и экран итога с окошком «Сияние». Большие числа и доля ворот задаются подменой источника значений панели (top_hud.source) —
# симуляция не трогается. Печатает «SLOT|id|кегль|текст|ширина текста/место» для отчёта.
# Временное сохранение user://bench_v69s (настоящий user://save.json не трогается). Аргумент: папка для PNG.
const DIR := "user://bench_v69s"
const DT := 1.0 / 30.0
var out_dir := ""
var fake := {}

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(file: String) -> void:
	await step(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(file))
	print("  %s" % file)

func slots(m: Node) -> void:
	for id in m.top_hud.slots:
		var s = m.top_hud.slots[id]
		print("SLOT|%s|%d|%s|%.0f/%.0f" % [id, s.label.get_theme_font_size("font_size"), s.label.text, s.text_px(), s.text_width])

func fake_value(id: String) -> Vector2i:
	return fake.get(id, Vector2i(0, -1))

# Подставить значения окошек (id -> Vector2i) и обновить панель.
func show_fake(m: Node, values: Dictionary) -> void:
	fake = values
	m.top_hud.source = fake_value
	m.top_hud.update()

# Кадр main без физики (сцена выключена, чтобы бой не шёл сам): юниты, FPS-строка, панель.
func refresh(m: Node2D) -> void:
	m._process(1.0 / 60.0)
	m._update_ui()

func lang(code: String) -> void:
	TranslationServer.set_locale(code)
	await step(3)

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var locale := TranslationServer.get_locale()
	var g: Node = root.get_node_or_null("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.radiance = 1240
	await lang("ru")
	g.go_hub()
	await step(5)
	await shot("hub_ru.png")
	var h := current_scene
	h.tabs.current_tab = 1
	await shot("hub_gifts_ru.png")
	h.tabs.current_tab = 0
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	m.banner.visible = false
	refresh(m)
	await shot("respite_ru.png")
	m._start_wave()
	for t in 90:
		m._physics_process(DT)
	m.banner.visible = false
	refresh(m)
	print("бой, малые числа: %s" % m.top_hud.get_values())
	slots(m)
	await shot("battle_small_ru.png")
	await lang("en")
	m.banner.visible = false
	refresh(m)
	await shot("battle_small_en.png")
	await lang("ru")
	m.banner.visible = false
	show_fake(m, {"wave": Vector2i(7, 10), "zombies_left": Vector2i(1234, -1), "troops": Vector2i(2048, -1), "gate": Vector2i(1500, 1500), "gold": Vector2i(4321, -1)})
	refresh(m)
	print("4 цифры:")
	slots(m)
	await shot("battle_4digits_gate100_ru.png")
	show_fake(m, {"wave": Vector2i(10, 10), "zombies_left": Vector2i(12345, -1), "troops": Vector2i(23456, -1), "gate": Vector2i(12000, 30000), "gold": Vector2i(99999, -1)})
	print("5 цифр:")
	slots(m)
	await shot("battle_5digits_gate40_ru.png")
	await lang("en")
	m.top_hud.update()
	await shot("battle_5digits_gate40_en.png")
	await lang("ru")
	show_fake(m, {"wave": Vector2i(10, 10), "zombies_left": Vector2i(123456, -1), "troops": Vector2i(9, -1), "gate": Vector2i(0, 1500), "gold": Vector2i(1234567, -1)})
	print("6-7 цифр (сокращение), ворота 0:")
	slots(m)
	await shot("battle_6digits_gate0_ru.png")
	m.top_hud.source = m._hud_value
	m.top_hud.update()
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 900:
		m._physics_process(DT)
		t += 1
	m._on_defeat()
	refresh(m)
	await shot("result_ru.png")
	await lang("en")
	await shot("result_en.png")
	m.queue_free()
	await step(2)
	TranslationServer.set_locale(locale)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("SHOTS: готово")
	quit(0)
