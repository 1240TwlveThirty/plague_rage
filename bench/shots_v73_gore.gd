extends SceneTree
# Снимки задачи 23 (окно 1920x1080): волна 10, seed 3, герой (hero_mode 1) идёт к ближайшему зомби и бьёт каждый тик, ворота
# бессмертны. Кадры — m._process(1/60) по 2 на тик (тики — m._physics_process), поэтому кадр за кадром одинаково в копиях
# до и после правок: скрипт не использует новых полей и запускается и на прежнем main.gd (сравнение «до/после» по тем же seed).
#   <префикс>_battle.png        — массовый бой (тик BATTLE_TICK), вся камера;
#   <префикс>_hero_close.png    — удар героя крупно (камера x2.5 на герое, через 5 кадров после удара с добиванием);
#   <префикс>_field_after.png   — поле после волны (волна отбита, кровь подсохла).
# Аргументы: <папка> [префикс] [--font=...]. Печатает SHOT|файл|тик|юнитов|частиц|кусков.
const DT := 1.0 / 30.0
const BATTLE_TICK := 900
var m: Node2D
var out_dir := ""
var prefix := "after"

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var file := "%s_%s.png" % [prefix, name]
	root.get_texture().get_image().save_png(out_dir.path_join(file))
	var gibs = m.get("gib_n")
	print("SHOT|%s|тик %d|юнитов %d|частиц %d|кусков %s" % [file, m.tick_counter, m.count, m.hit_n, str(gibs)])

func chase(_t) -> Dictionary:
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

# Тик и два кадра отрисовки.
func tick() -> void:
	m._physics_process(DT)
	m._process(1.0 / 60.0)
	m._process(1.0 / 60.0)

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	if root.has_node("Game"):
		root.get_node("Game").free()
	_run.call_deferred()

func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a): return not a.begins_with("--font="))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1:
		prefix = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	m = load("res://scenes/main.tscn").instantiate()
	m.spawn_seed = 3
	m.hero_mode = 1
	m.record_path = "user://record_bench.json"
	m.process_mode = Node.PROCESS_MODE_DISABLED   # тики и кадры — вручную
	root.add_child(m)
	current_scene = m
	await step(3)
	m.banner.visible = false
	m.hero_feed = chase
	m.wave_number = 9
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	m.hp[m.hero_idx] = 1e6
	while m.tick_counter < BATTLE_TICK:
		tick()
		await process_frame   # кадр движка: слой крови (если есть) рисуется по кадрам
	m.banner.visible = false
	await step(1)
	await shot("battle")
	# удар героя крупно: следующий удар с добиванием
	var k0: int = m.hero_kills
	var t := 0
	while m.hero_kills == k0 and t < 300:
		tick()
		await process_frame
		t += 1
	var cam: Camera2D = m.camera
	var z0 := cam.zoom
	var p0 := cam.position
	cam.zoom = z0 * 2.5
	cam.position = m.pos[m.hero_idx] if m.hero_idx >= 0 else p0
	for q in 5:   # 5 кадров после удара: брызги успели разлететься
		m._process(1.0 / 60.0)
		await process_frame
	await step(1)
	await shot("hero_close")
	cam.zoom = z0
	cam.position = p0
	# до конца волны, затем передышка: кровь подсыхает
	t = 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 600:
		tick()
		await process_frame
		t += 1
	for q in 360:   # 6 с передышки (кадры, тики стоят: в передышке бой не идёт)
		m._process(1.0 / 60.0)
		await process_frame
	m.banner.visible = false
	await step(1)
	await shot("field_after")
	m.queue_free()
	await step(2)
	print("SHOTS: готово")
	quit(0)
