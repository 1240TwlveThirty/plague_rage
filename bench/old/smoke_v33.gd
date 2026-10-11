extends SceneTree
# Smoke UI v33: сигнал всплеска (иконка мигает, полоса у края, надпись), скрыт в передышке; разведки нет; R сбрасывает.
var fails := 0
var m: Node2D

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await step(3)

func to_screen(world: Vector2) -> Vector2:
	return m.get_viewport().get_canvas_transform() * world

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(8)
	check("передышка: сигналов нет, надпись скрыта, разведки нет (маркеров 0, в HUD нет «Дальше»)", m._burst_signals().is_empty() and not m.burst_label.visible
		and m._recon_markers().is_empty() and not m.hud_label.text.contains("Дальше") and m.bursts_enabled and not m.scout_shown)
	var corner := to_screen(m.FIELD * 0.5 - Vector2(m.VIEW_HALF_W, m.VIEW_HALF_H))
	check("полоса подсветки привязана к краю экрана, иконка сверху на экране", corner.distance_to(Vector2.ZERO) < 0.5 and to_screen(Vector2(m.wave_cfg.spawn_center_x, 150.0)).y > 100.0,
		"угол экрана %s, иконка %s" % [corner, to_screen(Vector2(m.wave_cfg.spawn_center_x, 150.0))])
	await key(KEY_SPACE)
	while m.tick_counter < 3:
		await process_frame
	await step(6)
	var lr: Rect2 = m.burst_label.get_global_rect()
	check("старт волны 1: сигнал сверху сразу, надпись «Всплеск: сверху» вверху по центру, игра не на паузе", m._burst_signals() == [m.SIDE_TOP] and m.burst_label.visible
		and m.burst_label.text == "Всплеск: сверху" and absf(lr.get_center().x - 960.0) < 2.0 and lr.position.y < 120.0 and not paused and m.is_physics_processing() and m.tick_counter > 0,
		"надпись %s" % lr)
	# мигание 2 Гц и пульс полосы, пока всплеск не начался (первые 2.5 с)
	var on := 0
	var off := 0
	var alpha_max := 0.0
	var flips := 0
	var prev := -1
	var t0: float = m.wave_t
	while m.wave_t < 2.3 and not m._burst_signals().is_empty():
		var lit := int(fmod(m.wave_t * 2.0, 1.0) < 0.5)
		if lit == 1:
			on += 1
		else:
			off += 1
		if prev >= 0 and lit != prev:
			flips += 1
		prev = lit
		alpha_max = maxf(alpha_max, 0.35 * (0.5 + 0.5 * sin(m.wave_t * 2.0 * TAU)))
		await process_frame
	check("иконка мигает (2 Гц), подсветка пульсирует с альфой до 0.35", on > 0 and off > 0 and flips >= 3 and alpha_max > 0.3 and alpha_max <= 0.35 + 0.0001,
		"за %.1f с переключений %d, макс. альфа %.2f" % [m.wave_t - t0, flips, alpha_max])
	while m.wave_t < 2.7:
		await process_frame
	var zombies := 0
	for i in m.count:
		zombies += int(m.team[i] == 1)
	check("в 2.5 с всплеск начал появляться (50 зомби), иконка и полоса погасли, надпись ещё видна", zombies == 50 and m._burst_signals().is_empty() and m.burst_label.visible, "зомби %d, t = %.2f" % [zombies, m.wave_t])
	while m.wave_t < 3.3:
		await process_frame
	await step(6)
	check("надпись гаснет через 3 с", not m.burst_label.visible)
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 3600:
		m._physics_process(1.0 / 30.0)   # ускоренно
		t += 1
		if t % 300 == 0:
			await process_frame
	await step(8)
	check("передышка после волны 1: сигналов и надписи нет, баннер итога со строкой «убито: крестьяне 50»", m.wave_state == m.WS_RESPITE and m._burst_signals().is_empty() and not m.burst_label.visible
		and m.banner.visible and m.banner_labels[1].text.contains("убито: крестьяне 50"))
	# поражение во время сигнала, затем R
	await key(KEY_SPACE)
	var tick0: int = m.tick_counter
	while m.tick_counter < tick0 + 3:   # кадры без окна идут быстрее тиков
		await process_frame
	var had_signal: bool = not m._burst_signals().is_empty()
	m.gate_hp = 0.0
	await step(8)
	check("поражение на волне 2 во время сигнала: сигнал и надпись скрыты", had_signal and m.wave_state == m.WS_DEFEAT and m._burst_signals().is_empty() and not m.burst_label.visible)
	await key(KEY_R)
	await step(8)
	var m2: Node2D = current_scene
	check("R: новая сцена, таймеры и сигналы сброшены", m2 != null and m2 != m and m2.wave_state == m2.WS_RESPITE and m2.wave_t == 0.0 and m2.burst_idx == 0 and m2.burst_signal_n == 0
		and m2._burst_signals().is_empty() and not m2.burst_label.visible)
	print("SMOKE: провалов %d" % fails)
	quit()
