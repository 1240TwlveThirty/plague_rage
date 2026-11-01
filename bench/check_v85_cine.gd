extends SceneTree
# Задача 31 (без окна): режим съёмки. Настройки — data/cine.json, сцены — data/cine_scenes.json; тест читает их оттуда. Своё
# временное сохранение (user://bench_v85). Клавиши — через root.push_input (физические коды), как от игрока.
#   Детерминизм: сцена SCENE, бой идёт сам (физика движка, реальное время) ровно N тиков — хеш позиций и HP одинаков при скорости
#   1.0, при 0.25 и с включённым режимом съёмки; на 0.25 тики идут реже (реального времени больше).
#   Режим: F9 скрывает слои интерфейса (кроме экрана карточек и меню Esc), второй F9 — всё как было (слои, баннер, пауза и её
#   надпись); слой, показанный игрой в режиме, при выходе виден. Курсор скрыт, в меню Esc виден. Скорость: «]» быстрее, «[»
#   медленнее (по time_scales), «\» — 1.0, вне режима не действуют; выход из режима, уход в хаб и в меню, закрытие — 1.0 и звук 1.0.
#   Предел зума в режиме — cine_zoom_max, после выхода — прежний.
const DIR := "user://bench_v85"
const SCENE := "big_battle"
const N := 90
const CINE_SCENES := preload("res://scripts/cine_scenes.gd")
var fails := 0
var g: Node
var cfg: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)
	_run.call_deferred()

func key(name: String) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = OS.find_keycode_from_string(name)
	e.keycode = e.physical_keycode
	e.pressed = true
	root.push_input(e, true)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e, true)
	await step(2)

# Останавливает физику боя на тике stop: после main в том же шаге физики.
class Stopper extends Node:
	var m: Node2D
	var stop := 0
	func _init() -> void:
		process_physics_priority = 100
	func _physics_process(_d: float) -> void:
		if m != null and m.tick_counter >= stop:
			m.set_physics_process(false)

func digest(m: Node2D) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(m.pos.slice(0, m.count).to_byte_array())
	ctx.update(m.hp.slice(0, m.count).to_byte_array())
	return ctx.finish().hex_encode()

# Бой сцены: физика выключена до сборки, затем N тиков сам при скорости speed (режим съёмки on).
func run_scene(speed: float, on: bool) -> Array:
	var sc := CINE_SCENES.find(SCENE)
	g.run_seed = int(sc.seed)
	var prep := func(n: Node) -> void:
		if n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
			CINE_SCENES.prepare(n, sc)
			n.ready.connect(func(): n.set_physics_process(false), CONNECT_ONE_SHOT)
	node_added.connect(prep)
	g.start_run(1)
	await step(3)
	node_added.disconnect(prep)
	var m: Node2D = current_scene
	CINE_SCENES.build(m, sc)
	if on:
		m.cine.set_on(true)
	m.cine.set_scale(speed) if on else null
	if not on:
		Engine.time_scale = speed
	var t0: int = m.tick_counter
	var st := Stopper.new()
	st.m = m
	st.stop = t0 + N
	root.add_child(st)
	var ms := Time.get_ticks_msec()
	m.set_physics_process(true)
	while m.is_physics_processing():
		await process_frame
	var real := (Time.get_ticks_msec() - ms) / 1000.0
	var out := [digest(m), m.tick_counter - t0, real, m.count]
	st.queue_free()
	Engine.time_scale = 1.0
	if on:
		m.cine.set_on(false)
	g.go_menu()
	await step(2)
	return out

