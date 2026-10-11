extends SceneTree
# Тесты v28 (несколько отрядов одного типа): (а) регрессия против bak28, (в) создание и покупка, (г) разделение,
# (д) слияние, (е) очистка, (ж) два отряда лучников, (з) бой трёх отрядов пехоты, (и) детерминизм.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/main_bak28.gd"

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

func units_of(m: Node2D, s: int) -> Array:
	var ids := []
	for i in m.count:
		if m.unit_squad[i] == s:
			ids.append(i)
	return ids

func type_total(m: Node2D, type: int) -> int:
	var n := 0
	for i in m.count:
		if m.unit_type[i] == type:
			n += 1
	return n

# Сетка отряда: слоты уникальны, в каждой колонке ряды 0..h-1 без дыр, глубины колонок отличаются не больше чем на 1.
func grid_ok(m: Node2D, s: int, strict := true) -> bool:
	var width: int = m.squad_width[s]
	var seen := {}
	var heights := {}
	var top := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			var k: int = m.unit_slot_idx[i]
			if k < 0 or k >= m.TEMP_SLOT_BASE or seen.has(k):
				return false
			seen[k] = true
			var col := k % width
			heights[col] = heights.get(col, 0) + 1
			top[col] = maxi(top.get(col, 0), k / width)
	var lo := 1 << 30
	var hi := 0
	for col in heights:
		if top[col] != heights[col] - 1:
			return false
		lo = mini(lo, heights[col])
		hi = maxi(hi, heights[col])
	return heights.is_empty() or ((hi - lo <= 1 or not strict) and width <= m.WIDTH_MAX and hi <= m.ROWS_MAX)

# Целостность: нет ссылок на свободные отряды, squad_n равен числу юнитов, выбор на занятом отряде, 0 и 1 заняты.
func integrity(m: Node2D) -> String:
	var n := PackedInt32Array()
	n.resize(m.SQUAD_MAX)
	for i in m.count:
		var s: int = m.unit_squad[i]
		if s == -1:
			continue
		if s < 0 or s >= m.SQUAD_MAX or m.squad_used[s] == 0:
			return "юнит %d ссылается на свободный отряд %d" % [i, s]
		if m.unit_type[i] != m.squad_type[s]:
			return "юнит %d не того типа, что отряд %d" % [i, s]
		n[s] += 1
	for s in m.SQUAD_MAX:
		if n[s] != m.squad_n[s]:
			return "squad_n[%d] = %d, а юнитов %d" % [s, m.squad_n[s], n[s]]
		if m.squad_used[s] == 0 and m.squad_n[s] != 0:
			return "свободный отряд %d с юнитами" % s
	if m.squad_used[0] == 0 or m.squad_used[1] == 0:
		return "отряд 0 или 1 освобождён"
	if m.squad_used[m.sel_primary] == 0:
		return "выбран свободный отряд %d" % m.sel_primary
	return ""

func used_list(m: Node2D) -> Array:
	var r := []
	for s in m.SQUAD_MAX:
		if m.squad_used[s] == 1:
			r.append("%d:%s×%d" % [s, "П" if m.squad_type[s] == m.infantry_type else "Л", m.squad_n[s]])
	return r

func checksum(m: Node2D) -> Vector2:
	var c := Vector2.ZERO
	for i in m.count:
		c += m.pos[i] * (1.0 + (i % 7)) + Vector2(m.hp[i], m.unit_squad[i] + 2)
	for s in m.SQUAD_MAX:
		c += m.squad_pos[s] * (s + 1.0) + Vector2(m.squad_angle[s] + m.squad_used[s], m.squad_n[s] * (s + 1) + m.squad_volley_t[s])
	return c + Vector2(m.count, m.gold)

func compare(waves: bool) -> String:
	var a := new_main(OLD, 1, waves)
	var b := new_main(NEW, 1, waves)
	var first := -1
	for t in range(1, 901):
		if waves and a.wave_state == a.WS_RESPITE:
			for m in [a, b]:
				m._buy(0)
				m._buy(1)
				m._start_wave()
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0:
			if a.count != b.count or a.gate_hp != b.gate_hp or a.gold != b.gold or a.arrows_fired != b.arrows_fired:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.unit_slot_idx[i] != b.unit_slot_idx[i]:
						first = t
						break
	var res := ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first) + " (юнитов %d, волна %d)" % [b.count, b.wave_number]
	a.free()
	b.free()
	return res

