extends SceneTree
# Стресс отрисовки задачи 23 (с окном): копия main на 3000 юнитов (bench/main_v39_3000.gd, её делает bench/make_v39.py из рабочего
# main.gd) без волн — 400 своих и 2600 зомби; зомби ставятся вплотную к строю, и перед каждым тиком скрипт добивает KILL случайных
# (свой ГСЧ скрипта, seed 7; смерть идёт обычным путём через _remove_dead) — десятки смертей на тик весь замер. TICKS тиков подряд, на каждый — тик симуляции, кадр отрисовки main (_process: юниты, эффекты) и кадр движка
# (рендер); время каждой части отдельно, поэтому видна цена эффектов без шума догоняющей симуляции. Тики и кадры — вручную.
# Не использует новых полей (частицы и куски — если есть): запускается и на прежней копии (сравнение «до/после» по тем же seed).
# Печатает STRESS|юнитов|смертей за тик сред.|пик|тик мс|кадр main мс (медиана, p95)|рендер мс (медиана, p95)|FPS без тика|частиц пик|кусков пик.
const DT := 1.0 / 30.0
const TICKS := 60
const KILL := 40   # зомби, которых скрипт добивает перед каждым тиком (hp = 0): десятки смертей на тик весь замер
const HOT := 10   # «резня»: тиков с 10+ смертями

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	if root.has_node("Game"):
		root.get_node("Game").free()
	_run.call_deferred()

func med(a: PackedFloat32Array, q := 0.5) -> float:
	var s := a.duplicate()
	s.sort()
	return s[mini(int(s.size() * q), s.size() - 1)]

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var m: Node2D = Node2D.new()
	m.set_script(load("res://bench/main_v39_3000.gd"))
	m.record_path = "user://record_bench.json"
	m.spawn_seed = 3
	m.waves_enabled = false
	m.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m)
	current_scene = m
	for i in 8:
		await process_frame
	m.banner.visible = false
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	# зомби — вокруг строя игрока (центр своих), чтобы бой шёл сразу
	var c := Vector2.ZERO
	var own := 0
	for i in m.count:
		if m.team[i] == 0:
			c += m.pos[i]
			own += 1
	c /= maxf(own, 1)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in m.count:
		if m.team[i] == 1:
			var p := c + Vector2.from_angle(r.randf() * TAU) * r.randf_range(30.0, 160.0)
			m.pos[i] = p
			m.prev_pos[i] = p
	var n0: int = m.count
	var tick_ms := PackedFloat32Array()
	var proc_ms := PackedFloat32Array()
	var rend_ms := PackedFloat32Array()
	var hot_proc := PackedFloat32Array()   # тики с HOT и больше смертей: цена эффектов в резне
	var hot_rend := PackedFloat32Array()
	var deaths := 0
	var peak := 0
	var part_peak := 0
	var gib_peak := 0
	for t in TICKS:
		var alive := []
		for i in m.count:
			if m.team[i] == 1 and m.hp[i] > 0.0:
				alive.append(i)
		for k in mini(KILL, alive.size()):
			m.hp[alive[r.randi() % alive.size()]] = 0.0
		var before: int = m.count
		var a := Time.get_ticks_usec()
		m._physics_process(DT)
		var b := Time.get_ticks_usec()
		var d: int = maxi(before - m.count, 0)
		deaths += d
		peak = maxi(peak, d)
		m._process(DT)
		var e := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		var f := Time.get_ticks_usec()
		tick_ms.append((b - a) / 1000.0)
		proc_ms.append((e - b) / 1000.0)
		rend_ms.append((f - e) / 1000.0)
		if d >= HOT:
			hot_proc.append((e - b) / 1000.0)
			hot_rend.append((f - e) / 1000.0)
		var hn = m.get("hit_n")
		var gn = m.get("gib_n")
		part_peak = maxi(part_peak, int(hn) if hn != null else 0)
		gib_peak = maxi(gib_peak, int(gn) if gn != null else 0)
	var fps := 1000.0 / maxf(med(proc_ms) + med(rend_ms), 0.001)
	var hot_fps := 1000.0 / maxf(med(hot_proc) + med(hot_rend), 0.001) if not hot_proc.is_empty() else 0.0
	print("STRESS|юнитов %d|смертей за тик сред. %.1f|пик %d|тик %.2f мс|кадр main %.2f / %.2f мс|рендер %.2f / %.2f мс|FPS без тика %.1f|резня (%d тиков с %d+ смертями): кадр main %.2f / %.2f мс, рендер %.2f мс, FPS без тика %.1f|частиц пик %d|кусков пик %d" % [
		n0, float(deaths) / TICKS, peak, med(tick_ms), med(proc_ms), med(proc_ms, 0.95), med(rend_ms), med(rend_ms, 0.95), fps, hot_proc.size(), HOT,
		med(hot_proc) if not hot_proc.is_empty() else 0.0, med(hot_proc, 0.95) if not hot_proc.is_empty() else 0.0,
		med(hot_rend) if not hot_rend.is_empty() else 0.0, hot_fps, part_peak, gib_peak])
	m.queue_free()
	for i in 2:
		await process_frame
	quit(0)
