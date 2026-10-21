extends SceneTree
# Смоук задачи 11 с окном: ручной удар героя (игровой режим через Game, герой по данным). Скриншоты в папку из аргумента:
# swing_ready.png — герой в поле, перед ним три зомби, сзади один; swing_start.png — первый кадр удара: дуга-вспышка вперёд, выпад,
# задетые белые; swing_mid.png — середина вспышки (гаснет, кромка расширяется); swing_after.png — вспышки нет, герой на месте.
# Эффекты — по времени кадра: кадры отрисовки подаются вручную (m._process(delta)), тики симуляции — m._physics_process.
const DIR := "user://bench_v61"
const DT := 1.0 / 30.0
const P := Vector2(1500, 360)   # герой в свободном поле (дальше от строя и ворот)
var fails := 0
var out_dir := ""

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

# Снимок экрана; кадр отрисовки main — вручную с шагом dt (0 — эффекты не стареют).
func shot(m: Node2D, name: String, dt := 0.0) -> Image:
	m._process(dt)
	await step(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	return img

# Пикселей, заметно изменившихся между снимками a и b, в секторе вокруг героя: направление ang, полуугол half, радиусы r0..r1 (мир).
func changed(m: Node2D, a: Image, b: Image, ang: float, half: float, r0: float, r1: float) -> int:
	var px: Vector2 = Vector2(a.get_size()) / m.get_viewport_rect().size
	var ct: Transform2D = m.get_viewport().get_canvas_transform()
	var n := 0
	for k in 40:
		for r in range(int(r0), int(r1)):
			var w: Vector2 = P + Vector2.from_angle(ang - half + 2.0 * half * k / 39.0) * float(r)
			var q := Vector2i((ct * w) * px)
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

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var g: Node = root.get_node_or_null("Game")
	var au: Node = root.get_node_or_null("Audio")
	if g == null or au == null:
		print("SMOKE: нет автозагрузки Game или Audio")
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
	var z := []
	for w in [Vector2(14, 0), Vector2(20, 9), Vector2(21, -8), Vector2(-16, 0)]:   # три впереди (взгляд вправо), один сзади
		z.append(m.count)
		m._spawn_zombie(P + w, m.zombie_type)
		m.hp[m.count - 1] = 100.0
		m.prev_pos[m.count - 1] = P + w
	m.hero_feed = func(_t): return {"move": Vector2.ZERO, "face": 0.0}
	m._physics_process(DT)
	m.prev_pos = m.pos.duplicate()
	var ready := await shot(m, "swing_ready.png")
	check("перед ударом вспышки нет, герой смотрит вправо", not m.hero_fx.visible and is_equal_approx(m.hero_face_ang, 0.0) and m.hero_view.position == P)
	# удар: ввод одного тика
	m.hero_feed = func(t: int): return {"move": Vector2.ZERO, "face": 0.0, "attack": t == m.tick_counter}
	m._physics_process(DT)
	m.hero_feed = func(_t): return {"move": Vector2.ZERO}
	m.prev_pos = m.pos.duplicate()
	var hits := []
	for j in z:
		hits.append(m.hp[j] < 100.0)
	check("удар J: задеты три зомби впереди, сзади — нет", hits == [true, true, true, false] and m.hero_swing_n == 1, str(hits))
	var img := await shot(m, "swing_start.png")
	var F: int = m.FLOATS_PER_UNIT
	var flash := []
	for j in z:
		flash.append(m.buf[j * F + 13])
	var lunge: Vector2 = m.hero_view.position - P
	check("первый кадр: дуга-вспышка видна (нода эффектов над юнитами, под героем: z %d, раньше в дереве)" % m.hero_fx.z_index, m.hero_fx.visible and m.hero_fx_age == 0.0
		and m.hero_fx.z_index == m.hero_view.z_index and m.hero_fx.get_index() < m.hero_view.get_index() and m.hero_fx.position == P)
	check("выпад вперёд на %.1f px по направлению удара" % lunge.x, absf(lunge.x - m.HERO_LUNGE_PX) < 0.01 and absf(lunge.y) < 0.01)
	check("задетые мигают белым (custom.y = 1), незадетый — нет: %s" % str(flash), flash == [1.0, 1.0, 1.0, 0.0])
	var front := changed(m, ready, img, 0.0, deg_to_rad(50.0), 6.0, m.hero_cfg.arc_range + 2.0)
	var back := changed(m, ready, img, PI, deg_to_rad(50.0), 22.0, m.hero_cfg.arc_range + 2.0)
	check("на экране: в секторе удара изменилось %d пикселей, сзади (вне сектора, за спрайтом героя) — %d" % [front, back], front > 300 and back < front / 10)
	var playing := false
	for p in au.sfx_players:
		playing = playing or (p.stream == au.streams.get("hero_swing") and p.stream != null)   # звук ~0.1 с: к проверке мог доиграть
	check("звук удара hero_swing (временно %s) запущен плеером эффектов, шина SFX" % au.sounds.hero_swing.path.get_file(), playing and au.sounds.hero_swing.bus == "SFX")
	img = await shot(m, "swing_mid.png", 0.07)
	img = await shot(m, "swing_mid.png", 0.0)
	check("середина вспышки (%.2f с): ещё видна, гаснет; мигание кончилось (2 кадра)" % m.hero_fx_age, m.hero_fx.visible and m.hero_fx_age > 0.05
		and m.buf[z[0] * F + 13] == 0.0 and m.hero_flash_slots.is_empty())
	await shot(m, "swing_tmp.png", 0.1)
	img = await shot(m, "swing_after.png", 0.0)
	DirAccess.remove_absolute(out_dir.path_join("swing_tmp.png"))
	check("после arc_fx_time (%.2f с): вспышки нет, герой на месте" % m.hero_cfg.arc_fx_time, not m.hero_fx.visible and m.hero_view.position == P)
	# J с клавиатуры: событие -> ввод ближайшего тика
	m.hero_feed = Callable()
	for t in 30:
		m._physics_process(DT)
	var e := InputEventKey.new()
	e.keycode = KEY_J
	e.physical_keycode = KEY_J
	e.pressed = true
	m._unhandled_input(e)
	m._physics_process(DT)
	m._process(1.0 / 60.0)
	check("клавиша J (InputMap hero_attack): удар на ближайшем тике, новая вспышка", m.hero_swing_n == 2 and m.hero_fx.visible)
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
