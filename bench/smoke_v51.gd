extends SceneTree
# Смоук v51 с окном: язык ru / en. Скриншоты главного меню, хаба (обе вкладки), паузы, боя и настроек на обоих языках;
# смена языка сразу, без перезапуска (в том числе баннер и HUD боя); на английском ничего не вылезает за экран, текст
# кнопок помещается в кнопку. Аргумент: папка для PNG (по умолчанию user://). Сохранение и настройки — временные.
const DIR := "user://bench_v51"
const SCREEN := Rect2(0, 0, 1920, 1080)
var fails := 0
var out_dir := ""
var st: Node
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await step(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name))

# Видимые Label и Button под узлом: целиком на экране, у кнопок текст не шире кнопки. Пустой массив — всё в порядке.
func overflow(node: Node) -> Array:
	var bad := []
	_overflow(node, bad)
	return bad

func _overflow(node: Node, bad: Array) -> void:
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	if node is ScrollContainer:
		return   # содержимое прокрутки может уходить за край
	if (node is Label or node is Button) and (node as Control).get_global_rect().size.x > 0.0:
		var c := node as Control
		var r := c.get_global_rect()
		if not SCREEN.grow(1.0).encloses(r):
			bad.append("%s за экраном %s" % [c.name if c.text == "" else tr(c.text), r])
		elif c is Button and c.get_minimum_size().x > r.size.x + 1.0:
			bad.append("«%s» шире кнопки" % tr(c.text))
	for ch in node.get_children():
		_overflow(ch, bad)

func lang(l: String) -> void:
	st.set_language(l)
	await step(3)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	print("SMOKE v51: языки ru / en")
	st = root.get_node("Settings")
	g = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	st.path = DIR + "/settings.cfg"
	st.persist = true
	g.save_path = DIR + "/save.json"
	g._setup()
	g.radiance = 150
	for l in ["ru", "en"]:
		await lang(l)
		check("%s: TranslationServer.get_locale" % l, TranslationServer.get_locale() == l)
		g.go_menu()
		await step(4)
		var mn := current_scene
		check("%s: меню — «%s»" % [l, tr("UI_MENU_PLAY")], tr(mn.play_button.text) == ("Играть" if l == "ru" else "Play"), tr(mn.play_button.text))
		check("%s: меню помещается" % l, overflow(mn).is_empty(), ", ".join(overflow(mn)))
		await shot("v51_menu_%s.png" % l)
		mn.settings_button.pressed.emit()
		await step(2)
		var sm: CanvasLayer = mn.settings_menu
		for t in sm.tabs.get_tab_count():
			sm.tabs.current_tab = t
			await step(2)
			check("%s: настройки, вкладка %s помещается" % [l, tr(sm.tabs.get_tab_title(t))], overflow(sm).is_empty(), ", ".join(overflow(sm)))
			await shot("v51_settings_%d_%s.png" % [t, l])
		sm.close()
		g.go_hub()
		await step(4)
		var h := current_scene
		check("%s: хаб, вкладка «Осада» помещается" % l, overflow(h).is_empty(), ", ".join(overflow(h)))
		await shot("v51_hub_%s.png" % l)
		h.tabs.current_tab = 1
		await step(2)
		check("%s: хаб, вкладка «Дары» помещается" % l, overflow(h).is_empty(), ", ".join(overflow(h)))
		await shot("v51_hub_gifts_%s.png" % l)
		h.tabs.current_tab = 0
		g.start_run(1)
		await step(6)
		var m := current_scene
		check("%s: бой — HUD «%s»" % [l, m.hud_label.text.get_slice(" ", 0)], m.hud_label.text.begins_with("Волна" if l == "ru" else "Wave"), m.hud_label.text.get_slice("\n", 0))
		check("%s: бой — интерфейс помещается" % l, overflow(m).is_empty(), ", ".join(overflow(m)))
		await shot("v51_battle_%s.png" % l)
		m._open_esc_menu()
		await step(3)
		check("%s: пауза помещается" % l, overflow(m.esc_menu).is_empty(), ", ".join(overflow(m.esc_menu)))
		await shot("v51_pause_%s.png" % l)
		m.esc_menu.close()
		await step(2)
		if l == "en":
			# смена языка прямо в бою: баннер, HUD и подписи пересобираются сразу
			await lang("ru")
			await step(4)
			check("в бою en -> ru: баннер и HUD на русском", m.banner_parts[3].begins_with("Расставь") and m.hud_label.text.begins_with("Волна")
				and m.action_buttons[0].text.begins_with("+ Отряд"), "%s | %s" % [m.banner_parts[3], m.hud_label.text.get_slice("\n", 0)])
			await lang("en")
			await step(4)
			check("в бою ru -> en: баннер и HUD на английском", m.banner_parts[3].begins_with("Position") and m.hud_label.text.begins_with("Wave")
				and m.action_buttons[0].text.begins_with("+ Squad"), "%s | %s" % [m.banner_parts[3], m.hud_label.text.get_slice("\n", 0)])
		m._abandon_run()
	var cfg := ConfigFile.new()
	check("язык сохранён в settings.cfg (general/language = en)", cfg.load(st.path) == OK and cfg.get_value("general", "language", "") == "en")
	st.language = "ru"
	st.load_settings()
	check("«перезапуск»: язык из файла — en", st.language == "en" and TranslationServer.get_locale() == "en")
	st.set_language("ru")
	st.persist = false
	print("SMOKE: провалов %d" % fails)
	quit()
