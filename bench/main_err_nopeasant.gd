extends Node2D

const UNIT_COUNT := 600
const UNIT_TYPES_PATH := "res://bench/types_noname.json"
const FLOATS_PER_UNIT := 12   # 8 (трансформ 2D) + 4 (цвет)
const CELL_SIZE := 12.0
const GRID_W := 170
const GRID_H := 86
const CELL_COUNT := GRID_W * GRID_H   # 14620 клеток, поле 2040x1032 px
const MIN_DIST := 5.0        # ближе этого юниты отталкиваются
const PUSH_K := 0.5          # доля перекрытия, которую снимаем за тик
const VIEW_RANGE := 12.0   # равен CELL_SIZE: окно 3x3 его гарантированно покрывает
const FIELD := Vector2(GRID_W * CELL_SIZE, GRID_H * CELL_SIZE)   # 2040 x 1032, юниты не выходят за край
# Юнит обновляется раз в 2 тика. Два обновления по PUSH_K оставляют 25% перекрытия,
# поэтому за одно обновление снимаем 1 - 0.5^2 = 75%.
const PUSH_K_2 := 1.0 - (1.0 - PUSH_K) * (1.0 - PUSH_K)
const SLOT_GAIN := 5.0        # сила притяжения к слоту (1/с)
const SLOT_SPACING := 6.0
const TURN_SPEED := 1.5          # рад/с, поворот на месте
const ABOUT_FACE_ANGLE := 2.1    # около 120°: если угол больше, разворот «кругом»
const MOVE_ANGLE := 0.7          # около 40°: пока угол больше, отряд стоит и поворачивается

# --- Данные юнитов: параллельные массивы. Юнит = индекс i ---
var pos := PackedVector2Array()   # позиции
var vel := PackedVector2Array()   # желаемая скорость, px/с (решается раз в 2 тика, применяется каждый тик)
var team := PackedByteArray()     # 0 = левые, 1 = правые
var buf := PackedFloat32Array()
var cell_of := PackedInt32Array()
var cell_start := PackedInt32Array()
var cursor := PackedInt32Array()
var sorted_units := PackedInt32Array()
var hp := PackedFloat32Array()
var cooldown := PackedFloat32Array()
var tick_parity := false
var update_odd := false   # какая половина обновляется в этом тике: false = чётные индексы
var count := UNIT_COUNT        # живых юнитов сейчас
var squad_pos := PackedVector2Array()
var squad_target := PackedVector2Array()
var squad_angle := PackedFloat32Array()
var squad_count := 0
var squad_team := PackedByteArray()
var squad_stop_dist := PackedFloat32Array()   # отряд стоит, когда до цели не больше этого
var unit_squad := PackedInt32Array()    # -1 = без отряда
var unit_slot := PackedVector2Array()
var unit_slot_idx := PackedInt32Array()   # k = ряд * ширина + колонка
var squad_width := PackedInt32Array()
var squad_rows := PackedInt32Array()      # ceil(начальное число юнитов / ширина)
var squad_dirty := PackedByteArray()      # 1 = в отряде кто-то погиб, нужна перестройка
var slot_owner := PackedInt32Array()      # scratch для _compact_squad: юнит в слоте k или -1
var col_map := PackedInt32Array()         # scratch для _compact_squad: старая колонка -> номер занятой или -1
var squad_compact_t := 0.0
var squad_speed := PackedFloat32Array()   # 0.75 * минимальная скорость юнитов отряда: строй успевает

# --- Типы юнитов (data/unit_types.json): плоские массивы по номеру типа ---
var unit_type := PackedByteArray()
var type_hp := PackedFloat32Array()
var type_damage := PackedFloat32Array()
var type_range_sq := PackedFloat32Array()   # квадрат дальности атаки
var type_cooldown := PackedFloat32Array()
var type_speed := PackedFloat32Array()
var type_id := {}   # имя -> номер

