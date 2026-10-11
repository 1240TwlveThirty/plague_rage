extends SceneTree
# Тесты v34 (всплески по слоям, красная полоса): (а) регрессия против bak34 при BURSTS_LAYERED = false,
# (б) план по слоям, (в) тайминг, (г) появление, (д) конец волны.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/old/main_bak34.gd"

func new_main(path: String, seed: int, waves: bool, layered := true, layer := 1) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	if "bursts_layered" in m:
		m.bursts_layered = layered
		m.debug_layer = layer
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
			if a.count != b.count or a.gate_hp != b.gate_hp or a.gold != b.gold or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state or a.wave_remaining != b.wave_remaining \
					or a.wave_t != b.wave_t or a.burst_idx != b.burst_idx or a.burst_signal_n != b.burst_signal_n:
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
		parts.append("%.4f/%.4f/%d/%d/%s" % [b.t_start, b.t_group, b.group, b.side, "+".join(recs)])
	return ";".join(parts)

# Волна w слоя layer; для слоёв 2 и 3 последняя волна «большая»: 1000 и 2000 зомби (count_base в памяти).
func make_plan(m: Node2D, layer: int, w: int) -> Array:
	m.wave_cfg.count_base = 50
	if w == 10 and layer == 2:
		m.wave_cfg.count_base = 1000 - m.wave_cfg.count_step * 9
	elif w == 10 and layer == 3:
		m.wave_cfg.count_base = 2000 - m.wave_cfg.count_step * 9
	return m._plan_wave(w)

