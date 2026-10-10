extends SceneTree
# Этап 2: (б) детерминизм 3 волны, (в) спавн и пределы, (г) покупки, (ж) лечение, пехота 1400.
func new_main(seed: int) -> Node2D:
	var m: Node2D = load("res://scripts/main.gd").new()
	m.spawn_seed = seed
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func slot_check(m: Node2D, s: int) -> String:
	var width: int = m.squad_width[s]
	var used := {}
	var h := {}
	var n := 0
	for i in m.count:
		if m.unit_squad[i] != s:
			continue
		n += 1
		var k: int = m.unit_slot_idx[i]
		if k >= m.TEMP_SLOT_BASE:
			return "остался временный индекс"
		if used.has(k):
			return "дубль слота"
		used[k] = true
		h[k % width] = h.get(k % width, 0) + 1
	for k in used:
		if k / width >= h[k % width]:
			return "дыра в колонке"
	return "ok (%d юн., ширина %d)" % [n, width]

func run_waves(seed: int, waves: int) -> PackedVector2Array:
	var m := new_main(seed)
	var trace := PackedVector2Array()
	var done := 0
	for t in range(1, 30 * 600):
		if m.wave_state == m.WS_RESPITE:
			if done == waves:
				break
			m._start_wave()
			done += 1
		m._physics_process(1.0 / 30.0)
		var s := Vector2.ZERO
		for i in m.count:
			s += m.pos[i] * (1.0 + (i % 7)) + Vector2(m.hp[i], m.count)
		trace.append(s)
		if m.wave_state == m.WS_DEFEAT:
			break
	m.free()
	return trace

