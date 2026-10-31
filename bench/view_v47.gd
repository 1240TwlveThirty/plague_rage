extends SceneTree
# Вид поля (v47), с окном: волна 10 (seed 3, ворота бессмертны), FPS и время кадра, скриншоты.
# Аргументы: <папка для PNG> [fx 1|0] [debug 1|0] [фильтр замка nearest|linear_mipmap] [warcry 1|0].
# warcry 1 — дар «Клич Благодати» 3 и клич действует весь замер (кнопка и подсветка краёв на экране), суффикс _warcry.
# [spear 1] (задача 8) — до волны 10 куплено 300 копейщиков (отряд у ворот, «держать»), снимок строя view_<тег>_spear_squad.png, суффикс _spear. fx задаёт fx_enabled до _ready;
# [hero 1] (задача 10) — с героем (hero_mode 1, стоит у ворот; с задачи 11 бьёт удержанием J, взгляд вверх), суффикс _hero.
# [chase 1] (задача 13, 9-й аргумент, с hero 1) — герой идёт в орду и бьёт каждый тик (не гибнет): эффекты в реальном бою, суффикс _chase.
# [fxstress 1] (задача 12, с hero 1) — худший случай эффектов попаданий: каждый кадр всплеск на 4 точки (кровь, искры, пятна) —
# частицы и пятна весь замер на лимите data/fx.json; суффикс _fxstress. С героем печатает HEROFX|ударов|попаданий|пик частиц|пик пятен в очереди кадра (задача 27; до задачи 23 — пятен в буфере)|пик пар кусков тела|всплесков (задача 13; в fxstress куски на лимите).
# debug — отладка масок эффектов (как F2), тогда PNG с суффиксом _debug; фильтр (castle_filter) не nearest — суффикс с его именем. PNG: весь кадр, у ворот, края и замок у ворот крупнее (_castle); печатает TORCHES|число факелов.
# Печатает VIEW|fx|юнитов|тик|кадров|FPS|медиана кадра мс|95-й перцентиль мс; PNG: весь кадр, у ворот, левый и правый край.
const WARM_TICKS := 480    # 16 с (ускоренно): орда подходит к строю, бой идёт во время замера
const FRAMES := 2000

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var fx := args.size() < 2 or args[1] != "0"
	var debug := args.size() >= 3 and args[2] == "1"
	var filter: String = args[3] if args.size() >= 4 else "nearest"
	var warcry := args.size() >= 5 and args[4] == "1"
	var spear := args.size() >= 6 and args[5] == "1"
	var hero := args.size() >= 7 and args[6] == "1"   # задача 10: с героем (стоит у ворот, ввода нет), суффикс строки |hero
	var stress := hero and args.size() >= 8 and args[7] == "1"
	var chase := hero and args.size() >= 9 and args[8] == "1"   # задача 13: герой идёт к ближайшему зомби и бьёт каждый тик, не гибнет
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = 3
	if warcry:
		m.active_gifts = {"war_cry": 3}
	if hero:
		m.hero_mode = 1
		m.hero_feed = func(_t): return {"attack": true}   # задача 11: удар удержанием J — вспышка и мигание каждые 0.8 с
		if chase:
			m.hero_feed = func(_t): return _chase(m)
	if "fx_enabled" in m:
		m.fx_enabled = fx
	if "castle_filter" in m:
		m.castle_filter = filter
	root.add_child(m)
	current_scene = m
	for i in 8:
		await process_frame
	if spear:
		m.gold = 1e6
		m.shop_enabled[m.SHOP_ITEMS.find("spear_pack")] = 1   # в данных v1 копейщики выключены (задача 9)
		for k in 10:
			m._buy(m.SHOP_ITEMS.find("spear_pack"))
		m.squad_order[2] = m.ORDER_HOLD
		m.squad_target[2] = Vector2(1330, 520)   # для снимка — в поле справа от пехоты
		m.banner.visible = false
		var t0: int = m.tick_counter
		while m.tick_counter < t0 + 300:   # отряд выходит из ворот и собирает строй (по тикам симуляции, не по кадрам)
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var px: Vector2 = Vector2(shot.get_size()) / m.get_viewport_rect().size
		var c: Vector2 = (m.get_viewport().get_canvas_transform() * m.squad_pos[2]) * px
		shot.get_region(Rect2i(int(c.x) - 240, int(c.y) - 135, 480, 270)).save_png(out_dir.path_join("view_spear_squad.png"))
		shot.save_png(out_dir.path_join("view_spear_squad_full.png"))
	m.wave_number = 9
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	if chase and m.hero_idx >= 0:
		m.hp[m.hero_idx] = 1e6
	Engine.time_scale = 4.0
	while m.tick_counter < WARM_TICKS and m.wave_state == m.WS_BATTLE:
		await process_frame
	Engine.time_scale = 1.0
	if warcry:
		m.war_cry_dur = 1000000   # для замера: клич действует до конца
		m.request_war_cry()
		await process_frame
		await process_frame
	if debug:
		m.color_mode = 1
		m._sync_fx_debug()
	var dts := PackedFloat64Array()
	var t_prev := Time.get_ticks_usec()
	var t0 := t_prev
	var peak := 0
	var gpeak := 0
	var speak := 0   # задача 27: пик пятен в очереди кадра (stain_used — кольцевой буфер — убран в задаче 23; обращение к нему обрывало скрипт до quit(), окно висело)
	for i in FRAMES:
		await process_frame
		if stress:
			var c: Vector2 = m.HERO_SPAWN + Vector2(0, -60)
			m.hero_hit_pos = PackedVector2Array([c, c + Vector2(20, 5), c + Vector2(-20, 5), c + Vector2(0, -15)])
			m.hero_hit_idx = PackedInt32Array([0, 0, 0, 0])
			m.hero_hit_dead = PackedByteArray([i % 2, 0, 1, 0])
			if "hero_hit_type" in m:
				m.hero_hit_type = PackedInt32Array([m.zombie_type, m.zombie_type, m.knight_type, m.zombie_type])   # задача 13: куски тела добитых
				m.hero_hit_dir = PackedByteArray([0, 1, 2, 3])
			m.hero_swing_from = m.HERO_SPAWN
			m._hit_fx_spawn()
		if hero:
			peak = maxi(peak, m.hit_n)
			gpeak = maxi(gpeak, m.get("gib_n") if "gib_n" in m else 0)
			speak = maxi(speak, m.get("stain_stamp_n") if "stain_stamp_n" in m else 0)
		var t := Time.get_ticks_usec()
		dts.append((t - t_prev) / 1000.0)
		t_prev = t
	var fps := FRAMES / ((t_prev - t0) / 1e6)
	var sorted := dts.duplicate()
	sorted.sort()
	print("VIEW|%s|%d|%d|%d|%.1f|%.3f|%.3f" % [("fx" if fx else "nofx") + ("_warcry" if warcry else "") + ("_spear" if spear else "") + ("_hero" if hero else "") + ("_fxstress" if stress else "") + ("_chase" if chase else ""), m.count, m.tick_counter, FRAMES, fps, sorted[FRAMES / 2], sorted[FRAMES * 95 / 100]])
	if hero:
		print("HEROFX|%d|%d|%d|%d|%d|%d|убито героем %d" % [m.hero_swing_n, m.hero_hits, peak, speak, gpeak, m.get("hit_bursts") if "hit_bursts" in m else -1, m.hero_kills])
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var tag: String = ("fx" if fx else "nofx") + ("_debug" if debug else "") + ("" if filter == "nearest" else "_" + filter) + ("_warcry" if warcry else "") + ("_spear" if spear else "")
	img.save_png(out_dir.path_join("view_%s_full.png" % tag))
	# Точка поля p — пиксель кадра: преобразование холста (камера с зумом camera_min_zoom), затем масштаб окна к базе
	var to_px: Vector2 = Vector2(img.get_size()) / m.get_viewport_rect().size
	var gate: Vector2 = (m.get_viewport().get_canvas_transform() * m.GATE_POS) * to_px
	img.get_region(Rect2i(int(gate.x) - 480, int(gate.y) - 300, 960, 540)).save_png(out_dir.path_join("view_%s_gate.png" % tag))
	img.get_region(Rect2i(0, 300, 640, 560)).save_png(out_dir.path_join("view_%s_left.png" % tag))
	img.get_region(Rect2i(img.get_width() - 640, 300, 640, 560)).save_png(out_dir.path_join("view_%s_right.png" % tag))
	img.get_region(Rect2i(int(gate.x) - 240, int(gate.y) - 80, 480, 270)).save_png(out_dir.path_join("view_%s_castle.png" % tag))
	print("TORCHES|%d" % m.fx_torches)
	quit()


# chase: к ближайшему живому зомби (стоит, если ближе 12 px), взгляд на него, удар каждый тик (как bench/regress_hero.gd).
func _chase(m: Node2D) -> Dictionary:
	var h: int = m.hero_idx
	if h < 0:
		return {"move": Vector2.ZERO}
	var best := -1
	var bd := INF
	for j in m.count:
		if m.team[j] == 1 and m.hp[j] > 0.0:
			var d: float = m.pos[h].distance_squared_to(m.pos[j])
			if d < bd:
				bd = d
				best = j
	if best < 0:
		return {"move": Vector2.ZERO, "attack": true}
	var to: Vector2 = m.pos[best] - m.pos[h]
	return {"move": to.normalized() if bd > 144.0 else Vector2.ZERO, "face": to.angle(), "attack": true}
