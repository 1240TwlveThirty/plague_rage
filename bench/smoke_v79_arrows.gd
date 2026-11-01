extends SceneTree
# Смоук задачи 29 (окно): стрелы на экране — там, где их считает flight_at (копия шейдера, по которой check_v79_arrows проверяет
# дугу). Бой волны 10 (свой seed), активная пауза, эффекты карты выключены (кадры неподвижны), интерфейс скрыт, зум ZOOM.
# Очередь стрел main — одна стрела, заданная тестом; кадр со стрелой и без неё (tint шейдера прозрачный) — разница точек:
#   стрела: середина разницы — точка flight_at (не дальше TOL px мира), длинная ось — по направлению полёта (не больше ANG_TOL);
#   тень: середина — на земле (flight_at ground); стрела упала (td >= тика падения) — разницы нет;
#   воткнутая (промах): видна с тика падения, после stuck_life — не видна.
const ZOOM := 3.0
const TOL := 1.0        # px мира
const ANG_TOL := 15.0   # градусов
const DIFF := 0.08      # порог разницы канала
const WIN := Vector2(420, 300)   # полуразмеры окна сравнения, px экрана
var fails := 0
var focus := Vector2.ZERO   # середина пути (мир)
var m: Node2D
var fx: Node2D

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

func frame() -> Image:
	await step(2)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

# Точки, где кадры a и b различаются (в окне WIN px экрана вокруг середины пути): [число, середина в мире, угол длинной оси (рад)].
func diff(a: Image, b: Image) -> Array:
	var xf: Transform2D = m.get_viewport().get_canvas_transform()
	var inv := xf.affine_inverse()
	var mid: Vector2 = xf * focus
	var pts: Array[Vector2] = []
	for y in range(maxi(int(mid.y - WIN.y), 0), mini(int(mid.y + WIN.y), a.get_height())):
		for x in range(maxi(int(mid.x - WIN.x), 0), mini(int(mid.x + WIN.x), a.get_width())):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > DIFF or absf(p.g - q.g) > DIFF or absf(p.b - q.b) > DIFF:
				pts.append(inv * Vector2(x + 0.5, y + 0.5))
	if pts.is_empty():
		return [0, Vector2.ZERO, 0.0]
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p in pts:
		var d := p - c
		sxx += d.x * d.x
		syy += d.y * d.y
		sxy += d.x * d.y
	return [pts.size(), c, 0.5 * atan2(2.0 * sxy, sxx - syy)]

func ang_diff(a: float, b: float) -> float:
	var d := fposmod(a - b, PI)   # ось без направления
	return rad_to_deg(minf(d, PI - d))

# Одна стрела в очереди main: от a к b, выпуск t0, падение t1; отрисовка заново берёт очередь в слоты.
func one(a: Vector2, b: Vector2, t0: float, t1: int) -> void:
	m.arrow_count = 1
	m.arrow_from[0] = a
	m.arrow_land[0] = b
	m.arrow_t0[0] = t0
	m.arrow_tick[0] = t1
	m.arrow_vid[0] = 0
	fx.clear()

func tint(mat: ShaderMaterial, on: bool, col: Color) -> void:
	mat.set_shader_parameter("tint", col if on else Color(col, 0.0))

func _run() -> void:
	node_added.connect(func(n): if n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd": n.fx_enabled = false)
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v79sm/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v79sm")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(10)
	m = current_scene
	fx = m.arrow_fx
	m.banner_hidden = true
	m.banner.visible = false
	m.set_physics_process(false)
	m._clear_sel()
	for c in m.get_children():
		if c is CanvasLayer:
			c.visible = false
	m.paused = true   # время картинки = tick_counter
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/arrows_fx.json"))
	var shadow_col := Color(Color(c.shadow_color), c.shadow_alpha)
	var td := float(m.tick_counter)
	var a: Vector2 = m.FIELD * Vector2(0.5, 0.3) + Vector2(-40, 20)   # открытое поле над строем, вдали от слоёв
	var b: Vector2 = a + Vector2(80, -10)
	focus = (a + b) * 0.5 - Vector2(0, 10)
	# зум к середине пути (как колесо: якорь — точка мира под серединой экрана)
	m.zoom_user = ZOOM * 0.97
	m.zoom_user_target = ZOOM
	m.zoom_anchor_screen = m.get_viewport_rect().size * 0.5
	m.zoom_anchor_world = focus
	var t_end := Time.get_ticks_msec() + 3000
	while m.zoom_user != m.zoom_user_target and Time.get_ticks_msec() < t_end:
		await process_frame
	await step(3)
	check("вид — у середины пути (%s), зум %.2f" % [str(m.view_rect()), m.camera.zoom.x], m.view_rect().grow(-20.0).has_point(a) and m.view_rect().grow(-20.0).has_point(b))
	for u in [0.25, 0.5, 0.8]:
		one(a, b, td - u * 20.0, int(td + (1.0 - u) * 20.0))   # 20 тиков полёта, сейчас доля u
		var img_on := await frame()
		var k: int = fx.slot_for(0)
		var want: Array = fx.flight_at(k, td)
		var wg: Array = fx.flight_at(k, td, true)
		tint(fx.air_mat, false, Color.WHITE)
		var img_no_air := await frame()
		tint(fx.shadow_mat, false, shadow_col)
		var img_none := await frame()
		tint(fx.air_mat, true, Color.WHITE)
		tint(fx.shadow_mat, true, shadow_col)
		var da := diff(img_on, img_no_air)
		var ds := diff(img_no_air, img_none)
		check("u %.2f: стрела на экране (%d точек) — середина %s, flight_at %s (%.2f px мира), ось %.0f° против %.0f°" % [u, da[0], str(da[1]), str(want[1]),
			(da[1] as Vector2).distance_to(want[1]), rad_to_deg(da[2]), rad_to_deg((want[2] as Vector2).angle())], want[0] and da[0] > 0
			and (da[1] as Vector2).distance_to(want[1]) <= TOL and ang_diff(da[2], (want[2] as Vector2).angle()) <= ANG_TOL)
		check("u %.2f: тень (%d точек) — на земле %s (%.2f px мира)" % [u, ds[0], str(ds[1]), (ds[1] as Vector2).distance_to(wg[1])],
			ds[0] > 0 and (ds[1] as Vector2).distance_to(wg[1]) <= TOL)
	# упала: на экране ни стрелы, ни тени
	one(a, b, td - 20.0, int(td))
	var on2 := await frame()
	tint(fx.air_mat, false, Color.WHITE)
	tint(fx.shadow_mat, false, shadow_col)
	var off2 := await frame()
	tint(fx.air_mat, true, Color.WHITE)
	tint(fx.shadow_mat, true, shadow_col)
	check("на тике падения стрелы и тени на экране нет", diff(on2, off2)[0] == 0)
	# воткнутая: промах в b на этом тике
	one(a, b, td - 20.0, int(td))
	await step(1)
	var before := await frame()
	fx.land(0, false, b)
	var stuck := await frame()
	var dk := diff(before, stuck)
	check("воткнутая на тике падения видна (%d точек) у точки падения (%.2f px мира)" % [dk[0], (dk[1] as Vector2).distance_to(b)], dk[0] > 0 and (dk[1] as Vector2).distance_to(b) <= 4.0)
	m.tick_counter += int(ceilf(float(c.stuck_life[1]) * Engine.physics_ticks_per_second)) + 1   # время картинки — после конца жизни (пауза)
	var gone := await frame()
	check("после stuck_life воткнутой нет", diff(before, gone)[0] == 0)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v79sm")
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
