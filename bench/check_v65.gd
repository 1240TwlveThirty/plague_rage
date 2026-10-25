extends SceneTree
const FONTS := preload("res://scripts/fonts.gd")   # контур и кегли — под шрифт по умолчанию (задача 22)
# Тесты задачи 15 (без окна): спрайтшит героя — сетка и анимации из hero.json, ошибки в данных — прежнее поведение (вся картинка,
# отражение); кадр удара растянут на вспышку arc_fx_time. Иллюстрации отрядов — data/unit_portraits.json: вырезка с пропорциями
# кнопки, уменьшенные копии art/ui совпадают с данными, другой crop — полоса из исходника при запуске, неверные записи отбрасываются,
# у кнопок без типа иллюстрации нет.
const MAIN := "res://scripts/main.gd"
const PORTRAITS := preload("res://scripts/portraits.gd")
var fails := 0
var SHOP: Vector2i    # кнопки из data/ui_layout.json (читаются в _run; тесты не зашивают размеры макета)
var SQUAD: Vector2i

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make() -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = 3
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.hero_mode = 1
	m._setup_data()
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await process_frame
	var lay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	SHOP = Vector2i(int(lay.shop_button_size[0]), int(lay.shop_button_size[1]))
	SQUAD = Vector2i(int(lay.squad_button_size[0]), int(lay.squad_button_size[1]))
	t_sheet()
	t_portraits()
	t_layout()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Сетка из hero_cfg (с правками patch) на новом спрайте; возвращает спрайт.
func sheet(m: Node2D, patch: Dictionary) -> Sprite2D:
	var cfg: Dictionary = m.hero_cfg.duplicate(true)
	cfg.merge(patch, true)
	for k in patch:
		if patch[k] == null:
			cfg.erase(k)
	var keep: Dictionary = m.hero_cfg
	m.hero_cfg = cfg
	if m.hero_sprite != null:
		m.hero_sprite.free()
	m.hero_sprite = Sprite2D.new()
	var tex: Texture2D = load(cfg.get("sprite_path", "res://art/knight_player.png"))
	m.hero_sprite.texture = tex
	m.hero_sprite.scale = m._hero_sprite_scale(tex.get_height())
	m._setup_hero_sheet(tex)
	m.hero_cfg = keep
	return m.hero_sprite

