extends SceneTree
# Задача 28б (без окна): название игры — в одном месте, ключ перевода TITLE_KEY (data/translations.csv), тест читает его оттуда.
#   Ключ переведён, одинаков в ru и en (название не переводится); project.godot config/name и export_presets.cfg (product_name,
#   file_description, имя исполняемого файла) — то же название; заголовок окна и заголовок главного меню — из ключа.
#   Папка данных пользователя не зависит от config/name: use_custom_user_dir и custom_user_dir_name — путь user:// прежний
#   (OS.get_data_dir() / custom_user_dir_name), сохранения и настройки после переименования на месте.
const TITLE_KEY := "GAME_TITLE"
const PRESETS := "res://export_presets.cfg"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var name_ru := String(TranslationServer.get_translation_object("ru").get_message(TITLE_KEY))
	var name_en := String(TranslationServer.get_translation_object("en").get_message(TITLE_KEY))
	check("название в переводах: «%s» (ru) и «%s» (en) — одинаковы, не пусто" % [name_ru, name_en], name_ru != "" and name_ru == name_en)
	var title := name_ru
	check("project.godot config/name — название (%s)" % ProjectSettings.get_setting("application/config/name"),
		ProjectSettings.get_setting("application/config/name") == title)
	var cf := ConfigFile.new()
	check("export_presets.cfg читается", cf.load(PRESETS) == OK)
	for s in cf.get_sections():
		if not s.ends_with(".options"):
			continue
		check("%s: product_name и file_description — название" % s, cf.get_value(s, "application/product_name", "") == title
			and cf.get_value(s, "application/file_description", "") == title)
		var exe: String = cf.get_value(s.trim_suffix(".options"), "export_path", "")
		check("%s: исполняемый файл — %s.exe (%s)" % [s, title, exe], exe.get_file() == title + ".exe")
	check("заголовок окна — название («%s»)" % root.title, root.title == title)
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check("главное меню: заголовок — ключ названия, на экране «%s»" % tr(menu.title_label.text), menu.title_label.text == TITLE_KEY and tr(menu.title_label.text) == title)
	menu.queue_free()
	# папка данных
	var custom := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	check("папка данных задана явно (use_custom_user_dir, %s), не от config/name" % custom,
		ProjectSettings.get_setting("application/config/use_custom_user_dir", false) and custom != "" and not custom.contains(title))
	check("user:// = %s" % OS.get_user_data_dir(), OS.get_user_data_dir() == OS.get_data_dir().path_join(custom)
		and ProjectSettings.globalize_path("user://save.json") == OS.get_user_data_dir().path_join("save.json"))
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
