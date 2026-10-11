extends RefCounted
# ПРОФИЛЬ (не для замеров): копия A с подсчётом итераций и временем по фазам.
# Единственное добавление: позиция после хода зажимается в границы поля (FIELD).

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
const FIELD := Vector2(GRID_W * CELL_SIZE, GRID_H * CELL_SIZE)   # 2040 x 1032

var pos := PackedVector2Array()
var team := PackedByteArray()
var cell_of := PackedInt32Array()
var cell_start := PackedInt32Array()
var cursor := PackedInt32Array()
var sorted_units := PackedInt32Array()
var hp := PackedFloat32Array()
var cooldown := PackedFloat32Array()
var tick_parity := false
var count := 0
var iters := 0
var hits := 0
var grid_us := 0
var upd_us := 0


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


func tick(delta: float) -> void:
	iters = 0
	hits = 0
	var t0 := Time.get_ticks_usec()
	_build_grid()
	var t1 := Time.get_ticks_usec()
	grid_us = t1 - t0
	tick_parity = not tick_parity
	if tick_parity:
		for i in count:
			_update_unit(i, delta)
	else:
		for i in range(count - 1, -1, -1):
			_update_unit(i, delta)
	upd_us = Time.get_ticks_usec() - t1
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
				iters += 1
				if j == i:
					continue
				var off := p - pos[j]
				var d2 := off.length_squared()
				if d2 <= VIEW_RANGE * VIEW_RANGE:
					hits += 1
				if d2 < MIN_DIST * MIN_DIST and d2 > 0.0001:
					var d := sqrt(d2)
					push += off / d * (MIN_DIST - d)
				if team[j] != my_team and d2 < best_d and d2 <= VIEW_RANGE * VIEW_RANGE:
					best_d = d2
					best = j

	var move := Vector2.ZERO
	if best != -1:
		if best_d > ATTACK_RANGE * ATTACK_RANGE:
			move = (pos[best] - p).normalized() * SPEED * delta
		elif cooldown[i] <= 0.0:
			hp[best] -= ATTACK_DAMAGE
			cooldown[i] = ATTACK_COOLDOWN
	else:
		move.x = (1.0 if my_team == 0 else -1.0) * SPEED * delta
	cooldown[i] = maxf(cooldown[i] - delta, 0.0)
	pos[i] = (p + move + push * PUSH_K).clamp(Vector2.ZERO, FIELD)   # граница поля


func _remove_dead() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0.0:
			count -= 1
			pos[i] = pos[count]
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
