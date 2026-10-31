extends SceneTree
# Смоук задачи 12 с окном: эффекты попаданий героя (игровой режим через Game, герой по данным; data/fx.json). Скриншоты в папку
# из аргумента: hit_ready.png — герой в поле, впереди зомби; hit_spark.png — первый кадр удара: искры и белые задетые;
# hit_blood.png — через 0.1 с: всплеск крови летит от героя; hit_stains.png — через 1 с: частиц нет, пятна на земле (слой крови,
# задача 23 — не гаснут); hit_shake.png — удар по 3: тряска экрана. Кадры отрисовки — вручную (m._process(delta)), тики —
# m._physics_process. Значения — из data/fx.json.
const DIR := "user://bench_v62"
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

# Непрозрачных пикселей слоя крови (задача 23) в круге радиуса r (мир) у точки c: пятна под юнитами могут быть закрыты спрайтами
# на снимке экрана, поэтому проверяется сам слой.
func layer_px(m: Node2D, c: Vector2, r: float) -> int:
	var img: Image = m.stain_vp.get_texture().get_image()
	var sc := float(m.hit_cfg.stain_layer_scale)
	var n := 0
	for y in range(-int(r), int(r) + 1):
		for x in range(-int(r), int(r) + 1):
			if x * x + y * y > r * r:
				continue
			var q := Vector2i(((c + Vector2(x, y)) * sc).round())
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and img.get_pixelv(q).a > 0.0:
				n += 1
	return n

# Пикселей «крови» (красный заметно больше зелёного и синего), изменившихся между снимками, в круге радиуса r (мир) у точки c.
func red_changed(m: Node2D, a: Image, b: Image, c: Vector2, r: float) -> int:
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
			if cb.r > cb.g + 0.15 and cb.r > cb.b + 0.1 and absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.15:
				n += 1
	return n

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

