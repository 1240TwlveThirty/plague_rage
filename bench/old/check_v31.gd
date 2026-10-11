extends SceneTree
# Тесты v31: (а) регрессия против bak30 при ARCHER_OWN_RANGE = false, (в) стопка кликом, (г) движущийся отряд,
# (е) детерминизм.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/old/main_bak30.gd"

func new_main(path: String, seed: int, waves: bool) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func slot_world(m: Node2D, i: int) -> Vector2:
	var s: int = m.unit_squad[i]
	return m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])

func teleport(m: Node2D, s: int) -> void:
	for i in m.count:
		if m.unit_squad[i] == s:
			m.pos[i] = slot_world(m, i)
			m.prev_pos[i] = m.pos[i]

func compare(waves: bool) -> String:
	var a := new_main(OLD, 1, waves)
	var b := new_main(NEW, 1, waves)
	var first := -1
	var ticks := 0
	var limit := 900
	if waves:
		limit = 6000
	for t in range(1, limit + 1):
		if waves and a.wave_state == a.WS_RESPITE:
			if a.wave_number == 3:
				break
			for m in [a, b]:
				m._buy(0)
				m._buy(1)
				m._start_wave()
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		ticks = t
		if first < 0:
			if a.count != b.count or a.gate_hp != b.gate_hp or a.gold != b.gold or a.arrows_fired != b.arrows_fired or a.arrows_hit != b.arrows_hit or a.wave_state != b.wave_state:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.unit_slot_idx[i] != b.unit_slot_idx[i]:
						first = t
						break
	var res := ("совпадает на всех %d тиках" % ticks if first < 0 else "расходится с тика %d" % first) + " (юнитов %d, пройдено волн %d, флаг дальности %s, отменено по дальности %d)" % [
		b.count, b.wave_number if b.wave_state == b.WS_RESPITE else b.wave_number - 1, b.archer_own_range, b.arrows_out_of_range]
	a.free()
	b.free()
	return res

# 7 отрядов лучников по 25 (строй 5 × 5, блок 30 × 30 px), расставлены порознь в ряд.
func build7(m: Node2D) -> Array:
	var ids := []
	for i in m.count:
		if m.unit_squad[i] == 1:
			ids.append(i)
	for q in range(25, ids.size()):
		m.hp[ids[q]] = 0.0
	m._remove_dead()
	m._update_squads(0.6)
	var squads := [1]
	for k in 6:
		var s: int = m._squad_create(1)
		m._squad_add_units(s, m.archer_type, 25)
		squads.append(s)
	var k := 0
	for s in squads:
		m.squad_user_width[s] = 5
		m._reflow_squad(s)
		m.squad_angle[s] = -PI / 2.0
		m.squad_pos[s] = Vector2(300 + k * 120, 300)
		m.squad_target[s] = m.squad_pos[s]
		teleport(m, s)
		k += 1
	return squads

# Сколько лучников (любых отрядов) стоит не дальше radius от точки.
func near(m: Node2D, centre: Vector2, radius: float) -> int:
	var n := 0
	for i in m.count:
		if m.unit_type[i] == m.archer_type and m.pos[i].distance_to(centre) <= radius:
			n += 1
	return n

# Тики, пока все отряды из списка не дойдут до целей (и ещё 2 с на построение).
func march(m: Node2D, squads: Array) -> void:
	for t in 3000:
		var arrived := true
		for s in squads:
			arrived = arrived and m.squad_pos[s].distance_to(m.squad_target[s]) <= 1.0
		if arrived:
			break
		m._physics_process(1.0 / 30.0)
	for t in 60:
		m._physics_process(1.0 / 30.0)

func test_stack() -> void:
	var p := Vector2(1000, 420)
	for mode in ["в одну точку", "в точки в пределах 20 px"]:
		var m := new_main(NEW, 1, true)
		var squads := build7(m)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var home := {}
		var res := []
		var msg_ok := true
		for s in squads:
			home[s] = m.squad_pos[s]
			var target := p
			if mode != "в одну точку" and s != squads[0]:
				target = p + Vector2.from_angle(rng.randf() * TAU) * 20.0 * sqrt(rng.randf())
			m.hud_msg = ""
			var done: bool = m._cmd_move(s, target)
			res.append(done)
			if not done:
				msg_ok = msg_ok and m.hud_msg == "Блок пересекается с отрядом %d" % (squads[0] + 1) and is_equal_approx(m.hud_msg_t, 2.0) and m.squad_target[s] == home[s]
		march(m, squads)
		var stayed := true
		for s in squads.slice(1):
			stayed = stayed and m.squad_pos[s] == home[s] and m.squad_target[s] == home[s]
			for i in m.count:
				if m.unit_squad[i] == s:
					stayed = stayed and m.pos[i].distance_to(slot_world(m, i)) < 1.0
		var ok: bool = res == [true, false, false, false, false, false, false] and msg_ok and stayed and m.squad_pos[squads[0]].distance_to(p) <= 1.0
		print("(в) 7 отрядов по 25 лучников, клик %s: приняты %s; сообщение и цель на месте у отказанных: %s; отказанные не двинулись: %s; в радиусе 30 px от пришедшего отряда лучников: %d (один отряд = 25): %s" % [
			mode, res, msg_ok, stayed, near(m, m.squad_pos[squads[0]], 30.0), ok and near(m, m.squad_pos[squads[0]], 30.0) == 25])
		if mode == "в одну точку":
			# касание вплотную и свободное место
			var t1: bool = m._cmd_move(squads[1], p + Vector2(30, 0))    # сбоку вплотную: блоки 30 × 30 касаются
			var t2: bool = m._cmd_move(squads[2], p + Vector2(0, 30))    # сзади вплотную
			var t3: bool = m._cmd_move(squads[3], p + Vector2(16, 0))    # половина блока: отказ
			var t4: bool = m._cmd_move(squads[4], Vector2(1500, 300))    # свободное место
			var t5: bool = m._cmd_move(squads[5], p + Vector2(30, 8))    # поверх отряда, идущего в точку сбоку: отказ
			march(m, squads)
			print("    вплотную сбоку: %s, вплотную сзади: %s, со сдвигом в полблока: %s, свободное место: %s, на цель идущего отряда: %s; после прихода в радиусе 70 px от точки лучников: %d (три отряда = 75)" % [
				"принят" if t1 else "отказ", "принят" if t2 else "отказ", "принят" if t3 else "отказ", "принят" if t4 else "отказ", "принят" if t5 else "отказ",
				near(m, p, 70.0)])
		m.free()