# --- Отрисовка ---
var multimesh: MultiMesh
var fps_label: Label
var grid_ms := 0.0
var sim_avg := 0.0
var sim_peak := 0.0
var sim_max := 0.0        


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_setup_data()
	if type_id.is_empty():
		return   # типы не загрузились: ошибка уже выведена, симуляция остановлена
	_setup_rendering()
	_setup_fps_label()


func _load_types() -> bool:
	if not FileAccess.file_exists(UNIT_TYPES_PATH):
		push_error("Нет файла типов юнитов: %s" % UNIT_TYPES_PATH)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(UNIT_TYPES_PATH))
	if not data is Array or data.is_empty():
		push_error("%s: ожидается непустой JSON-массив типов" % UNIT_TYPES_PATH)
		return false
	var n: int = data.size()
	type_hp.resize(n)
	type_damage.resize(n)
	type_range_sq.resize(n)
	type_cooldown.resize(n)
	type_speed.resize(n)
	var ids := {}
	for t in n:
		var e = data[t]
		if not e is Dictionary or not e.get("name") is String:
			push_error("%s: тип #%d без поля name" % [UNIT_TYPES_PATH, t])
			return false
		for key in ["hp", "damage", "range", "cooldown", "speed"]:
			if not (e.get(key) is float or e.get(key) is int):
				push_error("%s: у типа \"%s\" нет числового поля %s" % [UNIT_TYPES_PATH, e.name, key])
				return false
		if ids.has(e.name):
			push_error("%s: тип \"%s\" повторяется" % [UNIT_TYPES_PATH, e.name])
			return false
		ids[e.name] = t
		type_hp[t] = e.hp
		type_damage[t] = e.damage
		type_range_sq[t] = e.range * e.range
		type_cooldown[t] = e.cooldown
		type_speed[t] = e.speed
	type_id = ids   # заполняем только при полном успехе
	return true


func _type_of(type_name: String) -> int:
	if not type_id.has(type_name):
		push_error("%s: нет типа \"%s\"" % [UNIT_TYPES_PATH, type_name])
		return -1
	return type_id[type_name]


func _setup_data() -> void:
	if not _load_types():
		set_physics_process(false)
		set_process(false)
		return
	var squad_types := PackedInt32Array([_type_of("infantry"), _type_of("peasant")])   # тип по номеру отряда
	if squad_types.has(-1):
		type_id = {}
		set_physics_process(false)
		set_process(false)
		return
	pos.resize(UNIT_COUNT)
	team.resize(UNIT_COUNT)
	cell_of.resize(UNIT_COUNT)
	sorted_units.resize(UNIT_COUNT)
	cell_start.resize(CELL_COUNT + 1)
	cursor.resize(CELL_COUNT)
	hp.resize(UNIT_COUNT)
	unit_type.resize(UNIT_COUNT)
	cooldown.resize(UNIT_COUNT)
	cooldown.fill(0.0)
	vel.resize(UNIT_COUNT)
	vel.fill(Vector2.ZERO)   # стартовая скорость 0
	unit_squad.resize(UNIT_COUNT)
	unit_slot.resize(UNIT_COUNT)
	unit_slot_idx.resize(UNIT_COUNT)
	slot_owner.resize(UNIT_COUNT)   # выделяется один раз

	# Отряд 0: игрок (team 0). Отряд 1: зомби (team 1), останавливается в 8 px от цели.
	squad_count = 2
	squad_pos.resize(squad_count)
	squad_target.resize(squad_count)
	squad_angle.resize(squad_count)
	squad_team.resize(squad_count)
	squad_stop_dist.resize(squad_count)
	squad_pos[0] = Vector2(300, 500)
	squad_angle[0] = 0.0
	squad_team[0] = 0
	squad_stop_dist[0] = 0.0
	squad_pos[1] = Vector2(1200, 500)
	squad_angle[1] = PI
	squad_team[1] = 1
	squad_stop_dist[1] = 8.0   # между MIN_DIST и VIEW_RANGE: передние линии сходятся на дистанцию обзора
	for s in squad_count:
		squad_target[s] = squad_pos[s]

	var per_squad := UNIT_COUNT / squad_count   # 0..299 — отряд 0, 300..599 — отряд 1
	squad_width.resize(squad_count)
	squad_rows.resize(squad_count)
	squad_dirty.resize(squad_count)
	squad_dirty.fill(0)
	for s in squad_count:
		squad_width[s] = 20
		squad_rows[s] = ceili(per_squad / float(squad_width[s]))
	var max_width := 0
	for s in squad_count:
		max_width = maxi(max_width, squad_width[s])
	col_map.resize(max_width)   # выделяется один раз
	for i in UNIT_COUNT:
		var s := i / per_squad
		unit_squad[i] = s
		team[i] = squad_team[s]
		unit_type[i] = squad_types[s]
		hp[i] = type_hp[unit_type[i]]
		_set_line_slot(i, i - s * per_squad, squad_width[s])
		pos[i] = squad_pos[s] + unit_slot[i].rotated(squad_angle[s])
	squad_speed.resize(squad_count)
	for s in squad_count:
		var min_speed := INF
		for i in UNIT_COUNT:
			if unit_squad[i] == s:
				min_speed = minf(min_speed, type_speed[unit_type[i]])
		squad_speed[s] = 0.75 * min_speed


