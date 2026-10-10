extends SceneTree
# Smoke UI v32: разведка в передышке (маркеры, строка HUD), скрыта в бою; строка состава в баннере итога волны.
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

# Маркеры на экране и не под панелями отрядов и магазина (с запасом на подписи состава).
func markers_ok(markers: Array) -> bool:
	var ok := true
	for mk in markers:
		var n: int = mk.items.size()
		var at := to_screen(mk.pos)
		var r := Rect2(at + Vector2(-22.0 - n * 78.0 if mk.side == m.SIDE_RIGHT else -16.0, -16.0), Vector2(38.0 + n * 78.0, 32.0))
		ok = ok and r.position.x >= 0.0 and r.end.x <= 1920.0 and r.position.y >= 0.0 and r.end.y <= 1080.0
		ok = ok and not r.intersects(m.squad_panel.get_global_rect()) and not r.intersects(m.shop_panel.get_global_rect())
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(8)
	var mk: Array = m._recon_markers()
	check("передышка перед волной 1: один маркер сверху (50 крестьян), строка HUD «Дальше: волна 1 · ↑ 50»", mk.size() == 1 and mk[0].side == m.SIDE_TOP
		and mk[0].items == [[m.zombie_type, 50]] and m.hud_label.text.contains("Дальше: волна 1 · ↑ 50") and markers_ok(mk), m.hud_label.text.replace("\n", " / "))
	await key(KEY_SPACE)
	await step(8)
	check("в бою маркеры скрыты и строки «Дальше» нет", m.wave_state == m.WS_BATTLE and m._recon_markers().is_empty() and not m.hud_label.text.contains("Дальше"))
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 3600:
		m._physics_process(1.0 / 30.0)   # ускоренно: тики вручную
		t += 1
		if t % 300 == 0:
			await process_frame
	await step(8)
	check("после волны 1: в баннере строка состава, в HUD разведка волны 2", m.wave_state == m.WS_RESPITE and m.banner.visible and m.banner_labels[1].text.contains("убито: крестьяне 50")
		and m.hud_label.text.contains("Дальше: волна 2 · ↑ 95"), m.banner_labels[1].text.replace("\n", " / "))
	# переход к передышке перед волной 6: три стороны, бегуны
	for s in range(1, 200):   # seed, при котором у волны 6 активны обе боковые стороны (план зависит от spawn_seed + номер волны)
		m.spawn_seed = s
		var seen := {}
		for r in m._plan_wave(6):
			seen[r.side] = true
		if seen.size() == 3:
			break
	m.wave_state = m.WS_BATTLE
	m.wave_number = 5
	m._wave_cleared()
	await step(8)
	mk = m._recon_markers()
	var sides := []
	var has_runner := [false, false, false]
	for q in mk:
		sides.append(q.side)
		for it in q.items:
			if it[0] == m.runner_type:
				has_runner[q.side] = true
	check("передышка перед волной 6: маркеры трёх сторон, бегуны только сбоку, строка HUD со стрелками и бегунами", sides == [0, 1, 2] and not has_runner[0] and has_runner[1] and has_runner[2]
		and m.hud_label.text.contains("Дальше: волна 6 · ↑") and m.hud_label.text.contains("←") and m.hud_label.text.contains("→") and m.hud_label.text.contains("(бегуны 55)"),
		m.hud_label.text.replace("\n", " / "))
	check("маркеры на экране и не под панелями отрядов и магазина", markers_ok(mk), "верх %s, лево %s, право %s" % [to_screen(mk[0].pos), to_screen(mk[1].pos), to_screen(mk[2].pos)])
	await key(KEY_SPACE)
	await step(6)
	var types := {}
	var tt := 0
	while m.wave_state == m.WS_BATTLE and tt < 600:
		m._physics_process(1.0 / 30.0)
		tt += 1
		for i in m.count:
			if m.team[i] == 1:
				types[m.unit_type[i]] = true
		if tt % 200 == 0:
			await process_frame
	await step(4)
	check("волна 6 идёт: на поле крестьяне и бегуны, маркеры скрыты", m.wave_number == 6 and types.has(m.zombie_type) and types.has(m.runner_type) and (m.wave_state != m.WS_BATTLE or m._recon_markers().is_empty()))
	print("SMOKE: провалов %d" % fails)
	quit()
