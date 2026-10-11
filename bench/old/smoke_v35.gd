extends SceneTree
# Smoke v35 (масштаб ×4/3): сцена целиком, 3 волны слоя 1, деление и слияние отряда, пауза дерева, стрелки.
# Ошибки и предупреждения движка смотрятся в stderr запуска.
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
	check("старт: передышка, слой 1, 400 юнитов, квадрат юнита 5.33 px", m.wave_state == m.WS_RESPITE and m.debug_layer == 1 and m.count == 400
		and is_equal_approx(m.UNIT_QUAD, 5.33), "квадрат %s" % m.UNIT_QUAD)   # после этапа 2 размер квадрата — в трансформе инстанса
	# деление и слияние в передышке
	await key(KEY_G)
	var split_ok: bool = m.squad_used[2] == 1 and m.squad_n[0] == 150 and m.squad_n[2] == 150 and m.selected_squad == 2
	await step(5)
	await key(KEY_M)
	check("деление G (150 + 150) и слияние M (300)", split_ok and m.squad_n[0] == 300 and m.squad_used[2] == 0, "n0 %d" % m.squad_n[0])
	await key(KEY_G)   # в бой — двумя отрядами пехоты
	for w in range(1, 4):
		await key(KEY_SPACE)
		await wait_ticks(5)
		check("волна %d идёт" % w, m.wave_state == m.WS_BATTLE and m.wave_number == w)
		if w == 1:
			# пауза дерева: тики и кадры стоят
			await wait_ticks(60)
			paused = true
			var t0: int = m.tick_counter
			var p0: PackedVector2Array = m.pos.duplicate()
			await step(20)
			var held: bool = m.tick_counter == t0 and m.pos == p0
			paused = false
			await wait_ticks(5)
			check("пауза: тики и позиции стоят, после снятия идут", held and m.tick_counter > t0)
		var t := 0
		while m.wave_state == m.WS_BATTLE and t < 9000:
			m._physics_process(1.0 / 30.0)   # ускоренно
			t += 1
			if t % 200 == 0:
				await process_frame
		await step(6)
		check("волна %d отбита: передышка, стрелки стреляли и попадали" % w, m.wave_state == m.WS_RESPITE and m.arrows_fired > 0 and m.arrows_hit > 0,
			"%.0f с, стрел %d / попало %d, юнитов %d, ворота %.0f" % [t / 30.0, m.arrows_fired, m.arrows_hit, m.count, m.gate_hp])
		await key(KEY_Z)   # покупка пехоты между волнами
	var bad := 0
	for i in m.count:
		var p: Vector2 = m.pos[i]
		if p.x < 0.0 or p.x > m.FIELD.x or p.y < 0.0 or p.y > m.WALL_Y:
			bad += 1
	check("все юниты в поле и не ниже WALL_Y", bad == 0, "вне: %d" % bad)
	print("SMOKE: провалов %d" % fails)
	quit()
