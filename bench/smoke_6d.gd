extends SceneTree
# Смоук задачи 6d с окном: забег через Game с «Лазаретом» 3 (временное сохранение). Волна 1 — после победы павшие вернулись в отряды
# (число в отряде выросло к передышке, run_recovered > 0); магазин передышки: «Оружие: скорость атаки +10%» (ru) и «Weapons: attack speed +10%» (en);
# экран выбора с карточками на скорости атаки и №40 «Полевой госпиталь» — текст помещается в карточки. Скриншоты в папку из аргумента.
const DIR := "user://bench_6d"
const SCREEN := Rect2(0, 0, 1920, 1080)
const PICK := ["meteor_blades", "field_kitchen", "last_stand"]
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
	g.gift_levels["infirmary"] = 3
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	check("забег через Game: «Лазарет» 3 в наборе, доля возврата 0.30", m.active_gifts.get("infirmary", 0) == 3 and is_equal_approx(m.recover_fraction(), 0.3))
	m._start_wave()
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 900:
		m._physics_process(1.0 / 30.0)
		t += 1
	var start: int = m.squad_start_n[0] + m.squad_start_n[1]
	var fallen: int = m.squad_fallen[0] + m.squad_fallen[1]
	var after: int = m.squad_n[0] + m.squad_n[1]
	check("волна 1 побеждена: в начале %d, пало %d, вернулось %d (30%% по отрядам, вниз), стало %d" % [start, fallen, m.wave_recovered, after], m.wave_state == m.WS_RESPITE
		and m.wave_recovered > 0 and after == start - fallen + m.wave_recovered and m.wave_recovered == floori(m.squad_fallen[0] * 0.3 + 1e-9) + floori(m.squad_fallen[1] * 0.3 + 1e-9))
	m._update_ui()
	var k: int = m.SHOP_ITEMS.find("weapons")
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		m.ui_t = 0.0
		m._update_ui()
		await shot("6d_respite_%s.png" % loc)
		var want := "Оружие: скорость атаки +10%" if loc == "ru" else "Weapons: attack speed +10%"
		check("%s: строка магазина «%s»" % [loc, m.shop_buttons[k].text], m.shop_buttons[k].text.contains(want) and m.shop_buttons[k].visible)
		m.card_screen.open(PICK, m.card_defs, [])
		await shot("6d_cards_%s.png" % loc)
		var bad := fits(m.card_screen)
		check("%s: карточки №1, №40, №17 на экране выбора, текст внутри" % loc, bad.is_empty(), ", ".join(bad))
		m.card_screen.visible = false
	TranslationServer.set_locale("ru")
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
