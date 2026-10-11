extends SceneTree
# Тесты v38 (радиус лучников 480 px, счётчики до контакта). Режимы:
#   cell — (а) кольцо дальности, (б) выбор плотной клетки на 450 и 500 px, одиночный огонь против прежнего main;
#   series <main.gd> <файл.txt> — (в) 50 боёв 300 пехоты + 100 лучников против 300 зомби;
#   cap — (д) 300 лучников на волнах 5 и 10 слоя 1: arrows_dropped и пик очереди стрел;
#   cost <main.gd> — (е) стоимость выбора плотной клетки, мс на залп;
#   sweep <файл.txt> — 2.3: свип дальности, разброса и периода залпа на реальных волнах 2, 5, 8 слоя 1.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/old/main_v38_before.gd"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func new_main(path: String, rng_seed: int, waves := true) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func clear_zombies(m: Node2D) -> void:
	for i in m.count:
		if m.team[i] == 1:
			m.hp[i] = 0.0
	m._remove_dead()
	m.wave_kills = 0

func add_cluster(m: Node2D, at: Vector2, n: int, rng: RandomNumberGenerator, r := 8.0) -> void:
	for k in n:
		m._spawn_zombie(at + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)), m.zombie_type)

func test_cell() -> void:
	var m := new_main(NEW, 1)
	var arch: int = m.archer_type
	var range_far: float = m.type_range_far[arch]
	check("(а) range_far лучников после масштаба 480 px; кольцо дальности выбранного отряда лучников — 480, у пехоты нет",
		range_far == 480.0 and m._range_ring_radius(1) == 480.0 and m._range_ring_radius(0) == 0.0, "range_far %s" % range_far)
	var sp: Vector2 = m.squad_pos[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var res := []
	var ok := true
	for deg in [-90, -60, -120, -30, -150, 0, 180, -45, -135, -75, -105, -15, -165]:
		var line := "%d°:" % deg
		for dist in [450.0, 500.0]:
			var at: Vector2 = sp + Vector2.from_angle(deg_to_rad(deg)) * dist
			m.count = 400
			m.zombie_alive = 0
			add_cluster(m, at, 30, rng)
			m._rebuild_coarse()
			var cell: int = m._volley_target_cell(1, range_far)
			var picked := cell != -1
			line += " %d px %s" % [dist, "выбран" if picked else "нет"]
			if picked != (dist < range_far):
				ok = false
		res.append(line)
	m.count = 400
	m.zombie_alive = 0
	check("(б) кластер 30 зомби на 450 px от центра лучников выбирается, на 500 px нет (13 направлений)", ok, "; ".join(res))
	m.free()
	# одиночный огонь: тот же выбор цели, что до смены радиуса (ближайший зомби в 3x3 грубых клетках)
	var a := new_main(OLD, 1)
	var b := new_main(NEW, 1)
	var diff := 0
	var diff_near := 0
	var found := 0
	var cases := 0
	for q in 400:
		for x in [a, b]:
			x.count = 400
			x.zombie_alive = 0
		var n := rng.randi_range(1, 6)
		var pts := []
		for k in n:
			pts.append(b.squad_pos[1] + Vector2(rng.randf_range(-320.0, 320.0), rng.randf_range(-320.0, 30.0)))
		for x in [a, b]:
			for p in pts:
				x._spawn_zombie(p, x.zombie_type)
			x._rebuild_coarse()
		for i in range(300, 400, 7):
			cases += 1
			var ja: int = a._nearest_zombie_coarse(a.pos[i], a.type_range_far[a.archer_type])
			var jb: int = b._nearest_zombie_coarse(b.pos[i], b.type_range_far[b.archer_type])
			if jb != -1:
				found += 1
			if ja != jb:
				diff += 1
				if b.pos[i].distance_to(b.pos[jb]) <= 260.0:
					diff_near += 1
	check("(б) одиночный огонь: цель в пределах прежних 260 px выбирается та же (%d случаев, цель есть в %d)" % [cases, found], diff_near == 0 and a.pos[300] == b.pos[300],
		"отличий всего %d — только цели дальше 260 px в угловых клетках окна 3x3 (раньше их отсекал радиус)" % diff)
	check("(б) пороги режима одиночного огня те же", a.NEAR_RANGE == b.NEAR_RANGE and a.MODE_HYST == b.MODE_HYST and a.SINGLE_SCAN_T == b.SINGLE_SCAN_T)
	a.free()
	b.free()

func battle(path: String, rng_seed: int) -> Array:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.waves_enabled = false
	m.archers_follow = true
	m.record_path = "user://record_bench.json"
	m._setup_data()
	m.first_death_tick = -1
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var start := [0, 0]
	for i in m.count:
		start[m.team[i]] += 1
	var a: Array = start.duplicate()
	var last_death := -1
	var end_t := 60 * 30
	var contact := -1
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if contact < 0:
			for i in m.count:
				if m.unit_state[i] == m.ST_ATTACK:
					contact = t
					break
		if m.count < before:
			last_death = t
			a = [0, 0]
			for i in m.count:
				a[m.team[i]] += 1
		if a[0] == 0 or a[1] == 0 or (last_death > 0 and t - last_death >= 90):
			end_t = t
			break
	var has_stats: bool = "kills_by_arrows" in m
	var r := [rng_seed, start[0] - a[0], start[1] - a[1], a[0], a[1], end_t / 30.0, contact / 30.0, m.arrows_fired, m.arrows_hit,
		m.reach_sum / maxi(m.reach_n, 1), m.reach_dist_sum / maxi(m.reach_n, 1),
		m.volleys_before_contact if has_stats else -1, m.arrows_before_contact if has_stats else -1, m.kills_by_arrows if has_stats else -1, m.arrows_dropped]
	m.free()
	return r

func series(path: String, out_name: String) -> void:
	var lines: Array[String] = []
	lines.append("%s: бои %s (орда зомби против отряда, без волн, лучники следуют за пехотой), seed 1..50" % [out_name.get_basename(), path])
	lines.append("Конец боя: 3 с без смертей (от первой смерти) / одна сторона уничтожена / 60 с. Отношение = потери зомби / потери игрока.")
	lines.append("Контакт (столбец) = первый юнит в состоянии «бьёт»; залпы и стрелы «до контакта» = до первого урона по юниту игрока. reach = range_far − расстояние до переднего ряда пехоты.")
	lines.append("")
	lines.append("seed | потери t0 | потери t1 | отношение | конец, с | контакт, с | стрел | попало | reach | до фронта | залпов до конт. | стрел до конт. | убито стрелами")
	var sums := PackedFloat64Array()
	sums.resize(15)
	var ratios := PackedFloat64Array()
	for s in range(1, 51):
		var r := battle(path, s)
		var ratio: float = float(r[2]) / maxi(r[1], 1)
		ratios.append(ratio)
		for k in range(1, 15):
			sums[k] += r[k]
		lines.append("%4d | %9d | %9d | %9.3f | %8.1f | %10.2f | %5d | %6d | %5.1f | %9.1f | %15d | %14d | %13d" % [r[0], r[1], r[2], ratio, r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13]])
	var mean := 0.0
	for x in ratios:
		mean += x
	mean /= 50.0
	var sorted := ratios.duplicate()
	sorted.sort()
	lines.append("")
	lines.append("Итог по 50 боям:")
	lines.append("  потери игрока (team 0, из 400 на старте), среднее: %.1f" % (sums[1] / 50.0))
	lines.append("  отношение потерь t1/t0: среднее %.3f, медиана %.3f, min %.3f, max %.3f" % [mean, (sorted[24] + sorted[25]) * 0.5, sorted[0], sorted[49]])
	lines.append("  средний остаток: team 0 (игрок) %.1f, team 1 (зомби) %.1f; первый контакт %.2f с" % [sums[3] / 50.0, sums[4] / 50.0, sums[6] / 50.0])
	lines.append("  стрел за бой: выпущено %.1f, попало %.1f (%.1f%%), убито стрелами %.1f" % [sums[7] / 50.0, sums[8] / 50.0, 100.0 * sums[8] / maxf(sums[7], 1.0), sums[13] / 50.0])
	lines.append("  reach %.1f px (до переднего ряда пехоты %.1f px); до контакта: залпов %.2f, стрел %.1f; arrows_dropped всего %d" % [sums[9] / 50.0, sums[10] / 50.0, sums[11] / 50.0, sums[12] / 50.0, int(sums[14])])
	var f := FileAccess.open("res://bench/" + out_name, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	for k in range(lines.size() - 6, lines.size()):
		print(lines[k])

# Волна w слоя 1 до конца (или поражения). setup — словарь переопределений лучников: range_far, spread, volley_period, archers.
func wave_run(w: int, rng_seed: int, setup: Dictionary) -> Dictionary:
	var m := new_main(NEW, rng_seed)
	var arch: int = m.archer_type
	if setup.has("range_far"):
		m.type_range_far[arch] = setup.range_far
		m.type_spread[arch] = setup.spread
		m.type_volley_period[arch] = setup.volley_period
	if setup.has("archers"):
		m._squad_add_units(1, arch, setup.archers - m.squad_n[1])
		for i in m.count:
			if m.unit_squad[i] == 1:
				m.pos[i] = m.squad_pos[1] + m.unit_slot[i].rotated(m.squad_angle[1])
		m.gate_hp = 1e9
	var army: int = m.count
	m.wave_number = w - 1
	m.wave_plan_for = -1
	m._start_wave()
	var peak := 0
	var kills_at_contact := -1
	var ticks := 0
	while m.wave_state == m.WS_BATTLE and ticks < 30 * 600:
		m._physics_process(1.0 / 30.0)
		ticks += 1
		peak = maxi(peak, m.arrow_count)
		if kills_at_contact < 0 and m.contact_tick >= 0:
			kills_at_contact = m.kills_by_arrows
	var left := 0
	for i in m.count:
		if m.team[i] == 0:
			left += 1
	var r := {"fired": m.arrows_fired, "hit": m.arrows_hit, "kills": m.kills_by_arrows, "loss": army - left, "volleys": m.volleys_before_contact,
		"before": m.arrows_before_contact, "kills_before": kills_at_contact if kills_at_contact >= 0 else m.kills_by_arrows, "dropped": m.arrows_dropped, "peak": peak,
		"defeat": 1 if m.wave_state == m.WS_DEFEAT else 0, "secs": ticks / 30.0, "zombies": m._wave_count(w)}
	m.free()
	return r

func test_cap() -> void:
	for w in [5, 10]:
		var r := wave_run(w, 1, {"archers": 300})
		check("(д) волна %d слоя 1, 300 лучников: arrows_dropped = 0" % w, r.dropped == 0 and r.fired > 0,
			"стрел %d, пик очереди %d из 2048, %.0f с" % [r.fired, r.peak, r.secs])

func cost(path: String) -> void:
	var m := new_main(path, 2)
	m.wave_number = 9
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m._start_wave()
	for t in 240:
		m._physics_process(1.0 / 30.0)
	m._rebuild_coarse()
	var rf: float = m.type_range_far[m.archer_type]
	var t0 := Time.get_ticks_usec()
	var c := 0
	for k in 2000:
		c += m._volley_target_cell(1, rf)
	var us := (Time.get_ticks_usec() - t0) / 2000.0
	var cells := (floori((m.squad_pos[1].y + rf) / m.COARSE_SIZE) - floori((m.squad_pos[1].y - rf) / m.COARSE_SIZE) + 1) * (floori((m.squad_pos[1].x + rf) / m.COARSE_SIZE) - floori((m.squad_pos[1].x - rf) / m.COARSE_SIZE) + 1)
	print("COST %s: range_far %.0f, выбор плотной клетки %.4f мс на залп (окно до %d грубых клеток до обрезки по полю, зомби %d)" % [path, rf, us / 1000.0, cells, m.zombie_alive])
	m.free()

func sweep(out_name: String) -> void:
	var points := []
	for sp in [0.08, 0.05]:
		for rf in [260.0, 360.0, 480.0, 640.0]:
			points.append({"range_far": rf, "spread": sp, "volley_period": 2.5})
	points.append({"range_far": 480.0, "spread": 0.05, "volley_period": 1.8})
	var lines: Array[String] = []
	lines.append("archer_range_sweep: слой 1, волны 2, 5, 8, seed 1-3, стартовая армия (300 пехоты + 100 лучников) на стартовых местах, приказ «атака».")
	lines.append("Параметры лучников подставляются после загрузки (range_far — уже в px после масштаба); рабочие JSON не меняются. Среднее по 3 seed.")
	lines.append("«До контакта» = до первого урона по юниту игрока. Доля попаданий = попало / выпущено.")
	lines.append("")
	lines.append("range_far | spread | период | волна | зомби | выпущено | попало | доля | убито стрелами | из них до контакта | потери игрока | залпов до конт. | стрел до конт. | поражений")
	var best := -1
	var best_kills := -1.0
	var totals := []
	for q in points.size():
		var p: Dictionary = points[q]
		var tot := {"fired": 0.0, "hit": 0.0, "kills": 0.0, "kills_before": 0.0, "loss": 0.0, "volleys": 0.0, "before": 0.0, "defeat": 0.0}
		for w in [2, 5, 8]:
			var acc := {"fired": 0.0, "hit": 0.0, "kills": 0.0, "kills_before": 0.0, "loss": 0.0, "volleys": 0.0, "before": 0.0, "defeat": 0.0}
			var zombies := 0
			for sd in [1, 2, 3]:
				var r := wave_run(w, sd, p)
				zombies = r.zombies
				for k in acc:
					acc[k] += r[k] / 3.0
					tot[k] += r[k] / 9.0
			lines.append("%9.0f | %6.2f | %6.1f | %5d | %5d | %8.1f | %6.1f | %3.0f%% | %14.1f | %18.1f | %13.1f | %15.2f | %14.1f | %d из 3" % [p.range_far, p.spread, p.volley_period, w, zombies,
				acc.fired, acc.hit, 100.0 * acc.hit / maxf(acc.fired, 1.0), acc.kills, acc.kills_before, acc.loss, acc.volleys, acc.before, roundi(acc.defeat * 3.0)])
		lines.append("%9.0f | %6.2f | %6.1f | все   |       | %8.1f | %6.1f | %3.0f%% | %14.1f | %18.1f | %13.1f | %15.2f | %14.1f | %d из 9" % [p.range_far, p.spread, p.volley_period,
			tot.fired, tot.hit, 100.0 * tot.hit / maxf(tot.fired, 1.0), tot.kills, tot.kills_before, tot.loss, tot.volleys, tot.before, roundi(tot.defeat * 9.0)])
		totals.append(tot)
		if tot.kills_before > best_kills:
			best_kills = tot.kills_before
			best = q
		print(lines[lines.size() - 1])
	var bp: Dictionary = points[best]
	var summary := "Больше всего убитых стрелами до контакта: range_far %.0f, spread %.2f, период %.1f — %.1f за волну (среднее по волнам 2, 5, 8), доля попаданий %.0f%%" % [
		bp.range_far, bp.spread, bp.volley_period, best_kills, 100.0 * totals[best].hit / maxf(totals[best].fired, 1.0)]
	lines.append("")
	lines.append(summary)
	print(summary)
	var f := FileAccess.open("res://bench/" + out_name, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	match args[0]:
		"cell":
			test_cell()
			print("CHECK: провалов %d" % fails)
		"series":
			series(args[1], args[2])
		"cap":
			test_cap()
			print("CHECK: провалов %d" % fails)
		"cost":
			cost(args[1])
		"sweep":
			sweep(args[1])
	quit()
