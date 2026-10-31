extends SceneTree
# Задача 28, этап 5 (без окна): кадр героя 24x24. Значения — из data/hero.json, юнит — SPRITE_PX.
#   hero.json: frame_w, frame_h 24, pivot [11.5, 12.5], блок legacy (прежние 26x26, pivot [12.5, 13.5]).
#   Нынешний файл (если ещё прежний: ширина не frames x frame_w) — сетка legacy, одно предупреждение за запуск; новый лист
#   96x24 (собран в памяти) — основной блок: кадр 24, тексель = px мира, рост 24 = 1,5 юнита; pivot — в позиции героя.
#   Силуэт (этап 4) берёт ту же сетку. Кольцо и полоса HP — от hero_screen_scale_rel и зума (на экране растут с героем, центр —
#   позиция героя), не от размера кадра; hero_near_radius — из данных, как был.
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

# Пересобрать сетку героя на текстуре tex (как _setup_hero_view) и силуэт под неё.
func rebuild(m: Node2D, tex: Texture2D) -> void:
	m.hero_sprite.texture = tex
	m.hero_sprite.hframes = 1
	m.hero_sprite.vframes = 1
	m.hero_sprite.offset = Vector2.ZERO
	m.hero_sprite.scale = m._hero_sprite_scale(tex.get_height())
	m._setup_hero_sheet(tex)
	if m.hero_occ != null:
		m.hero_occ.free()
		m.hero_occ = null
	m._setup_hero_occlusion()

