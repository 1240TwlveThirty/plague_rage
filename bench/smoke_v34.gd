extends SceneTree
# Smoke UI v34: красная полоса сигнала у нужного края, без надписей и треугольников, гаснет; R сбрасывает.
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

func alphas() -> Array:
	return [m._signal_alpha(0), m._signal_alpha(1), m._signal_alpha(2)]

func wait_ticks(n: int) -> void:
	var t0: int = m.tick_counter
	while m.tick_counter < t0 + n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(8)
	var ui_layer: CanvasLayer = m.hud_label.get_parent()
	check("передышка: полос нет, надпись скрыта; интерфейс на слое выше поля (полоса рисуется под HUD и панелями)", alphas() == [0.0, 0.0, 0.0] and not m.burst_label.visible
		and ui_layer.layer >= 1 and m.squad_panel.get_parent() == ui_layer and m.shop_panel.get_parent() == ui_layer and m.bursts_layered and m.debug_layer == 1)
	var corner: Vector2 = m.get_viewport().get_canvas_transform() * (m.FIELD * 0.5 - Vector2(m.VIEW_HALF_W, m.VIEW_HALF_H))
	check("полоса привязана к краям экрана", corner.distance_to(Vector2.ZERO) < 0.5)
	# волна 1: только верх (боковые стороны с волны 3)
	await key(KEY_SPACE)
	await wait_ticks(3)
	await step(4)
	check("волна 1: сразу красная полоса сверху (0.30), боковых нет; надписи и треугольников нет, игра не на паузе", alphas() == [0.30, 0.0, 0.0] and not m.burst_label.visible and m.burst_msg == ""
		and m._burst_signals().is_empty() and not m.SIGNAL_TEXT_SHOWN and not m.SIGNAL_ICONS_SHOWN and not paused and m.is_physics_processing(), "альфа %s" % [alphas()])
	var lead: float = m._layer().signal_lead
	while m.wave_t < lead + 0.25:
		await process_frame
	var zombies := 0
	for i in m.count:
		zombies += int(m.team[i] == 1)
	check("в %.1f с всплеск появляется, полоса ещё горит (0.4 с после старта)" % lead, zombies > 0 and m._signal_alpha(0) == 0.30, "зомби %d" % zombies)
	var seen_fade := false
	while m.wave_t < lead + 0.75:
		var a: float = m._signal_alpha(0)
		if a > 0.01 and a < 0.29:
			seen_fade = true
		await process_frame
	check("полоса гаснет за 0.2 с и пропадает", seen_fade and m._signal_alpha(0) == 0.0, "t = %.2f" % m.wave_t)
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 6000:
		m._physics_process(1.0 / 30.0)   # ускоренно
		t += 1
		if t % 300 == 0:
			await process_frame
	await step(8)
	check("передышка после волны 1: полос нет, баннер итога на месте", m.wave_state == m.WS_RESPITE and alphas() == [0.0, 0.0, 0.0] and m.banner.visible and m.banner_labels[1].text.contains("убито: крестьяне 50"))
	# волна с боковым всплеском в первой группе: подбираем seed и волну
	var found := false
	for w in range(3, 12):
		for s in range(1, 60):
			m.spawn_seed = s
			var bursts: Array = m._plan_bursts(w, m._plan_wave(w))
			if bursts[0].side != m.SIDE_TOP:
				m.wave_number = w - 1
				m.wave_plan_for = -1
				found = true
				break
		if found:
			break
	await key(KEY_SPACE)
	await wait_ticks(3)
	await step(4)
	var first_side: int = m.wave_bursts[0].side
	var expect := [0.0, 0.0, 0.0]
	for b in m.wave_bursts:
		if b.group == 0:
			expect[b.side] = 0.30
	check("волна %d: полоса у края своей стороны (первая группа: %s), у остальных нет" % [m.wave_number, "слева" if first_side == m.SIDE_LEFT else "справа"], found and alphas() == expect and first_side != m.SIDE_TOP
		and not m.burst_label.visible, "альфа %s" % [alphas()])
	# поражение во время сигнала и R
	m.gate_hp = 0.0
	await step(8)
	check("поражение во время сигнала: полосы скрыты", m.wave_state == m.WS_DEFEAT and alphas() == [0.0, 0.0, 0.0])
	await key(KEY_R)
	await step(8)
	var old := m
	m = current_scene
	check("R: новая сцена, таймеры и сигналы сброшены", m != null and m != old and m.wave_state == m.WS_RESPITE and m.wave_t == 0.0 and m.burst_idx == 0 and m.burst_signal_n == 0 and alphas() == [0.0, 0.0, 0.0])
	print("SMOKE: провалов %d" % fails)
	quit()
