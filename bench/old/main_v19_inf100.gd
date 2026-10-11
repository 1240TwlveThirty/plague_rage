extends Node2D

const INFANTRY_COUNT := 100   # отряд 0: пехота игрока
const ARCHER_COUNT := 100     # отряд 1: лучники игрока
const UNIT_COUNT := 500       # остальные (UNIT_COUNT - INFANTRY_COUNT - ARCHER_COUNT) — зомби
const UNIT_TYPES_PATH := "res://data/unit_types.json"
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
const HORDE_GOAL := Vector2(40, 500)   # заглушка: ворота замка, куда идёт орда
const HORDE_SPEED_SPREAD := 0.1        # разброс скорости зомби: ±10%
const HORDE_CHAOS := 0.4               # доля бокового качания зомби при подходе к врагу
const BLOCK_COS := 0.5                 # передний сектор щита: ±60° от фронта отряда
const SHIELD_DOWN_TIME := 0.25         # щит опущен столько секунд после собственного удара
# --- Лучники ---
const ARCHER_GAP := 10.0               # зазор между строем ведущего отряда и строем лучников (сверх половин глубин)
const COARSE_SIZE := 48.0              # грубая сетка зомби (для прицеливания)
const COARSE_W := 43                   # ceil(2040 / 48)
const COARSE_H := 22                   # ceil(1032 / 48)
const COARSE_COUNT := COARSE_W * COARSE_H
const COARSE_EVERY := 4                # пересчёт грубой сетки раз в столько тиков
const NEAR_RANGE := 30.0               # зомби ближе — одиночный огонь
const MODE_HYST := 10.0                # дальше NEAR_RANGE + MODE_HYST — залп; между порогами режим не меняется
const MODE_VOLLEY := 0
const MODE_SINGLE := 1
const SINGLE_SCAN_T := 0.3             # одиночный огонь: лучник ищет цель раз в столько секунд
const VOLLEY_JITTER := 0.15            # залп: индивидуальная задержка выстрела ±столько секунд
const ARROW_SPEED := 200.0             # px/с, задаёт задержку падения стрелы
const ARROW_HIT_R := 8.0               # стрела попадает в ближайшего зомби в этом радиусе от точки падения
const ARROW_CAP := 2048                # ёмкость очереди стрел (с запасом)
const DEBUG_COLORS := true            # F2–F4: отладочная раскраска; false в релизе (остаётся только F1)
# Состояние юнита для раскраски F3 (пишется там, где принимается решение)
const ST_IDLE := 0     # стоит в слоте / идёт с ордой
const ST_CHASE := 1    # идёт на врага
const ST_RETURN := 2   # возвращается к слоту
const ST_ATTACK := 3   # враг в дальности атаки: стоит и бьёт

# --- Данные юнитов: параллельные массивы. Юнит = индекс i ---
var pos := PackedVector2Array()   # позиции
var prev_pos := PackedVector2Array()   # позиции в начале физического тика (для интерполяции при рендере)
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
var tick_counter := 0          # физических тиков с начала боя
var spawn_seed := 1            # seed генератора unit_rand
var unit_rand := PackedFloat32Array()   # 0..1 на юнита, выдаётся при спавне
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
var squad_rows := PackedInt32Array()      # число рядов сетки (при старте и после _reflow_squad)
var squad_dirty := PackedByteArray()      # 1 = в отряде кто-то погиб, нужна перестройка
var slot_owner := PackedInt32Array()      # scratch для _compact_squad: юнит в слоте k или -1
var col_map := PackedInt32Array()         # scratch для _compact_squad: старая колонка -> номер занятой или -1
var squad_compact_t := 0.0
var squad_speed := PackedFloat32Array()   # 0.75 * минимальная скорость юнитов отряда: строй успевает
# Якорь отряда (squad_pos) = центр живых слотов. unit_slot = _slot_vector(k, width) - squad_center_off[s],
# где squad_center_off — смещение центра живых слотов в координатах сетки (обновляет _reanchor).
var squad_center_off := PackedVector2Array()
var squad_reflow_n := PackedInt32Array()      # живых при прошлой перестройке (_reflow_squad)
var reflow_order := PackedInt32Array()        # scratch для _reflow_squad: юниты в порядке старых слотов
var slot_idx_prev := PackedInt32Array()       # scratch: slot_idx до перестройки (для unit_slot_changed_t)
var unit_state := PackedByteArray()           # ST_* (только для раскраски F3)
var unit_slot_changed_t := PackedFloat32Array()   # время (с) последней смены slot_idx (для F4)
var color_mode := 0                           # 0 = F1 по типу, 1 = F2 по ряду, 2 = F3 по состоянию, 3 = F4 смена слота
var squad_front_row := PackedInt32Array()     # scratch для F2: передний занятый ряд отряда

# --- Типы юнитов (data/unit_types.json): плоские массивы по номеру типа ---
var unit_type := PackedByteArray()
var type_hp := PackedFloat32Array()
var type_damage := PackedFloat32Array()
var type_range_sq := PackedFloat32Array()   # квадрат дальности атаки
var type_cooldown := PackedFloat32Array()
var type_speed := PackedFloat32Array()
var type_block_mult := PackedFloat32Array()   # множитель урона при блоке щитом; 1.0 = без щита
# Мягкая привязь к слоту: до leash_start юнит гонится за врагом, к leash_end — только к слоту.
var type_leash_start := PackedFloat32Array()
var type_leash_start_sq := PackedFloat32Array()
var type_leash_end := PackedFloat32Array()
var type_color := PackedColorArray()
var type_range_far := PackedFloat32Array()      # дальность стрельбы; 0 = не стреляет
var type_volley_period := PackedFloat32Array()  # период цикла залпа, с
var type_draw_time := PackedFloat32Array()      # натяжение перед залпом, с
var type_spread := PackedFloat32Array()         # разброс: радиус = spread * дистанция
var type_arrow_dmg := PackedFloat32Array()

