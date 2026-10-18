extends SceneTree
# Тесты v40, этап 2 (выбор мышью, рамка, ПКМ-приказы, несколько отрядов). Сцена в дереве (мышь переводится в мир
# через make_input_local), физика вручную. Аргументы: [select | box | rmb | multi | cmds | pause | freed | determ | regress] — по умолчанию все.
# События интерфейса и отрисовка — bench/smoke_v40.gd, время — bench/time_v40.gd.
const OLD := "res://bench/main_v40_before.gd"
const NEW := "res://scripts/main.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func scene(rng_seed := 1) -> Node2D:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	m.spawn_seed = rng_seed
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	m.set_physics_process(false)
	await process_frame
	return m

func drop(m: Node2D) -> void:
	m.queue_free()
	await process_frame

func key(m: Node2D, code: Key, shift := false, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	m._unhandled_input(e)

func mouse(m: Node2D, btn: MouseButton, w: Vector2, pressed: bool, shift := false, dbl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.shift_pressed = shift
	e.double_click = dbl
	e.position = m.get_global_transform_with_canvas() * w
	m._unhandled_input(e)

func motion(m: Node2D, w: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = m.get_global_transform_with_canvas() * w
	m._unhandled_input(e)

# Точка мира после пути «мир -> экран -> мир», как её видит игра в _unhandled_input (make_input_local).
func through_screen(m: Node2D, w: Vector2) -> Vector2:
	var e := InputEventMouseButton.new()
	e.position = m.get_global_transform_with_canvas() * w
	return (m.make_input_local(e) as InputEventMouseButton).position

func lclick(m: Node2D, w: Vector2, shift := false, dbl := false) -> void:
	mouse(m, MOUSE_BUTTON_LEFT, w, true, shift, dbl)
	mouse(m, MOUSE_BUTTON_LEFT, w, false, shift)

func ldrag(m: Node2D, a: Vector2, b: Vector2, shift := false) -> void:
	mouse(m, MOUSE_BUTTON_LEFT, a, true, shift)
	motion(m, b)
	mouse(m, MOUSE_BUTTON_LEFT, b, false, shift)

func rclick(m: Node2D, w: Vector2) -> void:
	mouse(m, MOUSE_BUTTON_RIGHT, w, true)
	mouse(m, MOUSE_BUTTON_RIGHT, w, false)

func rdrag(m: Node2D, a: Vector2, b: Vector2, flip := false) -> void:
	mouse(m, MOUSE_BUTTON_RIGHT, a, true)
	motion(m, b)
	if flip:
		key(m, KEY_F)
	mouse(m, MOUSE_BUTTON_RIGHT, b, false)

func teleport(m: Node2D) -> void:
	for i in m.count:
		if m.unit_squad[i] >= 0:
			m.pos[i] = m.squad_pos[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])
			m.prev_pos[i] = m.pos[i]

func place(m: Node2D, s: int, centre: Vector2, length: float, ang := 0.0) -> void:
	var h := Vector2.from_angle(ang) * length * 0.5
	m._place_formation(s, centre - h, centre + h)

# Армия: пехота 0 (150), 2 (75), 3 (75) в ряд вверху поля лицом вверх, лучники 1 (100) на старте.
func army(m: Node2D) -> void:
	m.split_frac = 0.5
	m.split_mode = 0
	key(m, KEY_1)
	key(m, KEY_G)
	key(m, KEY_G)
	place(m, 0, Vector2(500, 250), 200.0)
	place(m, 2, Vector2(1000, 250), 120.0)
	place(m, 3, Vector2(1500, 250), 120.0)
	teleport(m)
	key(m, KEY_1)

func units(m: Node2D, s: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in m.count:
		if m.unit_squad[i] == s:
			out.append(i)
	return out

func mask_of(list: Array) -> int:
	var k := 0
	for s in list:
		k |= 1 << s
	return k

func sel(m: Node2D, list: Array) -> void:
	m._clear_sel()
	for s in list:
		m._toggle_sel(s)

func integrity(m: Node2D) -> String:
	var n := PackedInt32Array()
	n.resize(m.SQUAD_MAX)
	var seen := {}
	for i in m.count:
		var s: int = m.unit_squad[i]
		if s < -1 or s >= m.SQUAD_MAX:
			return "юнит %d: отряд %d" % [i, s]
		if s < 0:
			continue
		if m.squad_used[s] == 0:
			return "юнит %d в свободном отряде %d" % [i, s]
		n[s] += 1
		var k: int = s * 1000000 + m.unit_slot_idx[i]
		if seen.has(k):
			return "отряд %d: слот %d занят дважды" % [s, m.unit_slot_idx[i]]
		seen[k] = true
	for s in m.SQUAD_MAX:
		if m.squad_n[s] != n[s]:
			return "отряд %d: squad_n %d, юнитов %d" % [s, m.squad_n[s], n[s]]
	return sel_error(m)

# Выбор: только занятые отряды игрока с живыми (в передышке — и пустые), главный — из выбранных или -1.
func sel_error(m: Node2D) -> String:
	for s in m.SQUAD_MAX:
		if (m.sel_mask >> s) & 1 == 1 and (m.squad_used[s] == 0 or (m.squad_n[s] == 0 and m.wave_state != m.WS_RESPITE)):
			return "в выборе несуществующий отряд %d" % s
	if m.sel_mask >> m.SQUAD_MAX != 0:
		return "лишние биты выбора"
	if m.sel_mask == 0 and m.sel_primary != -1:
		return "выбор пуст, главный %d" % m.sel_primary
	if m.sel_mask != 0 and (m.sel_primary < 0 or (m.sel_mask >> m.sel_primary) & 1 == 0):
		return "главный %d не из выбранных" % m.sel_primary
	return ""

func slots_full(m: Node2D, s: int) -> bool:
	var n: int = m.squad_n[s]
	var w: int = m.squad_width[s]
	var have := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			have[m.unit_slot_idx[i]] = true
	if have.size() != n:
		return false
	for col in w:
		for row in n / w + (1 if col < n % w else 0):
			if not have.has(row * w + col):
				return false
	return true

func kill_squad(m: Node2D, s: int) -> void:
	for i in m.count:
		if m.unit_squad[i] == s:
			m.hp[i] = 0.0

func start_battle(m: Node2D, w: int) -> void:
	m.wave_number = w - 1
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()

func pos_hash(m: Node2D) -> int:
	return hash([m.count, m.tick_counter, m.pos.slice(0, m.count), m.hp.slice(0, m.count), m.vel.slice(0, m.count)])

# (б) выбор кликом и клавишами.
func test_select() -> void:
	var m: Node2D = await scene()
	army(m)
	var s_px: float = m.SLOT_SPACING
	check("старт: выбран отряд 1 (sel_mask = 1, главный 0)", m.sel_mask == 1 and m.sel_primary == 0)
	var u := units(m, 2)
	lclick(m, m.pos[u[10]])
	var on_unit: bool = m.sel_mask == 4 and m.sel_primary == 2
	lclick(m, m.pos[units(m, 0)[0]])
	lclick(m, m.squad_pos[2] + Vector2(s_px * 0.5, s_px * 0.5))   # между четырьмя соседними слотами
	var on_gap: bool = m.sel_mask == 4
	# снаружи блока: левее крайней колонки (лицо вверх: колонки вдоль x)
	var left := INF
	for i in u:
		left = minf(left, m.pos[i].x)
	var edge := Vector2(left, m.squad_pos[2].y)
	lclick(m, m.pos[units(m, 0)[0]])
	lclick(m, edge - Vector2(s_px * 1.2, 0.0))
	var near_ok: bool = m.sel_mask == 4 and m.sel_primary == 2
	lclick(m, edge - Vector2(s_px * 3.0, 0.0))
	check("(б) ЛКМ: клик по юниту, на зазоре между юнитами и рядом с блоком (1.2 шага, PICK_RADIUS %.0f px) выбирает отряд; дальше (3 шага) — выбор пуст, главный -1" % m.PICK_RADIUS,
		on_unit and on_gap and near_ok and m.sel_mask == 0 and m.sel_primary == -1)
	# Shift
	lclick(m, m.squad_pos[0])
	lclick(m, m.squad_pos[2], true)
	var add_ok: bool = m.sel_mask == 5 and m.sel_primary == 2
	lclick(m, m.squad_pos[2], true)
	var off_ok: bool = m.sel_mask == 1 and m.sel_primary == 0
	lclick(m, Vector2(200, 600), true)
	check("(б) Shift+клик добавляет отряд и убирает его; Shift+клик в пустоту выбор не трогает", add_ok and off_ok and m.sel_mask == 1)
	# двойной клик
	lclick(m, m.squad_pos[3])
	lclick(m, m.squad_pos[3], false, true)
	var dbl_ok: bool = m.sel_mask == mask_of([0, 2, 3]) and m.sel_primary == 3
	lclick(m, m.squad_pos[1], true)
	lclick(m, m.squad_pos[1], true, true)
	check("(б) двойной клик выбирает все отряды типа (пехота 1, 3, 4; главный — тот, по которому кликнули); Shift+двойной по лучникам добавляет их",
		dbl_ok and m.sel_mask == mask_of([0, 1, 2, 3]) and m.sel_primary == 1, "маска %d" % m.sel_mask)
	lclick(m, Vector2(200, 600))
	var cleared: bool = m.sel_mask == 0
	key(m, KEY_A, false, true)
	var all_ok: bool = m.sel_mask == mask_of([0, 1, 2, 3]) and m.sel_primary >= 0
	key(m, KEY_2)
	var k2: bool = m.sel_mask == 2 and m.sel_primary == 1
	key(m, KEY_3, true)
	var k3: bool = m.sel_mask == 6 and m.sel_primary == 2
	key(m, KEY_7)
	key(m, KEY_7, true)
	key(m, KEY_3, true)
	check("(б) клик в пустоту очищает; Ctrl+A выбирает все отряды; 1-8 выбирает, Shift+цифра добавляет и убирает, свободный индекс игнорируется",
		cleared and all_ok and k2 and k3 and m.sel_mask == 2 and m.sel_primary == 1 and sel_error(m) == "")
	# перекрывающиеся блоки: отряд 4 наезжает на отряд 3
	m.squad_pos[3] = m.squad_pos[2] + Vector2(s_px * 6.5, s_px * 2.5)
	m.squad_target[3] = m.squad_pos[3]
	teleport(m)
	var boxes: Array = m._squad_boxes()
	var b2: PackedVector2Array = m._live_block(2, boxes, m.squad_pos[2])
	var b3: PackedVector2Array = m._live_block(3, boxes, m.squad_pos[3])
	var both := 0
	var wrong := 0
	var got := {2: 0, 3: 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for q in 400:
		var p: Vector2 = m.squad_pos[2] + Vector2(rng.randf_range(-20, 150), rng.randf_range(-60, 90))
		if not (Geometry2D.is_point_in_polygon(p, b2) and Geometry2D.is_point_in_polygon(p, b3)):
			continue
		both += 1
		var best := -1
		var best_d := INF
		for i in m.count:
			if m.unit_squad[i] in [2, 3] and m.pos[i].distance_squared_to(p) < best_d:
				best_d = m.pos[i].distance_squared_to(p)
				best = m.unit_squad[i]
		lclick(m, p)
		got[m.sel_primary] = got.get(m.sel_primary, 0) + 1
		if m.sel_primary != best or m.sel_mask != 1 << best:
			wrong += 1
	check("(б) точка в пересечении двух блоков (%d точек): выбирается отряд, чей юнит ближе" % both, both > 20 and wrong == 0 and got[2] > 0 and got[3] > 0, "отряд 3: %d, отряд 4: %d" % [got[2], got[3]])
	# зомби не выбираются
	for q in 30:
		m._spawn_zombie(Vector2(300 + q % 6 * s_px, 600 + q / 6 * s_px), m.zombie_type)
	key(m, KEY_1)
	lclick(m, Vector2(300 + s_px, 600 + s_px))
	var z_click: bool = m.sel_mask == 0
	key(m, KEY_1)
	ldrag(m, Vector2(250, 550), Vector2(450, 700))
	check("(б) зомби не выбираются ни кликом, ни рамкой (выбор очищается, как при клике в пустоту)", z_click and m.sel_mask == 0 and m._pick_squad(Vector2(300, 600)) == -1)
	await drop(m)

# (в) рамка.
func test_box() -> void:
	var m: Node2D = await scene()
	army(m)
	var s_px: float = m.SLOT_SPACING
	ldrag(m, Vector2(350, 200), Vector2(650, 400))
	var one: bool = m.sel_mask == 1 and m.sel_primary == 0
	ldrag(m, Vector2(1650, 400), Vector2(850, 200))   # справа налево и снизу вверх
	var two: bool = m.sel_mask == mask_of([2, 3]) and m.sel_primary == 2
	check("(в) рамка вокруг одного отряда из трёх и вокруг двух (в любую сторону)", one and two, "маска %d, главный %d" % [m.sel_mask, m.sel_primary])
	# доля юнитов: отряд 1 (150 юнитов, лицо вверх), рамка накрывает левые колонки целиком; центр отряда вне рамки
	var u := units(m, 0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in u:
		lo = lo.min(m.pos[i])
		hi = hi.max(m.pos[i])
	var res := PackedStringArray()
	var ok := true
	for cols in [3, 5]:
		var r := Rect2(lo - Vector2(40, 40), Vector2(40.0 + (cols - 0.5) * s_px, hi.y - lo.y + 80.0))
		var inside := 0
		for i in u:
			if r.has_point(m.pos[i]):
				inside += 1
		var share := inside / float(u.size())
		key(m, KEY_2)
		ldrag(m, r.position, r.end)
		var picked: bool = m.sel_mask == 1
		res.append("%d колонок: в рамке %.0f%% — %s" % [cols, share * 100.0, "выбран" if picked else "не выбран"])
		ok = ok and not r.has_point(m.squad_pos[0]) and picked == (share >= m.BOX_SELECT_FRAC) and (share < 0.22 if cols == 3 else share > 0.28) and (picked or m.sel_mask == 0)
	check("(в) рамка без центра отряда: около 20%% юнитов — не выбирает (и очищает выбор), около 30%% — выбирает (порог %.2f)" % m.BOX_SELECT_FRAC, ok, "; ".join(res))
	key(m, KEY_2)
	ldrag(m, m.squad_pos[0] - Vector2(15, 15), m.squad_pos[0] + Vector2(15, 15))
	var centre_ok: bool = m.sel_mask == 1
	ldrag(m, Vector2(850, 200), Vector2(1150, 400), true)
	var add_ok: bool = m.sel_mask == mask_of([0, 2]) and m.sel_primary == 0
	ldrag(m, Vector2(100, 500), Vector2(300, 700), true)
	check("(в) центр отряда в маленькой рамке — выбирает; Shift+рамка добавляет (главный прежний), пустая Shift+рамка выбор не трогает",
		centre_ok and add_ok and m.sel_mask == mask_of([0, 2]))
	mouse(m, MOUSE_BUTTON_LEFT, Vector2(1350, 200), true)
	motion(m, Vector2(1650, 400))
	var active: bool = m.box_active
	key(m, KEY_ESCAPE)
	var esc_off: bool = not m.box_active
	mouse(m, MOUSE_BUTTON_LEFT, Vector2(1650, 400), false)
	var esc_ok: bool = m.sel_mask == mask_of([0, 2])
	var t0: PackedVector2Array = m.squad_target.duplicate()
	mouse(m, MOUSE_BUTTON_LEFT, Vector2(1350, 200), true)
	motion(m, Vector2(1650, 400))
	mouse(m, MOUSE_BUTTON_RIGHT, Vector2(1650, 400), true)
	var rmb_off: bool = not m.box_active and not m.drag_active
	mouse(m, MOUSE_BUTTON_RIGHT, Vector2(1650, 400), false)
	mouse(m, MOUSE_BUTTON_LEFT, Vector2(1650, 400), false)
	check("(в) Esc и ПКМ во время рамки отменяют её: выбор тот же, приказа нет", active and esc_off and esc_ok and rmb_off and m.sel_mask == mask_of([0, 2]) and m.squad_target == t0)
	mouse(m, MOUSE_BUTTON_RIGHT, Vector2(600, 500), true)
	motion(m, Vector2(900, 500))
	mouse(m, MOUSE_BUTTON_LEFT, Vector2(900, 500), true)
	var cancelled: bool = not m.drag_active and not m.box_active
	mouse(m, MOUSE_BUTTON_LEFT, Vector2(900, 500), false)
	mouse(m, MOUSE_BUTTON_RIGHT, Vector2(900, 500), false)
	check("(в) ЛКМ во время ПКМ-протяжки отменяет её, рамка не начинается: выбор и цели те же", cancelled and m.sel_mask == mask_of([0, 2]) and m.squad_target == t0)
	await drop(m)

# (г) ПКМ-клик.
func test_rmb() -> void:
	var m: Node2D = await scene()
	army(m)
	var old: Node2D = load(OLD).new()
	old.spawn_seed = 1
	old.record_path = "user://record_bench.json"
	old._setup_data()
	army(old)
	var same_start: bool = old.squad_pos == m.squad_pos and old.pos.slice(0, old.count) == m.pos.slice(0, m.count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var diff := 0
	var refused := 0
	for q in 20:
		var s: int = [0, 2, 3, 1][q % 4]
		var p := Vector2(rng.randi_range(100, 2100), rng.randi_range(60, 700))
		if q % 3 == 0:
			p = (m.squad_pos[[2, 3, 1, 0][q % 4]] + Vector2(rng.randi_range(-30, 30), rng.randi_range(-30, 30))).round()   # на чужой блок: отказ
		key(m, KEY_1 + s)
		key(old, KEY_1 + s)
		m.hud_msg = ""
		old.hud_msg = ""
		rclick(m, p)
		old._cmd_move(s, through_screen(m, p))   # клик идёт через экран: с зумом камеры точка мира чуть сдвигается округлением
		if m.hud_msg != "":
			refused += 1
		if m.squad_target != old.squad_target or m.hud_msg != old.hud_msg or m.squad_pos != old.squad_pos:
			diff += 1
	check("(г) один отряд: ПКМ-клик в 20 точках даёт те же цели и те же отказы, что клик в версии этапа 1", same_start and diff == 0 and refused >= 3 and refused <= 17, "отказов %d из 20" % refused)
	old.free()
	await drop(m)
	m = await scene()
	army(m)
	var bad := PackedStringArray()
	for list in [[0, 2], [0, 2, 3], [2, 3, 1]]:
		sel(m, list)
		var c := Vector2.ZERO
		for s in list:
			c += m.squad_pos[s]
		c /= list.size()
		var p := c + Vector2(40, -60)
		var t0: PackedVector2Array = m.squad_target.duplicate()
		m.hud_msg = ""
		rclick(m, p)
		var mean := Vector2.ZERO
		for s in list:
			mean += m.squad_target[s]
			if (m.squad_target[s] - m.squad_target[list[0]]).distance_to(m.squad_pos[s] - m.squad_pos[list[0]]) > 0.01:
				bad.append("%s: смещения" % [list])
		if (mean / list.size()).distance_to(p) > 0.01 or m.hud_msg != "":
			bad.append("%s: середина %s вместо %s; %s" % [list, mean / list.size(), p, m.hud_msg])
		for s in m.SQUAD_MAX:
			if not s in list and m.squad_target[s] != t0[s]:
				bad.append("%s: сдвинут невыбранный %d" % [list, s])
		m.squad_target = t0.duplicate()
	check("(г) два-три отряда: середина якорей идёт в точку клика, взаимные смещения целей те же (допуск 0.01 px), невыбранные на месте", bad.is_empty(), "; ".join(bad))
	# край поля: набор сдвигается целиком
	sel(m, [0, 2, 3])
	var t_before: PackedVector2Array = m.squad_target.duplicate()
	rclick(m, Vector2(1000, 20))
	var boxes: Array = m._squad_boxes()
	var in_field := true
	var rel_ok := true
	for s in [0, 2, 3]:
		for corner: Vector2 in m._live_block(s, boxes, m.squad_target[s]):
			in_field = in_field and corner.y >= m.SLOT_SPACING * -0.5 - 0.01 and corner.x >= m.SLOT_SPACING * -0.5 - 0.01
		rel_ok = rel_ok and (m.squad_target[s] - m.squad_target[0]).distance_to(m.squad_pos[s] - m.squad_pos[0]) <= 0.01
	var top := INF
	for i in m.count:
		if m.unit_squad[i] in [0, 2, 3]:
			top = minf(top, (m.squad_target[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])).y)
	check("(г) клик у края поля: набор сдвинут целиком на минимум (верхний слот на y = %.2f), смещения те же" % top, in_field and rel_ok and absf(top) <= 0.02 and m.squad_target != t_before)
	m.squad_target = t_before.duplicate()
	# всё или ничего: блок отряда 4 попадает на невыбранных лучников
	sel(m, [2, 3])
	m.hud_msg = ""
	rclick(m, m.squad_pos[1] - (m.squad_pos[3] - m.squad_pos[2]) * 0.5)
	var refused_all: bool = m.squad_target == t_before and m.hud_msg == "Блок пересекается с отрядом 2"
	# между выбранными проверки нет: тот же клик с лучниками в наборе проходит
	sel(m, [2, 3, 1])
	m.hud_msg = ""
	rclick(m, (m.squad_pos[1] + m.squad_pos[2] + m.squad_pos[3]) / 3.0 + Vector2(-60, -30))
	var dbg := " [%s] %s %s" % [m.hud_msg, m.squad_target[1] - t_before[1], m.squad_target[2] - t_before[2]]
	var moved_all: bool = m.hud_msg == "" and m.squad_target[1] != t_before[1] and m.squad_target[2] != t_before[2]
	m.squad_target = t_before.duplicate()
	m._clear_sel()
	rclick(m, Vector2(700, 500))
	mouse(m, MOUSE_BUTTON_RIGHT, Vector2(600, 500), true)
	var no_drag: bool = not m.drag_active
	motion(m, Vector2(900, 500))
	mouse(m, MOUSE_BUTTON_RIGHT, Vector2(900, 500), false)
	check("(г) всё или ничего: блок одного из выбранных на невыбранном отряде — отказ всем с сообщением; ничего не выбрано — ПКМ игнорируется",
		refused_all and moved_all and no_drag and m.squad_target == t_before and m.hud_msg == "", "%s %s %s" % [refused_all, moved_all, no_drag] + dbg)
	await drop(m)

# Концы переднего ряда отряда в мире, по возрастанию проекции на dir.
func front_ends(m: Node2D, s: int, dir: Vector2) -> Array:
	var w: int = m.squad_width[s]
	var a: Vector2 = m.squad_pos[s] + (m._slot_vector(0, w) - m.squad_center_off[s]).rotated(m.squad_angle[s])
	var b: Vector2 = m.squad_pos[s] + (m._slot_vector(w - 1, w) - m.squad_center_off[s]).rotated(m.squad_angle[s])
	return [a, b] if a.dot(dir) <= b.dot(dir) else [b, a]

# (д) расстановка группы.
func test_multi() -> void:
	var m: Node2D = await scene()
	army(m)
	var s_px: float = m.SLOT_SPACING
	var lim := Vector2(m.FIELD.x, m.WALL_Y - 12.0)
	var bad := PackedStringArray()
	var placed := 0
	var refused := 0
	var adjusted := 0
	var cases := 0
	for list: Array in [[0, 2], [0, 2, 3], [0, 1, 2, 3]]:
		for length: float in [60.0, 200.0, 700.0]:
			for a8 in 8:
				for flip: bool in [false, true]:
					cases += 1
					# невыбранные — в углы, выбранные — в исходные места
					place(m, 3, Vector2(2000, 80), 120.0)
					place(m, 1, Vector2(2000, 650), 300.0)
					place(m, 0, Vector2(500, 250), 200.0)
					place(m, 2, Vector2(1000, 250), 120.0)
					if 3 in list:
						place(m, 3, Vector2(1500, 250), 120.0)
					if 1 in list:
						place(m, 1, Vector2(1300, 500), 300.0)
					teleport(m)
					sel(m, list)
					var dir := Vector2.from_angle(a8 * TAU / 8.0 + 0.1)
					var a := Vector2(1000, 365) - dir * length * 0.5
					var b := a + dir * length
					var face := Vector2(dir.y, -dir.x) * (-1.0 if flip else 1.0)
					var order := list.duplicate()
					order.sort_custom(func(x: int, y: int) -> bool:
						var px: float = m.squad_pos[x].dot(dir)
						var py: float = m.squad_pos[y].dot(dir)
						return px < py if px != py else x < y)
					var total := 0
					var min_len := s_px * (list.size() - 1)
					for s: int in list:
						total += m.squad_n[s]
						min_len += (ceili(m.squad_n[s] / float(m.ROWS_MAX)) - 1) * s_px
					var share := maxf(length, min_len) - s_px * (list.size() - 1)
					var g: Dictionary = m._multi_geometry(PackedInt32Array(list), a, b, flip)
					var before: PackedVector2Array = m.squad_pos.duplicate()
					m.hud_msg = ""
					rdrag(m, a, b, flip)
					var tag := "%s L=%d угол %d%s" % [list, length, a8 * 45, " F" if flip else ""]
					if m.squad_pos == before:
						refused += 1
						if m.hud_msg == "" or (g.fits and g.overlap < 0):
							bad.append(tag + ": отказ без причины")
						continue
					placed += 1
					if g.adjusted:
						adjusted += 1
					var prev_end := Vector2.ZERO
					for q in order.size():
						var s: int = order[q]
						var ends := front_ends(m, s, dir)
						var n: int = m.squad_n[s]
						var w: int = m.squad_width[s]
						if q == 0:
							var off: Vector2 = ends[0] - a
							if (not g.adjusted and off.length() > 0.5) or (g.adjusted and (absf(off.cross(face)) > 0.5 or off.length() < 0.5)):
								bad.append(tag + ": A сдвинут на %s" % off)
						else:
							var step: Vector2 = ends[0] - prev_end
							if absf(step.dot(dir) - s_px) > 0.01 or absf(step.cross(dir)) > 0.01:
								bad.append(tag + ": зазор %.2f, поперёк %.2f" % [step.dot(dir), step.cross(dir)])
						prev_end = ends[1]
						var clamped: bool = w == maxi(ceili(n / float(m.ROWS_MAX)), 1) or w == mini(n, m.WIDTH_MAX)
						if absf((w - 1) * s_px - share * n / total) > s_px * 0.5 + 0.01 and not clamped:
							bad.append(tag + ": длина отряда %d = %.0f, доля %.1f" % [s, (w - 1) * s_px, share * n / total])
						if Vector2.from_angle(m.squad_angle[s]).dot(face) <= 0.99:
							bad.append(tag + ": лицо отряда %d" % s)
						if not slots_full(m, s) or m.squad_target[s] != m.squad_pos[s]:
							bad.append(tag + ": слоты отряда %d" % s)
					for i in m.count:
						var sq: int = m.unit_squad[i]
						if sq in list:
							var p: Vector2 = m.squad_pos[sq] + m.unit_slot[i].rotated(m.squad_angle[sq])
							if p.x < -0.01 or p.y < -0.01 or p.x > lim.x + 0.01 or p.y > lim.y + 0.01:
								bad.append(tag + ": слот вне поля %s" % p.round())
								break
					var boxes: Array = m._squad_boxes()
					for x in list.size():
						for y in x:
							var common := 0.0
							for poly in Geometry2D.intersect_polygons(m._live_block(list[x], boxes, m.squad_pos[list[x]]), m._live_block(list[y], boxes, m.squad_pos[list[y]])):
								common += m._poly_area(poly)
							if common > 0.5:
								bad.append(tag + ": блоки %d и %d перекрываются на %.1f px²" % [list[x], list[y], common])
					if integrity(m) != "":
						bad.append(tag + ": " + integrity(m))
	check("(д) расстановка 2, 3, 4 отрядов × линии 60, 200, 700 px × 8 углов × F (%d случаев, поставлено %d, из них сдвинуто целиком %d, отказов %d): A на месте (0.5 px), порядок по проекции, длины по n_i, зазор SLOT_SPACING, перекрытий 0, слоты без дыр, всё в поле и не ниже WALL_Y - 12, лицо общее, F инвертирует" % [cases, placed, adjusted, refused],
		bad.is_empty() and placed >= cases * 3 / 4, "ошибок %d: %s" % [bad.size(), "; ".join(bad.slice(0, 4))])
	# пересечение с невыбранным: отказ
	place(m, 3, Vector2(1900, 80), 120.0)
	place(m, 1, Vector2(1300, 600), 300.0)
	place(m, 0, Vector2(500, 250), 200.0)
	place(m, 2, Vector2(1000, 250), 120.0)
	teleport(m)
	sel(m, [0, 2])
	var before: PackedVector2Array = m.squad_pos.duplicate()
	var angles: PackedFloat32Array = m.squad_angle.duplicate()
	m.hud_msg = ""
	rdrag(m, Vector2(1100, 620), Vector2(1500, 620))
	var over_ok: bool = m.squad_pos == before and m.squad_angle == angles and m.hud_msg == "Блок пересекается с отрядом 2"
	m.hud_msg = ""
	rdrag(m, Vector2(1100, 30), Vector2(1100, 1000))   # вертикальная линия длиннее поля: сдвиг вдоль лица не поможет
	check("(д) линия через невыбранный отряд — отказ с сообщением, все на месте; линия длиннее поля — отказ", over_ok and m.squad_pos == before and m.hud_msg == "Строй не помещается в поле", m.hud_msg)
	# сдвиг целиком: линия у верхнего края лицом вниз (ряды уходят вверх за край)
	var g2: Dictionary = m._multi_geometry(PackedInt32Array([0, 2]), Vector2(900, 20), Vector2(500, 20))
	rdrag(m, Vector2(900, 20), Vector2(500, 20))
	var top := INF
	for i in m.count:
		if m.unit_squad[i] in [0, 2]:
			top = minf(top, (m.squad_pos[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])).y)
	check("(д) группа вылезла за край: сдвинута целиком вдоль лица на минимум (предпросмотр красный, верхний слот на y = %.2f)" % top, g2.adjusted and g2.fits and absf(top) < 0.02 and m.squad_pos != before)
	# один отряд: то же, что _place_formation
	await drop(m)
	m = await scene()
	army(m)
	var m2: Node2D = await scene()
	army(m2)
	var same := true
	for q in 12:
		var a := Vector2(300 + q * 90, 420 + q % 3 * 40)
		var b := a + Vector2.from_angle(q * 0.7) * (40 + q * 45)
		var s: int = [0, 2][q % 2]
		m._place_formation_multi(PackedInt32Array([s]), a, b, q % 4 == 1)
		m2._place_formation(s, a, b, q % 4 == 1)
		same = same and m.squad_pos == m2.squad_pos and m.squad_angle == m2.squad_angle and m.squad_width == m2.squad_width and m.unit_slot.slice(0, m.count) == m2.unit_slot.slice(0, m.count) \
			and m.unit_slot_idx.slice(0, m.count) == m2.unit_slot_idx.slice(0, m.count) and m.squad_user_width == m2.squad_user_width
	check("(д) один отряд: _place_formation_multi даёт ровно то же, что _place_formation (12 линий)", same)
	await drop(m2)
	await drop(m)

# (е) команды набора.
func test_cmds() -> void:
	var m: Node2D = await scene()
	army(m)
	sel(m, [0, 2, 1])
	var bad := PackedStringArray()
	for q in [[KEY_W, m.ORDER_HOLD], [KEY_E, m.ORDER_RETREAT], [KEY_Q, m.ORDER_ATTACK]]:
		key(m, q[0])
		if m.squad_order[0] != q[1] or m.squad_order[2] != q[1] or m.squad_order[1] != q[1] or m.squad_order[3] != (m.ORDER_ATTACK):
			bad.append("приказ %d" % q[1])
	var ang: PackedFloat32Array = m.squad_angle.duplicate()
	var at: PackedVector2Array = m.squad_pos.duplicate()
	key(m, KEY_F)
	for s in [0, 1, 2]:
		if absf(absf(angle_difference(ang[s], m.squad_angle[s])) - PI) > 0.001 or m.squad_pos[s].distance_to(at[s]) > 0.01:
			bad.append("F %d" % s)
	if m.squad_angle[3] != ang[3]:
		bad.append("F тронул невыбранный")
	ang = m.squad_angle.duplicate()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.shift_pressed = true
	wheel.position = Vector2(500, 500)
	m._unhandled_input(wheel)
	for s in [0, 1, 2]:
		if absf(angle_difference(ang[s], m.squad_angle[s]) - m.ROTATE_STEP) > 0.001 or m.squad_pos[s].distance_to(at[s]) > 0.01:
			bad.append("колесо %d" % s)
	if m.squad_angle[3] != ang[3]:
		bad.append("колесо тронуло невыбранный")
	var uw_set: bool = m.squad_user_width[0] > 0 and m.squad_user_width[2] > 0 and m.squad_user_width[3] > 0
	key(m, KEY_T)
	if not uw_set or m.squad_user_width[0] != 0 or m.squad_user_width[2] != 0 or m.squad_user_width[1] != 0 or m.squad_user_width[3] == 0:
		bad.append("T")
	check("(е) Q/W/E, F, Shift+колесо, T действуют на все выбранные отряды (и только на них)", bad.is_empty(), ", ".join(bad))
	# стрелки для набора
	bad.clear()
	var notes := PackedStringArray()
	for side in [m.SIDE_LEFT, m.SIDE_TOP, m.SIDE_RIGHT, -1]:
		place(m, 0, Vector2(500, 250), 200.0)
		place(m, 2, Vector2(1000, 250), 120.0)
		place(m, 3, Vector2(1900, 80), 120.0)
		place(m, 1, Vector2(1900, 650), 300.0)
		teleport(m)
		sel(m, [0, 2])
		m.squad_order[0] = m.ORDER_HOLD
		var post: Array = m._side_post(side)
		var v: Vector2 = post[1]
		var line: float = maxf((m.squad_width[0] - 1) * m.SLOT_SPACING, m.SLOT_SPACING) + maxf((m.squad_width[2] - 1) * m.SLOT_SPACING, m.SLOT_SPACING)
		var d: Vector2 = Vector2(-v.y, v.x) * line
		var g: Dictionary = m._multi_geometry(PackedInt32Array([0, 2]), post[0] - d * 0.5, post[0] + d * 0.5)
		key(m, {m.SIDE_LEFT: KEY_LEFT, m.SIDE_TOP: KEY_UP, m.SIDE_RIGHT: KEY_RIGHT, -1: KEY_DOWN}[side])
		var dir := d.normalized()
		var e0 := front_ends(m, 0, dir)
		var e2 := front_ends(m, 2, dir)
		var lo: Vector2 = e0[0] if e0[0].dot(dir) < e2[0].dot(dir) else e2[0]
		var hi: Vector2 = e0[1] if e0[1].dot(dir) > e2[1].dot(dir) else e2[1]
		var mid := (lo + hi) * 0.5
		var tag := "сторона %d" % side
		if Vector2.from_angle(m.squad_angle[0]).dot(v) <= 0.99 or Vector2.from_angle(m.squad_angle[2]).dot(v) <= 0.99:
			bad.append(tag + ": лицо")
		if m.squad_order[0] != m.ORDER_HOLD or not slots_full(m, 0) or not slots_full(m, 2) or integrity(m) != "":
			bad.append(tag + ": приказ или слоты")
		if absf((mid - post[0]).dot(dir)) > m.SLOT_SPACING or (not g.adjusted and absf((mid - post[0]).dot(v)) > 0.5):
			bad.append(tag + ": середина линии %s, пост %s" % [mid.round(), (post[0] as Vector2).round()])
		if absf((lo - (post[0] - d * 0.5)).dot(dir)) > 0.5:
			bad.append(tag + ": начало линии")
		notes.append("%d: %s%s" % [side, mid.round(), " (сдвиг)" if g.adjusted else ""])
	check("(е) стрелки для двух отрядов: общий пост, одна линия длиной в сумму ширин через _place_formation_multi, лицо к стороне, приказ тот же", bad.is_empty(), "; ".join(bad) + " середины линий: " + ", ".join(notes))
	# деление и слияние
	sel(m, [0, 2])
	m.hud_msg = ""
	key(m, KEY_G)
	var split_refused: bool = m.hud_msg == "Выбери один отряд" and m.squad_used[4] == 0
	sel(m, [0, 1])
	m.hud_msg = ""
	key(m, KEY_M)
	var types_refused: bool = m.hud_msg == "Сливаются только отряды одного типа" and m.squad_n[0] == 150 and m.squad_n[1] == 100
	sel(m, [3, 0, 2])
	key(m, KEY_M)
	check("(е) деление при двух выбранных: «Выбери один отряд»; слияние отрядов разных типов: отказ с сообщением; слияние трёх пехотных: один отряд (наименьший индекс) с %d юнитами, слоты уникальны и без дыр, выбор на нём" % m.squad_n[0],
		split_refused and types_refused and m.squad_n[0] == 300 and m.squad_used[2] == 0 and m.squad_used[3] == 0 and m.sel_mask == 1 and m.sel_primary == 0 and slots_full(m, 0) and integrity(m) == "", integrity(m))
	# один выбранный: слияние как раньше (в первый другой того же типа), покупка — в главный
	key(m, KEY_G)
	var t: int = m.sel_primary
	key(m, KEY_M)
	var single_merge: bool = t == 2 and m.squad_used[2] == 0 and m.squad_n[0] == 300 and m.sel_mask == 1
	key(m, KEY_G)
	sel(m, [0, 2])
	var buy_primary: bool = m._buy_target(m.infantry_type) == 2 and m._buy_target(m.archer_type) == 1
	sel(m, [2, 0])
	buy_primary = buy_primary and m._buy_target(m.infantry_type) == 0
	m._clear_sel()
	check("(е) один выбранный: слияние как раньше; покупка идёт в главный выбранный своего типа, иначе в первый отряд типа (и при пустом выборе)",
		single_merge and buy_primary and m._buy_target(m.infantry_type) == 0 and m._buy_target(m.archer_type) == 1)
	await drop(m)

# (ж) на паузе всё меняет только данные.
func test_pause() -> void:
	var m: Node2D = await scene(2)
	army(m)
	start_battle(m, 3)
	for t in 150:
		m._physics_process(DT)
	key(m, KEY_SPACE)
	var h := pos_hash(m)
	var t0: PackedVector2Array = m.squad_target.duplicate()
	var bad := PackedStringArray()
	lclick(m, m.pos[units(m, 2)[0]])
	if m.sel_mask != 4:
		bad.append("клик")
	ldrag(m, Vector2(100, 50), Vector2(2100, 720))
	if m.sel_mask != mask_of([0, 1, 2, 3]):
		bad.append("рамка")
	sel(m, [0, 2])
	rclick(m, (m.squad_pos[0] + m.squad_pos[2]) * 0.5 + Vector2(0, 120))
	if m.squad_target[0] == t0[0] or m.squad_target[2] == t0[2] or m.squad_target[3] != t0[3]:
		bad.append("ПКМ-клик")
	var p0: PackedVector2Array = m.squad_pos.duplicate()
	sel(m, [2, 3])
	rdrag(m, Vector2(900, 420), Vector2(1300, 420))
	if m.squad_pos[2] == p0[2] or m.squad_pos[3] == p0[3] or m.squad_pos[0] != p0[0]:
		bad.append("расстановка")
	key(m, KEY_A, false, true)
	key(m, KEY_W)
	check("(ж) на паузе: клик, рамка, ПКМ-клик и расстановка группы меняют выбор, цели и строй", m.paused and bad.is_empty(), ", ".join(bad))
	for t in 90:
		m._physics_process(DT)
	check("(ж) позиции, скорости, HP юнитов и счётчик тиков за паузу не изменились", pos_hash(m) == h and integrity(m) == "", integrity(m))
	var places: PackedVector2Array = m.squad_pos.duplicate()
	key(m, KEY_SPACE)
	for i in m.count:
		if m.team[i] == 1:
			m.hp[i] = 0.0
	for k in m.wave_left.size():
		m.wave_left[k] = 0
	m.wave_remaining = 0
	for b in m.wave_bursts:
		b.state = 3
	m._physics_process(DT)
	var moving: bool = pos_hash(m) != h
	m.wave_state = m.WS_BATTLE   # зомби убраны: волна бы кончилась; дальше — только движение отрядов
	var err := ""
	for t in 600:
		m._physics_process(DT)
		if err == "":
			err = integrity(m)
	var worst := 0.0
	for s in [0, 2, 3]:
		worst = maxf(worst, m.squad_pos[s].distance_to(m.squad_target[s]))
	check("(ж) после снятия паузы отряды идут и встают по заданному", moving and worst <= 1.0 and err == "" and m.squad_pos[2].distance_to(places[2]) < 2.0 * m.SLOT_SPACING,
		"до цели не больше %.2f px; %s" % [worst, err])
	await drop(m)

# (з) выбор не держит несуществующие отряды.
func test_freed() -> void:
	var m: Node2D = await scene()
	army(m)
	var bad := PackedStringArray()
	# гибель отряда в бою
	start_battle(m, 1)
	sel(m, [0, 3, 2])
	kill_squad(m, 2)
	m._physics_process(DT)
	if m.sel_mask != mask_of([0, 3]) or m.sel_primary != 3 or sel_error(m) != "":
		bad.append("гибель главного: маска %d, главный %d" % [m.sel_mask, m.sel_primary])
	key(m, KEY_3)
	key(m, KEY_3, true)
	lclick(m, m.squad_pos[2])
	if m.sel_mask & 4 != 0:
		bad.append("пустой отряд выбран в бою")
	sel(m, [3])
	kill_squad(m, 3)
	m._physics_process(DT)
	if m.sel_mask != 0 or m.sel_primary != -1:
		bad.append("гибель единственного выбранного: маска %d, главный %d" % [m.sel_mask, m.sel_primary])
	var before: PackedVector2Array = m.squad_target.duplicate()
	rclick(m, Vector2(600, 400))
	key(m, KEY_UP)
	key(m, KEY_F)
	if m.squad_target != before:
		bad.append("приказ при пустом выборе")
	# конец волны: пустые созданные отряды освобождаются
	sel(m, [0, 1])
	for i in m.count:
		if m.team[i] == 1:
			m.hp[i] = 0.0
	for k in m.wave_left.size():
		m.wave_left[k] = 0
	m.wave_remaining = 0
	for b in m.wave_bursts:
		b.state = 3
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 300:
		m._physics_process(DT)
		t += 1
	if m.wave_state != m.WS_RESPITE or m.squad_used[2] == 1 or m.squad_used[3] == 1 or m.sel_mask != 3 or sel_error(m) != "":
		bad.append("очистка пустых: состояние %d, маска %d" % [m.wave_state, m.sel_mask])
	# передышка: N создаёт пустой отряд и выбирает его; с началом волны пустой уходит из выбора
	key(m, KEY_1)
	key(m, KEY_N)
	var created: int = m.sel_primary
	if created != 2 or m.sel_mask != 4 or m._buy_target(m.infantry_type) != 2:
		bad.append("N: главный %d" % created)
	key(m, KEY_1, true)
	m.gate_hp = 1e9
	m._start_wave()
	m._physics_process(DT)
	if m.sel_mask != 1 or m.sel_primary != 0 or sel_error(m) != "":
		bad.append("пустой отряд в бою: маска %d, главный %d" % [m.sel_mask, m.sel_primary])
	check("(з) гибель отряда, очистка пустых в конце волны, слияние: в sel_mask и sel_primary нет несуществующих отрядов; главный — ближайший оставшийся или -1; при пустом выборе приказы игнорируются",
		bad.is_empty(), "; ".join(bad))
	await drop(m)

# (к) детерминизм: бой с выбором, рамкой и приказами по сценарию.
func scenario(rng_seed: int) -> Array:
	var m: Node2D = await scene(rng_seed)
	army(m)
	start_battle(m, 5)
	var err := ""
	var h := 0
	var ticks := 0
	while m.wave_state == m.WS_BATTLE and ticks < 900:
		match ticks:
			40:
				lclick(m, m.pos[units(m, 2)[0]])
				rclick(m, Vector2(900, 400))
			120:
				ldrag(m, Vector2(100, 50), Vector2(2100, 500))
				rdrag(m, Vector2(600, 330), Vector2(1400, 330))
			240:
				key(m, KEY_SPACE)
				lclick(m, m.squad_pos[0])
				lclick(m, m.squad_pos[3], true)
				key(m, KEY_W)
				key(m, KEY_LEFT)
				key(m, KEY_2)
				rclick(m, Vector2(1000, 560))
				key(m, KEY_SPACE)
			400:
				key(m, KEY_A, false, true)
				rclick(m, Vector2(1000, 420))
				key(m, KEY_Q)
			520:
				lclick(m, m.squad_pos[0], false, true)
				key(m, KEY_F)
				rdrag(m, Vector2(1300, 300), Vector2(700, 380), true)
				key(m, KEY_P)
				key(m, KEY_1)
				m.split_frac = 0.4
				key(m, KEY_G)
				key(m, KEY_UP)
				key(m, KEY_P)
		m._physics_process(DT)
		ticks += 1
		if err == "":
			err = integrity(m)
			if err != "":
				err = "тик %d: %s" % [ticks, err]
		if ticks % 30 == 0:
			h = hash([h, pos_hash(m), m.sel_mask, m.sel_primary, m.squad_target, m.squad_angle])
	var r := [h, err, ticks, m.count, m.sel_mask, m.sel_primary, m.wave_state]
	await drop(m)
	return r

func test_determ() -> void:
	for sd in [1, 2]:
		var a: Array = await scenario(sd)
		var b: Array = await scenario(sd)
		check("(к) волна 5, seed %d: выбор, рамка, ПКМ-клик, расстановка группы, пауза, стрелки, деление по сценарию — целостность отрядов и выбора каждый тик, два прогона одинаковы" % sd,
			a[1] == "" and a == b and a[2] > 520, "%d тиков, юнитов %d, маска %d, главный %d, хеш %d; %s" % [a[2], a[3], a[4], a[5], a[0], a[1]])

# (м) без команд симуляция как в коммите этапа 1.
func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func plain(path: String, rng_seed: int, waves: bool) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func test_regress() -> void:
	var a := plain(OLD, 5, false)
	var b := plain(NEW, 5, false)
	var first := -1
	for t in 900:
		a._physics_process(DT)
		b._physics_process(DT)
		if first < 0 and not same(a, b):
			first = t
	check("(м) без команд, 30 с без волн (seed 5, юнитов %d): pos, hp, count как в коммите этапа 1 на каждом тике" % b.count, first < 0, "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	a = plain(OLD, 7, true)
	b = plain(NEW, 7, true)
	b.weapon_stat = "damage"   # копия до правок знает только «Оружие» на уроне (задача 6d перевела его на скорость атаки); сравнивается выбор и мышь
	first = -1
	var ticks := 0
	var buys := [0, 1, 2, 0, 1, 3]
	for w in 3:
		for x in [a, b]:
			x._buy(buys[w * 2])
			x._buy(buys[w * 2 + 1])
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 600:
			a._physics_process(DT)
			b._physics_process(DT)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
		if first < 0 and (a.wave_state != b.wave_state or a.wave_number != b.wave_number):
			first = ticks
	check("(м) 3 волны с покупками (seed 7, %d тиков, волна %d, юнитов %d): совпадает на каждом тике" % [ticks, b.wave_number, b.count], first < 0 and b.wave_number == 3, "первое расхождение: тик %d" % first)
	a.free()
	b.free()

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "all"
	if which in ["all", "select"]:
		await test_select()
	if which in ["all", "box"]:
		await test_box()
	if which in ["all", "rmb"]:
		await test_rmb()
	if which in ["all", "multi"]:
		await test_multi()
	if which in ["all", "cmds"]:
		await test_cmds()
	if which in ["all", "pause"]:
		await test_pause()
	if which in ["all", "freed"]:
		await test_freed()
	if which in ["all", "determ"]:
		await test_determ()
	if which in ["all", "regress"]:
		test_regress()
	print("CHECK: провалов %d" % fails)
	quit()
