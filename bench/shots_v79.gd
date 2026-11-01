extends SceneTree
# Кадры задачи 29 (окно): бой как --scene=battle (seed и волна из data/screenshot.json; тики — до первого большого залпа), кадр — как клавиша F12 (Shots.capture,
# без отладочных надписей). Аргумент: папка для PNG (bench/report_29).
#   arrows_z1, arrows_z2 — залп в полёте (больше всего стрел на экране), активная пауза, зум 1.0 и 2.0 к середине стрел;
#   arrows_hits — попадания (искры) и воткнутые стрелы, зум 2.0; arrows_stuck — воткнутые после промахов, зум 2.0.
const DT := 1.0 / 30.0
const VOLLEY_MIN := 60   # стрел в полёте: залп (в отряде лучников волны 10 их около 100)
var m: Node2D

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func view(mult: float, world: Vector2) -> void:
	var vs: Vector2 = m.get_viewport_rect().size
	m.zoom_user = mult * 0.97 if mult > 1.0 else 1.03   # цель не равна текущему — камера идёт к якорю
	m.zoom_user_target = mult
	m.zoom_anchor_screen = vs * 0.5
	m.zoom_anchor_world = world
	var t_end := Time.get_ticks_msec() + 3000
	while m.zoom_user != m.zoom_user_target and Time.get_ticks_msec() < t_end:
		await process_frame

func shot(out: String, name: String, info: String) -> void:
	m._update_ui()
	await _frames(3)
	var p: String = await root.get_node("Shots").capture()
	var dst := out.path_join(name + ".png")
	DirAccess.copy_absolute(p, dst)
	DirAccess.remove_absolute(p)
	var fx: Node2D = m.arrow_fx
	print("SHOT79|%s|%s|в полёте %d, на экране %d, искр %d, воткнутых %d|вид %s" % [dst.get_file(), info, fx.in_flight, fx.drawn,
		fx.get("spark_n") if fx.get("spark_n") != null else 0, fx.get("stuck_n") if fx.get("stuck_n") != null else 0, str(m.view_rect())])

# Середина стрел в полёте (по земле) в момент картинки.
func flight_center() -> Vector2:
	var td: float = m.tick_counter
	var c := Vector2.ZERO
	var n := 0
	for a in m.arrow_count:
		if m.arrow_t0[a] <= td and td < m.arrow_tick[a]:
			var u: float = (td - m.arrow_t0[a]) / (m.arrow_tick[a] - m.arrow_t0[a])
			c += m.arrow_from[a].lerp(m.arrow_land[a], u)
			n += 1
	return c / maxf(n, 1)

# Тики по одному с кадром между ними, пока cond не выполнится (не дольше limit тиков).
func run_until(cond: Callable, limit: int) -> bool:
	for t in limit:
		if m.wave_state != m.WS_BATTLE:
			return false
		m._physics_process(DT)
		await process_frame
		if cond.call():
			return true
	return false

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/screenshot.json"))
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v79shots/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v79shots")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = int(cfg.scene_seed)
	g.start_run(1)
	await _frames(6)
	m = current_scene
	m.banner_hidden = true
	m.banner.visible = false
	m.wave_number = int(cfg.battle_wave) - 1
	m.wave_plan_for = -1
	m._start_wave()
	m.set_physics_process(false)
	m.banner.visible = false
	m._clear_sel()
	await _frames(2)
	var fx: Node2D = m.arrow_fx
	# залп в полёте: от начала волны тики по одному с кадром, пока в полёте не окажется VOLLEY_MIN стрел (первый большой залп)
	var ok := await run_until(func(): return fx.in_flight >= VOLLEY_MIN, 1800)
	print("SHOT79|залп найден: %s, тик %d, в полёте %d" % [ok, m.tick_counter, fx.in_flight])
	await run_until(func(): return false, 6)   # стрелы на середине дуги
	m.paused = true
	await _frames(2)
	var c := flight_center()
	await view(1.0, c)
	await shot(out, "arrows_z1", "залп в полёте, зум 1.0")
	await view(2.0, c)
	await shot(out, "arrows_z2", "залп в полёте, зум 2.0, середина %s" % str(c))
	m.paused = false
	if fx.get("stuck_n") != null:
		# попадания: дождаться падения залпа (искры), зум 2.0 к местам падения
		await run_until(func(): return fx.spark_n >= 6, 240)
		m.paused = true
		await _frames(1)
		var sc: Vector2 = fx.spark_center()
		await view(2.0, sc)
		await shot(out, "arrows_hits", "попадания, зум 2.0, %s" % str(sc))
		m.paused = false
		await run_until(func(): return fx.spark_n == 0 and fx.stuck_n >= 4, 120)
		m.paused = true
		await _frames(1)
		var stc: Vector2 = fx.stuck_center()
		await view(2.0, stc)
		await shot(out, "arrows_stuck", "воткнутые стрелы, зум 2.0, %s" % str(stc))
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v79shots")
	quit(0)