func test_plan() -> void:
	var rows := []
	for layer in [1, 2, 3]:
		var bad := []
		var side_n := [0, 0, 0]
		var side_n300 := [0, 0, 0]
		var eligible := 0
		var joined := 0
		var groups_total := 0
		var groups_multi := 0
		var L := {}
		for seed in range(1, 41):   # проверки строения — на всех; статистика долей — первые 300 всплесков и все
			var m := new_main(NEW, seed, true, true, layer)
			var m2 := new_main(NEW, seed, true, true, layer)
			L = m._layer()
			for w in range(1, 11):
				var plan := make_plan(m, layer, w)
				var bursts: Array = m._plan_bursts(w, plan)
				var plan2 := make_plan(m2, layer, w)
				var want := {}
				var total := 0
				for r in plan:
					want[r.type] = want.get(r.type, 0) + r.count
					total += r.count
				var got := {}
				var ok := true
				var lateral_bursts := 0
				for b in bursts:
					lateral_bursts += int(b.side != m.SIDE_TOP)
				var by_group := {}
				var prev_t := -INF
				for b in bursts:
					for r in b.records:
						got[r.type] = got.get(r.type, 0) + r.count
						ok = ok and r.count > 0
						if r.type == m.runner_type and lateral_bursts > 0:
							ok = ok and b.side != m.SIDE_TOP   # бегуны только на боковых всплесках
					if w < int(L.sides_from_wave):
						ok = ok and b.side == m.SIDE_TOP
					ok = ok and b.t_start >= prev_t and absf(b.t_start - b.t_group) <= 0.3 + 0.0001
					prev_t = b.t_start
					if not by_group.has(b.group):
						by_group[b.group] = []
					by_group[b.group].append(b)
				var n_expect := clampi(ceili(total / float(L.burst_target_size)), int(L.burst_count_min), int(L.burst_count_max))
				ok = ok and want == got and bursts.size() <= n_expect and (bursts.size() == n_expect or total < n_expect * 3)
				ok = ok and bursts.size() >= mini(int(L.burst_count_min), total) and bursts.size() <= int(L.burst_count_max)
				# группы: стороны разные, размер не больше group_max, шаг времени групп
				var gids := by_group.keys()
				gids.sort()
				var prev_group_t := -INF
				for g in gids:
					var sides := {}
					for b in by_group[g]:
						ok = ok and not sides.has(b.side) and b.t_group == by_group[g][0].t_group
						sides[b.side] = true
					ok = ok and sides.size() <= int(L.group_max)
					var tg: float = by_group[g][0].t_group
					if g == 0:
						ok = ok and is_equal_approx(tg, L.signal_lead)
					else:
						ok = ok and tg >= prev_group_t + maxf(2.0, 0.6 * L.gap) - 0.0001
					prev_group_t = tg
					groups_total += 1
					groups_multi += int(sides.size() >= 2)
				ok = ok and bursts_key(bursts) == bursts_key(m2._plan_bursts(w, plan2))
				if not ok:
					bad.append("seed %d волна %d" % [seed, w])
				# статистика: стороны (только волны, где боковые допустимы) и присоединения к группе
				var in_order := bursts.duplicate()
				in_order.sort_custom(func(p, q): return p.order < q.order)
				var cur_sides := {}
				for k in in_order.size():
					var b: Dictionary = in_order[k]
					if w >= int(L.sides_from_wave):
						side_n[b.side] += 1
						if side_n300[0] + side_n300[1] + side_n300[2] < 300:
							side_n300[b.side] += 1
					if k > 0:
						var same_group: bool = b.group == in_order[k - 1].group
						if not cur_sides.has(b.side) and cur_sides.size() < int(L.group_max):
							eligible += 1
							joined += int(same_group)
						if not same_group:
							cur_sides = {}
					cur_sides[b.side] = true
				if seed == 1 and w in [1, 3, 5, 10]:
					rows.append("      %4d | %5d | %5d | %2d | %5d | %.1f с" % [layer, w, total, bursts.size(), gids.size(), bursts[bursts.size() - 1].t_start])
			m.free()
			m2.free()
		var all: int = side_n[0] + side_n[1] + side_n[2]
		var w_sum: float = L.side_weight_top + L.side_weight_left + L.side_weight_right
		var weights := [L.side_weight_top / w_sum, L.side_weight_left / w_sum, L.side_weight_right / w_sum]
		var dev300 := 0.0
		var dev_all := 0.0
		for s in 3:
			dev300 = maxf(dev300, absf(side_n300[s] / 300.0 - weights[s]) * 100.0)
			dev_all = maxf(dev_all, absf(side_n[s] / float(all) - weights[s]) * 100.0)
		print("(б) слой %d, волны 1-10 × 40 seed: ошибок строения %d %s" % [layer, bad.size(), bad.slice(0, 3)])
		print("    стороны, первые 300 всплесков: верх/лево/право %.1f%% / %.1f%% / %.1f%% при весах %.0f / %.0f / %.0f, отклонение до %.1f п.п. (допуск 5): %s; на всех %d — до %.1f п.п." % [
			side_n300[0] / 3.0, side_n300[1] / 3.0, side_n300[2] / 3.0, weights[0] * 100.0, weights[1] * 100.0, weights[2] * 100.0, dev300, dev300 <= 5.0, all, dev_all])
		print("    присоединение к группе, когда оно возможно: %.1f%% из %d случаев при pair_prob %.0f%% (допуск 5 п.п.): %s; групп из 2-3 сторон %.1f%% из %d" % [
			100.0 * joined / maxi(eligible, 1), eligible, L.pair_prob * 100.0, absf(100.0 * joined / maxi(eligible, 1) - L.pair_prob * 100.0) <= 5.0, 100.0 * groups_multi / maxi(groups_total, 1), groups_total])
	print("      слой | волна | зомби |  N | групп | последний всплеск (seed 1)\n%s" % "\n".join(rows))