func test_create_buy() -> void:
	var m := new_main(NEW, 1, true)
	m.gold = 1e9
	var ok := true
	var out := []
	ok = ok and m._cmd_new_squad() and m.sel_primary == 2 and m.squad_type[2] == m.infantry_type and m.squad_n[2] == 0
	ok = ok and m.squad_order[2] == m.ORDER_ATTACK and m.squad_aspect[2] == m.squad_aspect[0] and m.squad_ranged[2] == 0
	out.append("N при выбранной пехоте: отряд 3 (индекс 2), пехота, 0 юнитов: %s" % ok)
	m._buy(0)   # пехота в выбранный отряд того же типа
	var gate := Vector2(m.GATE_POS.x, m.WALL_Y - 40.0)
	var ok2: bool = m.squad_n[2] == 50 and m.squad_n[0] == 300 and m.squad_pos[2] == gate and m.squad_target[2] == gate
	ok2 = ok2 and is_equal_approx(m.squad_angle[2], -PI / 2.0) and grid_ok(m, 2)
	m._buy(1)   # лучники при выбранной пехоте -> первый отряд лучников
	ok2 = ok2 and m.squad_n[1] == 125 and m.squad_n[2] == 50
	for t in 240:
		m._physics_process(1.0 / 30.0)
	var far := 0.0
	for i in units_of(m, 2):
		far = maxf(far, m.pos[i].distance_to(slot_world(m, i)))
	ok2 = ok2 and far < m.SLOT_SPACING and m.squad_pos[2] == gate
	out.append("покупка: пехота в выбранный отряд 3 (у ворот %s, за 8 с юниты в слотах, макс. отклонение %.2f px), лучники в отряд 2: %s" % [gate, far, ok2])
	m._select_only(1)
	var ok3: bool = m._cmd_new_squad() and m.sel_primary == 3 and m.squad_type[3] == m.archer_type and m.squad_ranged[3] == 1 and m.squad_aspect[3] == m.squad_aspect[1]
	m._buy(1)
	ok3 = ok3 and m.squad_n[3] == 25 and m.squad_n[1] == 125
	m._buy(0)   # пехота при выбранных лучниках -> первый отряд пехоты (0)
	ok3 = ok3 and m.squad_n[0] == 350
	out.append("N при выбранных лучниках: отряд лучников; лучники в него, пехота в отряд 1: %s" % ok3)
	# cap по сумме отрядов типа
	var buys := [0, 0]
	for k in 2:
		m._select_only(2 if k == 0 else 3)
		while m._buy(k):
			buys[k] += 1
	var ok4: bool = type_total(m, m.infantry_type) == m.shop_cap[0] and type_total(m, m.archer_type) == m.shop_cap[1] and m._at_cap(0) and m._at_cap(1)
	out.append("cap по сумме отрядов: пехота %d (предел %d, отряды %d+%d), лучники %d (предел %d, отряды %d+%d): %s" % [
		type_total(m, m.infantry_type), m.shop_cap[0], m.squad_n[0], m.squad_n[2], type_total(m, m.archer_type), m.shop_cap[1], m.squad_n[1], m.squad_n[3], ok4])
	# вне передышки N/G/M игнорируются
	m._select_only(0)
	m._start_wave()
	var before := used_list(m)
	var ok5: bool = m.wave_state == m.WS_BATTLE and not m._cmd_new_squad() and not m._cmd_split() and not m._cmd_merge() and used_list(m) == before and m.hud_msg == ""
	out.append("в бою N, G, M игнорируются: %s" % ok5)
	print("(в) " + "\n    ".join(out))
	print("    целостность: %s" % ("ок" if integrity(m) == "" else integrity(m)))
	m.free()