# --- Лучники: отряды, грубая сетка зомби, стрелы-события ---
var squad_follow := PackedInt32Array()      # номер ведущего отряда или -1
var squad_ranged := PackedByteArray()       # 1 = отряд стреляет
var squad_type := PackedInt32Array()        # тип юнитов отряда (для параметров залпа)
var squad_volley_mode := PackedByteArray()  # MODE_VOLLEY / MODE_SINGLE
var squad_volley_t := PackedFloat32Array()  # время с начала цикла залпа
var squad_volley_fired := PackedByteArray() # 1 = в этом цикле уже выстрелили (идёт перезарядка)
var coarse_zcount := PackedInt32Array()      # зомби в грубой клетке
var coarse_sum := PackedVector2Array()      # сумма их позиций (центр масс = сумма / число)
var coarse_start := PackedInt32Array()
var coarse_cursor := PackedInt32Array()
var coarse_units := PackedInt32Array()      # индексы зомби по клеткам (могут устареть до пересчёта)
var coarse_cell_of := PackedInt32Array()
var arrow_land := PackedVector2Array()      # точка падения
var arrow_tick := PackedInt32Array()        # тик падения
var arrow_dmg := PackedFloat32Array()
var arrow_count := 0
var arrow_rng := RandomNumberGenerator.new()
var arrows_fired := 0   # статистика
var arrows_hit := 0     # статистика
var arrows_dropped := 0 # статистика: не влезли в ARROW_CAP
var mode_switches := 0  # статистика: смены режима стрельбы
var squad_depth := PackedFloat32Array()     # глубина строя = занятых рядов * SLOT_SPACING (кеш, см. _update_squad_extent)
var squad_front_x := PackedFloat32Array()   # локальная x переднего ряда относительно якоря (кеш)
var first_death_tick := -1   # статистика: тик первой смерти (начало контакта)
var reach_sum := 0.0         # статистика: сумма reach = range_far - расстояние до переднего ряда ведущего
var reach_dist_sum := 0.0    # статистика: сумма расстояний центр лучников -> передний ряд ведущего
var reach_n := 0             # тиков в сумме (первые 10 с до контакта)
var blocked_hits := 0   # статистика: удары, ослабленные щитом
var total_hits := 0     # статистика: удары по юнитам со щитом (block_mult < 1.0)
var leash_ticks := 0    # статистика: юнито-тики, где привязь перевешивает (w > 0.5)
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
	type_block_mult.resize(n)
	type_leash_start.resize(n)
	type_leash_start_sq.resize(n)
	type_leash_end.resize(n)
	type_color.resize(n)
	type_range_far.resize(n)
	type_volley_period.resize(n)
	type_draw_time.resize(n)
	type_spread.resize(n)
	type_arrow_dmg.resize(n)
	var ids := {}
	for t in n:
		var e = data[t]
		if not e is Dictionary or not e.get("name") is String:
			push_error("%s: тип #%d без поля name" % [UNIT_TYPES_PATH, t])
			return false
		for key in ["hp", "damage", "range", "cooldown", "speed", "block_mult", "leash_start", "leash_end",
				"range_far", "volley_period", "draw_time", "spread", "arrow_dmg"]:
			if not (e.get(key) is float or e.get(key) is int):
				push_error("%s: у типа \"%s\" нет числового поля %s" % [UNIT_TYPES_PATH, e.name, key])
				return false
		if e.leash_end < e.leash_start:
			push_error("%s: у типа \"%s\" leash_end меньше leash_start" % [UNIT_TYPES_PATH, e.name])
			return false
		if not e.get("color") is String or not Color.html_is_valid(e.color):
			push_error("%s: у типа \"%s\" нет поля color с hex-цветом" % [UNIT_TYPES_PATH, e.name])
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
		type_block_mult[t] = e.block_mult
		type_leash_start[t] = e.leash_start
		type_leash_start_sq[t] = e.leash_start * e.leash_start
		type_leash_end[t] = e.leash_end
		type_color[t] = Color.html(e.color)
		type_range_far[t] = e.range_far
		type_volley_period[t] = e.volley_period
		type_draw_time[t] = e.draw_time
		type_spread[t] = e.spread
		type_arrow_dmg[t] = e.arrow_dmg
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
	var infantry := _type_of("infantry")   # отряд 0
	var archer := _type_of("archer")       # отряд 1
	var peasant := _type_of("peasant")     # орда зомби
	if infantry == -1 or archer == -1 or peasant == -1:
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
	reflow_order.resize(UNIT_COUNT)   # выделяется один раз
	slot_idx_prev.resize(UNIT_COUNT)   # выделяется один раз
	unit_state.resize(UNIT_COUNT)
	unit_state.fill(ST_IDLE)
	unit_slot_changed_t.resize(UNIT_COUNT)
	# Лучники: грубая сетка зомби и очередь стрел, всё выделяется один раз.
	coarse_zcount.resize(COARSE_COUNT)
	coarse_sum.resize(COARSE_COUNT)
	coarse_start.resize(COARSE_COUNT + 1)
	coarse_start.fill(0)
	coarse_cursor.resize(COARSE_COUNT)
	coarse_units.resize(UNIT_COUNT)
	coarse_cell_of.resize(UNIT_COUNT)
	arrow_land.resize(ARROW_CAP)
	arrow_tick.resize(ARROW_CAP)
	arrow_dmg.resize(ARROW_CAP)
	arrow_count = 0
	arrow_rng.seed = spawn_seed + 7919   # отдельный seeded-генератор разброса стрел

	# Отряд 0: пехота игрока (team 0). Отряд 1: лучники (team 0), идут за отрядом 0.
	# Зомби (team 1) без отряда: орда идёт к HORDE_GOAL.
	squad_count = 2
	squad_pos.resize(squad_count)
	squad_target.resize(squad_count)
	squad_angle.resize(squad_count)
	squad_team.resize(squad_count)
	squad_stop_dist.resize(squad_count)
	squad_pos[0] = Vector2(300, 500)
	squad_pos[1] = Vector2(300, 500)   # временно: после расстановки встаёт за отрядом 0
	squad_angle.fill(0.0)
	squad_team.fill(0)
	squad_stop_dist.fill(0.0)
	squad_center_off.resize(squad_count)
	squad_center_off.fill(Vector2.ZERO)
	squad_reflow_n.resize(squad_count)
	squad_front_row.resize(squad_count)
	squad_follow = PackedInt32Array([-1, 0])
	squad_ranged = PackedByteArray([0, 1])
	squad_type = PackedInt32Array([infantry, archer])
	squad_volley_mode.resize(squad_count)
	squad_volley_mode.fill(MODE_VOLLEY)
	squad_volley_t.resize(squad_count)
	squad_volley_t.fill(0.0)
	squad_volley_fired.resize(squad_count)
	squad_volley_fired.fill(0)
	squad_depth.resize(squad_count)
	squad_depth.fill(0.0)
	squad_front_x.resize(squad_count)
	squad_front_x.fill(0.0)

	var squad_size := PackedInt32Array([INFANTRY_COUNT, ARCHER_COUNT])
	squad_width = PackedInt32Array([20, 25])   # лучники: шире и мельче (25 x 4)
	squad_rows.resize(squad_count)
	squad_dirty.resize(squad_count)
	squad_dirty.fill(0)
	for s in squad_count:
		squad_rows[s] = ceili(squad_size[s] / float(squad_width[s]))
	var max_width := 0
	for s in squad_count:
		max_width = maxi(max_width, squad_width[s])
	col_map.resize(max_width)   # выделяется один раз
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed
	unit_rand.resize(UNIT_COUNT)
	for i in UNIT_COUNT:
		unit_rand[i] = rng.randf()
		var s := 0 if i < INFANTRY_COUNT else (1 if i < INFANTRY_COUNT + ARCHER_COUNT else -1)
		if s >= 0:
			unit_squad[i] = s
			team[i] = squad_team[s]
			unit_type[i] = squad_type[s]
			_set_line_slot(i, i - (0 if s == 0 else INFANTRY_COUNT), squad_width[s])
			pos[i] = squad_pos[s] + unit_slot[i].rotated(squad_angle[s])
		else:
			unit_squad[i] = -1
			unit_slot_idx[i] = -1
			unit_slot[i] = Vector2.ZERO
			team[i] = 1
			unit_type[i] = peasant
			# Стартовые позиции как раньше: строй шириной 20 в (1200, 500), лицом влево.
			pos[i] = Vector2(1200, 500) + _slot_vector(i - INFANTRY_COUNT - ARCHER_COUNT, 20).rotated(PI)
		hp[i] = type_hp[unit_type[i]]
	unit_slot_changed_t.fill(-1000.0)   # стартовая расстановка — не смена слота
	for s in squad_count:
		squad_reflow_n[s] = squad_size[s]
		_reanchor(s)   # squad_pos переезжает в центр строя, мировые позиции юнитов те же
	for s in squad_count:
		var lead := squad_follow[s]
		if lead >= 0:   # ведомый отряд сразу ставим на его место за ведущим
			var shift := _follow_target(s) - squad_pos[s]
			squad_pos[s] += shift
			for i in UNIT_COUNT:
				if unit_squad[i] == s:
					pos[i] += shift
		squad_target[s] = squad_pos[s]
	prev_pos = pos.duplicate()   # иначе _remove_dead до первого физического тика выходит за границы prev_pos
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
		var c := type_color[unit_type[i]]
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
	prev_pos = pos.duplicate()   # для интерполяции в _process
	tick_counter += 1
	_update_squads(delta)
	_build_grid()
	grid_ms = (Time.get_ticks_usec() - t) / 1000.0
	# Лучники: грубая сетка и режим раз в COARSE_EVERY тиков; выстрелы и падение стрел — каждый тик.
	if tick_counter % COARSE_EVERY == 1:
		_rebuild_coarse()
		for s in squad_count:
			if squad_ranged[s] == 1:
				_update_archer_mode(s)
	_update_archers(delta)
	_process_arrows()   # после _build_grid: мелкая сетка этого тика ещё актуальна
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
	if color_mode == 1:
		# F2: передний занятый ряд каждого отряда
		squad_front_row.fill(1 << 30)
		for i in count:
			var s := unit_squad[i]
			if s >= 0:
				squad_front_row[s] = mini(squad_front_row[s], unit_slot_idx[i] / squad_width[s])
	var now := tick_counter / float(Engine.physics_ticks_per_second)
	var by_type := color_mode == 0
	var frac := Engine.get_physics_interpolation_fraction()
	var have_prev := prev_pos.size() == pos.size()   # до первого физического тика prev_pos пуст
	for i in count:
		var o := i * FLOATS_PER_UNIT
		var rp := prev_pos[i].lerp(pos[i], frac) if have_prev else pos[i]   # позиция между тиками
		buf[o + 3] = rp.x
		buf[o + 7] = rp.y
		# цвет пишем каждый кадр: после _remove_dead на индекс i мог встать юнит другого типа.
		# F1 без вызова функции: вызов на юнита стоит ~1.7 мс на 3000 юнитов.
		var c := type_color[unit_type[i]] if by_type else _unit_color(i, now)
		buf[o + 8] = c.r
		buf[o + 9] = c.g
		buf[o + 10] = c.b
	multimesh.visible_instance_count = count
	multimesh.buffer = buf          # один вызов вместо UNIT_COUNT
	draw_ms = (Time.get_ticks_usec() - t) / 1000.0
	fps_label.text = "FPS: %d | units: %d | sim avg: %.1f peak: %.1f | grid: %.1f ms | цвет: F%d" % [
		Engine.get_frames_per_second(), count, sim_avg, sim_peak, grid_ms, color_mode + 1]


