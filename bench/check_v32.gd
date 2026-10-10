extends SceneTree
# Тесты v32 (бегуны, павшие рыцари, три стороны, разведка): (а) регрессия против bak32, (б) план волн 1-30,
# (в) появление с трёх сторон, (г) chase, (д) золото.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/main_bak32.gd"
const SIDE_NAMES := ["верх", "лево", "право"]

func new_main(path: String, seed: int, waves: bool) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func compare(waves: bool) -> String:
	var a := new_main(OLD, 1, waves)
	var b := new_main(NEW, 1, waves)
	var first := -1
	var ticks := 0
	for t in range(1, 901 if not waves else 3001):
		if waves and a.wave_state == a.WS_RESPITE:
			if a.wave_number == 2:
				break
			for m in [a, b]:
				m._buy(0)
				m._buy(1)
				m._start_wave()
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		ticks = t
		if first < 0:
			if a.count != b.count or a.gate_hp != b.gate_hp or a.gold != b.gold or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.unit_slot_idx[i] != b.unit_slot_idx[i] or a.unit_type[i] != b.unit_type[i]:
						first = t
						break
	var res := ("совпадает на всех %d тиках" % ticks if first < 0 else "расходится с тика %d" % first) + " (юнитов %d, золото %d)" % [b.count, int(b.gold)]
	a.free()
	b.free()
	return res

func plan_key(plan: Array) -> String:
	var parts := []
	for r in plan:
		parts.append("%d/%d/%d" % [r.type, r.side, r.count])
	return ",".join(parts)

func test_plan() -> void:
	var bad := []
	var sides_seen := {}
	var rows := []
	for seed in [1, 2, 3]:
		var m := new_main(NEW, seed, true)
		var m2 := new_main(NEW, seed, true)
		var cfg: Dictionary = m.wave_cfg
		for w in range(1, 31):
			var plan: Array = m._plan_wave(w)
			var total: int = m._wave_count(w)
			var sum := 0
			var by_type := {}
			var by_side := [0, 0, 0]
			var runners_side := [0, 0, 0]
			var pk_side := [0, 0, 0]
			for r in plan:
				sum += r.count
				by_type[r.type] = by_type.get(r.type, 0) + r.count
				by_side[r.side] += r.count
				if r.type == m.runner_type:
					runners_side[r.side] += r.count
				else:
					pk_side[r.side] += r.count
				if r.count <= 0:
					bad.append("seed %d волна %d: пустая запись" % [seed, w])
			var share := 0.0
			if w >= int(cfg.sides_from_wave):
				share = cfg.runner_share
			elif w >= int(cfg.runner_from_wave):
				share = cfg.runner_share_early
			var exp_runners := roundi(total * share)
			var exp_knights := 0
			if w >= int(cfg.knight_from_wave):
				exp_knights = mini(roundi((w - int(cfg.knight_from_wave) + 1) * cfg.knight_per_wave * 2.0), int(cfg.knight_cap))
			var laterals := int(by_side[1] > 0) + int(by_side[2] > 0)
			var ok: bool = sum == total and by_type.get(m.runner_type, 0) == exp_runners and by_type.get(m.knight_type, 0) == exp_knights
			ok = ok and by_type.get(m.zombie_type, 0) == total - exp_runners - exp_knights and by_side[0] > 0
			if w < int(cfg.sides_from_wave):
				ok = ok and laterals == 0 and runners_side[1] + runners_side[2] == 0   # до sides_from_wave боковых сторон нет
			else:
				ok = ok and laterals >= 1 and runners_side[0] == 0 and absi(runners_side[1] - runners_side[2]) <= (1 if laterals == 2 else exp_runners)
				# веса: верх 2, боковая 1 (с точностью до округления)
				var pk: int = pk_side[0] + pk_side[1] + pk_side[2]
				for side in [1, 2]:
					if by_side[side] > 0:
						ok = ok and absf(pk_side[side] - pk / float(2 + laterals)) <= 1.0
			ok = ok and plan_key(plan) == plan_key(m2._plan_wave(w))   # детерминизм: второй экземпляр с тем же seed
			if not ok:
				bad.append("seed %d волна %d: %s" % [seed, w, plan_key(plan)])
			sides_seen["%d%d" % [int(by_side[1] > 0), int(by_side[2] > 0)]] = sides_seen.get("%d%d" % [int(by_side[1] > 0), int(by_side[2] > 0)], 0) + 1
			if seed == 1 and w in [1, 3, 5, 7, 10, 20, 30]:
				rows.append("      волна %d (%d): верх %d, лево %d, право %d; бегуны %d, рыцари %d" % [w, total, by_side[0], by_side[1], by_side[2], by_type.get(m.runner_type, 0), by_type.get(m.knight_type, 0)])
		m.free()
		m2.free()
	print("(б) план волн 1-30, seed 1-3: сумма = count(w), бегуны и рыцари по формулам, стороны по правилам, два экземпляра дают одинаковые планы; ошибок %d %s" % [bad.size(), bad.slice(0, 3)])
	print("    сочетания боковых сторон на 90 планах (лево-право): %s; примеры (seed 1):\n%s" % [sides_seen, "\n".join(rows)])