# Разделение отряда 0 размера n; возвращает описание или "ОШИБКА ...".
func split_case(m: Node2D, n: int) -> String:
	var keys := {}
	for i in units_of(m, 0):
		keys[i] = int((m.pos[i] - m.squad_pos[0]).rotated(-m.squad_angle[0]).y * 16.0)
	var order: int = m.squad_order[0]
	var angle: float = m.squad_angle[0]
	var target: Vector2 = m.squad_target[0]
	var uw: int = m.squad_user_width[0]
	var p0: Vector2 = m.squad_pos[0]
	m._select_only(0)
	var done: bool = m._cmd_split()
	if n < 2:
		return "n=1 отказ" if (not done and m.hud_msg != "" and m.squad_used[2] == 0 and m.squad_n[0] == 1) else "ОШИБКА n=1"
	var t: int = m.sel_primary
	var stay := units_of(m, 0)
	var gone := units_of(m, t)
	var max_stay := -(1 << 40)
	var min_gone := 1 << 40
	for i in stay:
		max_stay = maxi(max_stay, keys[i])
	for i in gone:
		min_gone = mini(min_gone, keys[i])
	var ok: bool = done and t >= 2 and stay.size() == n - n / 2 and gone.size() == n / 2 and m.squad_n[0] == stay.size() and m.squad_n[t] == gone.size()
	ok = ok and max_stay <= min_gone and grid_ok(m, 0) and grid_ok(m, t) and integrity(m) == ""
	ok = ok and m.squad_order[t] == order and m.squad_angle[t] == angle and m.squad_angle[0] == angle and m.squad_user_width[t] == uw and m.squad_type[t] == m.squad_type[0]
	ok = ok and m.squad_target[t].distance_to(target) < 60.0 and m.squad_pos[t].distance_to(p0) < 60.0
	return "%s%d→%d+%d" % ["" if ok else "ОШИБКА ", n, stay.size(), gone.size()]

func resize_squad0(m: Node2D, n: int) -> void:
	if n > m.squad_n[0]:
		m._squad_add_units(0, m.infantry_type, n - m.squad_n[0])
		teleport(m, 0)
	var ids := units_of(m, 0)
	for q in range(n, ids.size()):
		m.hp[ids[q]] = 0.0
	m._remove_dead()
	m._update_squads(0.6)

func test_split() -> void:
	var out := []
	for n in [300, 301, 3, 2, 1]:
		var m := new_main(NEW, 1, true)
		resize_squad0(m, n)
		out.append(split_case(m, n))
		m.free()
	print("(г) разделение, левая половина по local.y остаётся: %s" % ", ".join(out))
	var rot := []
	for k in 8:
		var m := new_main(NEW, 1, true)
		var dir := Vector2.from_angle(k * PI / 4.0)
		m.squad_pos[0] = Vector2(1100, 366)
		var mid: Vector2 = m.squad_pos[0] + dir * 150.0
		m._place_formation(0, mid - dir.orthogonal() * 100.0, mid + dir.orthogonal() * 100.0)
		teleport(m, 0)
		rot.append("%d°: %s" % [k * 45, split_case(m, 300)])
		m.free()
	print("    повёрнутый отряд, 8 углов: %s" % ", ".join(rot))
	var m := new_main(NEW, 1, true)
	for q in 6:
		m._select_only(0)
		m._cmd_new_squad()
	m._select_only(0)
	m.hud_msg = ""
	var before := used_list(m)
	var refused: bool = not m._cmd_split() and m.hud_msg != "" and used_list(m) == before and m.squad_n[0] == 300
	m.hud_msg = ""
	refused = refused and not m._cmd_new_squad() and m.hud_msg != "" and integrity(m) == ""
	print("    все 8 отрядов заняты (%s): разделение и создание отказаны с сообщением «%s»: %s" % [before, m.hud_msg, refused])
	m.free()

func test_merge() -> void:
	var m := new_main(NEW, 1, true)
	var out := []
	m._select_only(0)
	m._cmd_split()   # 0: 150, 2: 150, выбран 2
	var ok: bool = m._cmd_merge() and m.squad_n[0] == 300 and m.squad_used[2] == 0 and m.squad_n[2] == 0 and m.sel_primary == 0 and grid_ok(m, 0) and integrity(m) == ""
	ok = ok and m.squad_user_width[2] == 0 and m.squad_pos[2] == Vector2.ZERO and m.squad_width[2] == 1
	out.append("150+150 → %d, индекс 2 очищен, выбор на целевом: %s" % [m.squad_n[0], ok])
	var ok2: bool = m._cmd_new_squad() and m.sel_primary == 2 and m.squad_n[2] == 0
	out.append("освобождённый индекс 2 занят снова: %s" % ok2)
	# выбран отряд 0: другой вливается в него (0 не освобождается)
	m._squad_add_units(2, m.infantry_type, 40)
	m._select_only(0)
	var ok3: bool = m._cmd_merge() and m.squad_n[0] == 340 and m.squad_used[0] == 1 and m.squad_used[2] == 0 and m.sel_primary == 0 and grid_ok(m, 0)
	out.append("выбран отряд 1 (индекс 0): отряд 3 вливается в него, 300+40 → %d: %s" % [m.squad_n[0], ok3])
	# большой отряд: 600 + 600
	m._squad_add_units(0, m.infantry_type, 260)
	m._cmd_new_squad()
	m._squad_add_units(2, m.infantry_type, 600)
	m._select_only(2)
	var ok4: bool = m._cmd_merge() and m.squad_n[0] == 1200 and m.squad_width[0] <= m.WIDTH_MAX and m.squad_rows[0] <= m.ROWS_MAX and grid_ok(m, 0) and integrity(m) == ""
	out.append("600+600 → %d, строй %d × %d: %s" % [m.squad_n[0], m.squad_width[0], m.squad_rows[0], ok4])
	m._select_only(1)
	m.hud_msg = ""
	var ok5: bool = not m._cmd_merge() and m.hud_msg != "" and m.squad_n[1] == 100
	out.append("нет другого отряда лучников: отказ «%s»: %s" % [m.hud_msg, ok5])
	print("(д) слияние: " + "\n    ".join(out))
	m.free()