func _unit_color(i: int, now: float) -> Color:
	match color_mode:
		1:   # F2: передние 3 занятых ряда красные, остальные синие; без отряда серые
			var s := unit_squad[i]
			if s < 0:
				return Color.DIM_GRAY
			return Color.RED if unit_slot_idx[i] / squad_width[s] < squad_front_row[s] + 3 else Color.ROYAL_BLUE
		2:   # F3: по состоянию
			match unit_state[i]:
				ST_CHASE:
					return Color.RED
				ST_RETURN:
					return Color.LIME_GREEN
				ST_ATTACK:
					return Color.YELLOW
			return Color.ROYAL_BLUE
		3:   # F4: белый 0.5 с после смены slot_idx
			return Color.WHITE if now - unit_slot_changed_t[i] < 0.5 else Color.DIM_GRAY
	return type_color[unit_type[i]]   # F1: по типу


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
		# Мягкая привязь: дальше leash_start от слота скорость к врагу смешивается со скоростью
		# к слоту с весом w = smoothstep(leash_start, leash_end, d). Бьёт юнит при любом w.
		var leash_w := 0.0
		var slot_vel := Vector2.ZERO
		var sq := unit_squad[i]
		if sq >= 0:
			var slot_world := squad_pos[sq] + unit_slot[i].rotated(squad_angle[sq])
			var ds2 := p.distance_squared_to(slot_world)
			if ds2 > type_leash_start_sq[t]:
				var l0 := type_leash_start[t]
				var l1 := type_leash_end[t]
				leash_w = 1.0 if l1 <= l0 else smoothstep(l0, l1, sqrt(ds2))
				slot_vel = ((slot_world - p) * SLOT_GAIN).limit_length(type_speed[t] * 1.3)
				if leash_w > 0.5:
					leash_ticks += 2   # решение действует 2 тика (юнит обновляется раз в 2 тика)
		if best_d > type_range_sq[t]:
			var dir := (pos[best] - p).normalized()
			if unit_squad[i] == -1:
				# Зомби подходит к врагу, качаясь вбок; фаза своя у каждого (unit_rand).
				dir += dir.orthogonal() * HORDE_CHAOS * sin(tick_counter * 0.15 + unit_rand[i] * TAU)
			v = dir * type_speed[t]
			unit_state[i] = ST_CHASE
		else:
			unit_state[i] = ST_ATTACK
		if best_d <= type_range_sq[t] and cooldown[i] <= 0.0:
			var dmg := type_damage[t]
			var m := type_block_mult[unit_type[best]]
			if m < 1.0:
				total_hits += 1
				# Блок щитом: жертва в отряде, щит поднят (с её удара прошло >= SHIELD_DOWN_TIME;
				# cooldown = сколько осталось до её следующего удара), удар из переднего сектора.
				var sj := unit_squad[best]
				if sj >= 0 and type_cooldown[unit_type[best]] - cooldown[best] >= SHIELD_DOWN_TIME:
					var a := p - pos[best]
					if a.dot(Vector2.from_angle(squad_angle[sj])) > BLOCK_COS * a.length():
						dmg *= m
						blocked_hits += 1
			hp[best] -= dmg
			cooldown[i] = type_cooldown[t]
		if leash_w > 0.0:
			v = v.lerp(slot_vel, leash_w)   # смесь «к врагу (или стоять и бить)» и «к слоту»
			if leash_w > 0.5:
				unit_state[i] = ST_RETURN
	else:
		var s := unit_squad[i]
		if s >= 0:
			var slot_world := squad_pos[s] + unit_slot[i].rotated(squad_angle[s])
			v = ((slot_world - p) * SLOT_GAIN).limit_length(type_speed[t] * 1.3)
			# дальше полуслота от своего места — «возвращается», иначе «стоит»
			unit_state[i] = ST_RETURN if p.distance_squared_to(slot_world) > 9.0 else ST_IDLE
		else:
			unit_state[i] = ST_IDLE
			# Орда идёт к воротам; скорость у каждого зомби своя (±HORDE_SPEED_SPREAD).
			var to_goal := HORDE_GOAL - p
			if to_goal.length() > 4.0:
				v = to_goal.normalized() * type_speed[t] * (1.0 + HORDE_SPEED_SPREAD * (unit_rand[i] * 2.0 - 1.0))
	# Толчок не разовым сдвигом позиции, а добавкой к скорости на 2 тика до следующего решения:
	# delta здесь = 2 тика, поэтому за эти 2 тика юнит сместится ровно на push * PUSH_K_2.
	vel[i] = v + push * PUSH_K_2 / delta
	cooldown[i] = maxf(cooldown[i] - delta, 0.0)


