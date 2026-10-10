extends SceneTree
# v14: regress | jitter | course <script> <lstart> <lend> [shape]
const BIG := 100000.0

func set_soft(m: Node2D, l0: float, l1: float) -> void:
	var inf: int = m.type_id["infantry"]
	m.type_leash_start[inf] = l0
	m.type_leash_start_sq[inf] = l0 * l0
	m.type_leash_end[inf] = l1

func regress() -> void:
	var a: Node2D = load("res://bench/main_bak14.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a._setup_data()
	b._setup_data()
	a.type_leash_sq[a.type_id["infantry"]] = BIG * BIG
	set_soft(b, BIG, BIG)
	var first := -1
	for t in range(1, 30 * 30 + 1):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp):
			first = t
	print("(а) leash_start = leash_end = 100000 против bak14 без привязи: " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first) + "; leash_ticks=%d" % b.leash_ticks)
	a.free()
	b.free()

# Дёрганье: смены знака скорости (dot соседних vel < 0) на юнит-секунду, у игрока, в фазе боя.
func jitter_one(script_path: String, mode: String, rng_seed: int, acc: Array) -> void:
	var m: Node2D = load(script_path).new()
	m.spawn_seed = rng_seed
	m._setup_data()
	if mode == "none":
		if "type_leash_sq" in m:
			m.type_leash_sq[m.type_id["infantry"]] = BIG * BIG
		else:
			set_soft(m, BIG, BIG)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var prev := PackedVector2Array()
	prev.resize(m.UNIT_COUNT)
	var started := false
	var last_death := -1
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if m.count < before:
			started = true
			last_death = t
		var front := 1 << 30
		var width: int = m.squad_width[0]
		for i in m.count:
			if m.unit_squad[i] == 0:
				front = mini(front, m.unit_slot_idx[i] / width)
		var a := [0, 0]
		for i in m.count:
			a[m.team[i]] += 1
			if m.unit_squad[i] != 0:
				continue
			var u: int = m.unit_uid[i]
			var v: Vector2 = m.vel[i]
			if started:
				var g := 0 if m.unit_slot_idx[i] / width < front + 3 else 1
				acc[g * 2 + 1] += 1
				var pv: Vector2 = prev[u]
				if pv.length_squared() > 1e-6 and v.length_squared() > 1e-6 and pv.dot(v) < 0.0:
					acc[g * 2] += 1
			prev[u] = v
		if a[0] == 0 or a[1] == 0 or (last_death > 0 and t - last_death >= 90):
			break
	m.free()

func jitter() -> void:
	for cfg in [["res://bench/main_bak14_uid.gd", "hard", "bak14, жёсткая 24"], ["res://bench/main_v14_uid.gd", "soft", "мягкая 6/24"], ["res://bench/main_v14_uid.gd", "none", "без привязи"]]:
		var acc := [0, 0, 0, 0]   # смены и юнито-тики: первые 3 ряда, остальные
		for s in range(1, 11):
			jitter_one(cfg[0], cfg[1], s, acc)
		print("(б) %-18s первые 3 ряда: %.3f смен/юнит·с (%d за %d юнит·с);  остальные: %.3f (%d за %d юнит·с)" % [
			cfg[2], acc[0] / (acc[1] / 30.0), acc[0], acc[1] / 30, acc[2] / maxf(acc[3] / 30.0, 1.0), acc[2], acc[3] / 30])

func shape(m: Node2D) -> String:
	var width: int = m.squad_width[0]
	var h := {}
	for i in m.count:
		if m.unit_squad[i] == 0:
			h[m.unit_slot_idx[i] % width] = h.get(m.unit_slot_idx[i] % width, 0) + 1
	if h.is_empty():
		return "отряда нет"
	var lo := 1 << 30
	var hi := 0
	for c in h:
		lo = mini(lo, h[c])
		hi = maxi(hi, h[c])
	var dev := 0.0   # средний уход юнита от своего слота, px
	var n := 0
	for i in m.count:
		if m.unit_squad[i] == 0:
			dev += m.pos[i].distance_to(m.squad_pos[0] + m.unit_slot[i].rotated(m.squad_angle[0]))
			n += 1
	return "сетка %dx%d, колонок %d, глубина %d–%d, средний уход от слота %.1f px" % [width, m.squad_rows[0], h.size(), lo, hi, dev / n]

func course(script_path: String, l0: float, l1: float, with_shape: bool) -> void:
	var m: Node2D = load(script_path).new()
	m._setup_data()
	set_soft(m, l0, l1)
	var line := ""
	var times := PackedFloat64Array()
	var n0: int = m.count
	print("== %s, мягкая %d/%d" % [script_path.get_file().get_basename(), l0, l1])
	for t in range(1, 60 * 30 + 1):
		var dense: bool = m.count * 2 >= n0
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		if dense:
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
		if t % 90 == 0:
			var a := [0, 0]
			for i in m.count:
				a[m.team[i]] += 1
			line += " %d:%d" % [a[0], a[1]]
			if with_shape and t % 450 == 0:
				line += " [" + shape(m) + "]"
			if t % 900 == 0:
				print("   до %2d с:%s" % [t / 30, line])
				line = ""
	if with_shape:
		var mean := 0.0
		for x in times:
			mean += x
		mean /= maxi(times.size(), 1)
		times.sort()
		print("   тик (1 прогон, плотная фаза %d тиков): средний %.2f мс, p99 %.2f, max %.2f" % [times.size(), mean, times[ceili(times.size() * 0.99) - 1], times[times.size() - 1]])
	print("   leash_ticks=%d, блоков %.1f%% от %d ударов по пехоте" % [m.leash_ticks, 100.0 * m.blocked_hits / maxi(m.total_hits, 1), m.total_hits])
	m.free()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	match args[0]:
		"regress":
			regress()
		"jitter":
			jitter()
		"course":
			course(args[1], float(args[2]), float(args[3]), args.size() > 4)
	quit()