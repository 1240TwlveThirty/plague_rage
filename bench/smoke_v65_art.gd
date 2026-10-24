extends SceneTree
# Смоук задачи 15 с окном: новые арты. Забег через Game (герой включён по данным). Скриншоты в папку из аргумента:
# art_shop_ru.png, art_shop_en.png — магазин в передышке (пехота и лучники с иллюстрацией, «Оружие» и «Ворота» обычные);
# art_shop_disabled.png — золота нет: кнопки серые и темнее; art_squads.png — панель отрядов: выбранный (рамка #feae34),
# под мышью (ярче, светлая рамка), обычный; hero_idle.png, hero_walk.png, hero_attack_1..3.png — герой крупно (вырезка x4):
# покой, ходьба, кадры удара за вспышку. Проверки: состояние кнопок (режим отрисовки и параметры шейдера), картинка на экране
# (пиксели кнопки не однотонные), текст внутри кнопки; анимация, кадр, поворот, nearest и размер героя.
const DIR := "user://bench_v65"
const DT := 1.0 / 30.0
var fails := 0
var out_dir := ""

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(m: Node2D, name: String, delta := 1.0 / 60.0) -> Image:
	m._process(delta)   # main без собственного процесса: кадр отрисовки вручную
	m._update_ui()
	await step(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if name != "":
		img.save_png(out_dir.path_join(name))
	return img

# Вырезка вокруг героя, увеличенная x4 (nearest) — чтобы кадры были видны в отчёте.
func hero_crop(m: Node2D, img: Image, name: String) -> void:
	var px: Vector2 = Vector2(img.get_size()) / m.get_viewport_rect().size
	var c: Vector2 = (m.get_viewport().get_canvas_transform() * m.hero_view.position) * px
	var r := Rect2i(Vector2i(c) - Vector2i(60, 60), Vector2i(120, 120)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var sub := img.get_region(r)
	sub.resize(sub.get_width() * 4, sub.get_height() * 4, Image.INTERPOLATE_NEAREST)
	sub.save_png(out_dir.path_join(name))

# Разброс яркости пикселей прямоугольника кнопки на скриншоте: у иллюстрации большой, у однотонной кнопки — около 0.
func spread(img: Image, b: Control) -> float:
	var px: Vector2 = Vector2(img.get_size()) / Vector2(root.get_visible_rect().size)
	var r := Rect2i(Vector2i(b.get_global_rect().position * px), Vector2i(b.get_global_rect().size * px))
	var lo := 1.0
	var hi := 0.0
	for k in 200:
		var p := r.position + Vector2i(r.size.x * (0.55 + 0.4 * (k % 20) / 20.0), r.size.y * (0.15 + 0.7 * (k / 20) / 10.0))
		var v := img.get_pixelv(p).get_luminance()
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo

func has_pic(b: Button) -> bool:
	return b.get_node_or_null("Portrait") != null and b.get_node("Portrait").visible

func shader(b: Button, key: String) -> float:
	var pic := b.get_node_or_null("Portrait") as TextureRect
	return (pic.material as ShaderMaterial).get_shader_parameter(key) if pic != null else -1.0

func text_fits(b: Button) -> bool:
	var font := b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var w := 0.0
	for line in b.text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w + b.get_theme_stylebox("normal").get_minimum_size().x <= b.size.x + 0.5

func hover(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)

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
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	m.banner.visible = false   # дневник на старте закрывает экран
	await t_shop(m)
	await t_squads(m)
	await t_hero(m)
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_shop(m: Node2D) -> void:
	m.gold = 100000
	var inf: Button = m.shop_buttons[m.SHOP_ITEMS.find("inf_pack")]
	var arc: Button = m.shop_buttons[m.SHOP_ITEMS.find("archer_pack")]
	var plain := [m.shop_buttons[m.SHOP_ITEMS.find("weapons")], m.shop_buttons[m.SHOP_ITEMS.find("gate")]]
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		m.squad_panel_sig = -1
		m._update_squad_panel()
		var img := await shot(m, "art_shop_%s.png" % loc)
		check("%s: магазин виден; у пехоты и лучников иллюстрация (разброс яркости %.2f, %.2f), у «Оружия» и «Ворот» нет" % [loc, spread(img, inf), spread(img, arc)],
			m.shop_panel.visible and inf.get_node("Portrait").visible and arc.get_node("Portrait").visible and spread(img, inf) > 0.15 and spread(img, arc) > 0.15
			and plain.all(func(b): return b.get_node_or_null("Portrait") == null))
		check("%s: текст в кнопках магазина помещается, контур 4 px, кнопка %dx%d (не меньше 320x44; ширину панели задаёт самая длинная строка)" % [loc, inf.size.x, inf.size.y],
			m.shop_buttons.filter(func(b): return b.visible).all(text_fits) and inf.get_theme_constant("outline_size") == 4 and inf.size.x >= 320.0 and inf.size.y >= 44.0,
			inf.text.replace("\n", " / "))
	TranslationServer.set_locale("ru")
	check("обычное состояние: картинка не серая, яркость 1", inf.get_draw_mode() == BaseButton.DRAW_NORMAL and shader(inf, "gray") == 0.0 and shader(inf, "bright") == 1.0)
	m.gold = 0
	var img := await shot(m, "art_shop_disabled.png")
	check("нет золота: кнопки недоступны, картинка серая (gray 1) и темнее (%.2f)" % shader(inf, "bright"), inf.disabled and arc.disabled
		and inf.get_draw_mode() == BaseButton.DRAW_DISABLED and shader(inf, "gray") == 1.0 and shader(inf, "bright") < 1.0)
	m.gold = 100000
	await shot(m, "")

func t_squads(m: Node2D) -> void:
	var shown := []
	for s in m.SQUAD_MAX:
		if m.squad_used[s] == 1:
			shown.append(s)
	m._select_only(shown[0])
	m._update_squad_panel()
	var b0: Button = m.squad_buttons[shown[0]]
	var other := -1
	for s in shown:
		if s != shown[0] and m.squad_buttons[s].get_node_or_null("Portrait") != null and m.squad_buttons[s].get_node("Portrait").visible:
			other = s
	await shot(m, "")
	if other >= 0:
		hover(m.squad_buttons[other].get_global_rect().get_center())
	var img := await shot(m, "art_squads.png")
	var types := shown.map(func(s): return m.type_id.find_key(m.squad_type[s]))
	var pics_ok := shown.all(func(s): return has_pic(m.squad_buttons[s]) == (m.type_id.find_key(m.squad_type[s]) in ["infantry", "archer"]))
	check("панель отрядов (%s): у пехоты и лучников иллюстрация, цветной квадрат 18x18 на месте" % ", ".join(types), pics_ok
		and shown.all(func(s): return m.squad_swatches[s].visible and m.squad_swatches[s].custom_minimum_size == Vector2(18, 18)) and spread(img, b0) > 0.15)
	check("выбранный: нажатая кнопка, рамка #feae34 3 px", b0.button_pressed and b0.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]
		and (b0.get_theme_stylebox("pressed") as StyleBoxFlat).border_color == Color("#feae34"))
	if other >= 0:
		var bo: Button = m.squad_buttons[other]
		check("под мышью: режим hover, картинка ярче (%.2f), тонкая светлая рамка" % shader(bo, "bright"), bo.get_draw_mode() == BaseButton.DRAW_HOVER
			and shader(bo, "bright") > 1.0 and (bo.get_theme_stylebox("hover") as StyleBoxFlat).border_width_top == 1)
	else:
		check("второй отряд с иллюстрацией для наведения есть", false, str(types))
	check("текст в кнопках отрядов помещается", shown.all(func(s): return text_fits(m.squad_buttons[s])))
	hover(Vector2(960, 540))
	await shot(m, "")

func t_hero(m: Node2D) -> void:
	m.shop_panel.visible = false
	for c in m.get_children():   # интерфейс (дневник, подсказки) закрывает героя на крупных кадрах
		if c is CanvasLayer:
			c.visible = false
	var h: int = m.hero_idx
	var img := await shot(m, "")
	var s: Sprite2D = m.hero_sprite
	check("герой: спрайтшит %s, кадр %dx%d, nearest, тело на экране %.1f px мира" % [m.hero_cfg.sprite_path, s.texture.get_width() / s.hframes, s.texture.get_height() / s.vframes,
		s.scale.y * m.hero_cfg.body_px], s.hframes * s.vframes >= int(m.hero_cfg.frames) and s.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and is_equal_approx(s.scale.y * m.hero_cfg.body_px, m.SPRITE_PX * m.hero_cfg.size_scale))
	img = await shot(m, "hero_idle_full.png")
	hero_crop(m, img, "hero_idle.png")
	check("покой: анимация idle, кадр %d, поворот к зомби (вверх) %.2f" % [s.frame, s.rotation], m.hero_anim == "idle" and s.frame == int(m.hero_cfg.animations.idle.frames[0])
		and is_equal_approx(s.rotation, -PI / 2.0))
	m.hero_feed = func(_t): return Vector2(1, 0)
	m._physics_process(DT)
	m._physics_process(DT)
	img = await shot(m, "")
	hero_crop(m, img, "hero_walk.png")
	check("движение вправо: анимация walk, поворот 0 (вправо)", m.hero_anim == "walk" and is_equal_approx(s.rotation, 0.0) and m.pos[h].x > m.HERO_SPAWN.x)
	m.hero_feed = func(_t): return Vector2(-1, 0)
	m._physics_process(DT)
	await shot(m, "")
	check("движение влево: поворот на π (не отражение)", is_equal_approx(absf(s.rotation), PI) and not s.flip_h)
	# крупные кадры для отчёта — выше ворот, где героя не закрывают подсказки
	m.hero_feed = func(_t): return Vector2(0, -1)
	for t in 40:
		m._physics_process(DT)
	img = await shot(m, "")
	hero_crop(m, img, "hero_walk.png")
	m.hero_feed = func(_t): return Vector2.ZERO
	m._physics_process(DT)
	img = await shot(m, "")
	hero_crop(m, img, "hero_idle.png")
	check("остановился выше ворот: покой, взгляд вверх", m.hero_anim == "idle" and is_equal_approx(s.rotation, -PI / 2.0))
	m.hero_feed = func(_t): return {"move": Vector2.ZERO, "attack": true, "face": -PI / 2.0}
	m.cooldown[h] = 0.0
	var n0: int = m.hero_swing_n
	m._physics_process(DT)
	m.hero_feed = func(_t): return Vector2.ZERO
	var ft: float = m.hero_cfg.arc_fx_time
	var att: Array = m.hero_cfg.animations.attack.frames
	var seen := []
	img = await shot(m, "", 0.0)
	seen.append(s.frame)
	hero_crop(m, img, "hero_attack_1.png")
	for k in range(1, att.size()):
		img = await shot(m, "", ft / att.size())
		seen.append(s.frame)
		hero_crop(m, img, "hero_attack_%d.png" % (k + 1))
	check("удар (J): новый взмах, анимация attack, кадры за вспышку %s, поворот по удару (вверх)" % str(seen), m.hero_swing_n == n0 + 1 and seen == att.map(func(x): return int(x))
		and is_equal_approx(s.rotation, -PI / 2.0))
	await shot(m, "", ft)
	await shot(m, "", 0.02)
	check("вспышка кончилась: снова покой, кадр %d" % s.frame, m.hero_anim == "idle" and s.frame == int(m.hero_cfg.animations.idle.frames[0]))
	check("кольцо-маркер и полоса HP рисуются нодой героя, спрайт — её ребёнок над слоями замка и листвы", s.get_parent() == m.hero_view and m.hero_view.z_index == m.LEAF_Z + 1)