func _initialize() -> void:
	# (б) детерминизм
	var a := run_waves(5, 3)
	var b := run_waves(5, 3)
	var first := -1
	for k in mini(a.size(), b.size()):
		if a[k] != b[k]:
			first = k
			break
	print("(б) 3 волны, seed 5: тиков %d / %d, %s" % [a.size(), b.size(), "совпадает на каждом тике" if first < 0 and a.size() == b.size() else "расходится с тика %d" % first])
	# (в) спавн по формуле, пределы, squad = -1; волны 1..3 и волна 30 при неразрушимых воротах
	var m := new_main(1)
	var ok_formula := true
	var waves_log := []
	for w in 3:
		m._start_wave()
		var ticks := 0
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 300:
			m._physics_process(1.0 / 30.0)
			ticks += 1
		waves_log.append("волна %d: убито %d, формула %d" % [m.wave_number, m.wave_kills, m._wave_count(m.wave_number)])
		ok_formula = ok_formula and m.wave_kills == m._wave_count(m.wave_number)
	print("(в) %s — %s" % [", ".join(waves_log), "OK" if ok_formula else "FAIL"])
	m.free()
	m = new_main(2)
	m.gate_hp = 1e12
	m.gate_hp_max = 1e12
	m.wave_number = 29
	m._start_wave()
	var max_alive := 0
	var max_count := 0
	var bad_squad := 0
	var spawned := 0
	var prev_alive := 0
	for t in 60 * 30:
		var before_rem: int = m.wave_remaining
		m._physics_process(1.0 / 30.0)
		spawned += before_rem - m.wave_remaining
		max_alive = maxi(max_alive, m.zombie_alive)
		max_count = maxi(max_count, m.count)
		for i in m.count:
			if m.team[i] == 1 and m.unit_squad[i] != -1:
				bad_squad += 1
	print("(в) волна 30 (формула %d), 60 с: появилось %d, max живых зомби %d (предел %d), max юнитов %d (предел %d), зомби с отрядом: %d" % [
		m._wave_count(30), spawned, max_alive, int(m.wave_cfg.max_alive), max_count, m.MAX_UNITS, bad_squad])
	m.free()
	# (г) покупки
	m = new_main(3)
	var p0: float = m._price(0)
	m.gold = 0.0
	var no_gold: bool = m._buy(0)
	m.gold = 100000.0
	var inf_before := 0
	var arc_before := 0
	for i in m.count:
		if m.unit_squad[i] == 0: inf_before += 1
		if m.unit_squad[i] == 1: arc_before += 1
	var dmg0: float = m.type_damage[m.infantry_type]
	var arr0: float = m.type_arrow_dmg[m.archer_type]
	var prices := []
	for k in 3:
		prices.append(m._price(0))
		m._buy(0)
	m._buy(1)
	m._buy(1)
	m._buy(2)
	var ghp0: float = m.gate_hp_max
	m._buy(3)
	var inf_after := 0
	var arc_after := 0
	for i in m.count:
		if m.unit_squad[i] == 0: inf_after += 1
		if m.unit_squad[i] == 1: arc_after += 1
	print("(г) без золота купить нельзя: %s; цены пехоты %s (формула 100·(1+0.2·n)); пехота %d -> %d (+150), лучники %d -> %d (+50)" % [
		not no_gold, prices, inf_before, inf_after, arc_before, arc_after])
	print("    оружие: урон пехоты %.2f -> %.2f, стрел %.2f -> %.2f; ворота макс %.0f -> %.0f, hp %.0f" % [
		dmg0, m.type_damage[m.infantry_type], arr0, m.type_arrow_dmg[m.archer_type], ghp0, m.gate_hp_max, m.gate_hp])
	print("    слоты сразу после покупки: пехота %s, лучники %s" % [slot_check(m, 0), slot_check(m, 1)])
	var at_gate := 0
	for i in m.count:
		if m.team[i] == 0 and m.pos[i].y >= m.WALL_Y - 7.0:
			at_gate += 1
	for t in 15 * 30:
		m._physics_process(1.0 / 30.0)
	var dev := 0.0
	var nn := 0
	for i in m.count:
		var s: int = m.unit_squad[i]
		if s >= 0:
			dev += m.pos[i].distance_to(m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s]))
			nn += 1
	print("    новые юниты у ворот сразу: %d; через 15 с средний уход от слота %.2f px; слоты: пехота %s, лучники %s" % [at_gate, dev / nn, slot_check(m, 0), slot_check(m, 1)])
	m._start_wave()
	print("    в бою купить нельзя: %s" % (not m._buy(0)))
	m.free()
	# (ж) лечение после волны
	m = new_main(4)
	m._start_wave()
	var hurt := 0
	var t2 := 0
	while m.wave_state == m.WS_BATTLE and t2 < 30 * 300:
		m._physics_process(1.0 / 30.0)
		t2 += 1
		if t2 % 30 == 0:
			for i in m.count:
				if m.team[i] == 0 and m.hp[i] < m.type_hp[m.unit_type[i]]:
					hurt = maxi(hurt, 1)
	var not_full := 0
	for i in m.count:
		if m.team[i] == 0 and m.hp[i] != m.type_hp[m.unit_type[i]]:
			not_full += 1
	print("(ж) во время волны раненые были: %s; после волны не с полным hp: %d из %d" % [hurt == 1, not_full, m.count])
	m.free()
	# Пехота 1400: передний край и задний ряд
	m = new_main(6)
	m.gold = 1e9
	while true:
		var n := 0
		for i in m.count:
			if m.unit_squad[i] == 0:
				n += 1
		if n >= 1400:
			break
		m._buy(0)
	for t in 20 * 30:
		m._physics_process(1.0 / 30.0)
	var fy := INF
	var by := -INF
	var n0 := 0
	for i in m.count:
		if m.unit_squad[i] == 0:
			var w: Vector2 = m.squad_pos[0] + m.unit_slot[i].rotated(m.squad_angle[0])
			fy = minf(fy, w.y)
			by = maxf(by, w.y)
			n0 += 1
	print("пехота %d: ширина %d, рядов %d; слоты: передний край y=%.0f, задний y=%.0f (нужно ≤ %.0f), глубина %.0f px" % [
		n0, m.squad_width[0], m.squad_rows[0], fy, by, m.WALL_Y - 20.0, by - fy])
	m.free()
	quit()