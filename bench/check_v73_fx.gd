extends SceneTree
# Тесты задачи 23 (без окна): резня, слой крови, тряска, «Жестокость». Значения баланса — из data/fx.json, не зашиты.
#   потолки: смертей с брызгами за кадр (mass_deaths_per_frame, лишние — выборка; брызги — квад с шейдером, не больше mass_splash_max),
#   пятен за кадр (stains_per_frame), частиц всего (max_particles), кусков (max_gibs); брызги и куски — только в видимой области;
#   добитые героем не показываются второй раз; тряска — shake_base_px + shake_extra_px за каждые shake_extra_per попавших, не больше
#   shake_max_px, x shake_levels[уровень настройки], смещение — целые px экрана, не больше потолка; «Жестокость: выкл» — без кусков,
#   брызги цветов пыли, пятна stain_colors_no_gore; новый забег — слой с нуля; смерти из боя доходят до эффектов (событие смерти).
const DT := 1.0 / 30.0
const DIR := "user://bench_v73"
var fails := 0
var c: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func make() -> Node2D:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	m.spawn_seed = 3
	m.hero_mode = 1
	m.record_path = "user://record_bench.json"
	m.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m)
	return m

# Смерти в очередь событий: n штук, в видимой области (inside) или за ней.
func deaths(m: Node2D, n: int, inside: bool, team := 1) -> void:
	var vr: Rect2 = m.view_rect()
	for k in n:
		if m.death_n >= m.death_pos.size():
			break
		var p := vr.get_center() + Vector2((k % 40) * 6.0 - 120.0, (k / 40) * 6.0 - 60.0) if inside else vr.position - Vector2(200.0 + k, 200.0)
		m.death_pos[m.death_n] = p
		m.death_team[m.death_n] = team
		m.death_type[m.death_n] = m.zombie_type
		m.death_dir[m.death_n] = 0
		m.death_n += 1