# Зомби у героя: смещения w, HP каждого; индексы.
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
	var h: int = m.hero_idx
	m.pos[h] = P
	m.prev_pos[h] = P
	check("data/fx.json загружен: лимит частиц %d, пятен за кадр %d (слой крови), тряска %s (%d px на %.2f с)" % [m.hit_cfg.max_particles, m.hit_cfg.stains_per_frame,
		m.hit_cfg.screen_shake_enabled, int(m.hit_cfg.shake_base_px), m.hit_cfg.shake_time], not m.hit_cfg.is_empty() and m.hit_pos.size() == int(m.hit_cfg.max_particles)
		and m.stain_vp != null and st.screen_shake)
	var stains0: int = m.stain_total
	var z := zombies(m, [Vector2(14, 0), Vector2(20, 9), Vector2(21, -8)], 100.0)
	m.hp[z[1]] = 1.0   # этот удар его добьёт
	m.hero_feed = func(_t): return {"move": Vector2.ZERO, "face": 0.0}
	m._physics_process(DT)
	m.prev_pos = m.pos.duplicate()
	var ready := await shot(m, "hit_ready.png")
	var rng_state := [m.unit_rng.state, m.arrow_rng.state]
	swing(m)
	check("удар: задеты 3, один добит", m.hero_hit_idx.size() == 3 and m.hero_hit_dead.count(1) == 1)
	var hit_at: Vector2 = m.hero_hit_pos[1]
	var spark := await shot(m, "hit_spark.png", 1.0 / 120.0)
	var n0: int = m.hit_n
	var sparks := 0
	var away := 0
	var blood := 0
	for i in m.hit_n:
		if m.hit_drag[i] == 0.0:
			sparks += 1
		else:
			blood += 1
			if m.hit_vel[i].x > 0.0:
				away += 1
	var bh: Array = m.hit_cfg.blood_hit
	var bk: Array = m.hit_cfg.blood_kill
	var mult := float(m.hit_cfg.hero_blood_mult)   # задача 23: брызг от удара героя больше, крупные капли на каждом добитом
	var bd: Array = m.hit_cfg.big_drop_count if m.hit_cfg.hero_big_drop_every_kill else [0, 0]
	var lo := 2 * roundi(bh[0] * mult) + roundi(bk[0] * mult) + int(bd[0])
	var hi := 2 * roundi(bh[1] * mult) + roundi(bk[1] * mult) + int(bd[1])
	check("первый кадр: искр %d (spark_count на попадание), крови %d (2 задетых по %d–%d, добитый %d–%d, x%.1f, крупных капель %d–%d — от %d до %d)" % [sparks, blood,
		bh[0], bh[1], bk[0], bk[1], mult, bd[0], bd[1], lo, hi],
		sparks == 3 * int(m.hit_cfg.spark_count) and blood >= lo and blood <= hi)
	check("кровь летит от героя по направлению удара (вправо) с разбросом: %d из %d со скоростью вправо" % [away, blood], away == blood)
	check("ГСЧ симуляции (unit_rng, arrow_rng) эффекты не трогают", rng_state == [m.unit_rng.state, m.arrow_rng.state])
	check("задетые мигают белым (custom.y)", m.buf[z[0] * m.FLOATS_PER_UNIT + 13] == 1.0)
	var bright := 0
	var px: Vector2 = Vector2(spark.get_size()) / m.get_viewport_rect().size
	var ct: Transform2D = m.get_viewport().get_canvas_transform()
	for k in [z[0], z[2]]:
		var q := Vector2i((ct * m.hero_hit_pos[m.hero_hit_idx.find(k)]) * px)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var c := spark.get_pixelv(q + Vector2i(dx, dy))
				if c.r > 0.9 and c.g > 0.8:
					bright += 1
	check("на экране искры и мигание: ярких пикселей у точек попадания %d" % bright, bright >= 6)
	var blood_img := await shot(m, "hit_blood.png", 0.1)
	var red := red_changed(m, ready, blood_img, hit_at + Vector2(6, 0), 14.0)
	check("через 0.1 с: кровь на экране (%d красных пикселей у точки добивания), частицы живы (%d), замедляются" % [red, m.hit_n], red >= 8 and m.hit_n > 0)
	for k in 8:   # 0.9 с: крупные капли живут до big_drop_life (0.8 с)
		m._process(0.1)
	var stains := await shot(m, "hit_stains.png", 0.0)
	check("через 0.9 с: частиц нет (гаснут за 0.3–0.8 с), пятна на земле: %d (по 1 на задетого, 3 на добитого)" % (m.stain_total - stains0), m.hit_n == 0
		and m.stain_total - stains0 == 5 and layer_px(m, hit_at + Vector2(4, 0), 14.0) >= 5)
	var sn: Node = m.stain_layer
	var pn: Node = null
	for c in m.get_children():
		if c is MultiMeshInstance2D and c.multimesh == m.hit_mm:
			pn = c
	check("слой крови под юнитами (тот же z, раньше в дереве), кровь и искры — над героем (z героя, позже в дереве)", sn != null and sn.z_index == m.unit_node.z_index
		and sn.get_index() < m.unit_node.get_index() and pn != null and pn.z_index == m.hero_view.z_index and pn.get_index() > m.hero_view.get_index())
	for k in 70:
		m._process(0.1)
	var later := await shot(m, "hit_stains_later.png", 0.0)
	check("через 7 с пятна на месте (слой крови не гаснет, подсыхает только после волны): пикселей слоя у удара %d" % layer_px(m, hit_at + Vector2(4, 0), 14.0),
		layer_px(m, hit_at + Vector2(4, 0), 14.0) >= 5)
	# Пауза: новые не создаются, старые стоят
	swing(m, PI)
	m.hp[z[0]] = 100.0
	swing(m)
	m.paused = true
	m._process(1.0 / 60.0)
	var n_paused: int = m.hit_n
	m.paused = false
	m._process(0.0)
	check("удар, замеченный кадром на паузе: частиц не создано", n_paused == 0)
	swing(m)
	m._process(0.0)
	var p_before: Vector2 = m.hit_pos[1]
	m.paused = true
	m._process(0.2)
	var frozen: bool = m.hit_pos[1] == p_before and m.hit_n > 0
	m.paused = false
	for k in 10:
		m._process(0.1)
	check("на паузе частицы стоят и не гаснут; после — гаснут", frozen and m.hit_n == 0)
	# Лимит частиц и пятен за кадр
	var many := zombies(m, [Vector2(10, -3), Vector2(12, 3), Vector2(16, -1)], 1e6)
	var s_before: int = m.stain_skipped
	for k in 80:
		swing(m)
		m._process(0.0)
	var cap := int(m.hit_cfg.max_particles)
	check("лимит: живых частиц %d (не больше max_particles %d), не создано %d; пятен в очереди кадра %d (не больше stains_per_frame %d), сверх — не впечатаны (%d)" % [
		m.hit_n, cap, m.hit_dropped, m.stain_stamp_n, int(m.hit_cfg.stains_per_frame), m.stain_skipped - s_before],
		m.hit_n <= cap and m.hit_n > cap * 0.8 and m.hit_dropped > 0 and m.stain_stamp_n <= int(m.hit_cfg.stains_per_frame) and m.stain_skipped > s_before)
	for k in 10:
		m._process(0.1)
	for j in many:
		m.hp[j] = 0.0
	m._remove_dead()
	# Тряска (задача 23): удар по 3 — амплитуда shake_base_px + shake_extra_px за каждые shake_extra_per попавших, x уровень
	var c: Dictionary = m.hit_cfg
	var zz := zombies(m, [Vector2(10, 0), Vector2(14, 5), Vector2(15, -5)], 1.0)
	m._build_grid()
	var shakes: int = m.shake_hit_count
	swing(m)
	m._process(0.0)
	var off: Vector2 = m.shake_raw * m.camera.zoom   # задача 28: до урезания краем поля
	var lvl: float = c.shake_levels[st.screen_shake_level]
	var want: float = minf(float(c.shake_base_px) + float(c.shake_extra_px) * floorf(m.hero_hit_pos.size() / float(c.shake_extra_per)), float(c.shake_max_px)) * lvl
	var shake_img := await shot(m, "hit_shake.png", 0.02)
	m._process(0.1)
	check("удар по %d: тряска экрана (амплитуда %.1f — ждём %.1f, смещение %.2f px экрана, не больше %.1f), через shake_time камера на месте" % [m.hero_hit_pos.size(),
		m.shake_last_amp, want, off.length(), float(c.shake_max_px) * lvl], m.shake_hit_count == shakes + 1 and is_equal_approx(m.shake_last_amp, want)
		and off.length() > 0.0 and off.length() <= float(c.shake_max_px) * lvl + 0.001 and m.camera.offset == Vector2.ZERO)
	st.screen_shake = false
	zz = zombies(m, [Vector2(10, 0), Vector2(14, 5), Vector2(15, -5)], 1.0)
	swing(m)
	m._process(0.0)
	check("«Тряска экрана» выключена в настройках — тряски нет", m.shake_hit_count == shakes + 1 and m.camera.offset == Vector2.ZERO)
	st.screen_shake = true
	for k in 10:
		m._process(0.1)
	# Убийства армией частиц не создают: бой без ударов героя
	m.hero_feed = func(_t): return {"move": Vector2.ZERO}
	m._start_wave()
	var kills0: int = m.wave_kills
	var t := 0
	while m.wave_kills < kills0 + 20 and t < 30 * 120:
		m._physics_process(DT)
		if t % 2 == 0:
			m._process(1.0 / 60.0)
		t += 1
	check("армия убила %d зомби без ударов героя — резня (задача 23): смертей с брызгами %d, пятен в слое %d, ударов героя не было" % [m.wave_kills - kills0, m.mass_shown, m.stain_total],
		m.wave_kills >= kills0 + 20 and m.stain_total > 0)
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
