extends SceneTree
# Смоук v64 с окном (задача 14): экран выбора карточки с карточками героя на ru и en. Забег через Game (временное сохранение,
# герой включён как в игре), две волны усиленной армией, после волны 2 — тройка с гарантированной карточкой героя.
# Скриншоты: настоящая тройка (cards_hero_pick_ru/en.png), все пять карточек героя (cards_hero_41_43_*.png, cards_hero_44_45_*.png),
# HUD с выбранными 44 и 45 (cards_hero_hud_ru.png). Проверки: текст внутри карточек, экран в окне 1920x1080, подсказки условий.
# Аргумент: папка для PNG (по умолчанию user://).
const DIR := "user://bench_v64s"
const SCREEN := Rect2(0, 0, 1920, 1080)
const CARDS := preload("res://scripts/cards.gd")
const A := ["wide_swing", "quick_hands", "commander_temper"]
const B := ["last_bastion", "commander_banner", "purse"]
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
	if not m.hero_on:
		print("  hero.json enabled false: карточек героя в игре нет — смоук пропущен")
		print("SMOKE: провалов 0")
		quit(0)
		return
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
	var heroes: Array = m.pending_offer.filter(func(id): return CARDS.is_hero(m.card_defs[id]))
	check("после волны 2 экран выбора открыт, 3 разные карточки, из них карточек героя %d (не меньше 1)" % heroes.size(), m.card_screen.visible
		and m.card_screen.buttons.size() == 3 and heroes.size() >= 1 and m.pending_offer[0] != m.pending_offer[1] and m.pending_offer[1] != m.pending_offer[2]
		and m.pending_offer[0] != m.pending_offer[2], str(m.pending_offer))
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		m.card_screen.open(m.pending_offer, m.card_defs, [])
		await shot("cards_hero_pick_%s.png" % loc)
		var bad := fits(m.card_screen)
		check("%s: настоящая тройка — карточки на экране, текст внутри" % loc, bad.is_empty(), ", ".join(bad))
		for set in [A, B]:
			m.card_screen.open(set, m.card_defs, [])
			var name := "cards_hero_41_43_%s.png" % loc if set == A else "cards_hero_44_45_%s.png" % loc
			await shot(name)
			bad = fits(m.card_screen)
			var tags: Array = m.card_screen.buttons.map(func(b): return b.find_children("*", "Label", true, false).map(func(l): return l.text))
			check("%s: %s — описания влезают, метка билда «%s» на карточках героя" % [loc, ", ".join(set), tr("UI_BUILD_HERO")], bad.is_empty()
				and tags.slice(0, 2).all(func(t): return "UI_BUILD_HERO" in t), ", ".join(bad))   # надписи — ключи перевода (автоперевод)
	TranslationServer.set_locale("ru")
	m.card_screen.open(m.pending_offer, m.card_defs, [])
	g.run_cards = [{"id": "last_bastion"}, {"id": "commander_banner"}]
	m.pending_offer = []
	m.card_screen.hide()
	m._prepare_cards()
	m._update_ui()
	await shot("cards_hero_hud_ru.png")
	var tips: Array = m.cards_rows.map(func(l): return l.tooltip_text)
	check("HUD: строки 44 и 45, подсказки с условием «ниже 40%%» и «%d px» (hero_near_radius)" % int(m.hero_near_r), m.cards_rows.size() == 2 and tips.size() == 2
		and "40%" in tips[0] and ("%d" % int(m.hero_near_r)) in tips[1],
		" | ".join(tips).replace("\n", " / "))
	g.run_cards = []
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
