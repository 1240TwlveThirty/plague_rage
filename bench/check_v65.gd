extends SceneTree
# Тесты задачи 15 (без окна): спрайтшит героя — сетка и анимации из hero.json, ошибки в данных — прежнее поведение (вся картинка,
# отражение); кадр удара растянут на вспышку arc_fx_time. Иллюстрации отрядов — data/unit_portraits.json: вырезка с пропорциями
# кнопки, уменьшенные копии art/ui совпадают с данными, другой crop — полоса из исходника при запуске, неверные записи отбрасываются,
# у кнопок без типа иллюстрации нет.
const MAIN := "res://scripts/main.gd"
const PORTRAITS := preload("res://scripts/portraits.gd")
var fails := 0

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
	t_sheet()
	t_portraits()
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
	m.hero_sprite.scale = Vector2.ONE * cfg.size_scale * m.SPRITE_PX / tex.get_height()
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
	check("сетка: %d x %d кадров, анимаций %d, orient %s, на экране тело %s px кадра = %.1f px мира (size_scale x юнит)" % [s.hframes, s.vframes, m.hero_anims.size(),
		d.orient, d.body_px, s.scale.y * d.body_px], s.hframes == tex.get_width() / int(d.frame_w) and s.vframes == tex.get_height() / int(d.frame_h)
		and m.hero_anims.size() == d.animations.size() and m.hero_rotate == (d.orient == "rotate") and is_equal_approx(s.scale.y * d.body_px, m.SPRITE_PX * d.size_scale)
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
		{"animations": {"idle": {"frames": []}}}, {"animations": {"idle": {"frames": [0], "fps": -1}}}, {"pivot": [1]}, {"body_px": 0}, {"orient": "spin"}]
	var wrong := []
	for p in bad:
		s = sheet(m, p)
		if not m.hero_anims.is_empty() or s.hframes != 1:
			wrong.append(str(p))
	check("неверная сетка (%d вариантов: кадр не делит картинку, кадров больше, нет idle, кадр вне frames, fps < 0, pivot, body_px, orient) — прежнее поведение" % bad.size(),
		wrong.is_empty(), ", ".join(wrong))
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
	check("data/unit_portraits.json: типы %s, у каждого path и crop" % ", ".join(d.keys()), p.defs.size() == d.size() and p.defs.has("infantry") and p.defs.has("archer")
		and p.defs.keys().all(func(t): return ResourceLoader.exists(p.defs[t].path)))
	var r: Rect2i = PORTRAITS.fit(Rect2i(0, 330, 1536, 219), Vector2i(640, 88), 1536, 1024)
	var q: Rect2i = PORTRAITS.fit(Rect2i(0, 330, 1536, 219), Vector2i(520, 80), 1536, 1024)
	check("вырезка с пропорциями кнопки по центру crop: магазин %s, отряд %s" % [str(r), str(q)], r == Rect2i(0, 334, 1536, 211) and q == Rect2i(56, 330, 1424, 219))
	check("crop за краем картинки обрезается по ней", PORTRAITS.fit(Rect2i(1000, 900, 1536, 219), Vector2i(640, 88), 1536, 1024).end <= Vector2i(1536, 1024))
	var sizes := {}
	for t in p.defs:
		for bs in [Vector2i(320, 44), Vector2i(260, 40)]:
			var tex := p.texture(t, bs)
			sizes["%s %s" % [t, bs]] = tex
	check("копии art/ui совпадают с данными и берутся как есть (импорт, %d шт., размер 2x кнопки)" % sizes.size(), p.defs.keys().all(func(t): return p.copy_fresh(t))
		and sizes.keys().all(func(k): return sizes[k] is CompressedTexture2D) and sizes.values().all(func(tx): return tx.get_width() in [640, 520] and tx.get_height() in [88, 80]))
	check("копии не тронули оригиналы: исходники 1536x1024", p.defs.keys().all(func(t): return load(p.defs[t].path).get_size() == Vector2(1536, 1024)))
	# другой crop — из исходника при запуске
	var p2 := PORTRAITS.new()
	p2.load_defs()
	p2.defs.infantry.crop = Rect2i(0, 100, 1536, 219)
	var tx: Texture2D = p2.texture("infantry", Vector2i(320, 44))
	check("crop в данных изменён, копии нет — полоса из исходника при запуске (ImageTexture 640x88 с mipmaps)", tx is ImageTexture and tx.get_size() == Vector2(640, 88)
		and tx.get_image().has_mipmaps())
	check("тип без иллюстрации — null", p.texture("spearman", Vector2i(320, 44)) == null and p.texture("", Vector2i(320, 44)) == null)
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
	b.custom_minimum_size = Vector2(320, 44)
	p.apply(b, "infantry")
	var pic := b.get_node_or_null("Portrait") as TextureRect
	check("кнопка с иллюстрацией: картинка и градиент за текстом, фильтр linear с mipmaps, контур текста %d px, рамка выбора 3 px #feae34" % p.OUTLINE_PX,
		pic != null and pic.visible and pic.show_behind_parent and b.get_node("Shade").show_behind_parent and pic.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		and b.get_theme_constant("outline_size") == p.OUTLINE_PX and (b.get_theme_stylebox("pressed") as StyleBoxFlat).border_width_left == 3
		and (b.get_theme_stylebox("pressed") as StyleBoxFlat).border_color == Color("#feae34") and b.get_child_count() == 0)
	p.apply(b, "spearman")
	check("тип сменился на тип без иллюстрации — обычная кнопка", not pic.visible and not b.has_theme_stylebox_override("normal") and not b.has_theme_constant_override("outline_size"))
	p.apply(b, "archer")
	check("и обратно — иллюстрация лучников", pic.visible and pic.texture == p.texture("archer", Vector2i(320, 44)) and b.has_theme_stylebox_override("normal"))
	b.free()
	var g := Button.new()
	g.custom_minimum_size = Vector2(320, 44)
	p.apply(g, "")
	check("«Оружие», «Ворота» (без типа): дочерних нод и переопределений нет", g.get_node_or_null("Portrait") == null and not g.has_theme_stylebox_override("normal"))
	g.free()
