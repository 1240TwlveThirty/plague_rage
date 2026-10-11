extends SceneTree
# Smoke v36 (масштаб как параметр, шаг 12): сцена целиком, 3 волны слоя 1, деление и слияние, пауза дерева, стрелки, F5.
# Режим jitter: (ж) сдвиг отрисовки — main с RENDER_JITTER 1.0 против копии с 0: pos совпадают, сдвиг в буфере до 1 px.
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
	if OS.get_cmdline_user_args().is_empty():
		_run.call_deferred()
	else:
		_jitter.call_deferred()

# (ж) два узла рядом: тики и _process вручную, чтобы оба шли одинаково.
func _jitter() -> void:
	var a: Node2D = load("res://scripts/main.gd").new()
	var b: Node2D = load("res://bench/old/main_v36_nojit.gd").new()
	for x in [a, b]:
		x.spawn_seed = 9
		x.record_path = "user://record_bench.json"
		root.add_child(x)
		x.set_physics_process(false)
		x.set_process(false)
	await step(3)
	a._start_wave()
	b._start_wave()
	var diff := -1
	var max_off := 0.0
	var min_x := 0.0
	var max_x := 0.0
	var min_y := 0.0
	var max_y := 0.0
	var buf_bad := 0
	var same_xy := 0
	for t in 900:
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if t % 10 == 0:
			for x in [a, b]:
				x.prev_pos = x.pos.duplicate()   # без интерполяции: позиция в буфере = pos + сдвиг
				x._process(0.0)
			for i in a.count:
				var off: Vector2 = Vector2(a.buf[i * 16 + 3], a.buf[i * 16 + 7]) - a.pos[i]
				min_x = minf(min_x, off.x)
				max_x = maxf(max_x, off.x)
				min_y = minf(min_y, off.y)
				max_y = maxf(max_y, off.y)
				max_off = maxf(max_off, maxf(absf(off.x), absf(off.y)))
				if off.distance_to(a._render_offset(i)) > 0.001 or Vector2(b.buf[i * 16 + 3], b.buf[i * 16 + 7]) != b.pos[i]:
					buf_bad += 1
				if is_equal_approx(off.x, off.y):
					same_xy += 1
		if diff < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp):
			diff = t
	check("(ж) RENDER_JITTER %.1f против 0: pos, hp, count совпадают на каждом из 900 тиков" % a.RENDER_JITTER, diff < 0 and a.RENDER_JITTER == 1.0 and b.RENDER_JITTER == 0.0, "расхождение: тик %d" % diff)
	check("(ж) сдвиг в буфере: максимум по |dx|, |dy| не больше 1.0 px и близок к нему; dx и dy независимы; без сдвига буфер = pos",
		max_off <= 1.0 + 0.0001 and max_off > 0.98 and buf_bad == 0 and same_xy == 0, "максимум %.4f; dx %.3f..%.3f, dy %.3f..%.3f; ошибок %d" % [max_off, min_x, max_x, min_y, max_y, buf_bad])
	print("SMOKE: провалов %d" % fails)
	quit()

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(8)
	check("старт: передышка, слой 1, 400 юнитов, шаг строя 12, квадрат юнита 8 px", m.wave_state == m.WS_RESPITE and m.debug_layer == 1 and m.count == 400
		and m.UNIT_QUAD == 8.0 and m.SLOT_SPACING == 12.0 and m.CELL_SIZE == 24.0, "квадрат %s" % m.UNIT_QUAD)
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
		if w == 2:
			await key(KEY_F5)
			var off: bool = not m.sprites_on
			var inf_i := 0   # любой пехотинец в отряде (в передышке стоит: кадр 0)
			while m.unit_type[inf_i] != m.infantry_type or m.unit_squad[inf_i] < 0:
				inf_i += 1
			var cell_off := int(m.buf[inf_i * 16 + 12])
			await key(KEY_F5)
			check("F5: спрайты выключаются (ячейка 3) и включаются (ячейка 0)", off and cell_off == 3 and m.sprites_on and int(m.buf[inf_i * 16 + 12]) == 0)
	var bad := 0
	for i in m.count:
		var p: Vector2 = m.pos[i]
		if p.x < 0.0 or p.x > m.FIELD.x or p.y < 0.0 or p.y > m.WALL_Y:
			bad += 1
	check("все юниты в поле и не ниже WALL_Y", bad == 0, "вне: %d" % bad)
	print("SMOKE: провалов %d" % fails)
	quit()
