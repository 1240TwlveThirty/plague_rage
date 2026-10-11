extends SceneTree
# Тесты v33 (всплески и сигнал): (а) регрессия против bak33 при BURSTS_ENABLED = false, (б) план всплесков,
# (в) тайминг сигнала и появления, (г) появление на волнах 5, 10, 30, (д) конец волны.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/old/main_bak33.gd"

func new_main(path: String, seed: int, waves: bool, bursts := true) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	if "bursts_enabled" in m:
		m.bursts_enabled = bursts
	m._setup_data()
	return m

func compare(waves: bool) -> String:
	var a := new_main(OLD, 1, waves)
	var b := new_main(NEW, 1, waves, false)
	var first := -1
	var ticks := 0
	for t in range(1, 901 if not waves else 6001):
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
			if a.count != b.count or a.gate_hp != b.gate_hp or a.gold != b.gold or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state or a.wave_remaining != b.wave_remaining:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.unit_slot_idx[i] != b.unit_slot_idx[i] or a.unit_type[i] != b.unit_type[i]:
						first = t
						break
	var res := ("совпадает на всех %d тиках" % ticks if first < 0 else "расходится с тика %d" % first) + " (юнитов %d, пройдено волн %d)" % [b.count, b.wave_number if waves else 0]
	a.free()
	b.free()
	return res

func bursts_key(bursts: Array) -> String:
	var parts := []
	for b in bursts:
		var recs := []
		for r in b.records:
			recs.append("%d:%d" % [r.type, r.count])
		parts.append("%.4f/%d/%s" % [b.t_start, b.side, "+".join(recs)])
	return ";".join(parts)

func test_plan() -> void:
	var bad := []
	var rows := []
	for seed in [1, 2, 3]:
		var m := new_main(NEW, seed, true)
		var m2 := new_main(NEW, seed, true)
		for w in range(1, 11):
			var plan: Array = m._plan_wave(w)
			var bursts: Array = m._plan_bursts(w, plan)
			var want := {}
			var got := {}
			var side_total := [0, 0, 0]
			var side_bursts := [0, 0, 0]
			for r in plan:
				want["%d/%d" % [r.side, r.type]] = want.get("%d/%d" % [r.side, r.type], 0) + r.count
				side_total[r.side] += r.count
			var ok := true
			var prev := -INF
			var biggest := 0
			for k in bursts.size():
				var b: Dictionary = bursts[k]
				side_bursts[b.side] += 1
				var size := 0
				for r in b.records:
					got["%d/%d" % [b.side, r.type]] = got.get("%d/%d" % [b.side, r.type], 0) + r.count
					size += r.count
					ok = ok and r.count > 0
				biggest = maxi(biggest, size)
				ok = ok and size > 0 and b.t_start >= prev + 6.0 - 0.0001
				if k == 0:
					ok = ok and is_equal_approx(b.t_start, m.wave_cfg.burst_signal_lead)
				else:
					ok = ok and absf(b.t_start - (m.wave_cfg.burst_signal_lead + k * m.wave_cfg.burst_gap)) <= m.wave_cfg.burst_gap_jitter + 0.0001
				prev = b.t_start
			for side in 3:   # число порций стороны = ceil(всего / burst_target_size)
				ok = ok and side_bursts[side] == (ceili(side_total[side] / float(m.wave_cfg.burst_target_size)) if side_total[side] > 0 else 0)
			ok = ok and want == got and bursts_key(bursts) == bursts_key(m2._plan_bursts(w, m2._plan_wave(w)))
			if not ok:
				bad.append("seed %d волна %d" % [seed, w])
			if seed == 1:
				rows.append("      %5d | %5d | %9d | %d/%d/%d | %7d | %.1f с" % [w, m._wave_count(w), bursts.size(), side_bursts[0], side_bursts[1], side_bursts[2], biggest, bursts[bursts.size() - 1].t_start])
		m.free()
		m2.free()
	print("(б) план всплесков, волны 1-10, seed 1-3: сумма по (сторона, тип) равна плану, первый в burst_signal_lead, шаг не меньше 6 с и в пределах разброса, два экземпляра дают одинаковый план; ошибок %d %s" % [bad.size(), bad])
	print("      волна | зомби | всплесков | верх/лево/право | крупнейший | последний всплеск (seed 1)\n%s" % "\n".join(rows))