func _setup_rendering() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 4)
	multimesh.mesh = quad
	multimesh.instance_count = UNIT_COUNT

	# Буфер заполняем целиком ОДИН раз: всё, что не меняется (матрица, цвет)
	buf.resize(UNIT_COUNT * FLOATS_PER_UNIT)
	for i in UNIT_COUNT:
		var o := i * FLOATS_PER_UNIT
		buf[o + 0] = 1.0   # x.x  (без поворота и масштаба)
		buf[o + 5] = 1.0   # y.y
		var c := Color.CORNFLOWER_BLUE if team[i] == 0 else Color.INDIAN_RED
		buf[o + 8] = c.r
		buf[o + 9] = c.g
		buf[o + 10] = c.b
		buf[o + 11] = c.a

	var node := MultiMeshInstance2D.new()
	node.multimesh = multimesh
	add_child(node)


func _setup_fps_label() -> void:
	var layer := CanvasLayer.new()
	fps_label = Label.new()
	layer.add_child(fps_label)
	add_child(layer)


# Симуляция: фиксированный шаг (по умолчанию 30 раз в секунду)
var sim_ms := 0.0
var draw_ms := 0.0

func _physics_process(delta: float) -> void:
	var t := Time.get_ticks_usec()
	_update_squads(delta)
	_build_grid()
	grid_ms = (Time.get_ticks_usec() - t) / 1000.0
	# За тик обновляется половина юнитов: чётные, затем нечётные.
	# Направление (tick_parity) меняется раз в 2 тика, чтобы каждая половина
	# по очереди проходилась и вперёд, и назад.
	if not update_odd:
		tick_parity = not tick_parity
	var half := 1 if update_odd else 0
	update_odd = not update_odd
	var dt2 := delta * 2.0   # юнит обновляется раз в 2 тика
	if tick_parity:
		for i in range(half, count, 2):
			_update_unit(i, dt2)
	else:
		var last := count - 1
		if (last - half) % 2 != 0:
			last -= 1
		for i in range(last, -1, -2):
			_update_unit(i, dt2)
	_move_units(delta)   # двигаются все юниты каждый тик, а не только обновлённая половина
	_remove_dead()
	sim_ms = (Time.get_ticks_usec() - t) / 1000.0
	sim_avg = lerpf(sim_avg, sim_ms, 0.05)
	sim_peak = maxf(sim_ms, sim_peak * 0.98)
	sim_max = maxf(sim_max, sim_ms)

