extends SceneTree
# Тесты v35, этап 2 (спрайты пехоты), без сцены: (б) симуляция как на этапе 1, (в) массивы после смертей,
# (г) анимация удара, (д) направления. Отрисовка (буфер, клавиши, время _process) — bench/smoke_v35s2.gd.
const NEW := "res://scripts/main.gd"
const OLD := "res://bench/main_v35_stage1.gd"
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
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i] or a.unit_state[i] != b.unit_state[i]:
			return false
	return true

# (б) pos, hp, count (и cooldown, состояние, золото, ворота, стрелы) совпадают с этапом 1 на каждом тике.
func test_ident() -> void:
	var a := new_main(OLD, 5)
	var b := new_main(NEW, 5)
	a._start_wave()
	b._start_wave()
	var first := -1
	for t in 900:
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and not same(a, b):
			first = t
	check("(б) 30 с (волна 1, seed 5): совпадает с этапом 1 на каждом тике", first < 0, "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	a = new_main(OLD, 7)
	b = new_main(NEW, 7)
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

# (в) swap-and-pop: у выживших unit_anim_t и unit_dir те же, что до убийства 200 случайных.
func test_arrays() -> void:
	var m := new_main(NEW, 3)
	m._start_wave()
	for t in 240:
		m._physics_process(1.0 / 30.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n: int = m.count
	var want := {}   # ключ (позиция + unit_rand) -> [anim, dir]
	for i in n:
		m.unit_anim_t[i] = 0.001 * (i + 1)
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
		want[key] = [m.unit_anim_t[i], m.unit_dir[i]]
	m._remove_dead()
	var bad := 0
	for i in m.count:
		var key := [m.pos[i], m.unit_rand[i], m.unit_type[i]]
		if not want.has(key) or want[key][0] != m.unit_anim_t[i] or want[key][1] != m.unit_dir[i]:
			bad += 1
	check("(в) убито 200 из %d: у %d выживших unit_anim_t и unit_dir прежние; длины массивов = MAX_UNITS" % [n, m.count],
		bad == 0 and dup == 0 and m.count == n - 200 and m.unit_anim_t.size() == m.MAX_UNITS and m.unit_dir.size() == m.MAX_UNITS, "не совпало %d, повторов ключа %d" % [bad, dup])
	m.free()

# (г) бой 300 пехоты + 100 лучников против 300 зомби: кадры пехоты по тикам. Юнит опознаётся по unit_rand (уникален).
func test_anim() -> void:
	var m: Node2D
	var seed_used := 0
	for s in range(1, 20):
		m = new_main(NEW, s, false)
		var seen := {}
		for i in m.count:
			seen[m.unit_rand[i]] = true
		if seen.size() == m.count:
			seed_used = s
			break
		m.free()
	var inf: int = m.infantry_type
	var prev_cd := {}      # id -> cooldown после прошлого тика
	var prev_fr := {}      # id -> кадр после прошлого тика
	var run_len := {}      # id -> длина текущего отрезка кадра
	var strikes := 0
	var intervals := 0
	var len2 := {}         # длина завершённого отрезка кадра 2 (тики) -> сколько
	var len1 := {}         # длина отрезка кадра 1, закончившегося ударом
	var windups := 0
	var windup_to_strike := 0
	var bad1 := 0
	var bad2 := 0
	var no_windup := 0     # удары без замаха перед ними (первый удар по подошедшему врагу)
	var frames := [0, 0, 0]
	var ticks := 0
	for t in 60 * 30:
		m._physics_process(1.0 / 30.0)
		ticks += 1
		var zombies := 0
		for i in m.count:
			if m.team[i] == 1:
				zombies += 1
			if m.unit_type[i] != inf or m.unit_squad[i] < 0:
				continue
			var id: float = m.unit_rand[i]
			var fr: int = m._unit_frame(i)
			frames[fr] += 1
			var struck: bool = prev_cd.has(id) and m.cooldown[i] > prev_cd[id]
			if struck:
				strikes += 1
			var pf: int = prev_fr.get(id, 0)
			if fr == 1 and not (m.unit_state[i] == m.ST_ATTACK and m.cooldown[i] <= m.WINDUP_T and m.unit_anim_t[i] == 0.0):
				bad1 += 1
			if fr == 2 and m.unit_anim_t[i] <= 0.0:
				bad2 += 1
			if fr != pf:
				var l: int = run_len.get(id, 0)
				if pf == 2:
					len2[l] = len2.get(l, 0) + 1
				elif pf == 1:
					windups += 1
					if fr == 2:
						windup_to_strike += 1
						len1[l] = len1.get(l, 0) + 1
				if fr == 2:
					intervals += 1
					if not struck:
						bad2 += 1
					if pf != 1:
						no_windup += 1
				run_len[id] = 1
			else:
				run_len[id] = run_len.get(id, 0) + 1
				if struck:
					bad2 += 1   # удар, а новый отрезок кадра 2 не начался
			prev_cd[id] = m.cooldown[i]
			prev_fr[id] = fr
		if zombies == 0:
			break
	var total: int = frames[0] + frames[1] + frames[2]
	var len2_ok := true
	for l in len2:
		if l < 4 or l > 5:   # 0.15 с = 4.5 тика, допуск ±1 тик по условию: 4 или 5 (тут строже)
			len2_ok = false
	var len1_ok := true
	for l in len1:
		if l > 5:   # WINDUP_T = 4.5 тика, + 1 тик
			len1_ok = false
	check("(г) отрезков кадра 2 (%d) столько же, сколько ударов пехоты (%d), каждый начинается в тик удара" % [intervals, strikes], intervals == strikes and strikes > 0 and bad2 == 0, "seed %d, %d тиков" % [seed_used, ticks])
	check("(г) длительность кадра 2: 0.15 с ± 1 тик", len2_ok, "длина в тиках -> число отрезков: %s" % [len2])
	check("(г) кадр 1 только у бьющих (ST_ATTACK), cooldown <= WINDUP_T, не поверх кадра 2", bad1 == 0, "нарушений %d" % bad1)
	check("(г) замах перед ударом не длиннее WINDUP_T + 1 тик", len1_ok, "длина замаха в тиках -> число: %s; замахов %d, из них закончились ударом %d; ударов без замаха %d" % [len1, windups, windup_to_strike, no_windup])
	print("  (г) доли кадров по юнито-тикам пехоты за бой: стоит %.1f%%, замах %.1f%%, атака %.1f%% (всего %d)" % [100.0 * frames[0] / total, 100.0 * frames[1] / total, 100.0 * frames[2] / total, total])
	m.free()

func expected_dir(deg: int) -> Array:
	# сектора по 90° вокруг 0 (вправо), 90 (вниз), 180 (влево), 270 (вверх); ровно на границе годятся оба соседа
	var d := posmod(deg, 360)
	var k := posmod(floori((d + 45) / 90.0), 4)
	if (d + 45) % 90 == 0:
		return [k, posmod(k - 1, 4)]
	return [k]

func squad_dirs(m: Node2D, s: int) -> Dictionary:
	var d := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			d[m.unit_dir[i]] = d.get(m.unit_dir[i], 0) + 1
	return d

# (д) направления
func test_dirs() -> void:
	var m := new_main(NEW, 1)
	var bad := 0
	for deg in range(-180, 180):
		if not m._nearest_dir(deg_to_rad(deg)) in expected_dir(deg):
			bad += 1
	# и через отряд: свежий юнит при любом угле отряда получает ближайшее направление
	for deg in 360:
		m.squad_angle[0] = wrapf(deg_to_rad(deg), -PI, PI)
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.unit_dir[i] = m._nearest_dir(m.squad_angle[0])
		m._update_unit_dirs()
		var d := squad_dirs(m, 0)
		if d.size() != 1 or not d.keys()[0] in expected_dir(deg):
			bad += 1
	check("(д) 360 углов отряда дают ожидаемое направление (функция и юниты отряда)", bad == 0, "ошибок %d" % bad)
	var m2 := new_main(NEW, 2)
	check("(д) старт: пехота и лучники смотрят вверх (3)", squad_dirs(m2, 0).keys() == [3] and squad_dirs(m2, 1).keys() == [3])
	m2.free()
	# поворот на 360° шагом 5° в обе стороны: смены только по одной, всего 4, по кругу, все юниты отряда разом
	for sign in [1, -1]:
		m.squad_angle[0] = m.PLAYER_ANGLE
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.unit_dir[i] = 3
		m._update_unit_dirs()
		var cur := 3
		var changes := 0
		var ok := true
		var at := []
		for k in range(1, 73):
			m.squad_angle[0] = wrapf(m.PLAYER_ANGLE + sign * deg_to_rad(5.0 * k), -PI, PI)
			m._update_unit_dirs()
			var d := squad_dirs(m, 0)
			if d.size() != 1:
				ok = false
				break
			var nd: int = d.keys()[0]
			if nd != cur:
				if nd != posmod(cur + sign, 4):
					ok = false
				changes += 1
				at.append(5 * k)
				cur = nd
		check("(д) поворот на 360° шагом 5° (%s): 4 смены по одной, по кругу, вернулись к исходному" % ("по часовой" if sign > 0 else "против"), ok and changes == 4 and cur == 3, "смены на градусах поворота %s" % [at])
	# качание ±8° вокруг границы сектора (-45°): смен нет — гистерезис (порог 55° от центра = граница + 10°)
	m.squad_angle[0] = m.PLAYER_ANGLE
	m._update_unit_dirs()
	var flips := 0
	for k in 40:
		m.squad_angle[0] = deg_to_rad(-45.0 + (8.0 if k % 2 == 0 else -8.0))
		m._update_unit_dirs()
		if squad_dirs(m, 0).keys() != [3]:
			flips += 1
	check("(д) качание ±8° вокруг границы сектора: смен нет", flips == 0, "смен %d" % flips)
	m.free()
	# стоящий отряд, 60 с боя без команд (волна 5): направление не меняется ни у кого
	m = new_main(NEW, 4)
	m.wave_number = 4
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m._start_wave()
	var moved := 0
	var units := 0
	for t in 1800:
		m._physics_process(1.0 / 30.0)
		if m.wave_state == m.WS_RESPITE:
			m._start_wave()
		for i in m.count:
			if m.unit_squad[i] >= 0:
				units += 1
				if m.unit_dir[i] != 3:
					moved += 1
	check("(д) стоящие отряды, 60 с боя без команд (волны с 5-й): смен направления 0", moved == 0, "юнито-тиков %d, не «вверх» %d, дошли до волны %d" % [units, moved, m.wave_number])
	m.free()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args[0] == "ident":
		test_ident()
	if args.is_empty() or args[0] == "arrays":
		test_arrays()
	if args.is_empty() or args[0] == "anim":
		test_anim()
	if args.is_empty() or args[0] == "dirs":
		test_dirs()
	print("CHECK: провалов %d" % fails)
	quit()
