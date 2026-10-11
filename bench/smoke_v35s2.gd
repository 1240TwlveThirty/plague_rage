extends SceneTree
# Smoke v35, этап 2 (спрайты пехоты), со сценой. Режимы:
#   (без аргументов) — (е) буфер MultiMesh, (з) клавиши F1-F5 и пауза; ошибки и предупреждения движка — в stderr;
#   time <main_3000.gd> — (ж) время _process на 3000 юнитах (медиана 300 вызовов);
#   shots <папка> — снимки экрана (только с окном, без --headless): 4 направления и бой.
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

# Ошибки в буфере у юнитов из списка: custom.x, базис и цвет против массивов симуляции.
func buf_errors(ids: Array, sprites: bool) -> int:
	var bad := 0
	for i in ids:
		var o: int = i * 16
		var b: PackedFloat32Array = m.buf
		var is_sprite: bool = sprites and m.unit_type[i] == m.infantry_type and m.unit_squad[i] >= 0
		var want_cell: float = m._unit_frame(i) if is_sprite else 3.0
		var basis := [b[o], b[o + 1], b[o + 4], b[o + 5]]
		var want_basis := [m.UNIT_QUAD, 0.0, 0.0, m.UNIT_QUAD]
		var want_col := Color.WHITE
		if is_sprite:
			var d: int = m.unit_dir[i] * 4
			want_basis = [m.DIR_BASIS[d], m.DIR_BASIS[d + 1], m.DIR_BASIS[d + 2], m.DIR_BASIS[d + 3]]
		elif m.color_mode == 0:
			want_col = m.type_color[m.unit_type[i]]
		var col_ok: bool = m.color_mode != 0 or (is_equal_approx(b[o + 8], want_col.r) and is_equal_approx(b[o + 9], want_col.g) and is_equal_approx(b[o + 10], want_col.b))
		for q in 4:
			if not is_equal_approx(basis[q], want_basis[q]):
				col_ok = false
		if b[o + 12] != want_cell or not col_ok or b[o + 11] != 1.0:
			bad += 1
	return bad

func cells(n: int) -> Dictionary:
	var d := {}
	for i in n:
		var c := int(m.buf[i * 16 + 12])
		d[c] = d.get(c, 0) + 1
	return d