func _move_units(delta: float) -> void:
	for i in count:
		pos[i] = (pos[i] + vel[i] * delta).clamp(Vector2.ZERO, FIELD)   # граница поля


func _remove_dead() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0.0:
			if first_death_tick < 0:
				first_death_tick = tick_counter
			if unit_squad[i] >= 0:
				squad_dirty[unit_squad[i]] = 1
			count -= 1
			pos[i] = pos[count]
			prev_pos[i] = prev_pos[count]   # та же перестановка, иначе lerp смешает разных юнитов
			vel[i] = vel[count]
			team[i] = team[count]
			hp[i] = hp[count]
			cooldown[i] = cooldown[count]
			unit_squad[i] = unit_squad[count]
			unit_slot[i] = unit_slot[count]
			unit_slot_idx[i] = unit_slot_idx[count]
			unit_type[i] = unit_type[count]
			unit_rand[i] = unit_rand[count]
			unit_state[i] = unit_state[count]
			unit_slot_changed_t[i] = unit_slot_changed_t[count]
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
	unit_slot[unit] = _slot_vector(k, width) - squad_center_off[unit_squad[unit]]


# Якорь отряда в центр живых слотов. Мировые позиции слотов не меняются.
# Возвращает сдвиг центра в координатах слотов.
func _reanchor(s: int) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for i in count:
		if unit_squad[i] == s:
			c += unit_slot[i]
			n += 1
	if n == 0:
		return Vector2.ZERO
	c /= n
	# Отряд, уже стоявший у цели, переносит цель вместе с якорем, иначе пойдёт «возвращаться».
	var arrived := squad_pos[s].distance_to(squad_target[s]) <= maxf(squad_stop_dist[s], 1.0)
	for i in count:
		if unit_squad[i] == s:
			unit_slot[i] -= c
	squad_center_off[s] += c
	var shift := c.rotated(squad_angle[s])
	squad_pos[s] += shift
	if arrived:
		squad_target[s] += shift
	_update_squad_extent(s)
	return c


