extends SceneTree
# Тесты v37, этап 1 (спрайты из JSON, лучники, отдача), без сцены: (б) симуляция как в предыдущем коммите,
# (г) состояния и отдача лучников, (д) массивы после смертей. Буфер, клавиши, плохие листы — bench/smoke_v37.gd.
# Аргументы: [ident | anim | arrays] [старый main] [новый main] — по умолчанию все тесты, bench/main_v37_before.gd и scripts/main.gd.
var old_path := "res://bench/old/main_v37_before.gd"
var new_path := "res://scripts/main.gd"
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

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.arrows_hit != b.arrows_hit:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i] or a.unit_state[i] != b.unit_state[i]:
			return false
	return true

func test_ident() -> void:
	var a := new_main(old_path, 5)
	var b := new_main(new_path, 5)
	a._start_wave()
	b._start_wave()
	var first := -1
	for t in 900:
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and not same(a, b):
			first = t
	check("(б) 30 с (волна 1, seed 5): совпадает с предыдущим коммитом на каждом тике", first < 0, "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	a = new_main(old_path, 7)
	b = new_main(new_path, 7)
	first = -1
	var ticks := 0
	var buys := [0, 1, 2, 0, 1, 3]
	for w in 3:
		for x in [a, b]:
			x._buy(buys[w * 2])
			x._buy(buys[w * 2 + 1])
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 600:
			a._physics_process(1.0 / 30.0)
			b._physics_process(1.0 / 30.0)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
		if first < 0 and (a.wave_state != b.wave_state or a.wave_number != b.wave_number):
			first = ticks
	check("(б) 3 волны с покупками (seed 7, %d тиков, волна %d, юнитов %d): совпадает на каждом тике" % [ticks, b.wave_number, b.count], first < 0 and b.wave_number == 3, "первое расхождение: тик %d" % first)
	a.free()
	b.free()

# (г) лучники в бою волны w: состояния по тикам. Юнит опознаётся по unit_rand.
func archers_battle(w: int, rng_seed: int) -> void:
	var m := new_main(new_path, rng_seed)
	m.wave_number = w - 1
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m._start_wave()
	var arch: int = m.archer_type
	var prev_anim := {}
	var prev_shot := {}
	var run := {}            # id -> [тиков в «атаке», прошлое смещение]
	var intervals := 0
	var melee := 0           # удары лучников в ближнем бою
	var merged := 0          # «атака» началась, пока шла прошлая
	var releases := 0
	var volley_arrows := 0
	var single_arrows := 0
	var acct_bad := 0
	var len2 := {}
	var states := [0, 0, 0]
	var max_recoil := 0.0
	var decay_bad := 0
	var bad_dir := 0
	var fire_tick := -1      # тик залпа отряда 1
	var rel := {}            # задержка собственного выпуска от тика залпа, тики -> сколько лучников
	var rel_min := 1000
	var rel_max := -1
	var prev_fired := 0
	var prev_squad_fired: int = m.squad_volley_fired[1]
	var ticks := 0
	var pending_lost := 0
	var uniq := {}
	var dup := 0
	var tail := 0
	while tail < 30 and ticks < 30 * 240:
		m._physics_process(1.0 / 30.0)
		ticks += 1
		if m.wave_state != m.WS_BATTLE:
			tail += 1
		if m.squad_volley_fired[1] == 1 and prev_squad_fired == 0:
			fire_tick = ticks
		prev_squad_fired = m.squad_volley_fired[1]
		var alive := {}
		var now_pending := 0     # лучники, у которых в этот тик начался отсчёт до собственного выпуска (стрелы залпа)
		var now_instant := 0     # «атака» началась сразу: одиночный выстрел или ближний удар
		for i in m.count:
			if m.unit_type[i] != arch or m.unit_squad[i] < 0:
				continue
			var id: float = m.unit_rand[i]
			alive[id] = true
			if ticks == 1:
				if uniq.has(id):
					dup += 1
				uniq[id] = true
			var anim: float = m.unit_anim_t[i]
			var st: int = m._unit_anim_state(i)
			states[st] += 1
			var rc: Vector2 = m._recoil_offset(i)
			max_recoil = maxf(max_recoil, rc.length())
			if rc.length() > 0.0 and rc.normalized().dot(m.DIR_VEC[m.unit_dir[i]]) > -0.999:
				bad_dir += 1
			var pa: float = prev_anim.get(id, 0.0)
			var ps: float = prev_shot.get(id, 0.0)
			if m.unit_shot_t[i] > 0.0 and ps == 0.0:
				now_pending += 1
			var rose: bool = anim > pa or (anim == pa and pa > 0.0)   # таймер убывает каждый тик: не убыл — «атака» началась заново
			if rose:
				intervals += 1
				if pa > 0.0:
					merged += 1
				if ps > 0.0:
					releases += 1
					var d := ticks - fire_tick
					rel[d] = rel.get(d, 0) + 1
					rel_min = mini(rel_min, d)
					rel_max = maxi(rel_max, d)
				else:
					now_instant += 1
				if run.has(id) and run[id][0] > 0:
					len2[run[id][0]] = len2.get(run[id][0], 0) + 1
				run[id] = [1, rc.length()]
			elif anim > 0.0:
				if rc.length() >= run[id][1]:
					decay_bad += 1
				run[id] = [run[id][0] + 1, rc.length()]
			elif run.has(id) and run[id][0] > 0:
				len2[run[id][0]] = len2.get(run[id][0], 0) + 1
				if rc.length() != 0.0:
					decay_bad += 1
				run[id] = [0, 0.0]
			prev_anim[id] = anim
			prev_shot[id] = m.unit_shot_t[i]
		for id in prev_shot:
			if not alive.has(id) and prev_shot[id] > 0.0:
				pending_lost += 1
				prev_shot[id] = 0.0
		# стрелы этого тика: залповые (начат отсчёт) + одиночные; остальные мгновенные «атаки» — ближние удары
		var single_now: int = m.arrows_fired - prev_fired - now_pending
		if single_now < 0 or now_instant < single_now:
			acct_bad += 1
		volley_arrows += now_pending
		single_arrows += single_now
		melee += now_instant - single_now
		prev_fired = m.arrows_fired
	var total: int = states[0] + states[1] + states[2]
	var len_ok := true
	for l in len2:
		if l > 5:
			len_ok = false
	print("  волна %d, seed %d: %d тиков, стрел %d, попало %d, ближних ударов лучников %d, лучников в конце %d" % [w, rng_seed, ticks, m.arrows_fired, m.arrows_hit, melee, m.squad_n[1]])
	check("(г) отрезков «атака» у лучников %d = стрел %d (залп %d + одиночных %d) + ближних ударов %d − погибших до выпуска %d" % [intervals, m.arrows_fired, volley_arrows, single_arrows, melee, pending_lost],
		intervals == m.arrows_fired + melee - pending_lost and releases == volley_arrows - pending_lost and acct_bad <= 5 and m.arrows_fired > 0 and dup == 0,
		"собственных выпусков %d; началось поверх прошлой «атаки» %d; тиков, где стрелок погиб в тик своего выстрела, %d; повторов id %d" % [releases, merged, acct_bad, dup])
	check("(г) собственные выпуски в залпе различаются и лежат в 0..0.30 с от залпа отряда (±0.15 с от середины)", rel.size() >= 5 and rel_min >= 0 and rel_max <= 10,
		"задержка в тиках -> лучников: %s" % [rel])
	check("(г) отдача: максимум = recoil_px (%.2f), направлена назад от взгляда, убывает каждый тик и гаснет за ATTACK_ANIM_T" % m.type_recoil[arch],
		absf(max_recoil - m.type_recoil[arch]) <= 0.01 and decay_bad == 0 and bad_dir == 0 and len_ok, "максимум %.4f; длина «атаки» в тиках -> число: %s; нарушений убывания %d" % [max_recoil, len2, decay_bad])
	print("  (г) доли состояний лучников по юнито-тикам: стоит %.1f%%, замах %.1f%%, атака %.1f%% (всего %d)" % [100.0 * states[0] / total, 100.0 * states[1] / total, 100.0 * states[2] / total, total])
	m.free()

func test_anim() -> void:
	archers_battle(3, 2)
	archers_battle(8, 3)
	# пехота: отдачи нет
	var m := new_main(new_path, 1, false)
	var mx := 0.0
	for t in 300:
		m._physics_process(1.0 / 30.0)
		for i in m.count:
			if m.unit_type[i] != m.archer_type:
				mx = maxf(mx, m._recoil_offset(i).length())
	check("(г) у пехоты и зомби отдачи нет (recoil_px 0)", mx == 0.0)
	m.free()

func test_arrays() -> void:
	var m := new_main(new_path, 3)
	m.wave_number = 4
	m.wave_plan_for = -1
	m._start_wave()
	for t in 240:
		m._physics_process(1.0 / 30.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n: int = m.count
	var want := {}
	for i in n:
		m.unit_anim_t[i] = 0.001 * (i + 1)
		m.unit_shot_t[i] = 0.002 * (i + 1)
		m.unit_dir[i] = (i * 7 + 1) % 4
	var order := range(n)
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	for k in 200:
		m.hp[order[k]] = 0.0
	var dup := 0
	for k in range(200, n):
		var i: int = order[k]
		var key := [m.pos[i], m.unit_rand[i], m.unit_type[i]]
		if want.has(key):
			dup += 1
		want[key] = [m.unit_anim_t[i], m.unit_dir[i], m.unit_shot_t[i], m.unit_render_off[i]]
	m._remove_dead()
	var bad := 0
	for i in m.count:
		var key := [m.pos[i], m.unit_rand[i], m.unit_type[i]]
		if not want.has(key) or want[key] != [m.unit_anim_t[i], m.unit_dir[i], m.unit_shot_t[i], m.unit_render_off[i]] or m.unit_render_off[i] != m._render_offset(i):
			bad += 1
	check("(д) убито 200 из %d: у %d выживших unit_anim_t, unit_shot_t, unit_dir, unit_render_off прежние; длины = MAX_UNITS" % [n, m.count],
		bad == 0 and dup == 0 and m.count == n - 200 and m.unit_anim_t.size() == m.MAX_UNITS and m.unit_shot_t.size() == m.MAX_UNITS and m.unit_dir.size() == m.MAX_UNITS
		and m.unit_render_off.size() == m.MAX_UNITS, "не совпало %d, повторов ключа %d" % [bad, dup])
	m.free()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "" if args.is_empty() else args[0]
	if args.size() >= 3:
		old_path = args[1]
		new_path = args[2]
	if mode == "" or mode == "ident":
		test_ident()
	if mode == "" or mode == "anim":
		test_anim()
	if mode == "" or mode == "arrays":
		test_arrays()
	print("CHECK: провалов %d" % fails)
	quit()
