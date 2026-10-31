extends SceneTree
# Кадры задачи 28 (окно): бой как --scene=battle (seed, волна и тики из data/screenshot.json), кадр — как клавиша F12
# (Shots.capture, без отладочных надписей), size из data/screenshot.json. Аргумент: папка для PNG (bench/report_28).
#   Этап 1: zoom1_<угол> — зум 1.0 (zoom_user_min), вид прижат к углу поля: чёрных полос нет.
#   Этап 4: hero_gate, hero_tree, hero_open — герой за воротами, за кроной, на открытом месте; hero_ring — рядом с выбранным
#   отрядом (контур выделения); зум 2.0 к герою. Точки — по прозрачности слоёв, как в smoke_v78_hero.
#   Этап 5: hero_size — зум zoom_user_max, герой среди юнитов (рост 1,5 юнита).
const DT := 1.0 / 30.0
var m: Node2D
var layers := []
var hero_pts: Array[Vector2] = []

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func alpha_at(k: int, w: Vector2) -> float:
	var sp: Sprite2D = layers[k][0]
	var img: Image = layers[k][1]
	if sp == null or img == null:
		return 0.0
	var uv := (w - sp.position) / (Vector2(img.get_size()) * sp.scale)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return 0.0
	return img.get_pixel(int(uv.x * img.get_width()), int(uv.y * img.get_height())).a

func hero_points() -> void:
	var s: Sprite2D = m.hero_sprite
	var img: Image = s.texture.get_image()
	if img.is_compressed():
		img.decompress()
	var fs := Vector2(img.get_width() / s.hframes, img.get_height() / s.vframes)
	var fx0 := (s.frame % s.hframes) * int(fs.x)
	var fy0 := (s.frame / s.hframes) * int(fs.y)
	hero_pts.clear()
	for v in int(fs.y):
		for u in int(fs.x):
			if img.get_pixel(fx0 + u, fy0 + v).a >= 0.5:
				var lp := s.offset + Vector2(u + 0.5, v + 0.5) - fs * 0.5
				if s.flip_h:
					lp.x = -lp.x
				hero_pts.append(s.transform * lp)

func exact(p: Vector2) -> Vector2:
	var t := 0
	var c := 0
	for q in hero_pts:
		if alpha_at(0, p + q) >= 0.5:
			t += 1
		if alpha_at(1, p + q) >= 0.5:
			c += 1
	return Vector2(t, c) / maxf(hero_pts.size(), 1)

func find(want: Callable, near: Vector2) -> Vector2:
	var cand := []
	for y in range(int(maxf(near.y - 500.0, 24.0)), int(minf(near.y + 500.0, m.FIELD.y - 24.0)), 4):
		for x in range(int(maxf(near.x - 500.0, 24.0)), int(minf(near.x + 500.0, m.FIELD.x - 24.0)), 4):
			cand.append(Vector2(x, y))
	cand.sort_custom(func(a, b): return a.distance_squared_to(near) < b.distance_squared_to(near))
	for p in cand:
		var e := exact(p)
		if want.call(e.x, e.y):
			return p
	return Vector2(-1, -1)

func view(mult: float, world: Vector2) -> void:
	var vs: Vector2 = m.get_viewport_rect().size
	m.zoom_user = mult * 0.97 if mult > 1.0 else 1.03   # цель не равна текущему — камера идёт к якорю
	m.zoom_user_target = mult
	m.zoom_anchor_screen = vs * 0.5
	m.zoom_anchor_world = world
	var t_end := Time.get_ticks_msec() + 3000
	while m.zoom_user != m.zoom_user_target and Time.get_ticks_msec() < t_end:
		await process_frame

func place(p: Vector2) -> void:
	m.pos[m.hero_idx] = p
	m.prev_pos[m.hero_idx] = p

func shot(out: String, name: String, info: String) -> void:
	m._update_ui()
	await _frames(4)
	var p: String = await root.get_node("Shots").capture()
	var dst := out.path_join(name + ".png")
	DirAccess.copy_absolute(p, dst)
	DirAccess.remove_absolute(p)
	print("SHOT78|%s|%s|вид %s" % [dst.get_file(), info, str(m.view_rect())])

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/screenshot.json"))
	var cam: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/camera.json"))
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v78shots/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v78shots")
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
	for t in int(cfg.battle_ticks):
		if m.wave_state != m.WS_BATTLE:
			break
		m._physics_process(DT)
	m.banner.visible = false
	m._clear_sel()
	# этап 1
	for c in [["lt", Vector2(-500, -500)], ["rb", m.FIELD + Vector2(500, 500)]]:
		await view(float(cam.zoom_user_min), c[1])
		await shot(out, "zoom1_" + c[0], "зум %s, угол %s" % [cam.zoom_user_min, c[0]])
	# этап 4
	for sp in [m.trees_sprite, m.castle_sprite]:
		var img: Image = sp.texture.get_image() if sp != null else null
		if img != null and img.is_compressed():
			img.decompress()
		layers.append([sp, img])
	place(m.HERO_SPAWN)
	await _frames(2)
	hero_points()
	var spots := [
		["hero_gate", find(func(t, c): return c == 1.0 and t == 0.0, m.GATE_POS)],
		["hero_tree", find(func(t, c): return t == 1.0 and c == 0.0, Vector2(300, m.FIELD.y * 0.45))],
		["hero_open", find(func(t, c): return t == 0.0 and c == 0.0, m.HERO_SPAWN + Vector2(0, -150))],
	]
	for e in spots:
		place(e[1])
		await view(2.0, e[1])
		await shot(out, e[0], "герой в %s" % str(e[1]))
	# рядом с выбранным отрядом: контур выделения отряда и кольцо героя
	m._select_only(0)
	var box := Rect2(m.squad_pos[0], Vector2.ZERO)   # отряд 0: прямоугольник его бойцов
	for i in m.count:
		if m.unit_squad[i] == 0 and m.hp[i] > 0.0:
			box = box.expand(m.pos[i])
	var sq := Vector2(box.end.x + 22.0, box.get_center().y)   # герой справа вплотную к контуру выделения
	place(sq)
	await view(2.0, sq)
	await shot(out, "hero_ring", "герой у контура выбранного отряда %s" % str(sq))
	m._clear_sel()
	# этап 5
	var near_units: Vector2 = Vector2(box.get_center().x, box.position.y - 18.0)   # над первым рядом отряда
	place(near_units)
	await view(float(cam.zoom_user_max), near_units)
	await shot(out, "hero_size", "зум %s, герой среди юнитов, лист %s" % [cam.zoom_user_max, "legacy" if m.hero_sheet_legacy else "24x24"])
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v78shots")
	quit(0)