# Волна w слоя layer: тики сигнала и старта каждого всплеска, проверки появления. big — число зомби волны (0 = обычное).
func run_wave(seed: int, layer: int, w: int, big: int) -> Dictionary:
	var m := new_main(NEW, seed, true, true, layer)
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	if big > 0:
		m.wave_cfg.count_base = big - m.wave_cfg.count_step * (w - 1)
	m.wave_number = w - 1
	m.wave_plan_for = -1   # план и всплески перестроить под изменённые настройки
	var respite_alpha: float = m._signal_alpha(0) + m._signal_alpha(1) + m._signal_alpha(2)
	m._start_wave()
	var n: int = m.wave_bursts.size()
	var info := []
	for b in m.wave_bursts:
		info.append({"t_start": b.t_start, "t_group": b.t_group, "group": b.group, "side": b.side, "size": m._burst_size(b), "sig": -1, "start": -1})
	var total: int = m.wave_remaining
	var errors := 0
	var max_alive_seen := 0
	var max_live := 0
	var lim := Vector2(m.FIELD.x, m.WALL_Y - 20.0)
	var bursts: Array = m.wave_bursts
	var t := 0
	var after_all := 0   # тиков после появления последнего зомби: если армия выбита, волна сама не кончится
	while m.wave_state == m.WS_BATTLE and t < 40000 and after_all < 900:
		if m.wave_remaining == 0:
			after_all += 1
		var c0: int = m.count
		var rem0: int = m.wave_remaining
		m._update_waves(1.0 / 30.0)
		t += 1
		for k in n:
			if info[k].sig < 0 and k < m.burst_signal_n and m.wave_bursts == bursts:
				info[k].sig = t
			if info[k].start < 0 and bursts[k].state != 0:
				info[k].start = t
		max_live = maxi(max_live, m.burst_live)
		if m.wave_remaining < rem0:
			if m.count - c0 != rem0 - m.wave_remaining:
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
		m.wave_state = m.WS_RESPITE
		m._physics_process(1.0 / 30.0)
		m.wave_state = m.WS_BATTLE
	var r := {"n": n, "info": info, "errors": errors, "total": total, "ticks": t, "left": m.wave_remaining, "cleared": m.wave_state == m.WS_RESPITE, "max_alive": max_alive_seen,
		"max_live": max_live, "lead": m._layer().signal_lead, "respite_alpha": respite_alpha, "after_alpha": m._signal_alpha(0) + m._signal_alpha(1) + m._signal_alpha(2)}
	m.free()
	return r

# Seed и волна слоя 1, где есть группа из двух сторон.
func find_group_case() -> Array:
	for seed in range(1, 100):
		var m := new_main(NEW, seed, true, true, 1)
		for w in range(5, 11):
			var groups := {}
			for b in m._plan_bursts(w, m._plan_wave(w)):
				groups[b.group] = groups.get(b.group, 0) + 1
			for g in groups:
				if groups[g] >= 2:
					m.free()
					return [seed, w]
		m.free()
	return [1, 8]

func test_timing() -> void:
	var c := find_group_case()
	var r := run_wave(c[0], 1, c[1], 0)
	var worst_sig := 0
	var worst_start := 0
	var sync := true
	var multi := 0
	var by_group := {}
	for q in r.info:
		worst_sig = maxi(worst_sig, absi(q.sig - maxi(ceili((q.t_group - r.lead) * 30.0 - 0.0001), 1)))
		worst_start = maxi(worst_start, absi(q.start - ceili(q.t_start * 30.0 - 0.0001)))
		if by_group.has(q.group):
			sync = sync and by_group[q.group].sig == q.sig and absf(q.t_start - by_group[q.group].t_start) <= 0.6 and q.side != by_group[q.group].side
			multi += 1
		else:
			by_group[q.group] = q
	print("(в) тайминг, слой 1, seed %d, волна %d (%d всплесков, групп %d, одновременно появлялось до %d): сигнал в t группы - %.1f с, отклонение %d тиков; появление в t_start, отклонение %d тиков; всплески одной группы: сигнал в один тик, старт в пределах 0.6 с, стороны разные: %s" % [
		c[0], c[1], r.n, by_group.size(), r.max_live, r.lead, worst_sig, worst_start, sync and multi > 0 and worst_sig == 0 and worst_start == 0 and r.errors == 0])
	# нехватка места: зомби бессмертны, предел живых чуть больше первого всплеска
	var m := new_main(NEW, c[0], true, true, 1)
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m.wave_number = c[1] - 1
	m._start_wave()
	var b0: int = m._burst_size(m.wave_bursts[0])
	m.wave_cfg.max_alive = b0 + 10
	var n: int = m.wave_bursts.size()
	var t_last: float = m.wave_bursts[n - 1].t_start
	while m.wave_t < t_last + 5.0:
		m._physics_process(1.0 / 30.0)
		for i in m.count:
			if m.team[i] == 1:
				m.hp[i] = 1000.0
	var held: bool = m.burst_idx == 1 and m.burst_signal_n == n and m.zombie_alive == b0
	var lit := 0
	for k in range(1, n):
		lit += int(m._signal_alpha(m.wave_bursts[k].side) > 0.29)
	# освобождаем место постепенно: всплески должны стартовать по порядку
	var order := []
	var bursts: Array = m.wave_bursts
	for step in 4000:
		for i in m.count:
			if m.team[i] == 1:
				m.hp[i] = 0.0 if step % 30 == 0 else 1000.0
		m._physics_process(1.0 / 30.0)
		for k in n:
			if bursts[k].state != 0 and not order.has(k):
				order.append(k)
		if order.size() == n or m.wave_state != m.WS_BATTLE:
			break
	var sorted := order.duplicate()
	sorted.sort()
	print("    нехватка места (первый всплеск %d бессмертен, max_alive %d): через 5 с после последнего t_start начался только первый, сигналы остальных горят: %s; после освобождения места стартовали по порядку %s: %s" % [
		b0, b0 + 10, held and lit == n - 1, order, order == sorted and order.size() == n])
	m.free()

