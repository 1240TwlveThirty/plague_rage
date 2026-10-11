extends SceneTree
# Smoke v38 (радиус лучников 480 px), со сценой: кольцо дальности выбранных лучников, волна слоя 1, счётчики до контакта.
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

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(8)
	await key(KEY_2)
	var ring: float = m._range_ring_radius(m.selected_squad)
	var c: Vector2 = m.squad_pos[1]
	var view := Rect2(m.FIELD * 0.5 - Vector2(m.VIEW_HALF_W, m.VIEW_HALF_H), Vector2(m.VIEW_HALF_W, m.VIEW_HALF_H) * 2.0)
	var inside := 0
	var above_wall := 0
	for deg in 360:
		var p := c + Vector2.from_angle(deg_to_rad(deg)) * ring
		if view.has_point(p):
			inside += 1
		if p.y <= m.WALL_Y:
			above_wall += 1
	check("(ж) выбран отряд лучников, кольцо дальности 480 px рисуется вокруг его центра", m.selected_squad == 1 and ring == 480.0, "центр %s" % c.round())
	check("(ж) кольцо на экране целиком", inside == 360, "на экране %d° из 360; верх кольца y = %.0f, низ y = %.0f при нижнем крае экрана %.0f; над стеной (поле боя) %d°" % [
		inside, c.y - ring, c.y + ring, view.end.y, above_wall])
	await key(KEY_SPACE)
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 9000:
		m._physics_process(1.0 / 30.0)
		t += 1
		if t % 200 == 0:
			await process_frame
	await step(6)
	check("волна 1 отбита, стрелки стреляли; счётчики до контакта заполнены", m.wave_state == m.WS_RESPITE and m.arrows_fired > 0 and m.arrows_dropped == 0 and m.volleys_before_contact >= 1,
		"стрел %d, попало %d, убито стрелами %d, залпов до контакта %d, стрел до контакта %d" % [m.arrows_fired, m.arrows_hit, m.kills_by_arrows, m.volleys_before_contact, m.arrows_before_contact])
	check("в отладочной строке новых счётчиков нет", not m.fps_label.text.contains("контакт"))
	await key(KEY_F5)
	await key(KEY_F5)
	print("SMOKE: провалов %d" % fails)
	quit()