func t_sheet() -> void:
	print("спрайтшит героя")
	var m := make()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	var tex: Texture2D = load(d.sprite_path)
	check("hero.json: sprite_path %s (%dx%d), кадр %sx%s, кадров %s, анимации %s" % [d.sprite_path, tex.get_width(), tex.get_height(), d.frame_w, d.frame_h,
		d.frames, ", ".join(d.animations.keys())], d.sprite_path == "res://art/knight_player.png" and not d.has("sprite") and d.animations.has("idle")
		and d.animations.has("attack") and int(tex.get_width()) % int(d.frame_w) == 0 and int(tex.get_height()) % int(d.frame_h) == 0)
	var s := sheet(m, {})
	var knight_px: float = m.KNIGHT_SPRITE_SCALE * m.SPRITE_PX
	check("сетка: %d x %d кадров, анимаций %d, orient %s; кадр %s px по высоте = %.1f px мира = рыцарь (%.1f) x hero_screen_scale_rel %s" % [s.hframes, s.vframes,
		m.hero_anims.size(), d.orient, d.frame_h, s.scale.y * d.frame_h, knight_px, d.hero_screen_scale_rel], s.hframes == tex.get_width() / int(d.frame_w)
		and s.vframes == tex.get_height() / int(d.frame_h) and m.hero_anims.size() == d.animations.size() and m.hero_rotate == (d.orient == "rotate")
		and is_equal_approx(s.scale.y * d.frame_h, knight_px * d.hero_screen_scale_rel) and not d.has("size_scale") and not d.has("body_px")
		and s.frame == int(d.animations.idle.frames[0]) and m.hero_anim == "idle")
	check("pivot: смещение кадра %s" % str(s.offset), s.offset.is_equal_approx(Vector2(d.frame_w / 2.0 - d.pivot[0], d.frame_h / 2.0 - d.pivot[1])))
	# удар: все кадры на одну вспышку
	var att: Array = d.animations.attack.frames
	var ft: float = m.hero_cfg.arc_fx_time
	var seq := []
	for k in att.size():
		seq.append(m._hero_frame("attack", ft * (k + 0.5) / att.size()))
	check("удар: кадры %s по долям вспышки %.2f с, в конце — последний" % [str(seq), ft], seq == att.map(func(x): return int(x))
		and m._hero_frame("attack", ft * 5.0) == int(att[-1]) and m._hero_frame("attack", 0.0) == int(att[0]))
	# fps по кругу
	s = sheet(m, {"animations": {"idle": {"frames": [0]}, "walk": {"frames": [0, 1, 2], "fps": 10}, "attack": {"frames": [3]}}})
	check("ходьба с fps 10 по кругу: 0.05 с — кадр 0, 0.15 — 1, 0.25 — 2, 0.35 — снова 0", [0.05, 0.15, 0.25, 0.35].map(func(t): return m._hero_frame("walk", t)) == [0, 1, 2, 0])
	m._hero_play("nothing")
	check("анимации нет в данных — покой", m.hero_anim == "idle" and s.frame == 0)
	# прежнее поведение
	s = sheet(m, {"frames": 1})
	check("frames 1: анимаций нет, вся картинка (1x1 кадр), отражение", m.hero_anims.is_empty() and s.hframes == 1 and s.vframes == 1 and not m.hero_rotate)
	s = sheet(m, {"frames": null, "frame_w": null, "frame_h": null, "animations": null})
	check("без полей сетки (как прежний hero.json): прежнее поведение", m.hero_anims.is_empty() and s.hframes == 1)
	var bad := [{"frame_w": 27}, {"frames": 5}, {"frame_h": 0}, {"animations": {"walk": {"frames": [0]}}}, {"animations": {"idle": {"frames": [4]}}},
		{"animations": {"idle": {"frames": []}}}, {"animations": {"idle": {"frames": [0], "fps": -1}}}, {"pivot": [1]}, {"orient": "spin"}]
	var wrong := []
	for p in bad:
		s = sheet(m, p)
		if not m.hero_anims.is_empty() or s.hframes != 1:
			wrong.append(str(p))
	check("неверная сетка (%d вариантов: кадр не делит картинку, кадров больше, нет idle, кадр вне frames, fps < 0, pivot, orient) — прежнее поведение" % bad.size(),
		wrong.is_empty(), ", ".join(wrong))
	# высота на экране не зависит от размера кадра: другая сетка того же листа и другой множитель
	s = sheet(m, {"frame_w": 52, "frame_h": 26, "frames": 2, "animations": {"idle": {"frames": [0]}}})
	var h1 := s.scale.y * 26.0
	s = sheet(m, {"frame_w": 13, "frame_h": 13, "frames": 16, "animations": {"idle": {"frames": [0]}}})
	var h2 := s.scale.y * 13.0
	s = sheet(m, {"hero_screen_scale_rel": 1.5})
	check("кадр 26 и кадр 13 px — одна высота на экране (%.1f, %.1f px мира); hero_screen_scale_rel 1.5 — %.1f; без сетки (вся картинка) — %.1f" % [h1, h2,
		s.scale.y * d.frame_h, sheet(m, {"frames": 1}).scale.y * tex.get_height()], is_equal_approx(h1, knight_px) and is_equal_approx(h2, knight_px)
		and is_equal_approx(sheet(m, {"hero_screen_scale_rel": 1.5}).scale.y * d.frame_h, knight_px * 1.5)
		and is_equal_approx(sheet(m, {"frames": 1}).scale.y * tex.get_height(), knight_px))
	s = sheet(m, {"orient": "flip"})
	check("orient flip — анимации есть, поворота нет", not m.hero_anims.is_empty() and not m.hero_rotate)
	var old := {"enabled": true}
	old.merge(d)
	old.erase("sprite_path")
	old["sprite"] = "res://art/hero_placeholder.png"
	var f := FileAccess.open("user://hero_old_v65.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var m2: Node2D = load(MAIN).new()
	m2.hero_path = "user://hero_old_v65.json"
	check("прежний ключ sprite вместо sprite_path принимается", m2._load_hero())
	m2.free()
	DirAccess.remove_absolute("user://hero_old_v65.json")
	m.hero_sprite.free()
	m.free()

func t_portraits() -> void:
	print("иллюстрации отрядов")
	var p := PORTRAITS.new()
	p.load_defs()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PORTRAITS.PATH))
	var types := d.keys().filter(func(k): return not k in PORTRAITS.GRADIENT_KEYS)
	check("data/unit_portraits.json: типы %s, у каждого path и crop" % ", ".join(types), p.defs.size() == types.size() and p.defs.has("infantry") and p.defs.has("archer")
		and p.defs.keys().all(func(t): return ResourceLoader.exists(p.defs[t].path)))
	check("градиент из файла: слева %.2f, справа %.2f, ширина %.2f кнопки; текстура — две точки (0 и ширина)" % [p.gradient.gradient_left_alpha, p.gradient.gradient_right_alpha,
		p.gradient.gradient_width], p.gradient.gradient_left_alpha == float(d.gradient_left_alpha) and p.gradient.gradient_right_alpha == float(d.gradient_right_alpha)
		and p.gradient.gradient_width == float(d.gradient_width) and is_equal_approx(p.shade_tex.gradient.get_offset(1), d.gradient_width)
		and is_equal_approx(p.shade_tex.gradient.get_color(0).a, d.gradient_left_alpha) and is_equal_approx(p.shade_tex.gradient.get_color(1).a, d.gradient_right_alpha))
	var r: Rect2i = PORTRAITS.fit(Rect2i(0, 330, 1536, 219), SHOP * 2, 1536, 1024)
	var q: Rect2i = PORTRAITS.fit(Rect2i(0, 330, 1536, 219), SQUAD * 2, 1536, 1024)
	check("вырезка с пропорциями кнопки по центру crop: магазин %s (%s), отряд %s (%s)" % [str(r), str(SHOP), str(q), str(SQUAD)],
		absf(float(r.size.x) / r.size.y - float(SHOP.x) / SHOP.y) < 0.05 and absf(float(q.size.x) / q.size.y - float(SQUAD.x) / SQUAD.y) < 0.05
		and Rect2i(0, 330, 1536, 219).encloses(r) and Rect2i(0, 330, 1536, 219).encloses(q))
	check("crop за краем картинки обрезается по ней", PORTRAITS.fit(Rect2i(1000, 900, 1536, 219), SHOP * 2, 1536, 1024).end <= Vector2i(1536, 1024))
	var sizes := {}
	for t in p.defs:
		for bs in [SHOP, SQUAD]:
			var tex := p.texture(t, bs)
			sizes["%s %s" % [t, bs]] = tex
	check("копии art/ui совпадают с данными и берутся как есть (импорт, %d шт., размер 2x кнопки)" % sizes.size(), p.defs.keys().all(func(t): return p.copy_fresh(t))
		and sizes.keys().all(func(k): return sizes[k] is CompressedTexture2D) and sizes.values().all(func(tx): return Vector2i(tx.get_size()) in [SHOP * 2, SQUAD * 2]))
	check("копии не тронули оригиналы: исходники 1536x1024", p.defs.keys().all(func(t): return load(p.defs[t].path).get_size() == Vector2(1536, 1024)))
	# другой crop — из исходника при запуске
	var p2 := PORTRAITS.new()
	p2.load_defs()
	p2.defs.infantry.crop = Rect2i(0, 100, 1536, 219)
	var tx: Texture2D = p2.texture("infantry", SHOP)
	check("crop в данных изменён, копии нет — полоса из исходника при запуске (ImageTexture 2x кнопки с mipmaps)", tx is ImageTexture and Vector2i(tx.get_size()) == SHOP * 2
		and tx.get_image().has_mipmaps())
	check("тип без иллюстрации — null", p.texture("spearman", SHOP) == null and p.texture("", SHOP) == null)
	# неверные записи
	var f := FileAccess.open("user://portraits_v65.json", FileAccess.WRITE)
	f.store_string('{"infantry": {"path": "res://art/infantry_art.png", "crop": [0, 330, 1536]}, "archer": {"crop": [0, 0, 10, 10]}, ' +
		'"runner": {"path": "res://art/infantry_art.png", "crop": [0, 0, 0, 10]}, "peasant": {"path": "res://art/infantry_art.png", "crop": [0, 0, 10.5, 10]}, ' +
		'"fallen_knight": {"path": "res://art/infantry_art.png", "crop": [0, 0, 100, 10]}}')
	f.close()
	var p3 := PORTRAITS.new()
	p3.load_defs("user://portraits_v65.json")
	check("неверные записи (3 числа, без path, w 0, дробное) отброшены, верная осталась", p3.defs.keys() == ["fallen_knight"], str(p3.defs.keys()))
	p3.load_defs("user://nope_v65.json")
	check("нет файла — без иллюстраций", p3.defs.is_empty())
	DirAccess.remove_absolute("user://portraits_v65.json")
	# кнопки
	var b := Button.new()
	b.custom_minimum_size = Vector2(SHOP)
	p.apply(b, "infantry")
	var pic := b.get_node_or_null("Portrait") as TextureRect
	check("кнопка с иллюстрацией: картинка и градиент за текстом, фильтр linear с mipmaps, контур текста %d px, рамка выбора 3 px #feae34" % FONTS.outline(p.OUTLINE_PX),
		pic != null and pic.visible and pic.show_behind_parent and b.get_node("Shade").show_behind_parent and pic.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		and b.get_theme_constant("outline_size") == FONTS.outline(p.OUTLINE_PX) and (b.get_theme_stylebox("pressed") as StyleBoxFlat).border_width_left == 3
		and (b.get_theme_stylebox("pressed") as StyleBoxFlat).border_color == Color("#feae34") and b.get_child_count() == 0)
	p.apply(b, "spearman")
	check("тип сменился на тип без иллюстрации — обычная кнопка", not pic.visible and not b.has_theme_stylebox_override("normal") and not b.has_theme_constant_override("outline_size"))
	p.apply(b, "archer")
	check("и обратно — иллюстрация лучников", pic.visible and pic.texture == p.texture("archer", SHOP) and b.has_theme_stylebox_override("normal"))
	b.free()
	var g := Button.new()
	g.custom_minimum_size = Vector2(SHOP)
	p.apply(g, "")
	check("«Оружие», «Ворота» (без типа): дочерних нод и переопределений нет", g.get_node_or_null("Portrait") == null and not g.has_theme_stylebox_override("normal"))
	g.free()