func _run() -> void:
	print("CHECK v78: кадр героя 24x24")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	check("hero.json: кадр %sx%s, pivot %s, legacy %s" % [d.frame_w, d.frame_h, str(d.pivot), str(d.get("legacy"))], int(d.frame_w) == 24 and int(d.frame_h) == 24
		and d.pivot == [11.5, 12.5] and d.get("legacy") is Dictionary and int(d.legacy.frame_w) == 26 and int(d.legacy.frame_h) == 26 and d.legacy.pivot == [12.5, 13.5])
	var g: Node = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute("user://bench_v78hero")
	g.save_path = "user://bench_v78hero/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(8)
	var m: Node2D = current_scene
	check("герой есть", m.hero_idx >= 0 and m.hero_sprite != null)
	var unit := float(m.SPRITE_PX)
	var s: Sprite2D = m.hero_sprite
	var file_tex: Texture2D = load(d.sprite_path)
	var nf := int(d.frames)
	var file_new: bool = file_tex.get_width() == nf * int(d.frame_w) and file_tex.get_height() == int(d.frame_h)
	var fw := int(d.frame_w) if file_new else int(d.legacy.frame_w)
	check("%s %dx%d: %s — кадр %d, кадров %d x %d, флаг legacy %s" % [d.sprite_path, file_tex.get_width(), file_tex.get_height(),
		"новый лист, основной блок" if file_new else "прежний лист, блок legacy", fw, s.hframes, s.vframes, m.hero_sheet_legacy],
		m.hero_sheet_legacy == not file_new and s.hframes == file_tex.get_width() / fw and s.vframes == 1 and not m.hero_anims.is_empty())
	check("предупреждение о прежнем листе — одно за запуск (флаг стоит, повторная сборка его не сбрасывает)", m.hero_legacy_warned == not file_new)
	rebuild(m, file_tex)
	check("повторная сборка на прежнем листе: снова legacy, флаг предупреждения тот же", m.hero_sheet_legacy == not file_new and m.hero_legacy_warned == not file_new)
	var h_old: float = s.scale.y * file_tex.get_height()
	# новый лист 96x24 (кадры — цветные квадраты 24x24, в точке pivot — отметка)
	var img := Image.create(nf * 24, 24, false, Image.FORMAT_RGBA8)
	for k in nf:
		img.fill_rect(Rect2i(k * 24 + 2, 2, 20, 20), Color(0.2 + 0.2 * k, 0.5, 0.8))
	var tex := ImageTexture.create_from_image(img)
	rebuild(m, tex)
	var ph: Vector2 = Vector2(d.pivot[0], d.pivot[1])
	check("лист %dx24: основной блок (не legacy), кадров %d x %d, смещение %s = (12 - 11.5, 12 - 12.5)" % [nf * 24, s.hframes, s.vframes, str(s.offset)],
		not m.hero_sheet_legacy and s.hframes == nf and s.vframes == 1 and s.offset.is_equal_approx(Vector2(12.0, 12.0) - ph))
	var h_new: float = s.scale.y * 24.0
	check("рост героя на экране: кадр 24 — %.1f px мира = %.2f юнита (%d px), тексель = px мира (масштаб %.3f); прежний лист — тот же рост %.1f" % [h_new, h_new / unit,
		int(unit), s.scale.y, h_old], is_equal_approx(h_new, m.KNIGHT_SPRITE_SCALE * unit * float(d.hero_screen_scale_rel)) and is_equal_approx(h_new / unit, 1.5 * float(d.hero_screen_scale_rel))
		and is_equal_approx(s.scale.y, 1.0 * float(d.hero_screen_scale_rel)) and is_equal_approx(h_old, h_new))
	# точка pivot кадра — в позиции героя (центр кольца, ось поворота)
	var piv_local: Vector2 = s.offset + ph - Vector2(12.0, 12.0)
	check("точка pivot кадра — в позиции героя при любом повороте: %s" % str(s.transform * piv_local), (s.transform * piv_local).length() < 0.001
		and (Transform2D(1.3, s.scale, 0.0, Vector2.ZERO) * piv_local).length() < 0.001)
	check("силуэт — та же сетка: кадров %d, смещение %s" % [m.hero_occ.hframes if m.hero_occ else 0, str(m.hero_occ.offset) if m.hero_occ else "—"],
		m.hero_occ != null and m.hero_occ.hframes == s.hframes and m.hero_occ.offset == s.offset)
	# кольцо и полоса HP
	var r1: float = m.hero_ring_radius()
	var base: float = m.camera_min_zoom()
	check("кольцо: радиус %.2f px мира = %s px экрана при базовом зуме x hero_screen_scale_rel; от кадра не зависит" % [r1, m.HERO_RING_PX],
		is_equal_approx(r1 * base, m.HERO_RING_PX * float(d.hero_screen_scale_rel)))
	var keep: Dictionary = m.hero_cfg
	var c2: Dictionary = keep.duplicate()
	c2.hero_screen_scale_rel = 1.5
	m.hero_cfg = c2
	var r15: float = m.hero_ring_radius()
	m.hero_cfg = keep
	check("hero_screen_scale_rel 1.5: кольцо в 1,5 раза больше (%.2f)" % r15, is_equal_approx(r15, r1 * 1.5))
	var cam: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/camera.json"))
	var ring0: float = r1 * m.camera.zoom.x
	var hero0: float = h_new * m.camera.zoom.x
	m.zoom_user = float(cam.zoom_user_max)
	m.zoom_user_target = m.zoom_user
	await step(2)
	var ring1: float = m.hero_ring_radius() * m.camera.zoom.x
	var hero1: float = s.get_global_transform_with_canvas().get_scale().y * 24.0
	check("зум x%s: кольцо на экране %.1f -> %.1f px, герой %.1f -> %.1f px — отношение то же (кольцо не отстаёт от героя); полоса HP — ширина кольца" % [cam.zoom_user_max,
		ring0, ring1, hero0, hero1], absf(ring1 / hero1 - ring0 / hero0) < 0.001 and ring1 > ring0 * 2.0)
	check("hero_near_radius из data (%s) — как в hero.json, от кадра не зависит" % d.hero_near_radius, is_equal_approx(m.hero_near_r, float(d.hero_near_radius)))
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v78hero")
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