# Волна w: тики сигнала и начала появления каждого всплеска. max_alive > 0 — подменить предел (в памяти).
func run_timing(seed: int, w: int, max_alive: int) -> Dictionary:
	var m := new_main(NEW, seed, true)
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	if max_alive > 0:
		m.wave_cfg.max_alive = max_alive
	m.wave_number = w - 1
	var respite_signals: int = m._burst_signals().size()
	m._start_wave()
	var n: int = m.wave_bursts.size()
	var t_starts := []
	var sizes := []
	for b in m.wave_bursts:
		t_starts.append(b.t_start)
		sizes.append(m._burst_size(b))
	var sig := PackedInt32Array()
	var start := PackedInt32Array()
	var alive_at_start := PackedInt32Array()
	sig.resize(n)
	start.resize(n)
	alive_at_start.resize(n)
	sig.fill(-1)
	start.fill(-1)
	var total: int = m.wave_remaining
	var errors := 0
	var max_alive_seen := 0
	var t := 0
	var lim := Vector2(m.FIELD.x, m.WALL_Y - 20.0)
	while m.wave_state == m.WS_BATTLE and t < 30000:
		var c0: int = m.count
		var idx0: int = m.burst_idx
		var active0: bool = m.burst_active
		var alive0: int = m.zombie_alive
		var rem0: int = m.wave_remaining
		m._update_waves(1.0 / 30.0)   # появление отдельно от остального тика: новые юниты в конце массивов
		t += 1
		for k in range(0, m.burst_signal_n):
			if sig[k] < 0:
				sig[k] = t
		if (m.burst_active and not active0) or m.burst_idx > idx0:
			var k2 := idx0
			if start[k2] < 0:
				start[k2] = t
				alive_at_start[k2] = alive0
		if m.wave_remaining < rem0:
			if m.count - c0 != rem0 - m.wave_remaining or rem0 - m.wave_remaining > int(m.wave_cfg.burst_chunk):
				errors += 1
			for i in range(c0, m.count):
				var p: Vector2 = m.pos[i]
				if m.unit_squad[i] != -1 or m.team[i] != 1 or p.x < 0.0 or p.x > lim.x or p.y < 0.0 or p.y > lim.y:
					errors += 1
		max_alive_seen = maxi(max_alive_seen, m.zombie_alive)
		if m.zombie_alive > int(m.wave_cfg.max_alive) or m.count > m.MAX_UNITS:
			errors += 1
		if m.wave_state != m.WS_BATTLE:
			break
		# остальной тик без _update_waves
		m.wave_state = m.WS_RESPITE
		m._physics_process(1.0 / 30.0)
		m.wave_state = m.WS_BATTLE
	var r := {"n": n, "sig": sig, "start": start, "alive": alive_at_start, "errors": errors, "total": total, "ticks": t, "left": m.wave_remaining, "state": m.wave_state,
		"max_alive": max_alive_seen, "respite_signals": respite_signals, "after_signals": m._burst_signals().size(), "t_start": t_starts, "size": sizes, "lead": m.wave_cfg.burst_signal_lead,
		"cleared": m.wave_state == m.WS_RESPITE, "army": 0}
	for i in m.count:
		if m.team[i] == 0:
			r.army += 1
	m.free()
	return r

func three_side_seed(w: int) -> int:
	for seed in range(1, 200):
		var m := new_main(NEW, seed, true)
		var sides := {}
		for r in m._plan_wave(w):
			sides[r.side] = true
		m.free()
		if sides.size() == 3:
			return seed
	return 1

