extends SceneTree
# Headless-тест баланса. Копия логики боя из main.gd (без рендера) + переключатели вариантов.
# Запуск:
#   godot --headless --path . --script res://scripts/test_sim.gd -- <вариант> [seed_from] [seed_to]
# Варианты: A B C D E F FB FE
#   FB = двойной буфер + красные первыми (проверка независимости от порядка)
#   FE = двойной буфер + сдвиг 6 px (проверка влияния сетки без эффекта порядка)

const DELTA := 1.0 / 60.0
const MAX_TICKS := 36000   # 10 минут симуляции на бой
const STALL_TICKS := 600   # 10 с без единой смерти = бой окончен


class Sim:
	const UNIT_COUNT := 1000
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
	const VIEW_RANGE := 12.0   # = CELL_SIZE, как в main.gd

	var pos := PackedVector2Array()
	var team := PackedByteArray()
	var cell_of := PackedInt32Array()
	var cell_start := PackedInt32Array()
	var cursor := PackedInt32Array()
	var sorted_units := PackedInt32Array()
	var hp := PackedFloat32Array()
	var cooldown := PackedFloat32Array()
	var tick_parity := false
	var count := UNIT_COUNT

	# --- переключатели теста ---
	var order_mode := "alt"   # alt = как в main.gd, fwd = только прямой, rev = только обратный
	var double_buf := false
	var pos_next := PackedVector2Array()
	var dmg := PackedFloat32Array()

	func setup(rng_seed: int, red_first: bool, x_shift: float) -> void:
		pos.resize(UNIT_COUNT)
		team.resize(UNIT_COUNT)
		var half := UNIT_COUNT / 2
		# Сдвиг генерируем по "слотам армии" в одном и том же порядке,
		# чтобы при одном seed геометрия A и B была одинаковой.
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed
		var slot_pos := PackedVector2Array()
		slot_pos.resize(UNIT_COUNT)
		for s in UNIT_COUNT:
			var p: Vector2
			if s < half:
				p = Vector2(100 + (s % 25) * 6, 100 + floori(s / 25.0) * 6)
			else:
				var j := s - half
				p = Vector2(1000 - (j % 25) * 6, 100 + floori(j / 25.0) * 6)
			p += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			p.x += x_shift
			slot_pos[s] = p
		for i in UNIT_COUNT:
			var s := (i + half) % UNIT_COUNT if red_first else i
			team[i] = 0 if s < half else 1
			pos[i] = slot_pos[s]
		cell_of.resize(UNIT_COUNT)
		sorted_units.resize(UNIT_COUNT)
		cell_start.resize(CELL_COUNT + 1)
		cursor.resize(CELL_COUNT)
		hp.resize(UNIT_COUNT)
		hp.fill(UNIT_HP)
		cooldown.resize(UNIT_COUNT)
		cooldown.fill(0.0)
		pos_next.resize(UNIT_COUNT)
		dmg.resize(UNIT_COUNT)
		dmg.fill(0.0)

	func tick(delta: float) -> void:
		_build_grid()
		tick_parity = not tick_parity
		var forward := tick_parity
		if order_mode == "fwd":
			forward = true
		elif order_mode == "rev":
			forward = false
		if forward:
			for i in count:
				_update_unit(i, delta)
		else:
			for i in range(count - 1, -1, -1):
				_update_unit(i, delta)
		if double_buf:
			for i in count:
				hp[i] -= dmg[i]
				dmg[i] = 0.0
			var tmp := pos
			pos = pos_next
			pos_next = tmp
		_remove_dead()

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
					if j == i:
						continue
					var off := p - pos[j]
					var d2 := off.length_squared()
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
				if double_buf:
					dmg[best] += ATTACK_DAMAGE
				else:
					hp[best] -= ATTACK_DAMAGE
				cooldown[i] = ATTACK_COOLDOWN
		else:
			move.x = (1.0 if my_team == 0 else -1.0) * SPEED * delta
		cooldown[i] = maxf(cooldown[i] - delta, 0.0)
		if double_buf:
			pos_next[i] = p + move + push * PUSH_K
		else:
			pos[i] = p + move + push * PUSH_K

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

	func alive(t: int) -> int:
		var n := 0
		for i in count:
			if team[i] == t:
				n += 1
		return n


func _run_battle(variant: String, rng_seed: int) -> String:
	var sim := Sim.new()
	var red_first := variant == "B" or variant == "FB"
	var x_shift := 6.0 if variant == "E" or variant == "FE" else 0.0
	match variant:
		"C":
			sim.order_mode = "fwd"
		"D":
			sim.order_mode = "rev"
		"F", "FB", "FE":
			sim.order_mode = "fwd"
			sim.double_buf = true
	sim.setup(rng_seed, red_first, x_shift)
	var ticks := 0
	var blue := 0
	var red := 0
	var last_count := sim.count
	var last_death_tick := 0
	var stalled := false
	while ticks < MAX_TICKS:
		sim.tick(DELTA)
		ticks += 1
		blue = sim.alive(0)
		red = sim.alive(1)
		if sim.count != last_count:
			last_count = sim.count
			last_death_tick = ticks
		elif ticks - last_death_tick >= STALL_TICKS:
			stalled = true
			break
		if trace and ticks % 300 == 0:
			var xs := PackedFloat32Array()
			for i in sim.count:
				xs.append(sim.pos[i].x)
			xs.sort()
			print("  t=%d blue=%d red=%d x_min=%.0f x_max=%.0f" % [ticks, blue, red, xs[0], xs[xs.size() - 1]])
		if blue == 0 or red == 0:
			break
	# Победитель = у кого больше живых. end: wipe = одна сторона уничтожена,
	# stall = 10 с без смертей (остатки разошлись), cap = упёрлись в MAX_TICKS.
	var winner := "draw"
	if blue > red:
		winner = "blue"
	elif red > blue:
		winner = "red"
	var end := "wipe" if (blue == 0 or red == 0) else ("stall" if stalled else "cap")
	return "%s,%d,%s,%s,%d,%d,%d" % [variant, rng_seed, winner, end, blue, red, ticks]


var trace := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	trace = args.has("trace")
	var variant := args[0] if args.size() > 0 else "A"
	var seed_from := int(args[1]) if args.size() > 1 else 1
	var seed_to := int(args[2]) if args.size() > 2 else 50
	for s in range(seed_from, seed_to + 1):
		print(_run_battle(variant, s))
	quit()