func test_cleanup() -> void:
	var m := new_main(NEW, 1, true)
	m.gold = 1e9
	m._cmd_new_squad()   # 2, пехота
	m._buy(0)
	m._cmd_new_squad()   # 3, пусто
	m._select_only(2)
	for i in m.count:
		if m.unit_squad[i] == 2 or m.unit_squad[i] == 1:
			m.hp[i] = 0.0   # выбиты отряд 3 и все лучники (отряд 2)
	m._remove_dead()
	m.wave_number = 1
	m.wave_state = m.WS_BATTLE
	m._wave_cleared()
	var ok: bool = m.squad_used[2] == 0 and m.squad_used[3] == 0 and m.squad_used[0] == 1 and m.squad_used[1] == 1 and m.squad_n[1] == 0 and m.sel_primary == 0 and integrity(m) == ""
	print("(е) очистка при входе в передышку: пустые отряды 3 и 4 освобождены, пустой отряд 2 (лучники) остался, выбор ушёл на отряд 1: %s" % ok)
	# 20 циклов: создание, покупка, разделение, слияние, гибель; целостность после каждого шага
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var bad := []
	var ops := [0, 0, 0, 0]
	var max_used := 0
	for cycle in 20:
		for step in 8:
			var used := []
			for s in m.SQUAD_MAX:
				if m.squad_used[s] == 1:
					used.append(s)
			m._select_only(used[rng.randi_range(0, used.size() - 1)])
			match rng.randi_range(0, 4):
				0:
					ops[0] += int(m._cmd_new_squad())
				1, 2:
					ops[1] += int(m._buy(rng.randi_range(0, 1)))
				3:
					ops[2] += int(m._cmd_split())
				4:
					ops[3] += int(m._cmd_merge())
			var e := integrity(m)
			if e != "":
				bad.append("цикл %d: %s" % [cycle, e])
		max_used = maxi(max_used, used_list(m).size())
		for t in 10:
			m._physics_process(1.0 / 30.0)   # передышка: пустые и свежие отряды в циклах тика
		m.wave_state = m.WS_BATTLE
		var doomed := rng.randi_range(0, m.SQUAD_MAX - 1)   # один отряд гибнет целиком, остальные теряют часть
		for i in m.count:
			if m.unit_squad[i] == doomed or rng.randf() < 0.2:
				m.hp[i] = 0.0
		m._remove_dead()
		m._update_squads(0.6)
		m.wave_number += 1
		m._wave_cleared()
		var e2 := integrity(m)
		for s in range(2, m.SQUAD_MAX):
			if m.squad_used[s] == 1 and m.squad_n[s] == 0:
				e2 = "пустой отряд %d не освобождён" % s
			if m.squad_used[s] == 1 and not grid_ok(m, s, false):   # после потерь колонки разной глубины — это норма
				e2 = "сетка отряда %d нарушена" % s
		if e2 != "":
			bad.append("цикл %d после волны: %s" % [cycle, e2])
	print("    20 циклов (создано %d, покупок %d, разделений %d, слияний %d, до %d отрядов сразу): нарушений %d %s; в конце %s" % [
		ops[0], ops[1], ops[2], ops[3], max_used, bad.size(), bad.slice(0, 3), used_list(m)])
	m.free()

