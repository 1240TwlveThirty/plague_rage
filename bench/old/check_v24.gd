extends SceneTree
func new_main(seed: int) -> Node2D:
	var m: Node2D = load("res://scripts/main.gd").new()
	m.spawn_seed = seed
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func alive_of(m: Node2D, s: int) -> int:
	var n := 0
	for i in m.count:
		if m.unit_squad[i] == s:
			n += 1
	return n

func max_slot_y(m: Node2D, s: int, anchor: Vector2) -> float:
	var y := -INF
	for i in m.count:
		if m.unit_squad[i] == s:
			y = maxf(y, (anchor + m.unit_slot[i].rotated(m.squad_angle[s])).y)
	return y

func run_waves(seed: int) -> PackedVector2Array:
	var m := new_main(seed)
	var tr := PackedVector2Array()
	var done := 0
	for t in 30 * 600:
		if m.wave_state == m.WS_RESPITE:
			if done == 3:
				break
			m._start_wave()
			done += 1
		m._physics_process(1.0 / 30.0)
		var s := Vector2.ZERO
		for i in m.count:
			s += m.pos[i] * (1.0 + (i % 7)) + Vector2(m.hp[i], m.count)
		tr.append(s)
		if m.wave_state == m.WS_DEFEAT:
			break
	m.free()
	return tr

func _initialize() -> void:
	# (а)
	var a: Node2D = load("res://bench/old/main_bak24.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	for x in [a, b]:
		x.waves_enabled = false
		x.record_path = "user://record_bench.json"
		x._setup_data()
	var first := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0:
			if a.count != b.count:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i]:
						first = t
						break
	print("(а) waves off против bak24: " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first))
	a.free()
	b.free()
	# (б) 1400 пехоты + 300 лучников (в обход магазина)
	var m := new_main(1)
	m._squad_add_units(0, m.infantry_type, 1400 - alive_of(m, 0))
	m._squad_add_units(1, m.archer_type, 300 - alive_of(m, 1))
	for s in 2:
		print("(б) отряд %d: %d юн., ширина %d, рядов %d, глубина %.0f px; max y слота от стартовой позиции (центр %s): %.0f (нужно ≤ %.0f); при центре y=700: %.0f" % [
			s, alive_of(m, s), m.squad_width[s], m.squad_rows[s], m.squad_depth[s],
			(m.PLAYER_START if s == 0 else m._follow_target(1, 0)).round(), max_slot_y(m, s, m.PLAYER_START if s == 0 else m._follow_target(1, 0)), m.WALL_Y - 20.0,
			max_slot_y(m, s, Vector2(m.PLAYER_START.x, 700.0))])
	m.free()
	# cap
	m = new_main(2)
	m._setup_fps_label()   # кнопки магазина
	m.gold = 1e9
	var bought := 0
	while m._buy(0):
		bought += 1
	var abought := 0
	while m._buy(1):
		abought += 1
	m._update_ui()
	print("(б) cap: куплено пехоты %d раз -> %d (cap 1200), лучников %d раз -> %d (cap 300); ещё раз: пехота %s, лучники %s; кнопки: «%s», «%s»" % [
		bought, alive_of(m, 0), abought, alive_of(m, 1), m._buy(0), m._buy(1), m.shop_buttons[0].text, m.shop_buttons[1].text])
	m.free()
	# (г)
	var r1 := run_waves(5)
	var r2 := run_waves(5)
	var d := -1
	for k in mini(r1.size(), r2.size()):
		if r1[k] != r2[k]:
			d = k
			break
	print("(г) 3 волны, seed 5: тиков %d / %d, %s" % [r1.size(), r2.size(), "совпадает на каждом тике" if d < 0 and r1.size() == r2.size() else "расходится с тика %d" % d])
	quit()