func _process(_delta: float) -> void:
	var t := Time.get_ticks_usec()
	for i in count:
		var o := i * FLOATS_PER_UNIT
		buf[o + 3] = pos[i].x
		buf[o + 7] = pos[i].y
		# цвет пишем каждый кадр: после _remove_dead на индекс i мог встать юнит другой команды
		var c := Color.CORNFLOWER_BLUE if team[i] == 0 else Color.INDIAN_RED
		buf[o + 8] = c.r
		buf[o + 9] = c.g
		buf[o + 10] = c.b
	multimesh.visible_instance_count = count
	multimesh.buffer = buf          # один вызов вместо UNIT_COUNT
	draw_ms = (Time.get_ticks_usec() - t) / 1000.0
	fps_label.text = "FPS: %d | units: %d | sim avg: %.1f peak: %.1f | grid: %.1f ms" % [
		Engine.get_frames_per_second(), count, sim_avg, sim_peak, grid_ms]


func _update_unit(i: int, delta: float) -> void:
	var t := unit_type[i]
	var my_team := team[i]
	var p := pos[i]
	var cx := clampi(floori(p.x / CELL_SIZE), 0, GRID_W - 1)
	var cy := clampi(floori(p.y / CELL_SIZE), 0, GRID_H - 1)
	var best := -1
	var best_d := INF
	var push := Vector2.ZERO

	for ny in range(maxi(cy - 1, 0), mini(cy + 1, GRID_H - 1) + 1):
		for nx in range(maxi(cx - 1, 0), mini(cx + 1, GRID_W - 1) + 1):
			var c := nx + ny * GRID_W
			for k in range(cell_start[c], cell_start[c + 1]):
				var j := sorted_units[k]
				# j == i не проверяем: у самого себя d2 = 0, его отсекают d2 > 0.0001 и team
				var q := pos[j]
				var d2 := p.distance_squared_to(q)
				if d2 > VIEW_RANGE * VIEW_RANGE:
					continue   # большинство соседей окна 3x3 дальше VIEW_RANGE
				if d2 < MIN_DIST * MIN_DIST and d2 > 0.0001:
					var off := p - q
					var d := sqrt(d2)
					push += off / d * (MIN_DIST - d)
				if d2 < best_d and team[j] != my_team:
					best_d = d2
					best = j

	# Здесь только решение: скорость, удар, перезарядка. Ход делает _move_units каждый тик.
	var v := Vector2.ZERO   # в дальности атаки стоим на месте
	if best != -1:
		if best_d > type_range_sq[t]:
			v = (pos[best] - p).normalized() * type_speed[t]
		elif cooldown[i] <= 0.0:
			hp[best] -= type_damage[t]
			cooldown[i] = type_cooldown[t]
	else:
		var s := unit_squad[i]
		if s >= 0:
			var slot_world := squad_pos[s] + unit_slot[i].rotated(squad_angle[s])
			v = ((slot_world - p) * SLOT_GAIN).limit_length(type_speed[t] * 1.3)
	vel[i] = v
	cooldown[i] = maxf(cooldown[i] - delta, 0.0)
	pos[i] = (p + push * PUSH_K_2).clamp(Vector2.ZERO, FIELD)   # толчок: разовый сдвиг при решении


func _move_units(delta: float) -> void:
	for i in count:
		pos[i] = (pos[i] + vel[i] * delta).clamp(Vector2.ZERO, FIELD)   # граница поля


func _remove_dead() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0.0:
			if unit_squad[i] >= 0:
				squad_dirty[unit_squad[i]] = 1
			count -= 1
			pos[i] = pos[count]
			vel[i] = vel[count]
			team[i] = team[count]
			hp[i] = hp[count]
			cooldown[i] = cooldown[count]
			unit_squad[i] = unit_squad[count]
			unit_slot[i] = unit_slot[count]
			unit_slot_idx[i] = unit_slot_idx[count]
			unit_type[i] = unit_type[count]
		else:
			i += 1


func _build_grid() -> void:
	for i in count:
		var cx := clampi(floori(pos[i].x / CELL_SIZE), 0, GRID_W - 1)
		var cy := clampi(floori(pos[i].y / CELL_SIZE), 0, GRID_H - 1)
		cell_of[i] = cx + cy * GRID_W

	cell_start.fill(0)
	for i in count:
		cell_start[cell_of[i] + 1] += 1

	for c in CELL_COUNT:
		cell_start[c + 1] += cell_start[c]
		cursor[c] = cell_start[c]

	for i in count:
		var c := cell_of[i]
		sorted_units[cursor[c]] = i
		cursor[c] += 1


