extends SceneTree
# Задача 33 (без окна): фоны главного меню и хаба. Настройки — data/ui_layout.json bg; тест читает их оттуда. Своё временное
# сохранение (user://bench_v86).
#   Меню и хаб: фон — TextureRect с картинкой bg.<menu|hub>_path на весь экран, режим по bg.mode (cover — KEEP_ASPECT_COVERED),
#   фильтр линейный, мышь сквозь; над ним — ColorRect затемнения: прозрачность dim_<menu|hub>, цвет dim_color, мышь сквозь.
#   Фон и затемнение — первые дети сцены (ниже логотипа, кнопок, вкладок, дневника, меню Esc).
#   Несуществующий путь (res:// и файл на диске) — прежний ColorRect UI.BG_COLOR, без ошибки; файл с диска (копия картинки
#   во временной папке) — грузится.
const DIR := "user://bench_v86"
const UI := preload("res://scripts/ui.gd")
const MODES := {"cover": TextureRect.STRETCH_KEEP_ASPECT_COVERED, "contain": TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "stretch": TextureRect.STRETCH_SCALE}
var fails := 0
var cfg: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)
	_run.call_deferred()

# Фон сцены по данным: картинка, режим, фильтр, на весь экран, мышь сквозь; затемнение — dim_<which>; оба ниже остальных узлов.
func check_scene(s: Control, which: String) -> void:
	var b: Control = s.bg
	var d: ColorRect = s.bg_dim
	var view := s.get_viewport_rect().size
	var tex_ok: bool = b is TextureRect and (b as TextureRect).texture != null and (b as TextureRect).texture.resource_path == str(cfg[which + "_path"])
	check("%s: фон — картинка %s" % [which, cfg[which + "_path"]], tex_ok, b.get_class())
	if not tex_ok:
		return
	var t := b as TextureRect
	check("%s: режим %s, фильтр линейный, на весь экран %s, мышь сквозь" % [which, cfg.mode, str(b.size)],
		t.stretch_mode == MODES[cfg.mode] and t.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR and t.expand_mode == TextureRect.EXPAND_IGNORE_SIZE
		and b.get_global_rect() == Rect2(Vector2.ZERO, view) and b.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var want := Color(str(cfg.dim_color))
	want.a = float(cfg["dim_" + which])
	check("%s: затемнение из данных — %s (у узла %s), видно только при > 0, на весь экран, мышь сквозь" % [which, str(want), str(d.color)],
		d.color.is_equal_approx(want) and d.visible == (want.a > 0.0) and d.get_global_rect() == Rect2(Vector2.ZERO, view)
		and d.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var others := s.get_children().filter(func(c): return c != b and c != d)
	check("%s: фон и затемнение — первые дети, остальных узлов %d — выше" % [which, others.size()],
		s.get_child(0) == b and s.get_child(1) == d and others.size() > 0 and others.all(func(c): return c.get_index() > 1))

# Сцена script с другим файлом фона: path -> ожидается ColorRect UI.BG_COLOR (missing) или картинка.
func with_path(script: String, path: String) -> Control:
	var s: Control = load(script).new()
	s.bg_path = path
	root.add_child(s)
	await step(2)
	return s

func _run() -> void:
	cfg = UI.bg_cfg()
	var g: Node = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	print("данные: %s" % str(cfg))
	check("bg в data/ui_layout.json: пути, режим, затемнения 0..1", ResourceLoader.exists(cfg.menu_path) and ResourceLoader.exists(cfg.hub_path)
		and MODES.has(cfg.mode) and float(cfg.dim_menu) >= 0.0 and float(cfg.dim_menu) <= 1.0 and float(cfg.dim_hub) >= 0.0 and float(cfg.dim_hub) <= 1.0)
	g.go_menu()
	await step(3)
	var mn: Control = current_scene
	check_scene(mn, "menu")
	g.go_hub()
	await step(3)
	var h: Control = current_scene
	check_scene(h, "hub")
	h._open_diary()
	await step(2)
	check("хаб: дневник открыт поверх фона", h.diary_panel.is_visible_in_tree() and h.bg.get_index() == 0)
	g.go_menu()
	await step(3)
	# несуществующий путь: прежний чёрный ColorRect, без ошибки
	var tmp := OS.get_temp_dir().path_join("plague_v86_bg_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(tmp)
	for sc in [["res://scripts/menu.gd", "menu"], ["res://scripts/hub.gd", "hub"]]:
		for p in ["res://art/ui/__no_bg_v86__.png", tmp.path_join("missing.png")]:
			var s: Control = await with_path(sc[0], p)
			var b: Control = s.bg
			check("%s, файла нет (%s): фон — ColorRect UI.BG_COLOR на весь экран, первый ребёнок, затемнение над ним" % [sc[1], p],
				b is ColorRect and (b as ColorRect).color == UI.BG_COLOR and b.size == s.get_viewport_rect().size and s.get_child(0) == b and s.get_child(1) == s.bg_dim)
			s.free()
		# файл с диска (копия картинки из данных): грузится
		var copy := tmp.path_join(sc[1] + ".png")
		DirAccess.copy_absolute(ProjectSettings.globalize_path(cfg[sc[1] + "_path"]), copy)
		var s2: Control = await with_path(sc[0], copy)
		var t2 := s2.bg as TextureRect
		check("%s, файл с диска: картинка %s" % [sc[1], str(t2.texture.get_size()) if t2 != null else "нет"],
			t2 != null and Vector2i(t2.texture.get_size()) == Image.load_from_file(copy).get_size())
		s2.free()
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp.path_join(f))
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
