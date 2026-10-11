extends RefCounted
# Вариант B2 = B1 + массивы в горячем цикле через локальные переменные.
# Записываемые массивы (pos, hp, cooldown) на время цикла отвязываются от полей,
# иначе первая запись в локальную копию запустила бы copy-on-write всего массива.

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
	_build_grid()
	tick_parity = not tick_parity
	var fwd := tick_parity
	var n := count
	var P := pos
	var T := team
	var HP := hp
	var CD := cooldown
	var CS := cell_start
	var SU := sorted_units
	pos = PackedVector2Array()
	hp = PackedFloat32Array()
	cooldown = PackedFloat32Array()
	for step in n:
		var i := step if fwd else n - 1 - step
		var my_team := T[i]
		var p := P[i]
		var cx := clampi(floori(p.x / CELL_SIZE), 0, GRID_W - 1)
		var cy := clampi(floori(p.y / CELL_SIZE), 0, GRID_H - 1)
		var best := -1
		var best_d := INF
		var push := Vector2.ZERO

		for ny in range(maxi(cy - 1, 0), mini(cy + 1, GRID_H - 1) + 1):
			for nx in range(maxi(cx - 1, 0), mini(cx + 1, GRID_W - 1) + 1):
				var c := nx + ny * GRID_W
				for k in range(CS[c], CS[c + 1]):
					var j := SU[k]
					if j == i:
						continue
					var off := p - P[j]
					var d2 := off.length_squared()
					if d2 < MIN_DIST * MIN_DIST and d2 > 0.0001:
						var d := sqrt(d2)
						push += off / d * (MIN_DIST - d)
					if T[j] != my_team and d2 < best_d and d2 <= VIEW_RANGE * VIEW_RANGE:
						best_d = d2
						best = j

		var move := Vector2.ZERO
		if best != -1:
			if best_d > ATTACK_RANGE * ATTACK_RANGE:
				move = (P[best] - p).normalized() * SPEED * delta
			elif CD[i] <= 0.0:
				HP[best] -= ATTACK_DAMAGE
				CD[i] = ATTACK_COOLDOWN
		else:
			move.x = (1.0 if my_team == 0 else -1.0) * SPEED * delta
		CD[i] = maxf(CD[i] - delta, 0.0)
		P[i] = (p + move + push * PUSH_K).clamp(Vector2.ZERO, FIELD)
	pos = P
	hp = HP
	cooldown = CD
	_remove_dead()


func alive(t: int) -> int:
	var n := 0
	for i in count:
		if team[i] == t:
			n += 1
	return n


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