# Кеш глубины строя (занятые ряды * SLOT_SPACING) и локальной x переднего ряда.
# Обновляется при перестройке слотов (_reanchor) и развороте, а не каждый тик.
func _update_squad_extent(s: int) -> void:
	var width := squad_width[s]
	var rmin := 1 << 30
	var rmax := -1
	var fx := -INF
	for i in count:
		if unit_squad[i] == s:
			var r := unit_slot_idx[i] / width
			rmin = mini(rmin, r)
			rmax = maxi(rmax, r)
			fx = maxf(fx, unit_slot[i].x)
	squad_depth[s] = (rmax - rmin + 1) * SLOT_SPACING if rmax >= 0 else 0.0
	squad_front_x[s] = fx if rmax >= 0 else 0.0


# Место ведомого отряда: позади ведущего на половину глубины каждого строя плюс ARCHER_GAP.
func _follow_target(s: int) -> Vector2:
	var lead := squad_follow[s]
	var back := squad_depth[lead] * 0.5 + squad_depth[s] * 0.5 + ARCHER_GAP
	return squad_pos[lead] - Vector2.from_angle(squad_angle[lead]) * back


# Замена убитых: в каждой колонке выжившие сдвигаются вперёд, к ряду 0, без дыр.
# Затем пустые колонки схлопываются: занятые встают подряд по центру строя.
func _compact_squad(s: int) -> void:
	_snapshot_slots(s)
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
			_set_line_slot(i, w * width + col, width)
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
			_set_line_slot(i, (k / width) * width + offset + col_map[k % width], width)
	_reanchor(s)
	_mark_slot_changes(s)


# Нужна ли перестройка глубины: колонки разной глубины (> 3) или потери >= 30% с прошлой перестройки.
func _needs_reflow(s: int) -> bool:
	var width := squad_width[s]
	for col in width:
		col_map[col] = 0
	var n := 0
	for i in count:
		if unit_squad[i] == s:
			col_map[unit_slot_idx[i] % width] += 1
			n += 1
	if n == 0:
		return false
	var lo := n
	var hi := 0
	for col in width:
		var h := col_map[col]
		if h > 0:
			lo = mini(lo, h)
			hi = maxi(hi, h)
	return hi - lo > 3 or n < 0.7 * squad_reflow_n[s]


# Перестройка глубины: живые (колонка за колонкой по старым слотам) раздаются в новую сетку
# с пропорцией 20:15, колонка за колонкой; глубины колонок отличаются не больше чем на 1.
func _reflow_squad(s: int) -> void:
	_snapshot_slots(s)
	var width := squad_width[s]
	var rows := squad_rows[s]
	for k in rows * width:
		slot_owner[k] = -1
	for i in count:
		if unit_squad[i] == s:
			slot_owner[unit_slot_idx[i]] = i
	var n := 0
	for col in width:
		for row in rows:
			var i := slot_owner[row * width + col]
			if i != -1:
				reflow_order[n] = i
				n += 1
	if n == 0:
		return
	var new_width := clampi(ceili(sqrt(n * 20.0 / 15.0)), 1, 20)
	var base := n / new_width
	var extra := n % new_width
	var m := 0
	for col in new_width:
		for row in base + (1 if col < extra else 0):
			_set_line_slot(reflow_order[m], row * new_width + col, new_width)
			m += 1
	squad_width[s] = new_width
	squad_rows[s] = ceili(n / float(new_width))
	squad_reflow_n[s] = n
	_reanchor(s)
	_mark_slot_changes(s)