func _run() -> void:
	cfg = load("res://scripts/cine.gd").load_cfg()
	g = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	print("детерминизм: сцена %s, %d тиков" % [SCENE, N])
	var a: Array = await run_scene(1.0, false)
	var b: Array = await run_scene(0.25, false)
	var c: Array = await run_scene(1.0, true)
	var d: Array = await run_scene(0.25, true)
	print("CINE85|1.0: %s за %.1f с|0.25: %s за %.1f с|режим 1.0: %s|режим 0.25: %s|юнитов %d" % [a[0], a[2], b[0], b[2], c[0], d[0], a[3]])
	check("хеш позиций и HP на тике %d одинаков: скорость 1.0 и 0.25, режим съёмки выкл и вкл (тиков %d/%d/%d/%d)" % [N, a[1], b[1], c[1], d[1]],
		a[0] == b[0] and a[0] == c[0] and a[0] == d[0] and a[1] == N and b[1] == N and c[1] == N and d[1] == N)
	check("на 0.25 реального времени больше (%.1f с против %.1f с)" % [b[2], a[2]], b[2] > a[2] * 2.0)
	# --- интерфейс до и после режима ---
	g.run_seed = 3
	g.start_run(1)
	await step(6)
	var m: Node2D = current_scene
	var cine: Node = m.cine
	var layers: Array = cine._layers()
	var vis_before := layers.map(func(l): return l.visible)
	var state_before := [m.banner.visible, m.banner_hidden, m.paused, m.pause_label.visible, m.pause_dim.visible, m.sel_mask]
	await key("[")
	check("вне режима «[» скорость не меняет", Engine.time_scale == 1.0)
	await key(cfg.cine_key)
	check("F9: режим включён, слоёв интерфейса %d — все скрыты; экран карточек и меню Esc — не из их числа" % layers.size(), cine.on and m.cine_on
		and layers.size() > 0 and layers.all(func(l): return not l.visible) and not m.card_screen in layers and not m.esc_menu in layers)
	check("курсор: скрыт (cine_hide_cursor %s)" % cfg.cine_hide_cursor, cine.cursor_mode() == (Input.MOUSE_MODE_HIDDEN if cfg.cine_hide_cursor else Input.MOUSE_MODE_VISIBLE))
	var list: Array = cfg.time_scales
	var i1 := list.find(1.0)
	await key(cfg.faster_key)
	var up := Engine.time_scale
	await key(cfg.slower_key)
	await key(cfg.slower_key)
	var down := Engine.time_scale
	await key(cfg.reset_key)
	check("скорость: «]» %s, «[» дважды %s, «\\» %s (шаги %s)" % [up, down, Engine.time_scale, str(list)],
		up == float(list[mini(i1 + 1, list.size() - 1)]) and down == float(list[maxi(i1 - 1, 0)]) and Engine.time_scale == 1.0)
	var zmax: float = m.cam_cfg.zoom_user_max
	check("предел приближения в режиме — cine_zoom_max %s" % cfg.cine_zoom_max, is_equal_approx(zmax, float(cfg.cine_zoom_max)))
	m._open_esc_menu()
	await step(2)
	check("меню Esc в режиме видно, курсор виден", m.esc_menu.visible and cine.cursor_mode() != Input.MOUSE_MODE_HIDDEN)
	m.esc_menu.close()
	await step(2)
	var hint_was: bool = m.hints.visible
	m.hints.visible = true   # игра сама показала подсказку в режиме: она в слое интерфейса — не на экране
	await step(2)
	check("подсказка, показанная игрой в режиме, не на экране (её слой скрыт)", not m.hints.is_visible_in_tree())
	await key(cfg.slower_key)
	await key(cfg.cine_key)
	var vis_after := layers.map(func(l): return l.visible)
	var state_after := [m.banner.visible, m.banner_hidden, m.paused, m.pause_label.visible, m.pause_dim.visible, m.sel_mask]
	check("после выхода подсказка, показанная в режиме, на экране", m.hints.is_visible_in_tree())
	m.hints.visible = hint_was
	check("второй F9: слои как до режима (%s), баннер, пауза, выбор — те же (%s)" % [str(vis_after), str(state_after)], vis_after == vis_before and state_after == state_before and not m.cine_on)
	check("выход из режима: скорость 1.0, звук 1.0, предел зума прежний (%s)" % m.cam_cfg.zoom_user_max, Engine.time_scale == 1.0 and AudioServer.playback_speed_scale == 1.0
		and m.cam_cfg.zoom_user_max < zmax)
	# пауза в бою: режим включается и выключается на паузе, надпись и затемнение — как были
	m._start_wave()
	await step(2)
	m._set_paused(true)
	await step(1)
	var pb := [m.paused, m.pause_label.visible, m.pause_dim.visible]
	await key(cfg.cine_key)
	var hidden_pause: bool = not m.pause_label.is_visible_in_tree() and not m.pause_dim.is_visible_in_tree() and m.paused
	await key(cfg.cine_key)
	check("бой на паузе: в режиме надписи и затемнения не видно, пауза идёт; после — как было %s" % str(pb), pb == [true, true, true] and hidden_pause
		and [m.paused, m.pause_label.visible, m.pause_dim.visible] == pb)
	m._set_paused(false)
	# уход из боя и закрытие: скорость 1.0
	await key(cfg.cine_key)
	await key(cfg.slower_key)
	var slow := Engine.time_scale
	g.go_hub()
	await step(4)
	check("режим, скорость %s -> уход в хаб: скорость 1.0, звук 1.0" % slow, slow < 1.0 and Engine.time_scale == 1.0 and AudioServer.playback_speed_scale == 1.0)
	g.start_run(1)
	await step(6)
	m = current_scene
	await key(cfg.cine_key)
	await key(cfg.slower_key)
	g.go_menu()
	await step(4)
	check("режим, замедление -> выход в меню: скорость 1.0", Engine.time_scale == 1.0)
	g.start_run(1)
	await step(6)
	m = current_scene
	await key(cfg.cine_key)
	await key(cfg.slower_key)
	m.cine.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check("режим, замедление -> закрытие окна: скорость 1.0", Engine.time_scale == 1.0)
	g.go_menu()
	await step(3)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
