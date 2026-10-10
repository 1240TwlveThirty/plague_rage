extends RefCounted
# Вариант C2 = C + решение и движение развязаны: _update_unit (половина юнитов) пишет vel,
# _move_units двигает всех юнитов каждый тик. Толчок — разовый сдвиг при решении.
# Основа — вариант C: за тик обновляется половина юнитов (чётные / нечётные по очереди).
# Движение и перезарядка получают 2*delta, урон за удар прежний.
# Внутренний цикл как в B6:
# distance_squared_to вместо off + length_squared, ранний continue для d2 > VIEW^2,
# без проверки j == i. Бит-в-бит с A не совпадает: меняется шаг по времени.

const SPEED := 60.0
const CELL_SIZE := 12.0
const GRID_W := 170
const GRID_H := 86
const CELL_COUNT := GRID_W * GRID_H
const MIN_DIST := 5.0
const ATTACK_RANGE := 7.0
const PUSH_K := 0.5
const UNIT_HP := 3.0
const ATTACK_DAMAGE := 1.0
const ATTACK_COOLDOWN := 0.8
const VIEW_RANGE := 12.0
# Толчок снимает 50% перекрытия за обновление. Два обновления A оставляют 25%,
# поэтому при обновлении раз в 2 тика снимаем 1 - 0.5^2 = 75%.
const PUSH_K_2 := 1.0 - (1.0 - PUSH_K) * (1.0 - PUSH_K)
const FIELD := Vector2(GRID_W * CELL_SIZE, GRID_H * CELL_SIZE)   # 2040 x 1032

var pos := PackedVector2Array()
var vel := PackedVector2Array()
var team := PackedByteArray()
var cell_of := PackedInt32Array()
var cell_start := PackedInt32Array()
var cursor := PackedInt32Array()
var sorted_units := PackedInt32Array()
var hp := PackedFloat32Array()
var cooldown := PackedFloat32Array()
var tick_no := 0
var count := 0


func setup(n: int, rng_seed: int) -> void:
	count = n
	pos.resize(n)
	team.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var half := n / 2
	for i in n:
		var p: Vector2
		if i < half:
			team[i] = 0
			p = Vector2(100 + (i % 25) * 6, 100 + floori(i / 25.0) * 6)
		else:
			var j := i - half
			team[i] = 1
			p = Vector2(1000 - (j % 25) * 6, 100 + floori(j / 25.0) * 6)
		pos[i] = p + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	cell_of.resize(n)
	sorted_units.resize(n)
	cell_start.resize(CELL_COUNT + 1)
	cursor.resize(CELL_COUNT)
	hp.resize(n)
	hp.fill(UNIT_HP)
	cooldown.resize(n)
	cooldown.fill(0.0)
	vel.resize(n)
	vel.fill(Vector2.ZERO)


func tick(delta: float) -> void:
	_build_grid()
	# Каждый тик обновляется половина юнитов: чётные индексы, затем нечётные.
	# Направление прохода чередуется раз в 2 тика, чтобы каждая половина
	# по очереди шла и вперёд, и назад (аналог tick_parity в A).
	var half := tick_no % 2
	var fwd := (tick_no / 2) % 2 == 0
	tick_no += 1
	var dt2 := delta * 2.0   # юнит обновляется раз в 2 тика
	if fwd:
		for i in range(half, count, 2):
			_update_unit(i, dt2)
	else:
		var last := count - 1
		if (last - half) % 2 != 0:
			last -= 1
		for i in range(last, -1, -2):
			_update_unit(i, dt2)
	_move_units(delta)
	_remove_dead()

func alive(t: int) -> int:
	var n := 0
	for i in count:
		if team[i] == t:
			n += 1
	return n


func _update_unit(i: int, delta: float) -> void:
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

	var v := Vector2.ZERO
	if best != -1:
		if best_d > ATTACK_RANGE * ATTACK_RANGE:
			v = (pos[best] - p).normalized() * SPEED
		elif cooldown[i] <= 0.0:
			hp[best] -= ATTACK_DAMAGE
			cooldown[i] = ATTACK_COOLDOWN
	else:
		v.x = (1.0 if my_team == 0 else -1.0) * SPEED
	vel[i] = v
	cooldown[i] = maxf(cooldown[i] - delta, 0.0)
	pos[i] = (p + push * PUSH_K_2).clamp(Vector2.ZERO, FIELD)


func _move_units(delta: float) -> void:
	for i in count:
		pos[i] = (pos[i] + vel[i] * delta).clamp(Vector2.ZERO, FIELD)


func _remove_dead() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0.0:
			count -= 1
			pos[i] = pos[count]
			vel[i] = vel[count]
			team[i] = team[count]
			hp[i] = hp[count]
			cooldown[i] = cooldown[count]
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
