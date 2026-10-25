extends SceneTree
# Снимки вариантов шрифта (задача 20, окно 1920x1080). Запуск: godot --path . -s res://bench/shots_v70_fonts.gd -- --font=<вариант> <папка>
# (вариант — default | fusion12 | fusion10, см. data/ui_theme.json). Для ru и en: главное меню, хаб (вкладка «Дары»), передышка
# (магазин и панель отрядов), бой (верхняя панель), выбор карточки. Файлы <вариант>_<язык>_<экран>.png.
# Печатает «CLIP|вариант|язык|экран|контрол|текст» — где текст не помещается (кнопки магазина и отрядов, окошки верхней панели,
# карточки, подписи хаба и меню выходят за свой прямоугольник или за экран). Временное сохранение user://bench_v70s.
const FONTS := preload("res://scripts/fonts.gd")
const DIR := "user://bench_v70s"
const DT := 1.0 / 30.0
var out_dir := ""
var lang := ""
var clips := 0

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await step(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("%s_%s_%s.png" % [FONTS.variant, lang, name]))
	print("  %s_%s_%s.png" % [FONTS.variant, lang, name])

func refresh(m: Node2D) -> void:
	m._process(1.0 / 60.0)
	m._update_ui()

# Текст контрола шире или выше его места (кнопка — за вычетом отступов StyleBox), либо контрол за экраном.
func clipped(c: Control) -> String:
	if not c.is_visible_in_tree():
		return ""
	var r := c.get_global_rect()
	if r.size.x < 1.0 or r.size.y < 1.0:
		return ""
	var scr := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	if not scr.encloses(r.grow(-0.5)):
		return "за экраном %s" % str(r)
	var text := ""
	var room := r.size
	if c is Button:
		text = (c as Button).text
		room -= c.get_theme_stylebox("normal").get_minimum_size()
	elif c is Label:
		text = (c as Label).text
		if (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			return ""   # перенос: ширина своя
		if (c as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
			var full := c.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, c.get_theme_font_size("font_size")).x
			return "сокращено многоточием (%d из %d px), полный текст — в подсказке" % [r.size.x, full] if full > r.size.x + 0.5 else ""
	else:
		return ""
	if text == "":
		return ""
	var font := c.get_theme_font("font")
	var fs := c.get_theme_font_size("font_size")
	var sz := font.get_multiline_string_size(c.tr(text) if c.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if c is Button and (c as Button).autowrap_mode != TextServer.AUTOWRAP_OFF:
		sz = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, room.x, fs, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	if sz.x > room.x + 0.5 or sz.y > room.y + 0.5:
		return "текст %dx%d в месте %dx%d (кегль %d)" % [sz.x, sz.y, room.x, room.y, fs]
	return ""

func scan(screen: String, node: Node) -> void:
	for c in node.find_children("*", "Control", true, false):
		var why := clipped(c)
		if why != "":
			clips += 1
			var t: String = c.text if "text" in c else ""
			print("CLIP|%s|%s|%s|%s|%s|%s" % [FONTS.variant, lang, screen, c.name, t.replace("\n", " / ").left(60), why])

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a): return not a.begins_with("--font="))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("шрифт: %s (родной кегль %d, контур не толще %d)" % [FONTS.variant, FONTS.native, FONTS.outline_max])
	var locale := TranslationServer.get_locale()
	var g: Node = root.get_node_or_null("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	node_added.connect(_on_node_added)
	for l in ["ru", "en"]:
		lang = l
		TranslationServer.set_locale(l)
		DirAccess.remove_absolute(g.save_path)
		g._setup()
		g.run_seed = 3
		g.radiance = 1240
		g.go_menu()
		await step(8)
		await shot("menu")
		scan("menu", current_scene)
		g.go_hub()
		await step(5)
		var h := current_scene
		h.tabs.current_tab = 1
		await step(3)
		await shot("hub_gifts")
		scan("hub_gifts", h)
		for id in g.gift_defs:   # все дары на уровне 1, Сияния нет: у каждой строки причина «Откроется после осады I»
			g.gift_levels[id] = 1
		g.radiance = 0
		h._refresh_gifts()
		await step(3)
		await shot("hub_gifts_locked")
		scan("hub_gifts_locked", h)
		g.gift_levels.clear()
		g.radiance = 1240
		g.start_run(1)
		await step(5)
		var m := current_scene as Node2D
		m.banner.visible = false
		m.squad_panel_sig = -1
		m._update_squad_panel()
		refresh(m)
		await shot("respite")
		scan("respite", m)
		m.card_screen.open(m.card_defs.keys().slice(0, 3), m.card_defs, [])
		await step(3)
		await shot("cards")
		scan("cards", m.card_screen)
		m.card_screen.visible = false
		m._start_wave()
		for t in 90:
			m._physics_process(DT)
		m.banner.visible = false
		refresh(m)
		await shot("battle")
		scan("battle", m)
		m.queue_free()
		await step(2)
	TranslationServer.set_locale(locale)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("SHOTS: готово, мест с обрезанным текстом %d" % clips)
	quit(0)
