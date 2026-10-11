extends SceneTree
# Smoke v37, этап 1 (спрайты из JSON, лучники, отдача), со сценой. Режимы:
#   (без аргументов) — атлас и шейдер, (в) буфер пехоты против предыдущего коммита, (г) лучники в буфере, (з) F1-F5 и пауза;
#   bad <main.gd> <missing|format|nofield> — (е) лист лучника не загрузился / не подошёл / нет поля sprite.
# Ошибки и предупреждения движка — в stderr запуска.
const OLD := "res://bench/main_v37_before.gd"
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

func mm_node(x: Node2D) -> MultiMeshInstance2D:
	for ch in x.get_children():
		if ch is MultiMeshInstance2D:
			return ch
	return null

func cells(x: Node2D) -> Dictionary:
	var d := {}
	for i in x.count:
		var c := int(x.buf[i * 16 + 12])
		d[c] = d.get(c, 0) + 1
	return d

# Ошибки буфера у юнитов из списка: ячейка, базис, цвет, альфа против массивов симуляции.
func buf_errors(ids: Array, sprites: bool) -> int:
	var bad := 0
	var b: PackedFloat32Array = m.buf
	for i in ids:
		var o: int = i * 16
		var ut: int = m.unit_type[i]
		var is_sprite: bool = sprites and m.type_sprite_frames[ut] > 0 and m.unit_squad[i] >= 0
		var want_cell: int = m.type_sprite_base[ut] + m._unit_frame(i) if is_sprite else m.cell_white
		var want_basis := [m.UNIT_QUAD, 0.0, 0.0, m.UNIT_QUAD]
		var want_col := Color.WHITE
		if is_sprite:
			var d: int = m.unit_dir[i] * 4
			want_basis = [m.DIR_BASIS[d], m.DIR_BASIS[d + 1], m.DIR_BASIS[d + 2], m.DIR_BASIS[d + 3]]
		elif m.color_mode == 0:
			want_col = m.type_color[ut]
		var ok: bool = m.color_mode != 0 or (is_equal_approx(b[o + 8], want_col.r) and is_equal_approx(b[o + 9], want_col.g) and is_equal_approx(b[o + 10], want_col.b))
		var basis := [b[o], b[o + 1], b[o + 4], b[o + 5]]
		for q in 4:
			if not is_equal_approx(basis[q], want_basis[q]):
				ok = false
		if int(b[o + 12]) != want_cell or not ok or b[o + 11] != 1.0:
			bad += 1
	return bad

