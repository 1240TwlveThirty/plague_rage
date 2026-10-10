extends RefCounted
# Вариант B5 = B4 + _build_grid и _remove_dead на локальных массивах,
# клетка и подсчёт в одном проходе, префиксная сумма без повторного чтения.
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
const FIELD_W := GRID_W * CELL_SIZE
const FIELD_H := GRID_H * CELL_SIZE
const MIN_D2 := MIN_DIST * MIN_DIST
const VIEW_D2 := VIEW_RANGE * VIEW_RANGE
const ATTACK_D2 := ATTACK_RANGE * ATTACK_RANGE

var px := PackedFloat32Array()
var py := PackedFloat32Array()
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
	px.resize(n)
	py.resize(n)
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
		p += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		px[i] = p.x
		py[i] = p.y
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
	var X := px
	var Y := py
	var T := team
	var HP := hp
	var CD := cooldown
	var CS := cell_start
	var SU := sorted_units
	px = PackedFloat32Array()
	py = PackedFloat32Array()
	hp = PackedFloat32Array()
	cooldown = PackedFloat32Array()
	var step_len := SPEED * delta
	for step in n:
		var i := step if fwd else n - 1 - step
		var my_team := T[i]
		var x := X[i]
		var y := Y[i]
		var cx := clampi(floori(x / CELL_SIZE), 0, GRID_W - 1)
		var cy := clampi(floori(y / CELL_SIZE), 0, GRID_H - 1)
		var best := -1
		var best_d := INF
		var push_x := 0.0
		var push_y := 0.0

		# Клетки nx-1..nx+1 одной строки лежат в sorted_units подряд:
		# один диапазон на строку вместо трёх. Порядок обхода тот же, что в A.
		var nx0 := maxi(cx - 1, 0)
		var nx1 := mini(cx + 1, GRID_W - 1) + 1
		for ny in range(maxi(cy - 1, 0), mini(cy + 1, GRID_H - 1) + 1):
			var row := ny * GRID_W
			for k in range(CS[row + nx0], CS[row + nx1]):
				var j := SU[k]
				if j == i:
					continue
				var ox := x - X[j]
				var oy := y - Y[j]
				var d2 := ox * ox + oy * oy
				if d2 < MIN_D2 and d2 > 0.0001:
					var d := sqrt(d2)
					var f := (MIN_DIST - d) / d
					push_x += ox * f
					push_y += oy * f
				if T[j] != my_team and d2 < best_d and d2 <= VIEW_D2:
					best_d = d2
					best = j

		var mx := 0.0
		var my := 0.0
		if best != -1:
			if best_d > ATTACK_D2:
				var dx := X[best] - x
				var dy := Y[best] - y
				var s := step_len / sqrt(dx * dx + dy * dy)
				mx = dx * s
				my = dy * s
			elif CD[i] <= 0.0:
				HP[best] -= ATTACK_DAMAGE
				CD[i] = ATTACK_COOLDOWN
		else:
			mx = step_len if my_team == 0 else -step_len
		CD[i] = maxf(CD[i] - delta, 0.0)
		X[i] = clampf(x + mx + push_x * PUSH_K, 0.0, FIELD_W)
		Y[i] = clampf(y + my + push_y * PUSH_K, 0.0, FIELD_H)
	px = X
	py = Y
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
	var X := px
	var Y := py
	var T := team
	var HP := hp
	var CD := cooldown
	px = PackedFloat32Array()
	py = PackedFloat32Array()
	team = PackedByteArray()
	hp = PackedFloat32Array()
	cooldown = PackedFloat32Array()
	var n := count
	var i := 0
	while i < n:
		if HP[i] <= 0.0:
			n -= 1
			X[i] = X[n]
			Y[i] = Y[n]
			T[i] = T[n]
			HP[i] = HP[n]
			CD[i] = CD[n]
		else:
			i += 1
	count = n
	px = X
	py = Y
	team = T
	hp = HP
	cooldown = CD


func _build_grid() -> void:
	var X := px
	var Y := py
	var CO := cell_of
	var CS := cell_start
	var CU := cursor
	var SU := sorted_units
	cell_of = PackedInt32Array()
	cell_start = PackedInt32Array()
	cursor = PackedInt32Array()
	sorted_units = PackedInt32Array()
	var n := count
	CS.fill(0)
	# клетка юнита и подсчёт по клеткам в одном проходе
	for i in n:
		var c := clampi(floori(X[i] / CELL_SIZE), 0, GRID_W - 1) + clampi(floori(Y[i] / CELL_SIZE), 0, GRID_H - 1) * GRID_W
		CO[i] = c
		CS[c + 1] += 1
	var acc := 0
	for c in CELL_COUNT:
		CU[c] = acc
		acc += CS[c + 1]
		CS[c + 1] = acc
	for i in n:
		var c := CO[i]
		SU[CU[c]] = i
		CU[c] += 1
	cell_of = CO
	cell_start = CS
	cursor = CU
	sorted_units = SU