extends SceneTree
# Ленты кадров анимации выбора карточки (задача 25, окно 1920x1080, ru): по FRAMES кадров с равным шагом в одной картинке
# (сетка COLS x 2; наведение и сгорание — область карточек CARDS_CROP 1:1, удар — весь кадр, уменьшенный в CELL_SCALE раз). Время анимации идёт вручную (fx_step) — кадры повторяемы.
#   pick_hover.png  — наведение: курсор проходит по первой карточке слева направо и сверху вниз (наклон, блик, подсветка);
#   pick_burn.png   — от выбора до удара: сгорание двух других, выезд выбранной по дуге, удар;
#   pick_impact.png — от удара до конца: вспышка, тряска, кольца, затухание;
#   settings_ru.png, settings_en.png — вкладка «Видео» настроек (строка «Анимация выбора карточки»).
# Аргумент: папка для PNG. Печатает «STRIP|файл|шаг, с|кадров» и SHOTS: готово.
const FRAMES := 10
const COLS := 5
const CELL_SCALE := 2
const CARDS_CROP := Rect2i(400, 180, 1120, 680)   # ряд карточек и центр экрана: ленты наведения и сгорания — без уменьшения
const DIR := "user://bench_v75s"
var out_dir := ""
var cards: CanvasLayer

func step(n: int) -> void:
	for i in n:
		await process_frame

func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

# Сетка кадров frames в одну картинку: кадр — область crop (px холста 1920x1080; пусто — весь) в масштабе 1/down.
func strip(frames: Array, file: String, dt: float, crop := Rect2i(), down := CELL_SCALE) -> void:
	if crop.size != Vector2i.ZERO:
		var k := float(frames[0].get_width()) / root.get_visible_rect().size.x   # окно может быть не 1920
		var c := Rect2i(Vector2i(Vector2(crop.position) * k), Vector2i(Vector2(crop.size) * k))
		frames = frames.map(func(f): return f.get_region(c))
		for f in frames:
			f.resize(crop.size.x, crop.size.y, Image.INTERPOLATE_NEAREST)
	var w: int = frames[0].get_width() / down
	var h: int = frames[0].get_height() / down
	var rows := ceili(frames.size() / float(COLS))
	var out := Image.create(w * COLS, h * rows, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var f: Image = frames[i]
		f.convert(Image.FORMAT_RGBA8)
		f.resize(w, h, Image.INTERPOLATE_NEAREST)
		out.blit_rect(f, Rect2i(0, 0, w, h), Vector2i((i % COLS) * w, (i / COLS) * h))
	out.save_png(out_dir.path_join(file))
	print("STRIP|%s|%.3f|%d" % [file, dt, frames.size()])

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func open_offer(m: Node2D) -> void:
	cards.open(m.card_defs.keys().slice(0, 3), m.card_defs, [])
	cards.set_process(false)   # время — только fx_step
	await step(3)

func _run() -> void:
	out_dir = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	TranslationServer.set_locale("ru")
	var g: Node = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	node_added.connect(_on_node_added)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	m.banner.visible = false
	cards = m.card_screen
	cards.fx_rng.seed = 25
	await open_offer(m)
	# наведение: путь курсора по первой карточке
	var r: Rect2 = cards.card_rect(0, false)
	cards._hover(0, true)
	var frames := []
	var dt := 0.1
	for i in FRAMES:
		var u := i / float(FRAMES - 1)
		cards.test_mouse = r.position + r.size * Vector2(0.1 + 0.8 * u, 0.15 + 0.7 * u)
		cards.fx_step(dt)
		frames.append(await grab())
	strip(frames, "pick_hover.png", dt, CARDS_CROP, 1)
	# выбор: от выбора до удара и от удара до конца
	var fx: Dictionary = cards.fx
	var t_hit: float = cards.impact_time()
	var total: float = cards.total_time(fx, cards.ANIM_FULL)
	cards._pick(0)
	frames = []
	dt = t_hit / FRAMES
	for i in FRAMES:
		frames.append(await grab())
		cards.fx_step(dt)
	strip(frames, "pick_burn.png", dt, CARDS_CROP, 1)
	frames = []
	dt = (total - t_hit) / FRAMES
	for i in FRAMES:
		if not cards.anim_on:
			break
		frames.append(await grab())
		cards.fx_step(dt * 0.999)
	strip(frames, "pick_impact.png", dt)
	# настройки: вкладка «Видео» с «Анимация выбора карточки», ru и en
	m.queue_free()
	g.go_menu()
	await step(8)
	var mn := current_scene
	for l in ["ru", "en"]:
		TranslationServer.set_locale(l)
		mn.settings_menu.open()
		mn.settings_menu.tabs.current_tab = 0
		await step(3)
		(await grab()).save_png(out_dir.path_join("settings_%s.png" % l))
		print("SHOT|settings_%s.png" % l)
		mn.settings_menu.close()
	TranslationServer.set_locale("ru")
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("SHOTS: готово")
	quit(0)