func test_timing() -> void:
	var r := run_timing(three_side_seed(6), 6, 0)
	var worst_sig := 0
	var worst_start := 0
	for k in r.n:
		worst_sig = maxi(worst_sig, absi(r.sig[k] - maxi(ceili((r.t_start[k] - r.lead) * 30.0 - 0.0001), 1)))
		worst_start = maxi(worst_start, absi(r.start[k] - ceili(r.t_start[k] * 30.0 - 0.0001)))
	print("(в) тайминг, волна 6 (%d всплесков, места хватает): сигнал в t_start - %.1f с, отклонение не больше %d тика; появление в t_start, отклонение не больше %d тика: %s" % [
		r.n, r.lead, worst_sig, worst_start, worst_sig <= 1 and worst_start <= 1 and r.errors == 0])
	# нехватка места: зомби первого всплеска бессмертны, предел живых — на 10 больше первого всплеска
	var m := new_main(NEW, three_side_seed(6), true)
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m.wave_number = 5
	m._start_wave()
	var b0: int = m._burst_size(m.wave_bursts[0])
	var b1: int = m._burst_size(m.wave_bursts[1])
	var t1: float = m.wave_bursts[1].t_start
	var side1: int = m.wave_bursts[1].side
	m.wave_cfg.max_alive = b0 + 10
	var sig_tick := -1
	var tick := 0
	while m.wave_t < t1 + 10.0:
		m._physics_process(1.0 / 30.0)
		tick += 1
		for i in m.count:
			if m.team[i] == 1:
				m.hp[i] = 1000.0
		if sig_tick < 0 and m.burst_signal_n >= 2:
			sig_tick = tick
	var held: bool = m.burst_idx == 1 and not m.burst_active and m.zombie_alive == b0 and m._burst_signals() == [side1]
	var sig_on_time: bool = absi(sig_tick - ceili((t1 - m.wave_cfg.burst_signal_lead) * 30.0 - 0.0001)) <= 1
	for i in m.count:
		if m.team[i] == 1:
			m.hp[i] = 0.0
	m._physics_process(1.0 / 30.0)   # зомби убраны в конце этого тика
	m._physics_process(1.0 / 30.0)
	var started: bool = m.burst_active or m.burst_idx == 2
	print("    нехватка места (первый всплеск %d бессмертен, max_alive %d, второй всплеск %d): через 10 с после t_start второй не начался, сигнал дан вовремя и горит: %s; после гибели первых начался на следующем тике: %s" % [
		b0, b0 + 10, b1, held and sig_on_time, started])
	m.free()
func test_spawn() -> void:
	for w in [5, 10, 30]:
		var r := run_timing(three_side_seed(w), w, 0)
		var started := 0
		for k in r.n:
			started += int(r.start[k] >= 0)
		print("(г) волна %d: зомби %d, всплесков %d (начались %d), осталось не появившихся %d; в поле и не ниже WALL_Y - 20, отряд -1, куски не больше burst_chunk, пределы не превышены (пик живых %d): ошибок %d; сигналов в передышке до волны %d, после %d; итог: %s за %.0f с" % [
			w, r.total, r.n, started, r.left, r.max_alive, r.errors, r.respite_signals, r.after_signals,
			"волна пройдена" if r.cleared else ("армия выбита, ворота бессмертны (осталось своих %d)" % r.army), r.ticks / 30.0])

func test_end() -> void:
	var m := new_main(NEW, 2, true)
	var out := []
	var ok := true
	for w in 2:
		m._start_wave()
		var bursts_n: int = m.wave_bursts.size()
		var t := 0
		var early := false   # волна не должна закончиться, пока есть не появившиеся
		while m.wave_state == m.WS_BATTLE and t < 6000:
			m._physics_process(1.0 / 30.0)
			t += 1
			if m.wave_state == m.WS_RESPITE and m.burst_idx < bursts_n:
				early = true
		ok = ok and m.wave_state == m.WS_RESPITE and m.wave_remaining == 0 and m.zombie_alive == 0 and m._burst_signals().is_empty() and m.burst_idx == bursts_n and not early
		out.append("волна %d за %.1f с, убито %d, осталось %d" % [m.wave_number, t / 30.0, m.wave_kills, m.wave_remaining])
	# следующая волна: таймеры и сигналы с нуля
	m._start_wave()
	ok = ok and m.wave_t == 0.0 and m.burst_idx == 0 and m.burst_signal_n == 0 and not m.burst_active
	m._physics_process(1.0 / 30.0)
	ok = ok and m._burst_signals().size() == 1 and m.burst_msg.begins_with("Всплеск: ")
	print("(д) конец волны: %s; волна кончается после гибели всех, remaining = 0; при старте следующей таймеры с нуля, первый сигнал сразу («%s»): %s" % ["; ".join(out), m.burst_msg, ok])
	m.free()

func _initialize() -> void:
	print("(а) BURSTS_ENABLED = false против bak33, waves off: " + compare(false))
	print("    с волнами и покупками, 3 волны: " + compare(true))
	test_plan()
	test_timing()
	test_spawn()
	test_end()
	quit()