# Для раскраски F4: запомнить slot_idx юнитов отряда перед перестройкой...
func _snapshot_slots(s: int) -> void:
	for i in count:
		if unit_squad[i] == s:
			slot_idx_prev[i] = unit_slot_idx[i]


# ...и отметить время у тех, чей slot_idx после неё другой.
func _mark_slot_changes(s: int) -> void:
	var now := tick_counter / float(Engine.physics_ticks_per_second)
	for i in count:
		if unit_squad[i] == s and slot_idx_prev[i] != unit_slot_idx[i]:
			unit_slot_changed_t[i] = now


func _update_squads(delta: float) -> void:
	squad_compact_t += delta
	if squad_compact_t >= 0.5:
		for s in squad_count:
			if squad_dirty[s] == 1:
				_compact_squad(s)
				squad_dirty[s] = 0
			if _needs_reflow(s):
				_reflow_squad(s)
		squad_compact_t = 0.0
	for s in squad_count:
		var lead := squad_follow[s]
		if lead >= 0:
			# Ведомый отряд сам не поворачивается: угол копируется у ведущего. Если ведущий
			# развернулся «кругом», ведомый делает свой _about_face, чтобы слоты отразились на месте.
			if absf(angle_difference(squad_angle[s], squad_angle[lead])) > ABOUT_FACE_ANGLE:
				_about_face(s)
			squad_angle[s] = squad_angle[lead]
			squad_target[s] = _follow_target(s)
			# Досягаемость стрелков: расстояние от их центра до переднего ряда ведущего, первые 10 с до контакта.
			if squad_ranged[s] == 1 and first_death_tick < 0 and tick_counter <= 10 * Engine.physics_ticks_per_second:
				var to_front := (squad_pos[lead] - squad_pos[s]).dot(Vector2.from_angle(squad_angle[lead])) + squad_front_x[lead]
				reach_dist_sum += to_front
				reach_sum += type_range_far[squad_type[s]] - to_front
				reach_n += 1
			var to_f := squad_target[s] - squad_pos[s]
			var dist_f := to_f.length()
			if dist_f > maxf(squad_stop_dist[s], 1.0):
				squad_pos[s] += to_f / dist_f * minf(squad_speed[s] * delta, dist_f)
			continue
		var to := squad_target[s] - squad_pos[s]
		var dist := to.length()
		if dist <= maxf(squad_stop_dist[s], 1.0):   # нижний предел 1 px: без дёргания у цели
			continue
		var diff := angle_difference(squad_angle[s], to.angle())
		# Отряд не поворачивается к цели ближе 2 слотов (12 px).
		if dist > 2.0 * SLOT_SPACING:
			if absf(diff) > ABOUT_FACE_ANGLE:
				_about_face(s)
				diff = angle_difference(squad_angle[s], to.angle())
			squad_angle[s] += clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)
		if absf(diff) < MOVE_ANGLE:
			squad_pos[s] += to / dist * minf(squad_speed[s] * delta, dist)


func _about_face(s: int) -> void:
	# Разворот «кругом» вокруг центра живых слотов: squad_pos не двигается.
	# Ряды отражаются вокруг занятых рядов, колонки — вокруг занятых колонок, угол + PI.
	_compact_squad(s)
	var width := squad_width[s]
	var occ_rows := 0
	var col_lo := width
	var col_hi := -1
	for i in count:
		if unit_squad[i] == s:
			var k := unit_slot_idx[i]
			occ_rows = maxi(occ_rows, k / width + 1)
			col_lo = mini(col_lo, k % width)
			col_hi = maxi(col_hi, k % width)
	squad_angle[s] = wrapf(squad_angle[s] + PI, -PI, PI)
	if col_hi < 0:
		return   # пустой отряд
	_snapshot_slots(s)
	for i in count:
		if unit_squad[i] == s:
			var k := unit_slot_idx[i]
			var row := occ_rows - 1 - k / width
			var col := col_lo + col_hi - k % width
			unit_slot_idx[i] = row * width + col
			unit_slot[i] = -unit_slot[i]   # точное отражение: мировая позиция при угле + PI та же
	# Сетка отражена: _slot_vector(k') = -_slot_vector(k) + K, поэтому новое смещение центра = K - старое.
	var grid_k := Vector2(-(occ_rows - 1) * SLOT_SPACING, (col_lo + col_hi - (width - 1)) * SLOT_SPACING)
	squad_center_off[s] = grid_k - squad_center_off[s]
	squad_dirty[s] = 1   # короткие колонки сейчас у задней линии: подтянутся при ближайшем сжатии
	_mark_slot_changes(s)
	_update_squad_extent(s)

# --- Лучники ------------------------------------------------------------------

