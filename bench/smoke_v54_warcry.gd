extends SceneTree
# Смоук v54 с окном: кнопка «Клич Благодати» в боевом HUD (задача 7). Забег через Game с купленным даром war_cry 1 (временное сохранение),
# волна 1: скриншоты warcry_ready.png (готов), warcry_active.png (действует: кнопка золотая, таймер, подсветка краёв), warcry_cooldown.png
# (перезарядка, заполнение полосы), warcry_respite.png (передышка) и warcry_en_active.png; кнопка целиком на экране, текст в кнопке;
# без дара кнопки нет. Аргумент: папка для PNG (по умолчанию user://).
const DIR := "user://bench_v54s"
const SCREEN := Rect2(0, 0, 1920, 1080)
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

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func ticks(m: Node2D, n: int) -> void:
	for i in n:
		if m.wave_state != m.WS_BATTLE:
			return
		m._physics_process(1.0 / 30.0)

func fits(m: Node2D) -> bool:
	var r: Rect2 = m.war_cry_button.get_global_rect()
	return SCREEN.encloses(r) and m.war_cry_button.get_theme_font("font").get_string_size(m.war_cry_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		m.war_cry_button.get_theme_font_size("font_size")).x <= r.size.x

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
	g.card_rules_path = ""
	g.card_rules = {}
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	check("без дара кнопки клича нет", m.war_cry_button == null and m.war_cry_level == 0)
	g.gift_levels["war_cry"] = 1
	g.start_run(1)
	await step(5)
	m = current_scene as Node2D
	check("дар куплен: кнопка под списком отрядов", m.war_cry_button != null and m.war_cry_button.is_visible_in_tree() and m.war_cry_box.get_parent() == m.squad_panel)
	m._update_ui()
	await shot("warcry_respite.png")
	check("передышка: «— только в бою», кнопка неактивна", tr(m.war_cry_button.text).contains("только в бою") and m.war_cry_button.disabled, m.war_cry_button.text)
	for t in [m.zombie_type, m.runner_type, m.knight_type]:   # бой не кончается сам: зомби бессмертны и не бьют
		m.base_type_hp[t] = 1e6
		m.base_type_damage[t] = 0.0
	m._start_wave()
	ticks(m, 30 * 14)   # орда подходит
	m._update_ui()
	await shot("warcry_ready.png")
	check("бой, готов: «[U] Клич Благодати» (задача 10: D — движение героя), кнопка активна, полоса полная, на экране", m.war_cry_button.text.begins_with("[U]") and not m.war_cry_button.disabled
		and m.war_cry_bar.value == 1.0 and fits(m), m.war_cry_button.text)
	m.war_cry_button.pressed.emit()   # клик по кнопке
	ticks(m, 30 * 3)
	m._update_ui()
	await shot("warcry_active.png")
	check("действует: золотая кнопка с таймером, полоса убывает, подсветка краёв видна", m.war_cry_until >= 0 and m.war_cry_button.text.contains("ещё")
		and m.war_cry_bar.value < 1.0 and m.war_cry_glow.size() == 4 and m.war_cry_glow.all(func(r): return r.visible) and fits(m), m.war_cry_button.text)
	TranslationServer.set_locale("en")
	m._update_ui()
	await shot("warcry_en_active.png")
	check("en: текст в кнопке", fits(m), m.war_cry_button.text)
	TranslationServer.set_locale("ru")
	ticks(m, 30 * 7)
	m._update_ui()
	await shot("warcry_cooldown.png")
	check("перезарядка: «Клич через N с», кнопка неактивна, полоса заполняется, подсветки нет", m.war_cry_until == -1 and m.war_cry_button.text.contains("через")
		and m.war_cry_button.disabled and m.war_cry_bar.value > 0.0 and m.war_cry_bar.value < 1.0 and not m.war_cry_glow[0].visible, m.war_cry_button.text)
	m.queue_free()
	await step(2)
	g.gift_levels["war_cry"] = 0
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
