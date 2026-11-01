extends SceneTree
# Задача 29 (без окна): видимые стрелы (scripts/arrow_fx.gd). Числа — из data/arrows_fx.json, data/audio.json.
#   Полёт (шейдер; проверяется его копия flight_at по данным буфера): стрела видна при arrow_t0 <= td < arrow_tick, выходит из
#   лучника (+ высота выпуска), к тику падения — ровно в точке падения; вершина дуги — arc_height_rel дистанции; тень на прямой
#   лучник — точка падения.
#   Предел: стрел в очереди больше max_visible — в слотах каждая N-я по номеру выстрела (не больше max_visible); меньше — все.
#   LOD: стрела короче lod_min_screen_px на экране — полёт и тени скрыты; ничего не летит — тоже.
#   Падение: искра (попадание) или воткнутая (промах) — когда время картинки дошло до тика падения; искра живёт spark_frames кадров,
#   воткнутая гаснет за stuck_life; воткнутых не больше max_stuck. В бою искр столько же, сколько попаданий симуляции.
#   Звук: без файлов (записи только в future_sounds) код доходит до вызова, но Audio не зовётся — в кеше потоков нет ни одного
#   arrow_*, значит и предупреждений нет; запись с несуществующим файлом — поток null один раз, дальше молча.
#   Флаг «Показывать стрелы» выкл: отрисовка стрел не вызывается (счётчик вызовов стоит, ноды скрыты), событий падения нет,
#   симуляция та же, что с флагом вкл (pos, hp, стрелы — бит в бит). Флаг хранится в settings.cfg (временная папка).
const DT := 1.0 / 30.0
var fails := 0
var c: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	_run.call_deferred()

# Очередь стрел main: n штук от a к b (t0, t1), номера выстрелов с vid0.
func fake(m: Node2D, n: int, a: Vector2, b: Vector2, t0: float, t1: int, vid0 := 0) -> void:
	m.arrow_count = n
	for k in n:
		m.arrow_from[k] = a
		m.arrow_land[k] = b
		m.arrow_t0[k] = t0
		m.arrow_tick[k] = t1
		m.arrow_vid[k] = vid0 + k

func state(m: Node2D) -> Array:
	return [m.count, m.pos.slice(0, m.count), m.hp.slice(0, m.count), m.arrows_fired, m.arrows_hit, m.arrow_count, m.gold, m.tick_counter]