# Грубая сетка зомби (клетка COARSE_SIZE): counting sort, на клетку — число зомби и сумма позиций.
# Между пересчётами индексы в coarse_units могут устареть (swap-and-pop в _remove_dead),
# поэтому при чтении проверяется j < count и team[j] == 1, позиция берётся текущая.
func _rebuild_coarse() -> void:
	coarse_zcount.fill(0)
	coarse_sum.fill(Vector2.ZERO)
	for i in count:
		if team[i] != 1:
			coarse_cell_of[i] = -1
			continue
		var p := pos[i]
		var c := clampi(floori(p.x / COARSE_SIZE), 0, COARSE_W - 1) + clampi(floori(p.y / COARSE_SIZE), 0, COARSE_H - 1) * COARSE_W
		coarse_cell_of[i] = c
		coarse_zcount[c] += 1
		coarse_sum[c] += p
	var acc := 0
	for c in COARSE_COUNT:
		coarse_start[c] = acc
		coarse_cursor[c] = acc
		acc += coarse_zcount[c]
	coarse_start[COARSE_COUNT] = acc
	for i in count:
		var c := coarse_cell_of[i]
		if c >= 0:
			coarse_units[coarse_cursor[c]] = i
			coarse_cursor[c] += 1


# Ближайший живой зомби в 3x3 грубых клетках вокруг p, не дальше max_d; -1 если нет.
func _nearest_zombie_coarse(p: Vector2, max_d: float) -> int:
	var cx := clampi(floori(p.x / COARSE_SIZE), 0, COARSE_W - 1)
	var cy := clampi(floori(p.y / COARSE_SIZE), 0, COARSE_H - 1)
	var best := -1
	var best_d := max_d * max_d
	for ny in range(maxi(cy - 1, 0), mini(cy + 1, COARSE_H - 1) + 1):
		for nx in range(maxi(cx - 1, 0), mini(cx + 1, COARSE_W - 1) + 1):
			var c := nx + ny * COARSE_W
			for k in range(coarse_start[c], coarse_start[c + 1]):
				var j := coarse_units[k]
				if j >= count or team[j] != 1 or hp[j] <= 0.0:
					continue
				var d2 := p.distance_squared_to(pos[j])
				if d2 <= best_d:
					best_d = d2
					best = j
	return best


# Режим стрельбы по дистанции от прямоугольника живых слотов отряда до ближайшего зомби.
# Кандидаты — зомби из грубых клеток, перекрывающих прямоугольник с запасом. Гистерезис:
# ближе NEAR_RANGE — одиночный огонь, дальше NEAR_RANGE + MODE_HYST — залп, между — без смены.
func _update_archer_mode(s: int) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var n := 0
	for i in count:
		if unit_squad[i] == s:
			var q := unit_slot[i]
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
			n += 1
	if n == 0:
		return
	var reach := NEAR_RANGE + MODE_HYST
	var sp := squad_pos[s]
	var ang := squad_angle[s]
	var wlo := Vector2(INF, INF)
	var whi := Vector2(-INF, -INF)
	for corner in [Vector2(lo.x - reach, lo.y - reach), Vector2(hi.x + reach, lo.y - reach), Vector2(lo.x - reach, hi.y + reach), Vector2(hi.x + reach, hi.y + reach)]:
		var w: Vector2 = sp + corner.rotated(ang)
		wlo = Vector2(minf(wlo.x, w.x), minf(wlo.y, w.y))
		whi = Vector2(maxf(whi.x, w.x), maxf(whi.y, w.y))
	var d_min := INF
	for cy in range(clampi(floori(wlo.y / COARSE_SIZE), 0, COARSE_H - 1), clampi(floori(whi.y / COARSE_SIZE), 0, COARSE_H - 1) + 1):
		for cx in range(clampi(floori(wlo.x / COARSE_SIZE), 0, COARSE_W - 1), clampi(floori(whi.x / COARSE_SIZE), 0, COARSE_W - 1) + 1):
			var c := cx + cy * COARSE_W
			for k in range(coarse_start[c], coarse_start[c + 1]):
				var j := coarse_units[k]
				if j >= count or team[j] != 1:
					continue
				var local := (pos[j] - sp).rotated(-ang)
				var inside := Vector2(clampf(local.x, lo.x, hi.x), clampf(local.y, lo.y, hi.y))
				d_min = minf(d_min, local.distance_to(inside))
	var mode := squad_volley_mode[s]
	if d_min < NEAR_RANGE:
		mode = MODE_SINGLE
	elif d_min > NEAR_RANGE + MODE_HYST:
		mode = MODE_VOLLEY
	if mode != squad_volley_mode[s]:
		squad_volley_mode[s] = mode
		mode_switches += 1
		squad_volley_t[s] = 0.0   # залп после переключения начинается с натяжения
		squad_volley_fired[s] = 0


func _update_archers(delta: float) -> void:
	for s in squad_count:
		if squad_ranged[s] == 0:
			continue
		if squad_volley_mode[s] == MODE_SINGLE:
			_single_fire(s)
		else:
			_volley(s, delta)


# Одиночный огонь: каждый лучник раз в SINGLE_SCAN_T (сдвиг по индексу) ищет ближайшего
# зомби в 3x3 грубых клетках и стреляет, если готов его cooldown (общий с ближним боем).
func _single_fire(s: int) -> void:
	var scan := maxi(roundi(SINGLE_SCAN_T * Engine.physics_ticks_per_second), 1)
	for i in count:
		if unit_squad[i] != s or (tick_counter + i) % scan != 0 or cooldown[i] > 0.0:
			continue
		var t := unit_type[i]
		var j := _nearest_zombie_coarse(pos[i], type_range_far[t])
		if j == -1:
			continue
		_fire_arrow(i, pos[j], 0.0)
		cooldown[i] = type_cooldown[t]


