extends SceneTree
# Тесты задачи 20 (без окна): варианты шрифта из data/ui_theme.json. Файлы шрифтов загружаются, в импорте сглаживание, хинтинг
# и субпиксельное позиционирование выключены; кегли игры (собраны из scripts/*.gd и data/ui_layout.json, не зашиты) через
# FONTS.px: default — без изменений, пиксельный — допустимый (родной x k, k >= fonts.min_scale) по правилу fonts.rounding
# (задача 21: ближайший, при равной разнице больший); контур не толще outline_max; подгонка текста кнопок — только допустимые. Печатает таблицу кеглей «KEGL|заданный|default|fusion12|...». Хаб: на вкладке «Дары» с
# причинами отказа у всех строк таблица целиком на экране (баг «Откроется после осады…» за правым краем).
# Временное сохранение user://bench_v70 (user://save.json не трогается).
const FONTS := preload("res://scripts/fonts.gd")
const DIR := "user://bench_v70"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

# Кегли, заданные в коде: FONTS.px(N), константы FONT / GIFT_FONT / FIT_MIN_FONT / DEFAULT_SIZE, размеры в вызовах _label,
# _text, _diary_text; кегли окошек верхней панели — из ui_layout.json.
func game_sizes() -> Array:
	var found := {}
	var consts := {}
	var lit := RegEx.create_from_string("FONTS\\.px\\((\\d+)")
	var named := RegEx.create_from_string("FONTS\\.px\\(([A-Z_]+)")
	var cdef := RegEx.create_from_string("^const ([A-Z_]+) := (\\d+)\\b")
	var helper := RegEx.create_from_string("_(?:label|text|diary_text)\\([^\\n]*?, (\\d+)[,)]")
	var srcs := {}
	for name in DirAccess.get_files_at("res://scripts"):
		if name.ends_with(".gd"):
			srcs[name] = FileAccess.get_file_as_string("res://scripts/" + name)
	for name in srcs:
		for line in srcs[name].split("\n"):
			var m := cdef.search(line)
			if m != null:
				consts[m.get_string(1)] = int(m.get_string(2))
	for name in srcs:
		for m in lit.search_all(srcs[name]):
			found[int(m.get_string(1))] = true
		for m in named.search_all(srcs[name]):
			if consts.has(m.get_string(1)):
				found[consts[m.get_string(1)]] = true
		for m in helper.search_all(srcs[name]):
			found[int(m.get_string(1))] = true
	found[FONTS.DEFAULT_SIZE] = true
	var lay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	found[int(lay.top_hud.font_size)] = true
	found[int(lay.top_hud.font_min)] = true
	var out := found.keys()
	out.sort()
	return out

# p — допустимый (n x k, k >= ms) и по правилу: nearest — ближе всех к s среди допустимых, при равной разнице больший; down — наибольший не больше s.
func allowed_ok(p: int, s: int, n: int, ms: int, rule: String) -> bool:
	if p % n != 0 or p < n * ms:
		return false
	for k in range(ms, ms + 20):
		var q := n * k
		if q == p:
			continue
		if rule == "down":
			if q <= s and q > p:
				return false
		elif absi(q - s) < absi(p - s) or (absi(q - s) == absi(p - s) and q > p):
			return false
	return rule != "down" or p <= s or p == n * ms

func _run() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_theme.json"))
	var variants: Dictionary = cfg.fonts.variants
	print("варианты: %s, по умолчанию %s" % [", ".join(variants.keys()), cfg.font_variant])
	check("font_variant по умолчанию — default (вид как раньше, пока не выбран другой)", cfg.font_variant == "default" and variants.has("default"))
	var sizes := game_sizes()
	print("кегли в игре: %s" % ", ".join(sizes.map(func(x): return str(x))))
	var pixel := []
	for v in variants:
		var d: Dictionary = variants[v]
		if not d.has("file"):
			continue
		pixel.append(v)
		var font := load(d.file) as FontFile
		var imp := ConfigFile.new()
		var ok_imp := imp.load(d.file + ".import") == OK
		check("%s: %s загружается, родной кегль %d, контур не толще %d" % [v, d.file.get_file(), int(d.native), int(d.outline_max)], font != null and int(d.native) > 0)
		check("%s: импорт без сглаживания, хинтинга и субпиксельного позиционирования, без системной подмены" % v, ok_imp
			and imp.get_value("params", "antialiasing", -1) == 0 and imp.get_value("params", "hinting", -1) == 0
			and imp.get_value("params", "subpixel_positioning", -1) == 0 and imp.get_value("params", "allow_system_fallback", true) == false
			and imp.get_value("params", "generate_mipmaps", true) == false and imp.get_value("params", "multichannel_signed_distance_field", true) == false)
	# таблица кеглей
	var head := ["заданный"]
	var rows := {}
	FONTS.reset("default")
	var same := true
	for s in sizes:
		rows[s] = [str(s), str(FONTS.px(s))]
		same = same and FONTS.px(s) == s and FONTS.outline(8) == 8
	head.append("default")
	check("default: кегли и контуры как заданы", same)
	for v in pixel:
		FONTS.reset(v)
		FONTS.load_cfg()
		var n: int = FONTS.native
		var ok: bool = FONTS.variant == v and n == int(variants[v].native)
		for s in sizes:
			var p := FONTS.px(s)
			rows[s].append(str(p))
			ok = ok and allowed_ok(p, s, n, FONTS.min_scale, FONTS.rounding)
		var fit := FONTS.fit_sizes(FONTS.DEFAULT_SIZE, 11)
		ok = ok and fit.all(func(f): return f % n == 0) and FONTS.outline(8) == int(variants[v].outline_max) and FONTS.outline(1) == 1
		head.append(v)
		check("%s: кегль — %d x k, k >= %d, правило %s (ближайший, при равной разнице больший); подгонка кнопок %s; контур 8 -> %d" % [v, n,
			FONTS.min_scale, FONTS.rounding, str(fit), FONTS.outline(8)], ok and FONTS.min_scale == int(cfg.fonts.get("min_scale", 2))
			and FONTS.rounding == str(cfg.fonts.get("rounding", "nearest")))
	FONTS.reset()
	print("KEGL|" + "|".join(head))
	for s in sizes:
		print("KEGL|" + "|".join(rows[s]))
	await t_hub()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_hub() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	g.radiance = 0
	for id in g.gift_defs:
		g.gift_levels[id] = 1   # следующий уровень требует пройденной осады: у каждой строки «Откроется после осады I»
	var scr := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	for l in ["ru", "en"]:
		TranslationServer.set_locale(l)
		g.go_hub()
		await step(3)
		var h := current_scene
		h.tabs.current_tab = 1
		await step(3)
		var reasons := 0
		var cut := 0
		for id in h.gift_rows:
			var r: Label = h.gift_rows[id].reason
			if r.text != "":
				reasons += 1
				cut += 1 if r.is_visible_in_tree() and r.get_global_rect().end.x > scr.end.x else 0
		var pr: Rect2 = h.gifts_panel.get_global_rect()
		check("%s: «Дары» с причинами отказа (%d строк): панель %s на экране, причины не за краем, полный текст — в подсказке" % [l, reasons, str(pr)],
			reasons > 0 and scr.encloses(pr) and cut == 0 and h.gift_rows.values().all(func(r): return r.reason.tooltip_text == r.reason.text))
	TranslationServer.set_locale("ru")
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