func archers_run(seed: int) -> Dictionary:
	var m := new_main(NEW, seed, true)
	m._select_only(1)
	m._cmd_split()   # лучники: 1 и 2 по 50
	var b: int = m.sel_primary
	m._place_formation(1, Vector2(900, 400), Vector2(1040, 400))   # ближе к орде
	m._place_formation(b, Vector2(900, 560), Vector2(1040, 560))   # дальше
	teleport(m, 1)
	teleport(m, b)
	m.squad_order[1] = m.ORDER_ATTACK
	m.squad_order[b] = m.ORDER_HOLD
	m._start_wave()
	var tr := PackedVector2Array()
	var res := {"b": b, "mode_diff": 0, "t_diff": 0, "first": [-1, -1], "dev": [0.0, 0.0]}
	for t in 600:
		m._physics_process(1.0 / 30.0)
		tr.append(checksum(m))
		if m.squad_volley_mode[1] != m.squad_volley_mode[b]:
			res.mode_diff += 1
		if m.squad_volley_t[1] != m.squad_volley_t[b] or m.squad_volley_fired[1] != m.squad_volley_fired[b]:
			res.t_diff += 1
		var q := 0
		for s in [1, b]:
			if res.first[q] < 0 and m.squad_arrows_fired[s] > 0:
				res.first[q] = t
			for i in m.count:
				if m.unit_squad[i] == s:
					res.dev[q] = maxf(res.dev[q], m.pos[i].distance_to(slot_world(m, i)))
			q += 1
	res.fired = [m.squad_arrows_fired[1], m.squad_arrows_fired[b]]
	res.switches = [m.squad_mode_switches[1], m.squad_mode_switches[b]]
	res.total = m.arrows_fired
	res.total_sw = m.mode_switches
	res.trace = tr
	m.free()
	return res

func test_archers() -> void:
	var r := archers_run(3)
	var r2 := archers_run(3)
	var same: bool = r.trace == r2.trace
	var ok: bool = r.fired[0] > 0 and r.fired[1] > 0 and r.fired[0] + r.fired[1] == r.total and r.switches[0] + r.switches[1] == r.total_sw
	ok = ok and r.mode_diff > 0 and r.t_diff > 0 and r.first[0] != r.first[1]
	print("(ж) два отряда лучников (индексы 1 и %d, по 50; первый «атака», второй «держать»), волна 1, 600 тиков:" % r.b)
	print("    стрел %d и %d (сумма %d = общий счётчик %d), первый выстрел на тиках %d и %d, смен режима %d и %d" % [
		r.fired[0], r.fired[1], r.fired[0] + r.fired[1], r.total, r.first[0], r.first[1], r.switches[0], r.switches[1]])
	print("    тиков с разным режимом %d, с разной фазой залпа %d; макс. отклонение от слота: «атака» %.1f px, «держать» %.1f px; независимы: %s; два прогона совпали: %s" % [
		r.mode_diff, r.t_diff, r.dev[0], r.dev[1], ok, same])