func run_smoke() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(8)
	var node: MultiMeshInstance2D
	for ch in m.get_children():
		if ch is MultiMeshInstance2D:
			node = ch
	var tex: Texture2D = node.texture
	var img := tex.get_image() if tex != null else null
	var white_ok := img != null and img.get_pixel(48, 0) == Color.WHITE and img.get_pixel(63, 15) == Color.WHITE
	var opaque := 0
	if img != null:
		for y in 16:
			for x in 48:
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
	check("(е) атлас 64x16 без mipmaps, ячейка 3 белая, в кадрах 0-2 есть картинка; фильтр Nearest, шейдер и custom_data включены",
		m.sprites_ok and tex is ImageTexture and tex.get_size() == Vector2(64, 16) and not img.has_mipmaps() and white_ok and opaque > 100
		and node.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and node.material is ShaderMaterial and m.multimesh.use_custom_data and m.multimesh.use_colors,
		"непрозрачных пикселей в кадрах %d" % opaque)
	check("(е) буфер: 16 float на юнита, длина 16 × MAX_UNITS = %d" % (16 * m.MAX_UNITS), m.FLOATS_PER_UNIT == 16 and m.buf.size() == 16 * m.MAX_UNITS and m.multimesh.buffer.size() == 16 * m.MAX_UNITS)
	# бой: волна 3 (есть бегуны), до первых ударов
	m.wave_number = 2
	m.wave_plan_for = -1
	await key(KEY_SPACE)
	var t := 0
	while m.total_hits < 40 and t < 3000:
		m._physics_process(1.0 / 30.0)
		t += 1
	# await process_frame возвращается после физических тиков кадра, но до _process узла: чтобы буфер и массивы
	# симуляции сравнивались в одном состоянии, физика на время проверок буфера остановлена.
	m.set_physics_process(false)
	await step(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ids := []
	var by_type := {}
	# 100 юнитов: все, кто сейчас в кадрах 1 и 2, остальные случайные
	for i in m.count:
		if m.unit_type[i] == m.infantry_type and m._unit_frame(i) > 0 and ids.size() < 40:
			ids.append(i)
	while ids.size() < 100:
		var i := rng.randi_range(0, m.count - 1)
		if not i in ids:
			ids.append(i)
	for i in ids:
		by_type[m.type_label[m.unit_type[i]]] = by_type.get(m.type_label[m.unit_type[i]], 0) + 1
	check("(е) F1: custom.x, базис и цвет у 100 юнитов соответствуют типу, кадру и направлению", buf_errors(ids, true) == 0 and cells(m.count).has(1) and cells(m.count).has(2),
		"выборка %s; ячейки по всем %d юнитам %s" % [by_type, m.count, cells(m.count)])
	# (з) клавиши
	await key(KEY_F5)
	check("(з) F5: спрайты выключены — у всех custom.x = 3 и квадрат 5.33", not m.sprites_on and cells(m.count).keys() == [3] and buf_errors(ids, false) == 0)
	await key(KEY_F5)
	check("(з) F5 ещё раз: спрайты снова включены", m.sprites_on and buf_errors(ids, true) == 0 and cells(m.count).size() > 1)
	for k in [KEY_F2, KEY_F3, KEY_F4]:
		await key(k)
		check("(з) F%d: все юниты цветными квадратами (custom.x = 3)" % (k - KEY_F1 + 1), m.color_mode == k - KEY_F1 and cells(m.count).keys() == [3] and buf_errors(ids, false) == 0)
	await key(KEY_F1)
	check("(з) F1: пехота спрайтами", m.color_mode == 0 and buf_errors(ids, true) == 0 and cells(m.count).size() > 1)
	# пауза: кадры, таймеры и буфер стоят
	m.set_physics_process(true)
	await step(3)
	paused = true
	await step(2)
	var buf0: PackedFloat32Array = m.buf.duplicate()
	var anim0: PackedFloat32Array = m.unit_anim_t.duplicate()
	var dir0: PackedByteArray = m.unit_dir.duplicate()
	var tick0: int = m.tick_counter
	await step(30)
	var held: bool = m.buf == buf0 and m.unit_anim_t == anim0 and m.unit_dir == dir0 and m.tick_counter == tick0
	paused = false
	var t1: int = m.tick_counter
	while m.tick_counter < t1 + 10:
		await process_frame
	check("(з) пауза: тики, таймеры кадров, направления и буфер не меняются; после снятия идут", held and m.buf != buf0)
	# поворот отряда в бою и новые юниты
	m._cmd_rotate(6)   # 90°
	t1 = m.tick_counter
	while m.tick_counter < t1 + 120:
		await process_frame
	var dirs := {}
	for i in m.count:
		if m.unit_squad[i] == m.selected_squad:
			dirs[m.unit_dir[i]] = true
	check("(з) Shift+колесо на 90°: отряд повернулся, спрайты смотрят вправо (0)", dirs.keys() == [0], "направления %s, угол %.2f" % [dirs.keys(), m.squad_angle[m.selected_squad]])
	t = 0
	while m.wave_state == m.WS_BATTLE and t < 9000:
		m._physics_process(1.0 / 30.0)
		t += 1
	await step(4)
	m.gold = 1000.0
	await key(KEY_Z)
	m.set_physics_process(false)
	await step(4)
	check("(з) после волны и покупки пехоты: буфер без ошибок у всех юнитов", m.wave_state == m.WS_RESPITE and buf_errors(range(m.count), true) == 0, "юнитов %d, ячейки %s" % [m.count, cells(m.count)])
	print("SMOKE: провалов %d" % fails)
	quit()

func run_time(path: String) -> void:
	m = load(path).new()
	m.waves_enabled = false
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	await step(4)
	for t in 60:
		m._physics_process(1.0 / 30.0)
	m.set_physics_process(false)
	var ms := PackedFloat64Array()
	for k in 300:
		m._process(0.0)
		ms.append(m.draw_ms)
	ms.sort()
	print("DRAW,%s,%d,%.4f,%.4f" % [path, m.count, ms[150], ms[15]])
	quit()

func shot(dir: String, name: String, centre: Vector2, half: Vector2, zoom: int) -> void:
	await step(3)
	var img := root.get_texture().get_image()
	var scr: Vector2 = m.get_viewport().get_canvas_transform() * centre
	var scale: Vector2 = Vector2(img.get_size()) / Vector2(root.get_visible_rect().size)
	var r := Rect2i(Vector2i((scr - half) * scale), Vector2i(half * 2.0 * scale))
	var crop := img.get_region(r)
	crop.resize(crop.get_width() * zoom, crop.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	crop.save_png(dir + "/" + name + ".png")
	print("SHOT %s %s окно %s" % [name, crop.get_size(), img.get_size()])

func run_shots(dir: String) -> void:
	m = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(10)
	var names := ["right", "down", "left", "up"]
	for d in 4:
		m.squad_angle[0] = wrapf(d * PI * 0.5, -PI, PI)
		for t in 90:
			m._physics_process(1.0 / 30.0)
		await shot(dir, "dir_" + names[d], m._front_centre(0), Vector2(48, 32), 6)
	m.squad_angle[1] = m.squad_angle[0]
	m.wave_number = 5
	m.wave_plan_for = -1
	await key(KEY_SPACE)
	var t := 0
	while m.total_hits < 150 and t < 3000:
		m._physics_process(1.0 / 30.0)
		t += 1
	print("бой: волна %d, состояние %d, тиков %d, ударов по пехоте %d, зомби %d" % [m.wave_number, m.wave_state, t, m.total_hits, m.zombie_alive])
	await step(2)
	paused = true
	await shot(dir, "battle", m._front_centre(0), Vector2(100, 50), 5)
	await shot(dir, "wide", m.squad_pos[0], Vector2(240, 150), 2)
	paused = false
	await key(KEY_F5)
	paused = true
	await shot(dir, "f5_off", m._front_centre(0), Vector2(100, 50), 5)
	quit()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		run_smoke.call_deferred()
	elif args[0] == "time":
		run_time.call_deferred(args[1])
	else:
		run_shots.call_deferred(args[1])
