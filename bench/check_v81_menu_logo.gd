extends SceneTree
# Задача 28в, этап 1 (без окна): логотип в главном меню. Два дочерних процесса (лог каждого — свой, ищутся ошибки и предупреждения):
#   с логотипом — копия art/ui/ui_logo.png во временной папке системы (настоящий файл не трогается); без — путь к несуществующему
#   файлу в той же папке. С логотипом: TextureRect в натуральный размер файла, nearest, stretch keep, позиция целая, по центру
#   по горизонтали, сверху на logo_top_margin; кнопки — на title_gap ниже логотипа, между кнопками button_gap (data/ui_layout.json menu).
#   Без: текстовый заголовок (ключ GAME_TITLE) на том же месте, кнопки на title_gap ниже. В логе обоих — ни ошибок, ни предупреждений
#   о логотипе.
#   Если настоящий файл есть — меню по умолчанию показывает его.
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "child":
		await _child(args[1])
		return
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json")).menu
	var real: String = cfg.logo_path
	var tmp := OS.get_temp_dir().path_join("plague_v81_logo_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(tmp)
	var copy := tmp.path_join("logo.png")
	var have_real := ResourceLoader.exists(real)
	if have_real:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(real), copy)
	else:   # файла логотипа нет в рабочей копии: картинка-заглушка того же вида (RGBA, чётные размеры)
		var img := Image.create(40, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color("#feae34"))
		img.save_png(copy)
	var size := Image.load_from_file(copy).get_size()
	for c in [[copy, true], [tmp.path_join("missing.png"), false]]:
		var out := []
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://bench/check_v81_menu_logo.gd",
			"--", "child", c[0]], out, true)
		var text: String = "".join(out)
		var line := ""
		for l in text.split("\n"):
			if l.begins_with("MENU81|"):
				line = l.strip_edges()   # Windows: строки вывода с 
		# ошибки — любые; предупреждения — про логотип (прочие, например нет арта тёмной панели настроек, к задаче не относятся)
		var bad := RegEx.create_from_string("(?m)^(ERROR|SCRIPT ERROR).*|Parse Error.*|Failed to load.*|^WARNING:.*(logo|" + c[0].get_file() + ").*").search(text)
		check("%s: дочерний процесс без ошибок в логе (код %d)%s" % ["с логотипом" if c[1] else "без файла", code,
			"" if bad == null else ": " + bad.get_string()], code == 0 and bad == null and line != "")
		var p := line.split("|")
		if p.size() < 9:
			fails += 1
			print(text)
			continue
		var head_rect: Rect2 = str_to_var(p[2])
		var play: Rect2 = str_to_var(p[3])
		var settings: Rect2 = str_to_var(p[4])
		var view: Vector2 = str_to_var(p[5])
		if c[1]:
			check("логотип: натуральный размер файла %s (на экране %s), nearest, stretch keep, позиция целая %s" % [str(size), str(head_rect.size), str(head_rect.position)],
				p[1] == "logo" and head_rect.size == Vector2(size) and p[6] == "nearest_keep" and head_rect.position == head_rect.position.round())
		else:
			check("без файла: текстовый заголовок «%s» (ключ GAME_TITLE)" % p[7], p[1] == "title" and p[7] != "" and p[7] == p[8])
		check("%s: сверху на logo_top_margin %d (%.0f), по центру (%.1f из %.0f)" % [p[1], int(cfg.logo_top_margin), head_rect.position.y,
			head_rect.get_center().x, view.x], is_equal_approx(head_rect.position.y, float(cfg.logo_top_margin)) and absf(head_rect.get_center().x - view.x * 0.5) <= 0.5)
		check("%s: «Играть» на title_gap %d ниже (%.0f), «Настройки» на button_gap %d ниже «Играть», кнопки по центру" % [p[1], int(cfg.title_gap),
			play.position.y - head_rect.end.y, int(cfg.button_gap)], is_equal_approx(play.position.y - head_rect.end.y, float(cfg.title_gap))
			and is_equal_approx(settings.position.y - play.end.y, float(cfg.button_gap)) and absf(play.get_center().x - view.x * 0.5) <= 0.5
			and play.end.y <= view.y)
	DirAccess.remove_absolute(copy)
	DirAccess.remove_absolute(tmp)
	if have_real:
		var menu: Control = load("res://scenes/menu.tscn").instantiate()
		root.add_child(menu)
		await process_frame
		check("по умолчанию меню показывает %s" % real, menu.logo != null and menu.title_label == null and menu.logo.texture.resource_path == real)
		menu.queue_free()
	else:
		print("  (файла %s нет в рабочей копии: меню по умолчанию — текстовый заголовок)" % real)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Дочерний процесс: меню с логотипом path; печатает MENU81|logo или title|прямоугольник|«Играть»|«Настройки»|экран|фильтр|текст|название.
func _child(path: String) -> void:
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.logo_path = path
	root.add_child(menu)
	for i in 3:
		await process_frame
	var head: Control = menu.logo if menu.logo != null else menu.title_label
	var mode := "-"
	if menu.logo != null:
		mode = "nearest_keep" if menu.logo.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and menu.logo.stretch_mode == TextureRect.STRETCH_KEEP else "other"
	print("MENU81|%s|%s|%s|%s|%s|%s|%s|%s" % ["logo" if menu.logo != null else "title", var_to_str(head.get_global_rect()), var_to_str(menu.play_button.get_global_rect()),
		var_to_str(menu.settings_button.get_global_rect()), var_to_str(root.get_visible_rect().size), mode,
		tr(menu.title_label.text) if menu.title_label != null else "", tr("GAME_TITLE")])
	quit(0)