func run_smoke() -> void:
	# два узла рядом: предыдущий коммит и рабочий main; тики и _process вручную, чтобы шли одинаково
	var old: Node2D = load(OLD).new()
	m = load("res://scripts/main.gd").new()
	for x in [old, m]:
		x.spawn_seed = 4
		x.record_path = "user://record_bench.json"
		root.add_child(x)
		x.set_physics_process(false)
		x.set_process(false)
	await step(4)
	var node := mm_node(m)
	var img: Image = node.texture.get_image()
	var inf: int = m.infantry_type
	var arch: int = m.archer_type
	var total_frames := 0
	for t in m.type_sprite_frames.size():
		total_frames += m.type_sprite_frames[t]
	var old_img: Image = mm_node(old).texture.get_image()
	var inf_same := img.get_region(Rect2i(0, 0, 48, 16)).get_data() == old_img.get_region(Rect2i(0, 0, 48, 16)).get_data()
	var bow: Image = (load("res://art/bowman.png") as Texture2D).get_image()
	bow.convert(Image.FORMAT_RGBA8)
	var bow_same := img.get_region(Rect2i(16 * m.type_sprite_base[arch], 0, 16, 16)).get_data() == bow.get_data()
	check("атлас: пехота 3 кадра с ячейки 0, лучник 1 кадр с ячейки 3, белая ячейка 4, всего 5; шейдеру передано число ячеек",
		m.type_sprite_frames[inf] == 3 and m.type_sprite_base[inf] == 0 and m.type_sprite_frames[arch] == 1 and m.type_sprite_base[arch] == 3
		and m.cell_white == 4 and m.atlas_cells == 5 and total_frames == 4 and img.get_size() == Vector2i(80, 16) and not img.has_mipmaps()
		and img.get_pixel(64, 0) == Color.WHITE and img.get_pixel(79, 15) == Color.WHITE and node.material.get_shader_parameter("cells") == 5.0
		and node.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "атлас %s, cells %s" % [img.get_size(), node.material.get_shader_parameter("cells")])
	check("атлас: кадры пехоты те же пиксели, что в предыдущем коммите; кадр лучника = bowman.png", inf_same and bow_same)
	# бой: волна 6, 12 с
	for x in [old, m]:
		x.wave_number = 5
		x.wave_plan_for = -1
		x._start_wave()
	var inf_bad := 0
	var inf_seen := 0
	var sq_bad := 0
	var arch_bad := 0
	var recoil_bad := 0
	var recoil_max := 0.0
	var inf_cells := {}
	var arch_cells := {}
	var sim_bad := 0
	for t in 360:
		old._physics_process(1.0 / 30.0)
		m._physics_process(1.0 / 30.0)
		if old.count != m.count or old.pos != m.pos:
			sim_bad += 1
		if t % 3 != 0:
			continue
		for x in [old, m]:
			x.prev_pos = x.pos.duplicate()   # без интерполяции: позиция в буфере = pos + сдвиги
			x._process(0.0)
		var checked := 0
		for i in m.count:
			var o: int = i * 16
			var a: PackedFloat32Array = old.buf
			var b: PackedFloat32Array = m.buf
			var ut: int = m.unit_type[i]
			if ut == inf and m.unit_squad[i] >= 0:
				if checked < 100:
					# (в) пехота: весь инстанс (трансформ, цвет, custom) побитно как в предыдущем коммите
					checked += 1
					inf_seen += 1
					inf_cells[int(b[o + 12])] = inf_cells.get(int(b[o + 12]), 0) + 1
					if a.slice(o, o + 16) != b.slice(o, o + 16):
						inf_bad += 1
			elif ut == arch and m.unit_squad[i] >= 0:
				arch_cells[int(b[o + 12])] = arch_cells.get(int(b[o + 12]), 0) + 1
				var off: Vector2 = Vector2(b[o + 3], b[o + 7]) - m.pos[i] - m.unit_render_off[i]
				recoil_max = maxf(recoil_max, off.length())
				if off.distance_to(m._recoil_offset(i)) > 0.001:
					recoil_bad += 1
				if int(b[o + 12]) != m.type_sprite_base[arch] or [b[o + 8], b[o + 9], b[o + 10]] != [1.0, 1.0, 1.0]:
					arch_bad += 1
			else:
				# квадраты: всё как раньше, кроме номера белой ячейки (3 -> 4)
				if a.slice(o, o + 12) != b.slice(o, o + 12) or int(a[o + 12]) != 3 or int(b[o + 12]) != m.cell_white:
					sq_bad += 1
	check("симуляция двух узлов совпадает на 360 тиках", sim_bad == 0)
	check("(в) пехота: буфер 100 юнитов × 120 кадров побитно как в предыдущем коммите (трансформ, цвет, custom.x)", inf_bad == 0 and inf_seen >= 100 * 100 and inf_cells.size() == 3,
		"сравнений %d, расхождений %d, ячейки %s" % [inf_seen, inf_bad, inf_cells])
	check("(в) квадраты (зомби): всё как раньше, кроме белой ячейки 3 -> 4", sq_bad == 0)
	check("(г) лучники: спрайт, цвет белый, кадр всегда 0 (ячейка %d) при любых состояниях" % m.type_sprite_base[arch], arch_bad == 0 and arch_cells.size() == 1, "ячейки %s" % [arch_cells])
	check("(г) отдача в буфере = _recoil_offset, максимум %.2f px" % m.type_recoil[arch], recoil_bad == 0 and absf(recoil_max - m.type_recoil[arch]) < 0.01, "максимум %.4f, ошибок %d" % [recoil_max, recoil_bad])
	old.queue_free()
	await step(2)
	# (з) клавиши и пауза на рабочем узле
	m.set_process(true)
	current_scene = m
	await step(3)
	var ids := range(m.count)
	check("(з) F1: буфер без ошибок у всех %d юнитов" % m.count, buf_errors(ids, true) == 0 and cells(m).size() >= 3, "ячейки %s" % [cells(m)])
	await key(KEY_F5)
	check("(з) F5: спрайты выключены у всех типов — у всех белая ячейка и квадрат", not m.sprites_on and cells(m).keys() == [m.cell_white] and buf_errors(ids, false) == 0)
	await key(KEY_F5)
	check("(з) F5 ещё раз: спрайты включены", m.sprites_on and buf_errors(ids, true) == 0 and cells(m).size() >= 3)
	for k in [KEY_F2, KEY_F3, KEY_F4]:
		await key(k)
		check("(з) F%d: все юниты цветными квадратами" % (k - KEY_F1 + 1), m.color_mode == k - KEY_F1 and cells(m).keys() == [m.cell_white] and buf_errors(ids, false) == 0)
	await key(KEY_F1)
	check("(з) F1: снова спрайты", m.color_mode == 0 and buf_errors(ids, true) == 0)
	m.set_physics_process(true)
	# дождаться кадра, где у кого-то из лучников идёт отдача, и встать на паузу
	var tick_lim: int = m.tick_counter + 900
	var recoiling := false
	while not recoiling and m.tick_counter < tick_lim:
		await process_frame
		for i in m.count:
			if m.unit_type[i] == arch and m.unit_anim_t[i] > 0.0:
				recoiling = true
				break
	paused = true
	await step(2)
	var buf0: PackedFloat32Array = m.buf.duplicate()
	var anim0: PackedFloat32Array = m.unit_anim_t.duplicate()
	var shot0: PackedFloat32Array = m.unit_shot_t.duplicate()
	var tick0: int = m.tick_counter
	await step(30)
	var held: bool = m.buf == buf0 and m.unit_anim_t == anim0 and m.unit_shot_t == shot0 and m.tick_counter == tick0
	paused = false
	var t1: int = m.tick_counter
	while m.tick_counter < t1 + 10:
		await process_frame
	check("(з) пауза во время отдачи: тики, таймеры, буфер (и смещение отдачи) стоят; после снятия идут", recoiling and held and m.buf != buf0)
	print("SMOKE: провалов %d" % fails)
	quit()