func _run() -> void:
	print("CHECK v79: видимые стрелы")
	c = JSON.parse_string(FileAccess.get_file_as_string("res://data/arrows_fx.json"))
	var st: Node = root.get_node("Settings")
	var tmp := OS.get_temp_dir().path_join("plague_v79_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(tmp)
	var st_path0: String = st.path
	var persist0: bool = st.persist
	st.path = tmp.path_join("settings.cfg")   # свой файл настроек: настоящий user://settings.cfg не трогается
	var g: Node = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute("user://bench_v79")
	g.save_path = "user://bench_v79/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(8)
	var m: Node2D = current_scene
	var fx: Node2D = m.arrow_fx
	check("отрисовка стрел установлена из data/arrows_fx.json (max_visible %d)" % int(c.max_visible), fx != null and not fx.cfg.is_empty()
		and fx.air_mm.instance_count == int(c.max_visible))
	if fx == null:
		print("CHECK: провалов %d" % fails)
		quit(1)
		return
	var art := ResourceLoader.exists(c.art_path)
	check("вид: %s, размер в мире %s" % ["картинка " + c.art_path if art else "кодом (нет " + c.art_path + "): древко %d px" % int(c.shaft_px), str(fx.arrow_size)],
		fx.from_art == art and (fx.arrow_size == Vector2(c.art_size_px[0], c.art_size_px[1]) if art else fx.arrow_size == Vector2(int(c.shaft_px) + 2, 3)))
	if not art:
		var img: Image = fx.make_arrow_image(fx.cfg)
		var mid := img.get_pixel(1, 1)
		check("стрела кодом: древко светлое (%s), контур тёмный (%s)" % [mid.to_html(false), img.get_pixel(0, 1).to_html(false)],
			mid.is_equal_approx(Color(c.shaft_color)) and img.get_pixel(0, 1).is_equal_approx(Color(c.outline_color)) and img.get_pixel(1, 0).is_equal_approx(Color(c.outline_color)))
	m.paused = true   # симуляция стоит: очередь стрел задаёт тест
	await step(2)
	var tick0: int = m.tick_counter
	var view: Rect2 = m.view_rect()
	var a: Vector2 = view.get_center() + Vector2(-150, 60)
	var b: Vector2 = view.get_center() + Vector2(150, -20)
	var dist := a.distance_to(b)
	# --- полёт (шейдер; здесь — его копия flight_at по тем же данным буфера, совпадение с картинкой — smoke_v79_arrows) ---
	var t0 := float(tick0)
	var t1 := tick0 + 30
	fake(m, 1, a, b, t0, t1)
	fx.on = true
	fx.clear()
	fx.frame(t0 - 0.5, 0.0, 1.0)   # включение: очередь — в слоты
	var k0: int = fx.slot_for(0)
	check("стрела очереди — в слоте (%d), буфер MultiMesh: %d слотов" % [k0, fx.air_mm.instance_count], k0 >= 0 and fx.registered)
	check("до выпуска (td < t0) стрелы нет", not fx.flight_at(k0, t0 - 0.5)[0] and fx.count_in_flight(t0 - 0.5) == 0)
	var f0: Array = fx.flight_at(k0, t0)
	check("в момент выпуска — у лучника, на высоте выпуска %s: %s" % [c.launch_height_px, str(f0[1])], f0[0]
		and (f0[1] as Vector2).is_equal_approx(a - Vector2(0, c.launch_height_px)) and (fx.flight_at(k0, t0, true)[1] as Vector2).is_equal_approx(a))
	var fm: Array = fx.flight_at(k0, t0 + 15.0)
	var top := (a + b) * 0.5 - Vector2(0, float(c.launch_height_px) * 0.5 + float(c.arc_height_rel) * dist)
	check("середина пути: тень на прямой, стрела выше на launch/2 + arc_height_rel * дистанция = %.1f px" % (top.y - (a + b).y * 0.5),
		(fm[1] as Vector2).is_equal_approx(top) and (fx.flight_at(k0, t0 + 15.0, true)[1] as Vector2).is_equal_approx((a + b) * 0.5))
	var f1: Array = fx.flight_at(k0, t1 - 0.001)
	check("перед тиком падения — у точки падения (%.2f px)" % (f1[1] as Vector2).distance_to(b), f1[0] and (f1[1] as Vector2).distance_to(b) < 0.1)
	check("на тике падения стрелы в полёте нет", not fx.flight_at(k0, float(t1))[0] and fx.count_in_flight(float(t1)) == 0)
	var up: Vector2 = fx.flight_at(k0, t0 + 3.0)[2]
	var down: Vector2 = fx.flight_at(k0, t0 + 27.0)[2]
	check("поворот по направлению движения: на взлёте нос вверх (%.2f), на снижении вниз (%.2f)" % [up.y, down.y], up.y < 0.0 and down.y > 0.0)
	# --- предел max_visible и выборка ---
	var cap := int(c.max_visible)
	var many := cap * 3 + 7
	fake(m, many, a, b, t0, t1, 1000)
	fx.register_queue()
	var stride := ceili(float(many) / cap)
	var want := 0
	for k in many:
		if (1000 + k) % stride == 0:
			want += 1
	var fl: int = fx.count_in_flight(t0 + 10.0)
	check("в полёте %d (> max_visible %d): на экране %d — каждая %d-я по номеру выстрела (их %d), не меньше половины предела" % [many, cap, fl, fx.stride, want],
		fl == want and fl <= cap and fl * 2 >= cap and fx.stride == stride)
	fake(m, cap - 5, a, b, t0, t1)
	fx.register_queue()
	fl = fx.count_in_flight(t0 + 10.0)
	check("в полёте %d (не больше max_visible): на экране все" % (cap - 5), fl == cap - 5 and fx.stride == 1)
	fake(m, m.ARROW_CAP, a, b, t0, t1)
	fx.register_queue()
	fl = fx.count_in_flight(t0 + 10.0)
	check("очередь полна (ARROW_CAP %d): на экране не больше max_visible (%d)" % [m.ARROW_CAP, fl], fl <= cap and fl > 0)
	# --- LOD ---
	fake(m, 10, a, b, t0, t1)
	fx.register_queue()
	var zl: float = float(c.lod_min_screen_px) / maxf(fx.arrow_size.x, fx.arrow_size.y)
	fx.frame(t0 + 10.0, 0.0, zl * 0.9)
	var lod_off: bool = fx.lod_skip and not fx.air_node.visible and not fx.shadow_node.visible
	fx.frame(t0 + 10.0, 0.0, zl * 1.1)
	check("LOD: стрела короче %s px экрана (зум %.3f) — полёт и тени скрыты, длиннее — видны" % [c.lod_min_screen_px, zl * 0.9], lod_off and not fx.lod_skip
		and fx.air_node.visible and fx.shadow_node.visible)
	fx.frame(float(t1) + 1.0, 0.0, 1.0)
	check("все упали — ноды полёта скрыты (нечего рисовать)", not fx.air_node.visible and not fx.shadow_node.visible)
	# --- падение: искра и воткнутая ---
	fx.clear()
	fake(m, 2, a, b, t0, t1)
	m.arrow_land[1] = b + Vector2(10, 0)
	fx.frame(t0, 0.0, 1.0)
	var h0: int = fx.hits_shown
	fx.land(0, true, b + Vector2(1, 1))
	fx.land(1, false, b)
	fx.frame(t1 - 0.5, 1.0 / 60.0, 1.0)
	check("до тика падения на экране эффекта нет", fx.spark_n == 0 and fx.stuck_count() == 0 and fx.ev_n == 2)
	fx.frame(float(t1), 1.0 / 60.0, 1.0)
	check("на тике падения: попадание — искра (%d), промах — воткнутая (%d)" % [fx.spark_n, fx.stuck_count()], fx.spark_n >= int(c.spark_count[0])
		and fx.spark_n <= int(c.spark_count[1]) and fx.stuck_count() == 1 and fx.ev_n == 0 and fx.hits_shown == h0 + 1 and fx.stuck_node.visible)
	var frames := 1
	while fx.spark_n > 0 and frames < 100:
		fx.frame(float(t1), 1.0 / 60.0, 1.0)
		frames += 1
	check("искра живёт от %d до %d кадров (%d)" % [int(c.spark_frames[0]), int(c.spark_frames[1]), frames], frames >= int(c.spark_frames[0]) and frames <= int(c.spark_frames[1]))
	var ks: int = (fx.st_next - 1 + fx.st_pos.size()) % fx.st_pos.size()
	var life_s: float = (fx.st_t1[ks] - fx.st_t0[ks]) / Engine.physics_ticks_per_second
	var a_mid: float = fx.stuck_alpha(ks, fx.st_t0[ks] + (fx.st_t1[ks] - fx.st_t0[ks]) * (1.0 - float(c.stuck_fade) * 0.5))
	check("воткнутая: живёт %.2f с (stuck_life %s), сначала непрозрачна, на угасании (последние %s жизни) — полупрозрачна (%.2f), потом не видна" % [
		life_s, str(c.stuck_life), c.stuck_fade, a_mid], life_s >= float(c.stuck_life[0]) - 0.001 and life_s <= float(c.stuck_life[1]) + 0.001
		and is_equal_approx(fx.stuck_alpha(ks, fx.st_t0[ks]), 1.0) and absf(a_mid - 0.5) < 0.01 and fx.stuck_count(fx.st_t1[ks]) == 0)
	fx.frame(fx.st_t1[ks] + 0.5, 1.0 / 60.0, 1.0)
	check("погасла — нода воткнутых скрыта", not fx.stuck_node.visible)
	var ms := int(c.max_stuck)
	for k in ms + 50:
		m.arrow_land[1] = b + Vector2(k % 40, k / 40)
		fx.land(1, false, b)
	fx.frame(float(t1) + 1.0, 1.0 / 60.0, 1.0)
	check("воткнутых не больше max_stuck %d (%d после %d промахов)" % [ms, fx.stuck_count(), ms + 50], fx.stuck_count() == ms)
	fake(m, 0, a, b, t0, t1)
	fx.clear()
	# --- звук ---
	var au: Node = root.get_node_or_null("Audio")
	var names: Array = [c.sound_whoosh] + c.sound_hits
	var ad: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
	check("data/audio.json: %s — в future_sounds, в sounds нет" % ", ".join(names), names.all(func(n): return ad.future_sounds.has(n) and not ad.sounds.has(n)))
	check("Audio без записей стрел: звуков стрел не зовём (свист %s, удары %s)" % [fx.snd_whoosh, str(fx.snd_hits)], au != null and fx.snd_whoosh == "" and fx.snd_hits.is_empty())
	# --- бой: флаг вкл ---
	m.set_physics_process(false)   # тики — только здесь
	m.wave_number = 9   # волна 10 (как --scene=battle): лучники стреляют весь замер
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	m.paused = false
	st.persist = true
	st.set_show_arrows(true)
	var w0: int = fx.whoosh_wanted
	var hits_sim0: int = m.arrows_hit
	var shown0: int = fx.hits_shown
	var stuck0: int = fx.stuck_shown
	var fired0: int = m.arrows_fired
	var q0: int = m.arrow_count
	var calls0: int = fx.draw_calls
	var max_drawn := 0
	for t in 900:
		m._physics_process(DT)
		await process_frame
		max_drawn = maxi(max_drawn, fx.count_in_flight(m.tick_counter - 1 + Engine.get_physics_interpolation_fraction()))
	m.paused = true
	await step(2)
	fx.frame(m.tick_counter + 1e6, 1.0 / 60.0, 1.0)   # все падения, что уже случились, — на экран
	var landed: int = (m.arrows_fired - fired0) - (m.arrow_count - q0)
	check("бой 900 тиков: стрел упало %d, попаданий симуляции %d = искр-попаданий %d, промахов = воткнутых %d" % [landed, m.arrows_hit - hits_sim0,
		fx.hits_shown - shown0, fx.stuck_shown - stuck0], landed > 0 and fx.hits_shown - shown0 == m.arrows_hit - hits_sim0
		and fx.stuck_shown - stuck0 == landed - (m.arrows_hit - hits_sim0) and fx.ev_dropped == 0)
	check("на экране не больше max_visible (пик %d), отрисовка вызывалась (%d)" % [max_drawn, fx.draw_calls - calls0], max_drawn > 0 and max_drawn <= cap and fx.draw_calls > calls0)
	check("звук: код дошёл до свиста (%d раз), но Audio не звал звуков стрел — в кеше потоков их нет, предупреждений нет" % (fx.whoosh_wanted - w0),
		fx.whoosh_wanted > w0 and fx.sounds_played == 0 and names.all(func(n): return not au.streams.has(n)))
	# запись есть, файла нет: один раз null в кеше, дальше молча, ничего не падает
	au.sounds[c.sound_whoosh] = {"path": "res://music_sounds/__nope_arrow.wav", "bus": "SFX", "volume_db": 0.0, "loop": false}
	fx.setup_sound(au)
	fx.whoosh_at = -1e9
	fx.released = 1
	fx._sounds()
	fx.whoosh_at = -1e9
	fx._sounds()
	check("запись без файла: свист зовётся (%d), поток null закеширован после первого вызова" % fx.sounds_played, fx.sounds_played == 2
		and au.streams.has(c.sound_whoosh) and au.streams[c.sound_whoosh] == null)
	au.sounds.erase(c.sound_whoosh)
	au.streams.erase(c.sound_whoosh)
	fx.setup_sound(au)
	# --- флаг выкл: отрисовка не вызывается, симуляция та же ---
	m.paused = false
	st.set_show_arrows(false)
	var cfg2 := ConfigFile.new()
	cfg2.load(st.path)
	check("флаг выкл сохранён в настройках (display/show_arrows = %s)" % str(cfg2.get_value("display", "show_arrows", null)), cfg2.get_value("display", "show_arrows", null) == false)
	await step(2)
	var calls1: int = fx.draw_calls
	var ev1: int = fx.ev_n
	var hits1: int = fx.hits_shown + fx.stuck_shown
	var fired1: int = m.arrows_fired
	for t in 300:
		m._physics_process(DT)
		await process_frame
	check("флаг выкл: отрисовка стрел не вызывается (вызовов %d -> %d), ноды скрыты, событий падения нет (%d), эффектов нет; стрелы в симуляции летят (%d выпущено)" % [
		calls1, fx.draw_calls, fx.ev_n, m.arrows_fired - fired1], fx.draw_calls == calls1 and not fx.air_node.visible and not fx.shadow_node.visible
		and not fx.spark_node.visible and not fx.stuck_node.visible and fx.ev_n == 0 and ev1 == 0 and fx.hits_shown + fx.stuck_shown == hits1
		and not m.arrow_fx_on and not fx.registered and m.arrows_fired > fired1)
	st.set_show_arrows(true)
	await step(2)
	check("флаг снова вкл: отрисовка идёт, очередь — снова в слотах", fx.draw_calls > calls1 and fx.shown and fx.registered and m.arrow_fx_on)
	m.paused = true
	# симуляция с флагом и без — бит в бит: две копии main без дерева, у одной стрелы «рисуются» (события в очередь эффектов)
	var on_m := sim_copy()
	var off_m := sim_copy()
	var sink: Node2D = preload("res://scripts/arrow_fx.gd").new()
	sink.setup(on_m, 0, null)   # ноды — в копию без дерева; события выстрелов и падений идут в слоты и очередь
	on_m.arrow_fx = sink
	on_m.arrow_fx_on = true
	var same := true
	var landed2 := 0
	for t in 1200:
		on_m._physics_process(DT)
		off_m._physics_process(DT)
		landed2 += sink.ev_n
		sink.ev_n = 0
		sink.ev_min = 1 << 30
		if state(on_m) != state(off_m):
			same = false
			break
	check("симуляция с событиями стрел и без — бит в бит, 1200 тиков волны 10 (выстрелов в слоты %d, событий падения %d)" % [sink.drawn, landed2], same and landed2 > 0 and sink.drawn > 0)
	sink.free()
	on_m.free()
	off_m.free()
	st.persist = persist0
	st.path = st_path0
	DirAccess.remove_absolute(tmp.path_join("settings.cfg"))
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v79")
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func sim_copy() -> Node2D:
	var s: Node2D = load("res://scripts/main.gd").new()
	s.spawn_seed = 3
	s.waves_enabled = true
	s.record_path = "user://record_bench.json"
	s._setup_data()
	s.wave_number = 9
	s.wave_plan_for = -1
	s.gate_hp = 1e9
	s.gate_hp_max = 1e9
	s._start_wave()
	return s
