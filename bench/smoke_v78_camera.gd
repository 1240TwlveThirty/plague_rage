extends SceneTree
# Смоук задачи 28 (окно): чёрных полос за краем карты нет. Бой волны 1 (свой seed), зум 1.0 (zoom_user_min) и zoom_user_max
# из data/camera.json, вид прижат к каждому углу поля; кадр вьюпорта: в крайних строках и столбцах доля точек цвета очистки
# (чёрный, default_clear_color) меньше BLACK_MAX — полоса за краем дала бы целую строку или столбец. То же с тряской у края.
const BLACK_MAX := 0.5
var fails := 0

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

# Доля точек цвета очистки в строке y (или столбце x при col) кадра img.
func black_share(img: Image, idx: int, col: bool) -> float:
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	var n := img.get_height() if col else img.get_width()
	var k := 0
	for i in n:
		var c := img.get_pixel(idx, i) if col else img.get_pixel(i, idx)
		if c.is_equal_approx(Color(clear.r, clear.g, clear.b, c.a)):
			k += 1
	return float(k) / n

func edges(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var out := []
	for d in [0, 1, 2]:
		out.append(black_share(img, d, false))
		out.append(black_share(img, h - 1 - d, false))
		out.append(black_share(img, d, true))
		out.append(black_share(img, w - 1 - d, true))
	return out

func frame() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _run() -> void:
	var cam: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/camera.json"))
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v78sm/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v78sm")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(10)
	var m: Node2D = current_scene
	m.banner_hidden = true
	m.banner.visible = false
	var vs: Vector2 = m.get_viewport_rect().size
	var corners := [Vector2(-500, -500), Vector2(m.FIELD.x + 500, -500), Vector2(-500, m.FIELD.y + 500), m.FIELD + Vector2(500, 500)]
	for z in [float(cam.zoom_user_min), float(cam.zoom_user_max)]:
		for a in corners:
			m.zoom_user = z * 0.97
			m.zoom_user_target = z
			m.zoom_anchor_screen = vs * 0.5
			m.zoom_anchor_world = a
			var t_end := Time.get_ticks_msec() + 3000
			while m.zoom_user != m.zoom_user_target and Time.get_ticks_msec() < t_end:
				await process_frame
			await step(3)
			var e: Array = edges(await frame())
			check("зум ×%s, угол %s: крайние строки и столбцы не чёрные (наибольшая доля %.2f)" % [z, a, e.max()], e.max() < BLACK_MAX, str(m.view_rect()))
	# проверка самой проверки: прежний предел 0.7 (в обход data) — чёрные поля по краям видны
	m.zoom_user = 0.7
	m.zoom_user_target = 0.7
	await step(3)
	var e7: Array = edges(await frame())
	check("контроль: при ×0.7 (прежний предел) чёрная полоса находится (доля %.2f)" % e7.max(), e7.max() >= BLACK_MAX)
	# тряска у края при зуме 1.0
	m.zoom_user = float(cam.zoom_user_min)
	m.zoom_user_target = m.zoom_user
	m.camera.position = m._camera_clamp(Vector2.ZERO, m.camera.zoom.x)
	m.shake_cap = 6.0
	var worst := 0.0
	for i in 20:
		m.shake_amp = 6.0
		m.shake_hit_t = float(m.hit_cfg.shake_time)
		await step(1)
		worst = maxf(worst, (edges(await frame()) as Array).max())
	check("тряска у левого верхнего края при зуме 1.0: 20 кадров, края не чёрные (наибольшая доля %.2f)" % worst, worst < BLACK_MAX)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v78sm")
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