# Волна w целиком: все подволны появляются; проверки на каждом тике.
func spawn_wave(seed: int, w: int) -> String:
	var m := new_main(NEW, seed, true)
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m.wave_number = w - 1
	m._start_wave()
	var plan_sides := [0, 0, 0]
	for r in m.wave_plan:
		plan_sides[r.side] += r.count
	var total: int = m.wave_remaining
	var spawned := [0, 0, 0]
	var by_type := {}
	var max_alive := 0
	var max_count := 0
	var errors := 0
	var lim := Vector2(m.FIELD.x, m.WALL_Y - 20.0)
	var centres := [Vector2(m.wave_cfg.spawn_center_x, m.wave_cfg.spawn_front_y), Vector2(m.wave_cfg.spawn_left_x, m.wave_cfg.spawn_left_y), Vector2(m.wave_cfg.spawn_right_x, m.wave_cfg.spawn_right_y)]
	var t := 0
	while m.wave_remaining > 0 and t < 20000:
		var before: int = m.count
		var left_before: int = m.wave_remaining
		m._update_waves(1.0 / 30.0)   # появление отдельно от остального тика: новые юниты — в конце массивов
		if m.wave_remaining < left_before:
			for i in range(before, m.count):
				var p: Vector2 = m.pos[i]
				if m.unit_squad[i] != -1 or m.team[i] != 1 or p.x < 0.0 or p.x > lim.x or p.y < 0.0 or p.y > lim.y:
					errors += 1
				var side := 0
				for q in [1, 2]:
					if p.distance_to(centres[q]) < p.distance_to(centres[side]):
						side = q
				spawned[side] += 1
				by_type[m.unit_type[i]] = by_type.get(m.unit_type[i], 0) + 1
			if m.count - before != left_before - m.wave_remaining:
				errors += 1
		max_alive = maxi(max_alive, m.zombie_alive)
		max_count = maxi(max_count, m.count)
		if m.zombie_alive > int(m.wave_cfg.max_alive) or m.count > m.MAX_UNITS:
			errors += 1
		# остальной тик без _update_waves
		m.wave_state = m.WS_RESPITE
		m._physics_process(1.0 / 30.0)
		m.wave_state = m.WS_BATTLE
		t += 1
	var ok: bool = errors == 0 and spawned == plan_sides and m.wave_remaining == 0 and spawned[0] + spawned[1] + spawned[2] == total
	var res := "волна %d (seed %d): план верх/лево/право %s, появилось %s; типы: крестьяне %d, бегуны %d, рыцари %d; пик живых зомби %d (предел %d), пик юнитов %d (предел %d); ошибок %d: %s" % [
		w, seed, plan_sides, spawned, by_type.get(m.zombie_type, 0), by_type.get(m.runner_type, 0), by_type.get(m.knight_type, 0), max_alive, int(m.wave_cfg.max_alive), max_count, m.MAX_UNITS, errors, ok]
	m.free()
	return res

# Seed, при котором у волны w активны обе боковые стороны.
func seed_three_sides(w: int) -> int:
	for seed in range(1, 200):
		var m := new_main(NEW, seed, true)
		var sides := {}
		for r in m._plan_wave(w):
			sides[r.side] = true
		m.free()
		if sides.size() == 3:
			return seed
	return -1

func test_spawn() -> void:
	for w in [5, 10, 30]:
		print("(в) " + spawn_wave(seed_three_sides(w), w))

# Одиночный юнит орды типа type в точке p рядом с пехотинцем victim: что он решает за одно обновление.
func decide(m: Node2D, type: int, p: Vector2, victim: int) -> Dictionary:
	m._spawn_zombie(p, type)
	var z: int = m.count - 1
	m.cooldown[z] = 0.0
	var hp0: float = m.hp[victim]
	m._build_grid()
	m._update_unit(z, 1.0 / 15.0)
	var to_enemy: Vector2 = (m.pos[victim] - p).normalized()
	var to_goal: Vector2 = (m.HORDE_GOAL - p).normalized()
	var v: Vector2 = m.vel[z]
	var r := {"speed": v.length(), "to_enemy": v.normalized().dot(to_enemy) if v.length() > 0.1 else 0.0, "to_goal": v.normalized().dot(to_goal) if v.length() > 0.1 else 0.0, "hit": hp0 - m.hp[victim]}
	m.hp[victim] = hp0
	m.hp[z] = 0.0
	m._remove_dead()
	return r

