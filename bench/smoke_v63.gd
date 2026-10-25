extends SceneTree
# Смоук задачи 13 с окном: куски тела, учащённые эффекты, тряска на каждый удар (игровой режим через Game, герой по данным;
# data/fx.json). Скриншоты в папку из аргумента: gib_0.png — первый кадр добивания (куски на месте зомби, всплеск, искры);
# gib_mid.png — через 0.25 с: верх улетел по удару, низ в другую сторону; gib_down.png — куски зомби, смотревшего вниз;
# burst.png — серия добиваний подряд (крупные капли); stains.png — через 1 с: кусков и частиц нет, пятна;
# shake_ui.png — кадр тряски: мир сдвинут, интерфейс на месте. Кадры — m._process(delta), тики — m._physics_process.
const DIR := "user://bench_v63"
const DT := 1.0 / 30.0
const P := Vector2(1500, 360)
var fails := 0
var out_dir := ""

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(m: Node2D, name: String, dt := 0.0) -> Image:
	m._process(dt)
	await step(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	return img

# Непрозрачных пикселей, изменившихся между снимками, в круге радиуса r (мир) у точки c.
func changed(m: Node2D, a: Image, b: Image, c: Vector2, r: float) -> int:
	var px: Vector2 = Vector2(a.get_size()) / m.get_viewport_rect().size
	var ct: Transform2D = m.get_viewport().get_canvas_transform()
	var n := 0
	for y in range(-int(r), int(r) + 1):
		for x in range(-int(r), int(r) + 1):
			if x * x + y * y > r * r:
				continue
			var q := Vector2i((ct * (c + Vector2(x, y))) * px)
			if q.x < 0 or q.y < 0 or q.x >= a.get_width() or q.y >= a.get_height():
				continue
			var ca := a.get_pixelv(q)
			var cb := b.get_pixelv(q)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.15:
				n += 1
	return n

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func zombies(m: Node2D, ws: Array, hp: float) -> Array:
	var z := []
	for w in ws:
		z.append(m.count)
		m._spawn_zombie(P + w, m.zombie_type)
		m.hp[m.count - 1] = hp
		m.prev_pos[m.count - 1] = P + w
	return z

func swing(m: Node2D, face := 0.0) -> void:
	m.hero_feed = func(t: int): return {"move": Vector2.ZERO, "face": face, "attack": t == m.tick_counter}
	m.cooldown[m.hero_idx] = 0.0
	m._physics_process(DT)
	m.hero_feed = func(_t): return {"move": Vector2.ZERO, "face": face}
	m.prev_pos = m.pos.duplicate()

func settle(m: Node2D) -> void:
	for k in 17:
		m._process(0.1)

func clear_units(m: Node2D, ids: Array) -> void:
	for j in ids:
		if j < m.count and m.team[j] == 1:
			m.hp[j] = 0.0
	m._remove_dead()
	m._build_grid()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var g: Node = root.get_node_or_null("Game")
	var st: Node = root.get_node_or_null("Settings")
	if g == null or st == null:
		print("SMOKE: нет автозагрузки Game или Settings")
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
	m.banner.visible = false
	var c: Dictionary = m.hit_cfg
	var h: int = m.hero_idx
	m.pos[h] = P
	m.prev_pos[h] = P
	check("fx.json: частиц за удар %s, за добивание %s, max_particles %d, max_gibs %d (пар %d), тряска %d px + %d за %d попавших на %.2f с, предел %d px" % [
		c.blood_hit, c.blood_kill, c.max_particles, c.max_gibs, m.gib_age.size(), int(c.shake_base_px), int(c.shake_extra_px), int(c.shake_extra_per), c.shake_time,
		int(c.shake_max_px)], m.hit_pos.size() == int(c.max_particles) and m.gib_age.size() == int(c.max_gibs) / 2 and st.screen_shake)
	# Ноды кусков: картинки из fx.json, nearest, сразу после юнитов (над пятнами), z юнитов — ниже героя
	var gn := []
	var sn: Node = null
	for ch in m.get_children():
		if ch is MultiMeshInstance2D and (ch.multimesh == m.gib_top_mm or ch.multimesh == m.gib_bot_mm):
			gn.append(ch)
		if ch == m.stain_layer:
			sn = ch
	var ui: int = m.unit_node.get_index()
	check("куски: 2 ноды MultiMesh (art/gib_top.png и art/gib_bottom.png 16x16, nearest) после юнитов и пятен, z юнитов, ниже героя",
		gn.size() == 2 and gn[0].texture.resource_path == c.gib_top_path and gn[1].texture.resource_path == c.gib_bottom_path
		and gn[0].texture.get_size() == Vector2(16, 16) and gn[0].texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and gn[0].get_index() == ui + 1 and gn[1].get_index() == ui + 2 and sn != null and sn.get_index() < ui
		and gn[0].z_index == m.unit_node.z_index and gn[0].z_index < m.hero_view.z_index)
	# 1. Добивание: зомби справа, смотрит вправо
	var z := zombies(m, [Vector2(14, 0)], 1.0)
	m.hero_feed = func(_t): return {"move": Vector2.ZERO, "face": 0.0}
	m._physics_process(DT)
	m.prev_pos = m.pos.duplicate()
	m.unit_dir[z[0]] = 0
	var ready := await shot(m, "gib_ready.png")
	var rng_state := [m.unit_rng.state, m.arrow_rng.state]
	var at: Vector2 = m.pos[z[0]]
	swing(m)
	check("удар добил зомби: тип и направление записаны", m.hero_hit_dead.count(1) == 1 and m.hero_hit_type[0] == m.zombie_type and m.hero_hit_dir[0] == 0)
	var img0 := await shot(m, "gib_0.png", 1.0 / 120.0)
	var top_v: Vector2 = m.gib_vel[0]
	var bot_v: Vector2 = m.gib_vel[1]
	var side := Vector2(0, signf(top_v.y))
	check("пара кусков на месте зомби: верх по удару (+x) и вбок, низ — в другую сторону вбок и назад (верх %s, низ %s)" % [top_v, bot_v],
		m.gib_n == 1 and m.gib_pos[0].distance_to(at) < 2.0 and top_v.x > 0.0 and top_v.dot(side) > 0.0 and bot_v.dot(side) < 0.0 and bot_v.x < 0.0
		and absf(bot_v.y) > absf(bot_v.x) and m.gib_dir[0] == 0)
	check("буфер: ориентация вправо (DIR_BASIS 0), позиция — целые px, альфа 1", m.gib_top_buf[0] == 16.0 and m.gib_top_buf[5] == 16.0
		and m.gib_top_buf[3] == roundf(m.gib_top_buf[3]) and m.gib_top_buf[11] == 1.0 and m.gib_top_mm.visible_instance_count == 1)
	var blood := 0
	var sparks := 0
	for i in m.hit_n:
		if m.hit_drag[i] == 0.0:
			sparks += 1
		else:
			blood += 1
	var bk: Array = c.blood_kill
	var mult := float(c.hero_blood_mult)
	var bd: Array = c.big_drop_count if c.hero_big_drop_every_kill else [0, 0]
	check("добивание: искр %d (spark_count %d) и крови %d (blood_kill %s x%.1f + крупных капель %s)" % [sparks, int(c.spark_count), blood, str(bk), mult, str(bd)],
		sparks == int(c.spark_count) and blood >= roundi(bk[0] * mult) + int(bd[0]) and blood <= roundi(bk[1] * mult) + int(bd[1]))
	check("ГСЧ симуляции (unit_rng, arrow_rng) не тронуты", rng_state == [m.unit_rng.state, m.arrow_rng.state])
	for k in 4:
		m._process(0.05)
	var mid := await shot(m, "gib_mid.png", 0.05)
	var tp: Vector2 = m.gib_pos[0]
	var bp: Vector2 = m.gib_pos[1]
	check("через 0.25 с: верх отлетел на %.1f px вперёд, низ на %.1f px вбок; на экране изменилось %d px у точки" % [tp.x - at.x, absf(bp.y - at.y), changed(m, ready, mid, at, 18.0)],
		tp.x - at.x > 12.0 and absf(bp.y - at.y) > 7.0 and changed(m, ready, mid, at, 18.0) >= 20)
	m._process(0.2)   # 0.46 с: ещё не гаснет
	var a1: float = m.gib_top_buf[11]
	m._process(0.2)   # 0.66 с: середина затухания
	var a2: float = m.gib_top_buf[11]
	m._process(0.2)
	check("жизнь 0.8 с, последние 0.3 с гаснут: альфа %.2f на 0.46 с, %.2f на 0.66 с, к 0.86 с кусков %d" % [a1, a2, m.gib_n],
		a1 == 1.0 and a2 > 0.3 and a2 < 0.7 and m.gib_n == 0 and m.gib_top_mm.visible_instance_count == 0)
	settle(m)
	# 2. Ориентация по unit_dir: зомби смотрит вниз
	z = zombies(m, [Vector2(14, 0)], 1.0)
	m._build_grid()
	m.unit_dir[z[0]] = 1
	swing(m)
	await shot(m, "gib_down.png", 0.1)
	check("зомби смотрел вниз — куски повёрнуты так же (DIR_BASIS 1)", m.gib_dir[0] == 1 and m.gib_top_buf[0] == 0.0 and m.gib_top_buf[1] == -16.0
		and m.gib_top_buf[4] == 16.0 and m.gib_bot_buf[1] == -16.0)
	settle(m)
	# 3. Каждый удар с попаданием — всплеск и тряска; удержание не копит тряску
	var tough := zombies(m, [Vector2(12, -2), Vector2(15, 4)], 1e6)
	m._build_grid()
	var b0: int = m.hit_bursts
	var sh0: int = m.shake_hit_count
	var ct0: Transform2D = m.get_viewport().get_canvas_transform()
	var hud0: Vector2 = m.fps_label.get_global_transform_with_canvas().origin
	var max_off := 0.0
	var whole := true
	var nonzero := 0
	for k in 12:
		swing(m)
		m._process(1.0 / 60.0)
		var o: Vector2 = m.camera.offset * m.camera.zoom   # px экрана
		max_off = maxf(max_off, o.length())
		whole = whole and absf(o.x - roundf(o.x)) < 1e-3 and absf(o.y - roundf(o.y)) < 1e-3
		nonzero += 1 if o != Vector2.ZERO else 0
		for f in 2:
			m._process(1.0 / 60.0)
	check("12 ударов подряд с попаданием: всплесков %d, трясок за удар %d" % [m.hit_bursts - b0, m.shake_hit_count - sh0], m.hit_bursts - b0 == 12 and m.shake_hit_count - sh0 == 12)
	var one: float = roundf(minf(float(c.shake_base_px), float(c.shake_max_px)) * float(c.shake_levels[root.get_node("Settings").screen_shake_level]))
	check("тряска за удар по одному: смещение целыми px экрана (%s), есть в %d из 12 кадров удара, не больше %.0f px (%.2f)" % [whole, nonzero, one, max_off], whole and nonzero == 12 and max_off <= one + 1e-3)
	# Удержание: удары каждый тик без затухания — смещение не копится
	max_off = 0.0
	for k in 30:
		swing(m)
		m._process(1.0 / 240.0)
		max_off = maxf(max_off, m.camera.offset.length() * m.camera.zoom.x)
	check("удержание (30 ударов подряд, кадры по 4 мс): смещение не копится — %.2f px, не больше %.0f" % [max_off, one], max_off <= one + 1e-3)
	clear_units(m, tough)
	settle(m)
	# 4. Тряска не сдвигает интерфейс; добил 3 — сумма не больше screen_shake_max_px
	var three := zombies(m, [Vector2(10, 0), Vector2(14, 5), Vector2(15, -5)], 1.0)
	m._build_grid()
	swing(m)
	var shot_img := await shot(m, "shake_ui.png", 1.0 / 120.0)
	var off: Vector2 = m.camera.offset * m.camera.zoom
	var ct1: Transform2D = m.get_viewport().get_canvas_transform()
	var hud1: Vector2 = m.fps_label.get_global_transform_with_canvas().origin
	var d := ct1.origin - ct0.origin
	var cap: float = float(c.shake_max_px) * float(c.shake_levels[st.screen_shake_level])
	check("удар по 3: тряска %.2f px экрана (не больше %.1f), мир сдвинут на (%.2f, %.2f), сдвиг целый, интерфейс на месте" % [off.length(), cap, d.x, d.y],
		off.length() > 0.0 and off.length() <= cap + 1e-3 and d != Vector2.ZERO
		and absf(d.x - roundf(d.x)) < 1e-3 and absf(d.y - roundf(d.y)) < 1e-3 and hud1 == hud0 and shot_img != null)
	for k in 3:
		m._process(0.05)
	check("через 0.15 с камера на месте", m.camera.offset == Vector2.ZERO)
	# 5. Настройка «Тряска экрана» выключает оба вида
	st.screen_shake = false
	var two := zombies(m, [Vector2(10, 0), Vector2(14, 5), Vector2(15, -5)], 1.0)
	m._build_grid()
	var s0: int = m.shake_hit_count
	swing(m)
	m._process(1.0 / 60.0)
	check("«Тряска экрана» выкл. — тряски нет", m.shake_hit_count == s0 and m.camera.offset == Vector2.ZERO)
	st.screen_shake = true
	settle(m)
	# 6. Крупные капли при добиваниях подряд
	var big := 0
	var first_big := -1
	for k in 4:
		zombies(m, [Vector2(13, 0)], 1.0)
		m._build_grid()
		swing(m)
		m._process(1.0 / 120.0)
		var nb := 0
		for i in m.hit_n:
			if m.hit_size[i] == c.big_drop_size and m.hit_drag[i] == c.big_drop_drag:
				nb += 1
		if k == 0:
			first_big = nb
		big = nb
		m._process(0.2)
	var burst := await shot(m, "burst.png", 0.0)
	var first_want: bool = first_big >= int(c.big_drop_count[0]) if c.hero_big_drop_every_kill else first_big == 0
	check("добивания подряд: у первого крупных капель %d (hero_big_drop_every_kill %s), к четвёртому живых %d (2x2, big_drop_count %s)" % [first_big,
		c.hero_big_drop_every_kill, big, c.big_drop_count], first_want and big >= int(c.big_drop_count[0]) and burst != null)
	for k in 30:
		m._process(0.1)
	# 7. Пауза: удар, замеченный кадром на паузе, кусков не создаёт; на паузе куски стоят
	z = zombies(m, [Vector2(13, 0)], 1.0)
	m._build_grid()
	swing(m)
	m.paused = true
	m._process(1.0 / 60.0)
	var g_paused: int = m.gib_n
	m.paused = false
	m._process(0.0)
	z = zombies(m, [Vector2(13, 0)], 1.0)
	m._build_grid()
	swing(m)
	m._process(1.0 / 60.0)
	var gp: Vector2 = m.gib_pos[0]
	m.paused = true
	m._process(0.3)
	var frozen: bool = m.gib_pos[0] == gp and m.gib_n == 1
	m.paused = false
	check("пауза: удар на паузе кусков не создал (%d), на паузе куски стоят" % g_paused, g_paused == 0 and frozen)
	settle(m)
	var stains := await shot(m, "stains.png", 0.0)
	check("через 1.7 с: кусков и частиц нет, пятна в слое есть (%d)" % m.stain_total, m.gib_n == 0 and m.hit_n == 0 and m.stain_total > 0 and stains != null)
	# 8. Лимит max_gibs: добитых на 10 больше, чем пар
	var made := 0
	var gdrop0: int = m.gib_dropped
	var pairs: int = m.gib_age.size()
	while made < pairs + 10:
		zombies(m, [Vector2(10, -4), Vector2(12, 4), Vector2(14, 0), Vector2(16, -6), Vector2(17, 6)], 1.0)
		m._build_grid()
		swing(m)
		made += m.hero_hit_dead.count(1)
		m._process(0.0)
	check("лимит: добито %d, пар кусков %d (max_gibs %d — %d пар), не создано %d" % [made, m.gib_n, int(c.max_gibs), pairs, m.gib_dropped - gdrop0],
		m.gib_n == pairs and m.gib_dropped - gdrop0 == made - pairs)
	settle(m)
	# 9. Армия кусков не создаёт
	m.hero_feed = func(_t): return {"move": Vector2.ZERO}
	m._start_wave()
	var kills0: int = m.wave_kills
	var gd0: int = m.gib_dropped
	var t := 0
	var seen := 0
	while m.wave_kills < kills0 + 20 and t < 30 * 120:
		m._physics_process(DT)
		if t % 2 == 0:
			m._process(1.0 / 60.0)
			seen = maxi(seen, m.gib_n)
		t += 1
	check("армия убила %d без ударов героя — куски только у смертей в камере с шансом gib_chance_mass %s (пар %d, не больше %d)" % [m.wave_kills - kills0,
		str(c.gib_chance_mass), seen, pairs], m.wave_kills >= kills0 + 20 and seen <= pairs)
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