func _run() -> void:
	c = JSON.parse_string(FileAccess.get_file_as_string("res://data/fx.json"))
	var st := root.get_node("Settings")
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	var m := make()
	await step(3)
	check("эффекты загружены, слой крови %s (x%s), буфер смертей %d" % [str(m.stain_vp.size) if m.stain_vp else "-", str(c.stain_layer_scale), m.death_pos.size()],
		not m.hit_cfg.is_empty() and m.stain_vp != null and m.death_pos.size() == int(c.death_buffer) and m.hit_pos.size() == int(c.max_particles)
		and m.gib_age.size() == int(c.max_gibs) / 2 and m.stain_stamp_buf.size() == int(c.stains_per_frame) * m.HIT_FPI)
	# --- потолки резни ---
	st.gore = 1
	var h0: int = m.hit_n
	var s0: int = m.stain_total
	var shown0: int = m.mass_shown
	deaths(m, m.death_pos.size(), true)
	var queued: int = m.death_n
	m._hit_fx_frame(1.0 / 60.0)
	var shown: int = m.mass_shown - shown0
	check("%d смертей в кадре в видимой области: с брызгами %d (не больше %d), выборкой пропущено %d, квадов брызг %d (не больше %d), частиц CPU не прибавилось (%d)" % [
		queued, shown, int(c.mass_deaths_per_frame), m.mass_sampled_out, m.splash_used, int(c.mass_splash_max), m.hit_n],
		shown == int(c.mass_deaths_per_frame) and m.mass_sampled_out == queued - shown and m.mass_frame_max == shown and m.splash_used == shown
		and m.splash_used <= int(c.mass_splash_max) and m.hit_n == h0 and m.death_n == 0)
	var stamped: int = m.stain_total - s0
	check("пятен за кадр впечатано %d (не больше %d), лишние не впечатаны (%d)" % [stamped, int(c.stains_per_frame), m.stain_skipped],
		stamped <= int(c.stains_per_frame) and stamped > 0 and m.stain_stamp_n <= int(c.stains_per_frame) and m.stain_skipped > 0)
	# за пределами камеры — без брызг и кусков, пятна есть
	for f in 120:
		m._hit_fx_frame(1.0 / 60.0)   # частицы прошлых кадров гаснут
	await step(2)
	h0 = m.hit_n
	shown0 = m.mass_shown
	var g0: int = m.gib_mass
	var sp0: int = m.splash_head
	s0 = m.stain_total
	deaths(m, 20, false)
	m._hit_fx_frame(1.0 / 60.0)
	check("20 смертей вне камеры: брызг и кусков нет, пятна в слой есть (%d)" % (m.stain_total - s0), m.mass_shown == shown0 and m.gib_mass == g0
		and m.splash_head == sp0 and m.stain_total - s0 == 20 * int(c.mass_stains))
	await step(2)
	# добитые героем — не второй раз
	s0 = m.stain_total
	shown0 = m.mass_shown
	deaths(m, 1, true)
	m.hero_kill_pos.append(m.death_pos[0])
	m._hit_fx_frame(1.0 / 60.0)
	check("смерть добитого героем (в hero_kill_pos) резнёй не показывается второй раз", m.mass_shown == shown0 and m.stain_total == s0)
	await step(2)
	# потолок кусков: много кадров по полной выборке, шанс куска — из данных
	var pairs := int(c.max_gibs) / 2
	var peak := 0
	for f in 200:
		deaths(m, int(c.mass_deaths_per_frame), true)
		m._hit_fx_frame(0.001)
		peak = maxi(peak, m.gib_n)
		await process_frame
	check("куски: пар не больше %d (max_gibs %d), было до %d, кусков у смертей не от героя %d (шанс %s)" % [pairs, int(c.max_gibs), peak, m.gib_mass, str(c.gib_chance_mass)],
		peak <= pairs and (m.gib_mass > 0 or float(c.gib_chance_mass) == 0.0))
	# --- тряска ---
	var levels: Array = c.shake_levels
	var zoom: Vector2 = m.camera.zoom
	for lvl in levels.size():
		st.screen_shake_level = lvl
		for hits in [1, int(c.shake_extra_per) * 2, int(c.shake_extra_per) * 20]:
			_fake_swing(m, hits, false)
			var cnt0: int = m.shake_hit_count
			m._hit_fx_spawn()
			var want := minf(float(c.shake_base_px) + float(c.shake_extra_px) * floorf(hits / float(c.shake_extra_per)), float(c.shake_max_px)) * float(levels[lvl])
			var ok := true
			var info := "уровень %d, попавших %d: амплитуда %.2f (ждём %.2f)" % [lvl, hits, m.shake_last_amp if m.shake_hit_count > cnt0 else 0.0, want]
			if want <= 0.0:
				ok = m.shake_hit_count == cnt0
			else:
				ok = m.shake_hit_count == cnt0 + 1 and is_equal_approx(m.shake_last_amp, want)
				m._hit_fx_frame(1.0 / 60.0)
				var off: Vector2 = m.camera.offset * zoom
				var cap := float(c.shake_max_px) * float(levels[lvl])
				ok = ok and off != Vector2.ZERO and off == off.round() and off.length() <= maxf(floorf(cap), 1.0) + 0.001
				info += ", смещение %s px экрана (не больше %.1f)" % [str(off), cap]
			check("тряска: " + info, ok)
			for f in 20:
				m._hit_fx_frame(1.0 / 60.0)
	check("тряска гаснет: через shake_time смещения нет", m.camera.offset == Vector2.ZERO)
	st.screen_shake_level = 2
	# --- «Жестокость: выкл» ---
	st.gore = 0
	await step(2)
	var gn0: int = m.gib_n
	var gm0: int = m.gib_mass
	var hn0: int = m.hit_n
	_fake_swing(m, 3, true)
	m._hit_fx_spawn()
	var spawned: int = m.hit_n - hn0
	var dust := true
	var dcols: Array = c.dust_colors.map(func(x): return Color(x))
	var scols: Array = c.spark_colors.map(func(x): return Color(x))
	for i in range(hn0, m.hit_n):
		dust = dust and (has_color(dcols, m.hit_col[i]) or has_color(scols, m.hit_col[i]))
	var gray := true
	var ncols: Array = c.stain_colors_no_gore.map(func(x): return Color(x))
	for k in m.stain_stamp_n:
		var o: int = k * m.HIT_FPI
		gray = gray and has_color(ncols, Color(m.stain_stamp_buf[o + 8], m.stain_stamp_buf[o + 9], m.stain_stamp_buf[o + 10]))
	var spl_dust := true
	for f in 100:
		deaths(m, int(c.mass_deaths_per_frame), true)
		m._hit_fx_frame(0.001)
		var o: int = ((m.splash_head - 1 + int(c.mass_splash_max)) % int(c.mass_splash_max)) * m.SPLASH_FPI
		spl_dust = spl_dust and has_color(dcols, Color(m.splash_buf[o + 8], m.splash_buf[o + 9], m.splash_buf[o + 10]))
		await process_frame
	check("«Жестокость: выкл»: удар героя с добиванием и сотни смертей — кусков нет, брызги — пыль и искры (и у смертей — цвет пыли), пятна серые",
		m.gib_n == gn0 and m.gib_mass == gm0 and dust and gray and spl_dust and spawned > 0, "куски %d->%d, у смертей %d->%d, пыль %s, серые %s, брызги смертей %s, частиц от удара %d" % [
		gn0, m.gib_n, gm0, m.gib_mass, dust, gray, spl_dust, spawned])
	st.gore = 1
	# --- смерти из боя, слой сбрасывается в новом забеге ---
	m.queue_free()
	await step(2)
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(3)
	var m1 := current_scene as Node2D
	m1._start_wave()
	for t in 900:
		m1._physics_process(DT)
		m1._process(1.0 / 30.0)
		if t % 10 == 0:
			await process_frame
	check("бой без героя: смерти доходят до эффектов — пятен %d, смертей с брызгами %d, событий сверх буфера %d" % [m1.stain_total, m1.mass_shown, m1.death_over],
		m1.stain_total > 0 and m1.mass_shown > 0 and m1.first_death_tick >= 0)
	m1._abandon_run()
	g.start_run(1)
	await step(3)
	var m2 := current_scene as Node2D
	check("новый забег: слой крови с нуля (пятен %d, очищается на кадре: %s)" % [m2.stain_total, m2.stain_vp.render_target_clear_mode == SubViewport.CLEAR_MODE_ONCE],
		m2 != m1 and m2.stain_total == 0 and m2.stain_vp.render_target_clear_mode == SubViewport.CLEAR_MODE_ONCE)
	m2.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Цвет есть в списке (буферы MultiMesh — float32: сравнение с допуском).
func has_color(list: Array, col: Color) -> bool:
	for x in list:
		if absf(x.r - col.r) < 0.002 and absf(x.g - col.g) < 0.002 and absf(x.b - col.b) < 0.002:
			return true
	return false

# Удар героя по hits зомби (только данные для отрисовки: позиции рядом с героем), dead — все добиты.
func _fake_swing(m: Node2D, hits: int, dead: bool) -> void:
	var p: Vector2 = m.pos[m.hero_idx] if m.hero_idx >= 0 else m.view_rect().get_center()
	m.hero_hit_idx = PackedInt32Array()
	m.hero_hit_pos = PackedVector2Array()
	m.hero_hit_dead = PackedByteArray()
	m.hero_hit_type = PackedInt32Array()
	m.hero_hit_dir = PackedByteArray()
	m.hero_swing_from = p
	for k in hits:
		m.hero_hit_idx.append(0)
		m.hero_hit_pos.append(p + Vector2(10.0 + k % 5, -8.0 + k / 5))
		m.hero_hit_dead.append(1 if dead else 0)
		m.hero_hit_type.append(m.zombie_type)
		m.hero_hit_dir.append(0)