func _slot_vector(k: int, width: int) -> Vector2:
	var row := k / width
	var col := k % width
	return Vector2(-row * SLOT_SPACING, (col - (width - 1) * 0.5) * SLOT_SPACING)


func _set_line_slot(unit: int, k: int, width: int) -> void:
	unit_slot_idx[unit] = k
	unit_slot[unit] = _slot_vector(k, width)


# Замена убитых: в каждой колонке выжившие сдвигаются вперёд, к ряду 0, без дыр.
# Затем пустые колонки схлопываются: занятые встают подряд по центру строя.
func _compact_squad(s: int) -> void:
	var width := squad_width[s]
	var rows := squad_rows[s]
	for k in rows * width:
		slot_owner[k] = -1
	for i in count:
		if unit_squad[i] == s:
			slot_owner[unit_slot_idx[i]] = i
	for col in width:
		var w := 0
		for row in rows:
			var i := slot_owner[row * width + col]
			if i == -1:
				continue
			var k := w * width + col
			unit_slot_idx[i] = k
			unit_slot[i] = _slot_vector(k, width)
			w += 1

	# Схлопывание пустых колонок: номера занятых 0..n-1 слева направо, со сдвигом к центру.
	for col in width:
		col_map[col] = -1
	for i in count:
		if unit_squad[i] == s:
			col_map[unit_slot_idx[i] % width] = 0
	var n := 0
	for col in width:
		if col_map[col] != -1:
			col_map[col] = n
			n += 1
	var offset := (width - n) / 2
	for i in count:
		if unit_squad[i] == s:
			var k := unit_slot_idx[i]
			k = (k / width) * width + offset + col_map[k % width]
			unit_slot_idx[i] = k
			unit_slot[i] = _slot_vector(k, width)


func _update_squads(delta: float) -> void:
	squad_compact_t += delta
	if squad_compact_t >= 0.5:
		for s in squad_count:
			if squad_dirty[s] == 1:
				_compact_squad(s)
				squad_dirty[s] = 0
		squad_compact_t = 0.0
	# Зомби (отряд 1) идут на отряд игрока. Позже: «ближайший отряд игрока».
	squad_target[1] = squad_pos[0]
	for s in squad_count:
		var to := squad_target[s] - squad_pos[s]
		var dist := to.length()
		if dist <= maxf(squad_stop_dist[s], 1.0):   # нижний предел 1 px: без дёргания у цели
			continue
		var diff := angle_difference(squad_angle[s], to.angle())
		if absf(diff) > ABOUT_FACE_ANGLE:
			_about_face(s)
			diff = angle_difference(squad_angle[s], to.angle())
		squad_angle[s] += clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)
		if absf(diff) < MOVE_ANGLE:
			squad_pos[s] += to / dist * minf(squad_speed[s] * delta, dist)


func _about_face(s: int) -> void:
	# Разворот «кругом»: последний занятый ряд становится первым, колонки зеркалятся.
	# squad_pos переносится на новый первый ряд, мировые позиции слотов при отражении не меняются.
	_compact_squad(s)
	var old_angle := squad_angle[s]
	var width := squad_width[s]
	var occ_rows := 0
	for i in count:
		if unit_squad[i] == s:
			occ_rows = maxi(occ_rows, unit_slot_idx[i] / width + 1)
	occ_rows = maxi(occ_rows, 1)   # пустой отряд: сдвиг 0
	squad_angle[s] = wrapf(old_angle + PI, -PI, PI)
	for i in count:
		if unit_squad[i] == s:
			var k := unit_slot_idx[i]
			var row := occ_rows - 1 - k / width
			var col := width - 1 - k % width
			_set_line_slot(i, row * width + col, width)
	squad_pos[s] -= Vector2.from_angle(old_angle) * (occ_rows - 1) * SLOT_SPACING
	_compact_squad(s)   # колонки снова подряд по центру, ряды без дыр


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		squad_target[0] = get_global_mouse_position()