# Бой без волн (300 зомби): three = false — обычный состав (пехота 300 одним отрядом), true — три отряда по 100
# с приказами «атака», «держать», «отход» и разными целями. Возвращает [потери игрока, потери зомби, проверки].
func battle(seed: int, mode: int) -> Array:
	var three := mode == 1 or mode == 2 or mode == 4 or mode == 6
	var orders := mode == 2
	var m := new_main(NEW, seed, false)
	var checks := {"retreat_hit": 0, "became_hold": false, "arrived": false, "hold_dev": 0.0, "attack_dev": 0.0}
	var a := 0
	var b := -1
	var c := -1
	if three:
		m.wave_state = m.WS_RESPITE   # подготовка как в передышке
		m.gold = 1e9
		var ids := units_of(m, 0)
		for q in range(200, 300):
			m.hp[ids[q]] = 0.0
		m._remove_dead()
		m._update_squads(0.6)
		m.first_death_tick = -1
		m._select_only(0)
		m._cmd_split()   # 100 + 100
		b = m.sel_primary
		m._cmd_new_squad()
		c = m.sel_primary
		m._buy(0)
		m._buy(0)   # 100 в третий отряд
		m._select_only(0)
		m.wave_state = m.WS_BATTLE
		for s in [a, b, c]:
			m.squad_pos[s] = Vector2(1010, 740)   # центр ниже линии: строй встанет лицом вверх
		if mode == 4:
			# рядом в одну линию: три блока 18 × 6
			m._place_formation(a, Vector2(960, 620), Vector2(1060, 620))
			m._place_formation(b, Vector2(840, 620), Vector2(940, 620))
			m._place_formation(c, Vector2(1080, 620), Vector2(1180, 620))
		else:
			# друг за другом, по 20 × 5: вместе занимают те же слоты, что обычный блок 20 × 15 (ряды y 598..682)
			m._place_formation(a, Vector2(953, 598), Vector2(1067, 598))
			m._place_formation(b, Vector2(953, 628), Vector2(1067, 628))
			m._place_formation(c, Vector2(953, 658), Vector2(1067, 658))
		for s in [a, b, c]:
			teleport(m, s)
		if mode == 6:
			for s in [a, b, c]:
				m.squad_user_width[s] = 0   # контроль: без заданной ширины
		if mode == 2:
			m.squad_order[b] = m.ORDER_HOLD      # средний держит
			m.squad_order[c] = m.ORDER_RETREAT   # задний отходит вправо-назад
			m.squad_target[c] = Vector2(1130, 700)
	elif mode == 7:
		# контроль подготовки: те же гибель 100 и покупка 100, но всё в отряде 0, блок 20 × 15
		m.wave_state = m.WS_RESPITE
		m.gold = 1e9
		var ids7 := units_of(m, 0)
		for q in range(200, 300):
			m.hp[ids7[q]] = 0.0
		m._remove_dead()
		m._update_squads(0.6)
		m.first_death_tick = -1
		m._select_only(0)
		m._buy(0)
		m._buy(0)
		m.wave_state = m.WS_BATTLE
		m.squad_pos[0] = Vector2(1010, 740)
		m._place_formation(0, Vector2(953, 598), Vector2(1067, 598))
		teleport(m, 0)
	elif mode == 5:
		# контроль: обычный блок 20 × 15, но поставленный перетаскиванием (ширина задана)
		m.squad_pos[0] = Vector2(1010, 740)
		m._place_formation(0, Vector2(953, 598), Vector2(1067, 598))
		teleport(m, 0)
	elif mode == 3:
		# тот же состав одним отрядом, но в линию 58 × 6 (как три отряда рядом)
		m.squad_pos[0] = Vector2(1010, 740)
		m._place_formation(0, Vector2(840, 620), Vector2(1180, 620))
		teleport(m, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var start := [0, 0]
	for i in m.count:
		start[m.team[i]] += 1
	var left: Array = start.duplicate()
	var last_death := -1
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if orders:
			if m.squad_order[c] == m.ORDER_RETREAT:
				for i in m.count:
					if m.unit_squad[i] == c and m.cooldown[i] > 0.0:
						checks.retreat_hit += 1   # при отходе не бьют: cooldown не взводится
			elif not checks.became_hold:
				checks.became_hold = m.squad_order[c] == m.ORDER_HOLD
				checks.arrived = m.squad_pos[c].distance_to(m.squad_target[c]) <= 1.0
			for i in m.count:
				if m.unit_squad[i] == b:
					checks.hold_dev = maxf(checks.hold_dev, m.pos[i].distance_to(slot_world(m, i)))
				elif m.unit_squad[i] == a:
					checks.attack_dev = maxf(checks.attack_dev, m.pos[i].distance_to(slot_world(m, i)))
		if m.count < before:
			last_death = t
			left = [0, 0]
			for i in m.count:
				left[m.team[i]] += 1
		if left[0] == 0 or left[1] == 0 or (last_death > 0 and t - last_death >= 90):
			break
	checks.orders = [m.squad_order[a], m.squad_order[b] if b >= 0 else -1, m.squad_order[c] if c >= 0 else -1]
	checks.start = start
	m.free()
	return [start[0] - left[0], start[1] - left[1], checks]

func test_battle() -> void:
	var names := ["обычный состав: пехота 300 одним блоком 20 × 15", "три отряда по 100 друг за другом в тех же слотах, все «атака»", "те же три отряда: передний «атака», средний «держать», задний «отход» в сторону", "пехота 300 одним отрядом в линию 58 × 6", "три отряда по 100 рядом в ту же линию (18 × 6 каждый), все «атака»", "контроль: обычный блок 20 × 15, поставленный перетаскиванием (ширина задана)", "контроль: три отряда друг за другом, ширина авто", "контроль: один отряд 20 × 15 после той же подготовки (гибель 100, покупка 100)"]
	var base := [0, 0, 0, 0, 3, 0, 0, 0]   # с чем сравнивать
	var sums := [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]
	var mean := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var retreat_hits := 0
	var holds := 0
	var hold_dev := 0.0
	var attack_dev := 0.0
	var orders_ok := true
	var start := []
	for seed in range(1, 21):
		for v in 8:
			var r := battle(seed, v)
			sums[v][0] += r[0]
			sums[v][1] += r[1]
			mean[v] += r[1] / float(maxi(r[0], 1)) / 20.0
			if v == 2:
				retreat_hits += r[2].retreat_hit
				holds += int(r[2].became_hold and r[2].arrived)
				hold_dev = maxf(hold_dev, r[2].hold_dev)
				attack_dev = maxf(attack_dev, r[2].attack_dev)
				orders_ok = orders_ok and r[2].orders == [0, 1, 1]
				start = r[2].start
	print("(з) бой без волн, 20 seed, %d игрока против %d зомби; ratio = потери зомби / потери игрока:" % [start[0], start[1]])
	for v in 8:
		var dev: float = (mean[v] / mean[base[v]] - 1.0) * 100.0
		print("    %s: потери %.1f / %.1f, ratio %.3f%s" % [names[v], sums[v][0] / 20.0, sums[v][1] / 20.0, mean[v],
			"" if v == 0 or v == 3 else " (%+.1f%% к %s, допуск ±15%%: %s)" % [dev, "обычному" if base[v] == 0 else "одному отряду в линию", absf(dev) <= 15.0]])
	print("    приказы по отрядам: при «отходе» ударов %d; дошёл до цели и встал «держать» в %d боях из 20; в конце приказы атака/держать/держать: %s; макс. отклонение от слота: «держать» %.1f px, «атака» %.1f px" % [
		retreat_hits, holds, orders_ok, hold_dev, attack_dev])

func scripted(seed: int) -> PackedVector2Array:
	var m := new_main(NEW, seed, true)
	m.gold = 5000.0
	var tr := PackedVector2Array()
	var wave := 0
	for t in 30 * 240:
		if m.wave_state == m.WS_RESPITE:
			if wave == 3:
				break
			match wave:
				0:
					m._select_only(0)
					m._cmd_new_squad()     # отряд пехоты
					m._buy(0)
					m._select_only(1)
					m._cmd_split()         # лучники пополам
					m._place_formation(m.sel_primary, Vector2(1080, 600), Vector2(1200, 600))
					m._select_only(0)
					m._place_formation(0, Vector2(900, 560), Vector2(1100, 560))
				1:
					m._select_only(2)
					m._cmd_merge()         # созданный отряд пехоты вливается в отряд 0
					m._buy(1)
					m._select_only(0)
					m._cmd_split()
					m._place_formation(m.sel_primary, Vector2(820, 600), Vector2(900, 520))
				2:
					m._select_only(1)
					m._cmd_merge()
					m._cmd_new_squad()
					m._buy(1)
					m._buy(0)
					m._select_only(0)
					m._cmd_merge()
			wave += 1
			m._start_wave()
		m._physics_process(1.0 / 30.0)
		tr.append(checksum(m))
	tr.append(Vector2(m.wave_number, m.count))
	var e := integrity(m)
	if e != "":
		print("    ОШИБКА целостности в сценарии: " + e)
	m.free()
	return tr

func test_determinism() -> void:
	var r1 := scripted(5)
	var r2 := scripted(5)
	var d := -1
	for k in mini(r1.size(), r2.size()):
		if r1[k] != r2[k]:
			d = k
			break
	print("(и) 3 волны с N, G, M, покупками и расстановкой, два прогона seed 5: %s (%d тиков, пройдено волн %d, юнитов в конце %d)" % [
		"совпадает на каждом тике" if d < 0 and r1.size() == r2.size() else "расходится с тика %d" % d, r1.size() - 1, int(r1[r1.size() - 1].x), int(r1[r1.size() - 1].y)])

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	if OS.get_cmdline_user_args().has("battle"):
		test_battle()
		quit()
		return
	print("(а) без N/G/M против bak28, waves off: " + compare(false))
	print("    то же с волнами и покупками пехоты и лучников: " + compare(true))
	test_create_buy()
	test_split()
	test_merge()
	test_cleanup()
	test_archers()
	test_battle()
	test_determinism()
	quit()