func t_layout() -> void:
	print("размеры кнопок (data/ui_layout.json)")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	var size_ok := func(v): return v is Array and v.size() == 2 and v.all(func(x): return (x is float or x is int) and x > 0)
	check("ui_layout.json: shop %s, squad %s, действия %s, Клич %s — размеры [w, h] больше 0" % [d.shop_button_size, d.squad_button_size, d.action_button_height,
		d.war_cry_size], size_ok.call(d.shop_button_size) and size_ok.call(d.squad_button_size) and size_ok.call(d.war_cry_size) and d.action_button_height > 0)
	var m: Node2D = load(MAIN).new()
	m._load_ui_layout()
	check("main читает размеры из файла", m.ui_layout.shop_button_size == Vector2(d.shop_button_size[0], d.shop_button_size[1])
		and m.ui_layout.squad_button_size == Vector2(d.squad_button_size[0], d.squad_button_size[1]) and m.ui_layout.action_button_height == float(d.action_button_height)
		and m.ui_layout.war_cry_size == Vector2(d.war_cry_size[0], d.war_cry_size[1]))
	var m2: Node2D = load(MAIN).new()
	var defaults: Dictionary = m2.ui_layout.duplicate()
	m2.free()
	check("значения по умолчанию в main — те же, что в файле (без файла кнопки того же размера)", defaults.shop_button_size == m.ui_layout.shop_button_size
		and defaults.squad_button_size == m.ui_layout.squad_button_size and defaults.action_button_height == m.ui_layout.action_button_height
		and defaults.war_cry_size == m.ui_layout.war_cry_size)
	# подгонка текста: длинный текст — кегль меньше, кнопка того же размера
	var shop: Vector2 = m.ui_layout.shop_button_size
	var b := Button.new()
	m._fixed_button(b, shop)
	b.text = "Z  +50 пехоты — 100 зол. (куплено 0)"
	m._fit_text(b)
	var fs0 := b.get_theme_font_size("font_size")
	b.text = "C  Оружие: скорость атаки +10% — 150 зол. (куплено 0) — очень длинная строка для проверки подгонки текста под кнопку фиксированного размера, три строки и больше"
	m._fit_text(b)
	var fs1 := b.get_theme_font_size("font_size")
	check("подгонка: короткий текст — кегль %d, длинный — %d (не меньше %d), размер кнопки не меняется (%s), перенос по словам" % [fs0, fs1, m.FIT_MIN_FONT, str(b.get_combined_minimum_size())],
		(fs1 < fs0 or FONTS.fit_sizes(fs0, m.FIT_MIN_FONT).size() == 1) and fs1 >= FONTS.px(m.FIT_MIN_FONT) and b.get_combined_minimum_size().x <= shop.x and b.clip_text and b.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
	b.free()
	m.free()