# Залп: цикл draw (draw_time) -> fire -> reload до volley_period от начала цикла.
# Если в момент выстрела цели нет, цикл ждёт на этой точке.
func _volley(s: int, delta: float) -> void:
	var ut := squad_type[s]
	var t := squad_volley_t[s] + delta
	if squad_volley_fired[s] == 0:
		if t < type_draw_time[ut]:
			squad_volley_t[s] = t
			return
		var cell := _volley_target_cell(s, type_range_far[ut])
		if cell == -1:
			squad_volley_t[s] = type_draw_time[ut]   # ждём цель натянутыми
			return
		# Каждая стрела целится в случайного живого зомби этой клетки (тот же seeded-генератор, что для разброса).
		var c0 := coarse_start[cell]
		var cn := coarse_start[cell + 1] - c0
		for i in count:
			if unit_squad[i] == s:
				var j := _random_zombie_in_cell(c0, cn)
				if j != -1:
					_fire_arrow(i, pos[j], (unit_rand[i] * 2.0 - 1.0) * VOLLEY_JITTER)
		squad_volley_fired[s] = 1
		squad_volley_t[s] = t
	elif t >= type_volley_period[ut]:
		squad_volley_t[s] = 0.0   # перезарядка закончилась: новый цикл с натяжения
		squad_volley_fired[s] = 0
	else:
		squad_volley_t[s] = t


# Самая плотная грубая клетка, центр которой (геометрический) не дальше range_far от центра отряда; -1 если нет.
func _volley_target_cell(s: int, range_far: float) -> int:
	var sp := squad_pos[s]
	var best := -1
	var best_n := 0
	for cy in range(clampi(floori((sp.y - range_far) / COARSE_SIZE), 0, COARSE_H - 1), clampi(floori((sp.y + range_far) / COARSE_SIZE), 0, COARSE_H - 1) + 1):
		for cx in range(clampi(floori((sp.x - range_far) / COARSE_SIZE), 0, COARSE_W - 1), clampi(floori((sp.x + range_far) / COARSE_SIZE), 0, COARSE_W - 1) + 1):
			var c := cx + cy * COARSE_W
			var cn := coarse_zcount[c]
			var center := Vector2((cx + 0.5) * COARSE_SIZE, (cy + 0.5) * COARSE_SIZE)
			if cn > best_n and center.distance_to(sp) <= range_far:
				best_n = cn
				best = c
	return best


# Случайный живой зомби из списка грубой клетки [c0, c0 + cn). Индексы могли устареть после
# _remove_dead: если выпал неживой или не зомби, берём следующего по кругу; никого — -1.
func _random_zombie_in_cell(c0: int, cn: int) -> int:
	if cn <= 0:
		return -1
	var start := arrow_rng.randi_range(0, cn - 1)
	for q in cn:
		var j := coarse_units[c0 + (start + q) % cn]
		if j < count and team[j] == 1 and hp[j] > 0.0:
			return j
	return -1


# Стрела-событие: точка падения = прицел + разброс (радиус spread * дистанция, seeded-генератор),
# тик падения = сейчас + задержка + дистанция / ARROW_SPEED.
func _fire_arrow(i: int, aim: Vector2, delay: float) -> void:
	if arrow_count >= ARROW_CAP:
		arrows_dropped += 1
		return
	var t := unit_type[i]
	var dist := pos[i].distance_to(aim)
	var land := aim + Vector2.from_angle(arrow_rng.randf() * TAU) * (type_spread[t] * dist * sqrt(arrow_rng.randf()))
	var ticks := roundi((delay + pos[i].distance_to(land) / ARROW_SPEED) * Engine.physics_ticks_per_second)
	arrow_land[arrow_count] = land
	arrow_tick[arrow_count] = tick_counter + maxi(ticks, 1)
	arrow_dmg[arrow_count] = type_arrow_dmg[t]
	arrow_count += 1
	arrows_fired += 1


# Падение стрел этого тика: урон ближайшему живому зомби в ARROW_HIT_R (мелкая сетка, 3x3), иначе промах.
# Дружественного огня нет. Очередь — swap-and-pop.
func _process_arrows() -> void:
	var a := 0
	while a < arrow_count:
		if arrow_tick[a] > tick_counter:
			a += 1
			continue
		var p := arrow_land[a]
		var cx := clampi(floori(p.x / CELL_SIZE), 0, GRID_W - 1)
		var cy := clampi(floori(p.y / CELL_SIZE), 0, GRID_H - 1)
		var best := -1
		var best_d := ARROW_HIT_R * ARROW_HIT_R
		for ny in range(maxi(cy - 1, 0), mini(cy + 1, GRID_H - 1) + 1):
			for nx in range(maxi(cx - 1, 0), mini(cx + 1, GRID_W - 1) + 1):
				var c := nx + ny * GRID_W
				for k in range(cell_start[c], cell_start[c + 1]):
					var j := sorted_units[k]
					if team[j] != 1 or hp[j] <= 0.0:
						continue
					var d2 := p.distance_squared_to(pos[j])
					if d2 <= best_d:
						best_d = d2
						best = j
		if best != -1:
			hp[best] -= arrow_dmg[a]
			arrows_hit += 1
		arrow_count -= 1
		arrow_land[a] = arrow_land[arrow_count]
		arrow_tick[a] = arrow_tick[arrow_count]
		arrow_dmg[a] = arrow_dmg[arrow_count]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		squad_target[0] = get_global_mouse_position()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				color_mode = 0
			KEY_F2, KEY_F3, KEY_F4:
				if DEBUG_COLORS:
					color_mode = event.keycode - KEY_F1