func run_bad(path: String, kind: String) -> void:
	m = load(path).new()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	await step(4)
	if kind == "nofield":
		check("(е) нет поля sprite у типа: типы не загружены, симуляция остановлена (ошибка загрузчика в stderr)", m.type_id.is_empty() and not m.is_physics_processing())
	else:
		var arch: int = m.archer_type
		m.set_physics_process(false)
		await step(3)
		var arch_cells := {}
		var inf_cells := {}
		for i in m.count:
			var c := int(m.buf[i * 16 + 12])
			if m.unit_type[i] == arch:
				arch_cells[c] = true
			else:
				inf_cells[c] = true
		check("(е) лист лучника %s: лучники квадратами цвета типа (белая ячейка %d), пехота спрайтами (ячейка 0), атлас из %d ячеек" % [m.type_sprite[arch], m.cell_white, m.atlas_cells],
			m.type_sprite_frames[arch] == 0 and m.cell_white == 3 and m.atlas_cells == 4 and arch_cells.keys() == [3] and inf_cells.keys() == [0]
			and is_equal_approx(m.buf[300 * 16 + 8], m.type_color[arch].r) and m.buf[300 * 16] == m.UNIT_QUAD)
	print("SMOKE: провалов %d" % fails)
	quit()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		run_smoke.call_deferred()
	else:
		run_bad.call_deferred(args[1], args[2])
