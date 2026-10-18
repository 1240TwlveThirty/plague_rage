extends SceneTree
# Смоук v53 с окном: экран выбора карточки (задача 6, этап D) на ru и en. Забег через Game (временное сохранение), две волны усиленной армией,
# после волны 2 — экран выбора; скриншоты cards_pick_ru.png и cards_pick_en.png (и с длинными английскими карточками), проверка, что текст
# карточек помещается в карточку, а экран — в окно 1920x1080. Аргумент: папка для PNG (по умолчанию user://).
const DIR := "user://bench_v53s"
const SCREEN := Rect2(0, 0, 1920, 1080)
const LONG := ["victory_sacrifice", "reserve_fund", "first_volley"]   # самые длинные описания на английском
var fails := 0
var out_dir := ""

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await step(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name))

# Карточки целиком на экране, их надписи — внутри карточки.
func fits(screen: CanvasLayer) -> Array:
	var bad := []
	for b in screen.buttons:
		var r: Rect2 = b.get_global_rect()
		if not SCREEN.encloses(r):
			bad.append("карточка %s за экраном" % str(r))
		for c in b.find_children("*", "Control", true, false):
			if (c is Label or c is RichTextLabel) and not r.grow(1.0).encloses(c.get_global_rect()):
				bad.append("%s: %s" % [c.name, str(c.get_global_rect())])
	return bad

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var g: Node = root.get_node_or_null("Game")
	if g == null:
		print("SMOKE: нет автозагрузки Game")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	for arr in [m.base_type_hp, m.type_hp]:
		arr[m.infantry_type] *= 10.0
		arr[m.archer_type] *= 10.0
	for i in m.count:
		m.hp[i] = m.type_hp[m.unit_type[i]] if m.team[i] == 0 else m.hp[i]
	for w in 2:
		m._start_wave()
		var t := 0
		while m.wave_state == m.WS_BATTLE and t < 30 * 900:
			m._physics_process(1.0 / 30.0)
			t += 1
	m._update_ui()
	check("после волны 2 экран выбора открыт, 3 карточки", m.card_screen.visible and m.card_screen.buttons.size() == 3)
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		m.card_screen.open(m.pending_offer, m.card_defs, [])
		await shot("cards_pick_%s.png" % loc)
		var bad := fits(m.card_screen)
		check("%s: карточки на экране, текст внутри карточек" % loc, bad.is_empty(), ", ".join(bad))
		m.card_screen.open(LONG, m.card_defs, ["CARD_PURSE_NAME", "CARD_MARAUDERS_NAME"])
		await shot("cards_pick_%s_long.png" % loc)
		bad = fits(m.card_screen)
		check("%s, длинные описания (%s): текст внутри карточек" % [loc, ", ".join(LONG)], bad.is_empty(), ", ".join(bad))
	TranslationServer.set_locale("ru")
	m.card_screen.open(m.pending_offer, m.card_defs, [])
	m.choose_card(m.pending_offer[0])
	m._update_ui()
	await shot("cards_hud_ru.png")
	check("после выбора HUD показывает список карточек", m.cards_label.visible and m.cards_label.text != "" and SCREEN.encloses(m.cards_label.get_global_rect()))
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