func test_moving() -> void:
	var m := new_main(NEW, 1, true)
	var squads := build7(m)
	var a: int = squads[1]
	var b: int = squads[0]
	var t := Vector2(900, 420)
	var b_home: Vector2 = m.squad_pos[b]
	var out := []
	var ok: bool = m._cmd_move(b, t)   # B пошёл к T
	for q in 30:
		m._physics_process(1.0 / 30.0)
	var moving: bool = m.squad_pos[b].distance_to(t) > 50.0
	var click1: bool = m._cmd_move(a, t + Vector2(5, 5))
	var g1: Dictionary = m._formation_geometry(a, t + Vector2(-12, -12), t + Vector2(12, -12))
	var old_spot: bool = m._cmd_move(squads[2], b_home)   # место, откуда B ушёл, свободно
	out.append("B идёт (до цели %.0f px): клик A на его цель — %s, перетаскивание — %s; клик на место, откуда B ушёл, — %s" % [
		m.squad_pos[b].distance_to(t), "принят" if click1 else "отказ", "отказ (отряд %d)" % (g1.overlap + 1) if g1.overlap >= 0 else "принято", "принят" if old_spot else "отказ"])
	ok = ok and moving and not click1 and g1.overlap == b and old_spot
	var ticks := 0
	while m.squad_pos[b].distance_to(m.squad_target[b]) > 1.0 and ticks < 3000:
		m._physics_process(1.0 / 30.0)
		ticks += 1
	for q in 60:
		m._physics_process(1.0 / 30.0)
	var click2: bool = m._cmd_move(a, t + Vector2(5, 5))
	var g2: Dictionary = m._formation_geometry(a, t + Vector2(-12, -12), t + Vector2(12, -12))
	out.append("B пришёл и стоит (через %.1f с): клик A — %s, перетаскивание — %s" % [ticks / 30.0, "принят" if click2 else "отказ", "отказ (отряд %d)" % (g2.overlap + 1) if g2.overlap >= 0 else "принято"])
	ok = ok and not click2 and g2.overlap == b and m.squad_target[a] == m.squad_pos[a]
	# рядом с пришедшим B — и клик, и перетаскивание проходят
	var click3: bool = m._cmd_move(a, m.squad_pos[b] + Vector2(30, 0))
	var g3: Dictionary = m._formation_geometry(squads[3], m.squad_pos[b] + Vector2(-42, -12), m.squad_pos[b] + Vector2(-18, -12))
	out.append("вплотную к B: клик — %s, перетаскивание с другой стороны — %s" % ["принят" if click3 else "отказ", "принято" if g3.overlap == -1 else "отказ"])
	ok = ok and click3 and g3.overlap == -1
	print("(г) движущийся отряд: %s; клик и перетаскивание ведут себя одинаково: %s" % ["; ".join(out), ok])
	m.free()

func scripted(seed: int) -> PackedVector2Array:
	var m := new_main(NEW, seed, true)
	var tr := PackedVector2Array()
	var moves := []
	m._start_wave()
	for t in 900:
		match t:
			10:
				moves.append(m._cmd_move(1, Vector2(1010, 600)))   # лучники на блок пехоты: отказ
			20:
				moves.append(m._cmd_move(1, Vector2(1160, 640)))   # рядом: принят
			200:
				moves.append(m._cmd_move(0, Vector2(1150, 640)))   # пехота на лучников: отказ
			260:
				moves.append(m._cmd_move(0, Vector2(980, 560)))
		m._physics_process(1.0 / 30.0)
		var c := Vector2(m.count, m.arrows_fired)
		for i in m.count:
			c += m.pos[i] * (1.0 + (i % 7)) + Vector2(m.hp[i], 0.0)
		tr.append(c)
	tr.append(Vector2(int(moves[0]) + 2 * int(moves[1]) + 4 * int(moves[2]) + 8 * int(moves[3]), m.count))
	m.free()
	return tr

func test_determinism() -> void:
	var r1 := scripted(4)
	var r2 := scripted(4)
	var code := int(r1[r1.size() - 1].x)
	print("(е) 30 с, волна 1 с кликами (отказ, принят, отказ, принят: %s), два прогона seed 4: %s" % [code == 10, "совпадает на каждом тике" if r1 == r2 else "РАСХОДИТСЯ"])

func _initialize() -> void:
	print("(а) против bak30, waves off: " + compare(false))
	print("    с волнами и покупками, 3 волны: " + compare(true))
	test_stack()
	test_moving()
	test_determinism()
	quit()