func test_spawn() -> void:
	for c in [[1, 5, 0, "слой 1, волна 5"], [1, 10, 0, "слой 1, волна 10"], [3, 10, 2000, "слой 3, большая волна"]]:
		var r := run_wave(2, c[0], c[1], c[2])
		var started := 0
		for q in r.info:
			started += int(q.start >= 0)
		print("(г) %s: зомби %d, всплесков %d (начались %d), одновременно появлялось до %d, не появилось %d; в поле и не ниже WALL_Y - 20, отряд -1, пределы не превышены (пик живых %d): ошибок %d; сигнал в передышке до волны %.2f, после %.2f; %s за %.0f с" % [
			c[3], r.total, r.n, started, r.max_live, r.left, r.max_alive, r.errors, r.respite_alpha, r.after_alpha,
			"волна пройдена" if r.cleared else "все появились, бой остановлен через 30 с после последнего", r.ticks / 30.0])

func test_end() -> void:
	var m := new_main(NEW, 2, true, true, 1)
	var out := []
	var ok := true
	for w in 3:
		m._start_wave()
		var bursts_n: int = m.wave_bursts.size()
		var early := false
		var t := 0
		while m.wave_state == m.WS_BATTLE and t < 9000:
			m._physics_process(1.0 / 30.0)
			t += 1
			if m.wave_state == m.WS_RESPITE and (m.burst_idx < bursts_n or m.burst_live > 0):
				early = true
		ok = ok and m.wave_state == m.WS_RESPITE and m.wave_remaining == 0 and m.zombie_alive == 0 and m.burst_pending == 0 and not early
		ok = ok and m._signal_alpha(0) + m._signal_alpha(1) + m._signal_alpha(2) == 0.0
		out.append("волна %d (%d всплесков) за %.1f с, убито %d" % [m.wave_number, bursts_n, t / 30.0, m.wave_kills])
	m._start_wave()
	ok = ok and m.wave_t == 0.0 and m.burst_idx == 0 and m.burst_signal_n == 0 and m.burst_live == 0 and m.burst_pending == 0
	m._physics_process(1.0 / 30.0)
	ok = ok and m.burst_signal_n >= 1 and m._signal_alpha(m.wave_bursts[0].side) > 0.29 and m.burst_msg == ""
	print("(д) конец волны: %s; волна кончается после гибели всех, remaining = 0; при старте следующей таймеры с нуля, полоса первой группы горит сразу, надписи нет: %s" % ["; ".join(out), ok])
	m.free()

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("tail"):
		test_spawn()
		test_end()
		quit()
		return
	print("(а) BURSTS_LAYERED = false против bak34, waves off: " + compare(false))
	print("    с волнами и покупками, 3 волны: " + compare(true))
	test_plan()
	test_timing()
	test_spawn()
	test_end()
	quit()