func test_chase() -> void:
	var m := new_main(NEW, 1, true)
	m.gold = 0.0
	# жертва: самый левый пехотинец переднего ряда; зомби слева от него (к цели — вниз-вправо, к врагу — вправо)
	var victim := -1
	for i in m.count:
		if m.unit_squad[i] == 0 and (victim < 0 or m.pos[i].x < m.pos[victim].x - 0.1 or (absf(m.pos[i].x - m.pos[victim].x) <= 0.1 and m.pos[i].y < m.pos[victim].y)):
			victim = i
	var vp: Vector2 = m.pos[victim]
	var out := []
	var ok := true
	for d in [10.0, 5.0]:
		var r_run := decide(m, m.runner_type, vp + Vector2(-d, 0), victim)
		var r_pea := decide(m, m.zombie_type, vp + Vector2(-d, 0), victim)
		if d == 10.0:
			ok = ok and r_run.to_goal > 0.99 and r_run.hit == 0.0 and r_pea.to_enemy > 0.8 and r_pea.hit == 0.0
			out.append("враг в 10 px (виден, вне дальности 7): бегун идёт к цели (cos к цели %.2f, скорость %.0f), крестьянин сворачивает к врагу (cos к врагу %.2f)" % [r_run.to_goal, r_run.speed, r_pea.to_enemy])
		else:
			ok = ok and r_run.hit > 0.0 and r_pea.hit > 0.0 and r_run.speed < 1.0 and r_pea.speed < 1.0
			out.append("враг в 5 px (в дальности): бьют оба (урон бегуна %.2f, крестьянина %.2f), оба стоят" % [r_run.hit, r_pea.hit])
	# траектория: оба идут сверху вниз в 10 px слева от фланга строя (приказ «держать», чтобы пехота не выходила из строя)
	var res := []
	for type in [m.runner_type, m.zombie_type]:
		var mm := new_main(NEW, 1, true)
		mm.squad_order[0] = mm.ORDER_HOLD
		mm.gate_hp = 1e9
		# путь к воротам — вертикаль x = 1010; левый фланг пехоты ставим на x = 1020 (в 10 px от пути), лучников убираем
		mm._place_formation(0, Vector2(1020, 450), Vector2(1134, 450))
		mm.squad_pos[1] = Vector2(400, 300)
		mm.squad_target[1] = mm.squad_pos[1]
		for i in mm.count:
			if mm.unit_squad[i] >= 0:
				mm.pos[i] = mm.squad_pos[mm.unit_squad[i]] + mm.unit_slot[i].rotated(mm.squad_angle[mm.unit_squad[i]])
		var start := Vector2(1010, 300)
		mm._spawn_zombie(start, type)
		var z: int = mm.count - 1
		mm.hp[z] = 1000.0   # чтобы дошёл: смотрим только путь
		mm.unit_rand[z] = 0.5   # без разброса скорости
		var turned := 0.0
		for t in 105:
			mm._physics_process(1.0 / 30.0)
			turned = maxf(turned, mm.pos[z].x - start.x)
		res.append([mm.pos[z].y - start.y, turned])
		mm.free()
	ok = ok and res[0][0] > 300.0 and res[0][1] < 2.0 and res[1][0] < 250.0 and res[1][1] > 3.0
	out.append("за 3.5 с вдоль фланга строя (в 10 px от него): бегун прошёл вниз %.0f px и сместился к строю на %.1f px, крестьянин прошёл %.0f px и свернул к строю на %.1f px" % [res[0][0], res[0][1], res[1][0], res[1][1]])
	print("(г) chase: %s: %s" % ["; ".join(out), ok])
	m.free()

func test_gold() -> void:
	var m := new_main(NEW, 1, true)
	var out := []
	var ok := true
	for c in [[m.zombie_type, "крестьянин"], [m.runner_type, "бегун"], [m.knight_type, "рыцарь"]]:
		var g0: float = m.gold
		m._spawn_zombie(Vector2(100, 100), c[0])
		m.hp[m.count - 1] = 0.0
		m._remove_dead()
		var gain: float = m.gold - g0
		ok = ok and is_equal_approx(gain, m.wave_cfg.gold_per_kill * m.type_bounty_mult[c[0]])
		out.append("%s +%.1f" % [c[1], gain])
	var g1: float = m.gold
	for i in m.count:
		if m.unit_squad[i] == 0:
			m.hp[i] = 0.0
			break
	m._remove_dead()
	ok = ok and m.gold == g1 and m.wave_kills_by_type[m.knight_type] == 1 and m.wave_kills_by_type[m.runner_type] == 1
	print("(д) золото за убитого (gold_per_kill %.1f): %s; за своего пехотинца золота нет; счётчики по типам верны: %s; строка баннера: «%s»" % [m.wave_cfg.gold_per_kill, ", ".join(out), ok, m._kills_text()])
	m.free()

func _initialize() -> void:
	print("(а) против bak32, waves off: " + compare(false))
	print("    с волнами и покупками, волны 1-2 (до первых бегунов): " + compare(true))
	test_plan()
	test_spawn()
	test_chase()
	test_gold()
	quit()
