extends SceneTree
# Тесты v39, этап 1 (активная пауза, деление на долю, стрелки «к стороне»), без сцены.
# Аргументы: [ident | pause | cmds | split | posts | scenario] — по умолчанию все. Буфер, фокус, клавиши со сценой — bench/smoke_v39.gd.
const OLD := "res://bench/main_v39_before.gd"
const NOPAUSE := "res://bench/main_v39_nopause.gd"
const NEW := "res://scripts/main.gd"
const DT := 1.0 / 30.0
# не состояние симуляции: флаг паузы, отрисовка, замеры времени, таймеры интерфейса
const SKIP := ["paused", "prev_pos", "buf", "sim_ms", "sim_avg", "sim_peak", "sim_max", "grid_ms", "draw_ms", "prof_acc", "prof_avg", "prof_n",
	"ui_t", "panel_t", "hud_msg", "hud_msg_t", "squad_panel_sig", "drawn_gate_hp",
	"hit_rng"]   # hit_rng — генератор визуала эффектов попаданий (задача 12), не состояние симуляции
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

func battle(path: String, rng_seed: int, w: int) -> Node2D:
	var m := new_main(path, rng_seed)
	m.wave_number = w - 1
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	return m

func key(m: Node2D, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	m._unhandled_input(e)

# Все переменные скрипта, кроме SKIP и узлов; у генераторов случайных чисел — их состояние.
func vars(m: Node2D) -> Array:
	var d := []
	for p in m.get_script().get_script_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or p.name in SKIP:
			continue
		var v: Variant = m.get(p.name)
		if v is RandomNumberGenerator:
			d.append([p.name, (v as RandomNumberGenerator).state])
		elif not (v is Object) and v != null:
			d.append([p.name, v])
	return d

func snap(m: Node2D) -> PackedByteArray:
	return var_to_bytes(vars(m))

# Снимок для возврата состояния: копии всех массивов.
func copy(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
		return v.duplicate(true)
	return v.duplicate() if typeof(v) > TYPE_ARRAY else v

func save_state(m: Node2D) -> Array:
	var d := vars(m)
	for r in d:
		r[1] = copy(r[1])
	return d

func load_state(m: Node2D, d: Array) -> void:
	for r in d:
		var v: Variant = m.get(r[0])
		if v is RandomNumberGenerator:
			(v as RandomNumberGenerator).state = r[1]
		else:
			m.set(r[0], copy(r[1]))

func diff_names(a: Array, b: Array) -> String:
	var out := PackedStringArray()
	for k in mini(a.size(), b.size()):
		if var_to_bytes(a[k][1]) != var_to_bytes(b[k][1]):
			out.append(a[k][0])
	return ", ".join(out)

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

# Целостность отрядов: squad_n = числу юнитов, отряд юнита занят, slot_idx в отряде уникальны. "" — всё в порядке.
func integrity(m: Node2D) -> String:
	var n := PackedInt32Array()
	n.resize(m.SQUAD_MAX)
	var seen := {}
	for i in m.count:
		var s: int = m.unit_squad[i]
		if s < -1 or s >= m.SQUAD_MAX:
			return "юнит %d: отряд %d" % [i, s]
		if s < 0:
			continue
		if m.squad_used[s] == 0:
			return "юнит %d в свободном отряде %d" % [i, s]
		n[s] += 1
		var k: int = s * 1000000 + m.unit_slot_idx[i]
		if seen.has(k):
			return "отряд %d: слот %d занят дважды" % [s, m.unit_slot_idx[i]]
		seen[k] = true
	for s in m.SQUAD_MAX:
		if m.squad_n[s] != n[s]:
			return "отряд %d: squad_n %d, юнитов %d" % [s, m.squad_n[s], n[s]]
	return ""

# Слоты отряда после перестройки: уникальны и без дыр (колонка за колонкой, глубины отличаются не больше чем на 1).
func slots_full(m: Node2D, s: int) -> bool:
	var n: int = m.squad_n[s]
	var w: int = m.squad_width[s]
	var have := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			have[m.unit_slot_idx[i]] = true
	if have.size() != n:
		return false
	for col in w:
		for row in n / w + (1 if col < n % w else 0):
			if not have.has(row * w + col):
				return false
	return true

func teleport(m: Node2D) -> void:
	for i in m.count:
		if m.unit_squad[i] >= 0:
			m.pos[i] = m.squad_pos[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])
			m.prev_pos[i] = m.pos[i]

func kill_squad(m: Node2D, s: int, keep := 0) -> void:
	var left: int = m.squad_n[s] - keep
	for i in m.count:
		if left > 0 and m.unit_squad[i] == s:
			m.hp[i] = 0.0
			left -= 1
	m._remove_dead()
	if m.squad_n[s] > 0:
		m._reflow_squad(s)

func kill_zombies(m: Node2D) -> void:
	for i in m.count:
		if m.team[i] == 1:
			m.hp[i] = 0.0
	for k in m.wave_left.size():
		m.wave_left[k] = 0
	m.wave_remaining = 0
	for b in m.wave_bursts:
		b.state = 3

# (а) PAUSE_ENABLED = false, без новых команд: как в последнем коммите.
func test_ident() -> void:
	var a := new_main(OLD, 5, false)
	var b := new_main(NOPAUSE, 5, false)
	var first := -1
	for t in 900:
		a._physics_process(DT)
		b._physics_process(DT)
		if first < 0 and not same(a, b):
			first = t
	check("(а) PAUSE_ENABLED = false, 30 с без волн (seed 5, юнитов %d): pos, hp, count как в 5a26a30 на каждом тике" % b.count, first < 0, "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	a = new_main(OLD, 7)
	b = new_main(NOPAUSE, 7)
	b.weapon_stat = "damage"   # копия до правок знает только «Оружие» на уроне (задача 6d перевела его на скорость атаки); сравнивается пауза
	first = -1
	var ticks := 0
	var buys := [0, 1, 2, 0, 1, 3]
	for w in 3:
		for x in [a, b]:
			x._buy(buys[w * 2])
			x._buy(buys[w * 2 + 1])
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 600:
			a._physics_process(DT)
			b._physics_process(DT)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
		if first < 0 and (a.wave_state != b.wave_state or a.wave_number != b.wave_number):
			first = ticks
	check("(а) 3 волны с покупками (seed 7, %d тиков, волна %d, юнитов %d): совпадает на каждом тике" % [ticks, b.wave_number, b.count], first < 0 and b.wave_number == 3, "первое расхождение: тик %d" % first)
	key(b, KEY_SPACE)   # передышка: Space начинает волну; затем Space и P в бою паузу не ставят
	var started: bool = b.wave_state == b.WS_BATTLE
	key(b, KEY_SPACE)
	key(b, KEY_P)
	check("(а) PAUSE_ENABLED = false: Space в передышке начинает волну, Space и P в бою паузу не ставят", started and not b.paused)
	a.free()
	b.free()

# (б) пауза в разгар боя.
func test_pause() -> void:
	var m := battle(NEW, 3, 10)
	for t in 600:
		m._physics_process(DT)
	var z := 0
	for i in m.count:
		z += m.team[i]
	var before := vars(m)
	var before_b := snap(m)
	key(m, KEY_SPACE)
	var was_paused: bool = m.paused
	for t in 150:
		m._physics_process(DT)
	var after_b := snap(m)
	check("(б) Space в бою ставит паузу; за 5 с паузы (150 вызовов тика, волна 10, тик 600, зомби %d, стрел в полёте %d) состояние не изменилось ни на бит" % [z, m.arrow_count],
		was_paused and before_b == after_b, "переменных в снимке %d, байт %d; отличаются: %s" % [before.size(), before_b.size(), diff_names(before, vars(m))])
	key(m, KEY_P)
	var off: bool = not m.paused
	key(m, KEY_P)
	var on: bool = m.paused
	key(m, KEY_SPACE)
	check("(б) P тоже переключает паузу; Space снимает", off and on and not m.paused)
	m._physics_process(DT)
	check("(б) после снятия симуляция идёт", snap(m) != after_b and m.tick_counter == 601)
	m.free()
	# прогон без паузы и прогон с паузой 3 с на тике 600: дальше тик в тик одинаково
	var a := battle(NEW, 3, 10)
	var b := battle(NEW, 3, 10)
	for t in 600:
		a._physics_process(DT)
		b._physics_process(DT)
	key(b, KEY_SPACE)
	for t in 90:
		b._physics_process(DT)
	key(b, KEY_SPACE)
	var first := -1
	var ticks := 0
	while ticks < 1800 and a.wave_state == a.WS_BATTLE:
		a._physics_process(DT)
		b._physics_process(DT)
		ticks += 1
		if first < 0 and (ticks % 30 == 0 or not same(a, b)) and snap(a) != snap(b):
			first = ticks
	check("(б) пауза 3 с на тике 600, затем %d тиков: состояние совпадает с прогоном без паузы (pos, hp, count каждый тик, полный снимок раз в секунду и в конце)" % ticks,
		first < 0 and snap(a) == snap(b) and a.tick_counter == b.tick_counter, "первое расхождение: тик %d; отличаются: %s" % [first, diff_names(vars(a), vars(b))])
	a.free()
	b.free()
	# волна кончилась на паузе быть не может, но флаг сбрасывается при переходе в передышку и при старте волны
	b = battle(NEW, 3, 10)
	for t in 100:
		b._physics_process(DT)
	kill_zombies(b)
	key(b, KEY_SPACE)
	var paused_before: bool = b.paused
	b.paused = false
	for t in 5:
		b._physics_process(DT)
	var respite: bool = b.wave_state == b.WS_RESPITE
	b.paused = true   # как если бы флаг остался
	b._wave_cleared()
	var cleared_resets: bool = not b.paused
	key(b, KEY_P)
	var p_in_respite: bool = b.paused
	b.paused = true
	key(b, KEY_SPACE)
	check("(б) пауза сбрасывается при переходе в передышку и при старте волны; в передышке P паузу не ставит, Space начинает волну",
		paused_before and respite and cleared_resets and not p_in_respite and b.wave_state == b.WS_BATTLE and not b.paused)
	b.wave_state = b.WS_DEFEAT
	key(b, KEY_SPACE)
	key(b, KEY_P)
	check("(б) при поражении (wave_state 1) пауза недоступна", not b.paused)
	b.free()
	var c := battle(NEW, 3, 2)
	c.gate_hp = 1.0
	key(c, KEY_SPACE)
	c.gate_hp = 0.0
	key(c, KEY_SPACE)
	c._physics_process(DT)
	check("(б) ворота пали: пауза снята", c.wave_state == c.WS_DEFEAT and not c.paused)
	c.free()

func pos_hash(m: Node2D) -> int:
	return hash([m.count, m.tick_counter, m.pos.slice(0, m.count), m.hp.slice(0, m.count), m.vel.slice(0, m.count)])

# (д) команды на паузе меняют только данные.
func test_cmds() -> void:
	var m := battle(NEW, 2, 3)
	for t in 150:
		m._physics_process(DT)
	key(m, KEY_SPACE)
	var h := pos_hash(m)
	var res := PackedStringArray()
	var bad := PackedStringArray()
	key(m, KEY_2)
	if m.sel_primary != 1:
		bad.append("выбор 2")
	key(m, KEY_1)
	for q in [[KEY_Y, m.ORDER_HOLD], [KEY_E, m.ORDER_RETREAT], [KEY_Q, m.ORDER_ATTACK], [KEY_Y, m.ORDER_HOLD]]:
		key(m, q[0])
		if m.squad_order[0] != q[1]:
			bad.append("приказ %d" % q[1])
	var ang: float = m.squad_angle[0]
	key(m, KEY_F)
	if absf(absf(angle_difference(ang, m.squad_angle[0])) - PI) > 0.001:
		bad.append("F")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.shift_pressed = true
	ang = m.squad_angle[0]
	m._unhandled_input(wheel)
	if absf(angle_difference(ang, m.squad_angle[0]) - m.ROTATE_STEP) > 0.001:
		bad.append("Shift+колесо")
	m._place_formation(0, Vector2(700, 300), Vector2(900, 300))   # протяжка: строй 18 колонок лицом вверх
	if m.squad_user_width[0] != 18 or m.squad_pos[0].distance_to(Vector2(800, 300)) > 150.0:
		bad.append("протяжка")
	key(m, KEY_T)
	if m.squad_user_width[0] != 0:
		bad.append("T")
	m.squad_target[0] = m.squad_pos[0]
	if not m._cmd_move(0, Vector2(600, 320)) or m.squad_target[0] != Vector2(600, 320):
		bad.append("клик")
	key(m, KEY_2)
	key(m, KEY_RIGHT)
	var post: Array = m._side_post(m.SIDE_RIGHT)
	if m._front_centre(1).distance_to(post[0]) > 0.6:
		bad.append("стрелка →")
	key(m, KEY_1)
	m.split_frac = 0.3
	key(m, KEY_K)
	key(m, KEY_G)
	var t_new: int = m.sel_primary
	if t_new < 2 or m.squad_n[t_new] != 90 or m.squad_n[0] != 210 or m.split_mode != 1:
		bad.append("деление")
	key(m, KEY_LEFT)
	check("(д) на паузе: 1-8, Q/W/E, F, Shift+колесо, протяжка, T, клик, стрелки, K, G меняют данные", bad.is_empty(), "не сработало: " + ", ".join(bad))
	check("(д) позиции, скорости и HP юнитов, счётчик тиков после команд те же", pos_hash(m) == h and integrity(m) == "", integrity(m))
	for t in 150:
		m._physics_process(DT)
	check("(д) ещё 5 с паузы: позиции те же", pos_hash(m) == h)
	var targets: PackedVector2Array = m.squad_target.duplicate()
	var angles: PackedFloat32Array = m.squad_angle.duplicate()
	key(m, KEY_SPACE)
	kill_zombies(m)
	var err := ""
	for t in 900:
		m._physics_process(DT)
		if err == "":
			err = integrity(m)
	var worst := 0.0
	var slot_err := 0.0
	var k := 0
	for s in m.SQUAD_MAX:
		if m.squad_used[s] == 1 and m.squad_n[s] > 0:
			worst = maxf(worst, m.squad_pos[s].distance_to(m.squad_target[s]))
			res.append("%d: %s" % [s + 1, m.squad_pos[s].round()])
	for i in m.count:
		if m.unit_squad[i] >= 0:
			var s: int = m.unit_squad[i]
			slot_err += m.pos[i].distance_to(m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s]))
			k += 1
	check("(д) после снятия паузы (30 с, зомби убраны) отряды дошли до заданных целей и встали в слоты", not m.paused and worst <= 1.0 and slot_err / k < 1.5 and err == "",
		"до цели не больше %.2f px, среднее до слота %.2f px; отряды %s; %s" % [worst, slot_err / k, ", ".join(res), err])
	var moved := 0
	for s in [0, 1, t_new]:
		if m.squad_pos[s].distance_to(targets[s]) <= 1.5 * m.SLOT_SPACING:
			moved += 1
	check("(д) места — те, что заданы на паузе (якорь у цели с точностью до перестройки)", moved == 3, "углы на паузе %s" % [Array(angles.slice(0, 3))])
	m.free()

# (е) деление.
func split_case(m: Node2D, base: Array, n: int, pct: int, mode: int, stat: Dictionary) -> void:
	load_state(m, base)
	m.split_frac = pct / 100.0
	m.split_mode = mode
	var ids := []
	var lx := {}
	var ly := {}
	var at := {}
	for i in m.count:
		if m.unit_squad[i] == 0:
			var l: Vector2 = (m.pos[i] - m.squad_pos[0]).rotated(-m.squad_angle[0])
			ids.append(i)
			lx[i] = int(l.x * 16.0)
			ly[i] = int(l.y * 16.0)
			at[i] = m.pos[i]
	var order: int = m.squad_order[0]
	var target: Vector2 = m.squad_target[0]
	var angle: float = m.squad_angle[0]
	var uw: int = m.squad_user_width[0]
	var ok: bool = m._cmd_split()
	stat.cases += 1
	if n < 2:
		if ok or m.squad_n[0] != n or m.sel_primary != 0 or m.hud_msg == "":
			stat.bad.append("n=%d: нет отказа" % n)
		return
	var k := clampi(n * pct / 100, 1, n - 1)
	var t: int = m.sel_primary
	var tag := "n=%d %d%% режим %d" % [n, pct, mode]
	if not ok or t < 2 or m.squad_n[t] != k or m.squad_n[0] != n - k or k < 1 or n - k < 1:
		stat.bad.append(tag + ": размеры %d и %d, ждали %d и %d" % [m.squad_n[0], m.squad_n[t] if t >= 0 else -1, n - k, k])
		return
	if integrity(m) != "" or not slots_full(m, 0) or not slots_full(m, t):
		stat.bad.append(tag + ": слоты " + integrity(m))
	if m.squad_order[t] != order or m.squad_angle[t] != angle or m.squad_user_width[t] != uw or m.squad_team[t] != 0 or m.squad_type[t] != m.squad_type[0] \
			or m.squad_target[t].distance_to(target) > m.SLOT_SPACING * m.WIDTH_MAX:
		stat.bad.append(tag + ": не унаследовано")
	# кто ушёл: ключ сортировки ушедших не меньше (0, 3) / не больше (1, 2) ключа любого оставшегося
	var gone_lo := 1 << 40
	var gone_hi := -(1 << 40)
	var stay_lo := 1 << 40
	var stay_hi := -(1 << 40)
	for i in ids:
		if m.pos[i] != at[i]:
			stat.moved += 1
		var v: int = ly[i] if mode < 2 else lx[i]
		if m.unit_squad[i] == t:
			gone_lo = mini(gone_lo, v)
			gone_hi = maxi(gone_hi, v)
		else:
			stay_lo = mini(stay_lo, v)
			stay_hi = maxi(stay_hi, v)
	var right: bool = gone_lo >= stay_hi if (mode == 0 or mode == 3) else gone_hi <= stay_lo
	if not right:
		stat.bad.append(tag + ": ушла не та часть")

func test_split() -> void:
	var stat := {"cases": 0, "bad": PackedStringArray(), "moved": 0}
	var sizes := PackedStringArray()
	for n in [300, 301, 100, 3, 2, 1]:
		for a in 8:
			var m := new_main(NEW, 1)
			if n > 300:
				m._squad_add_units(0, m.infantry_type, n - 300)
			elif n < 300:
				kill_squad(m, 0, n)
			var dir := Vector2.from_angle(a * TAU / 8.0 + 0.2)
			var half: Vector2 = dir * maxf((m.squad_width[0] - 1) * m.SLOT_SPACING, m.SLOT_SPACING) * 0.5
			m._place_formation(0, Vector2(1010, 300) - half, Vector2(1010, 300) + half)
			teleport(m)
			m.squad_order[0] = m.ORDER_HOLD
			var base := save_state(m)
			for pct in range(10, 95, 5):
				for mode in 4:
					split_case(m, base, n, pct, mode, stat)
			if a == 0:
				sizes.append("%d: %d/%d … %d/%d" % [n, clampi(n * 10 / 100, 1, maxi(n - 1, 1)), n - clampi(n * 10 / 100, 1, maxi(n - 1, 1)), clampi(n * 90 / 100, 1, maxi(n - 1, 1)), n - clampi(n * 90 / 100, 1, maxi(n - 1, 1))])
			m.free()
	check("(е) n = 300, 301, 100, 3, 2, 1 × доли 10-90%% × режимы 0-3 × 8 углов (%d случаев): размеры k и n - k (оба >= 1; n = 1 — отказ), слоты уникальны и без дыр, сумма сохраняется, ушла нужная часть, наследование" % stat.cases,
		stat.bad.is_empty(), "ошибок %d: %s" % [stat.bad.size(), "; ".join(stat.bad.slice(0, 4))])
	print("      уходит/остаётся при 10%% … 90%%: %s" % "; ".join(sizes))
	check("(е) позиции юнитов при делении не меняются", stat.moved == 0, "сдвинуто %d" % stat.moved)
	# ползунок: доля из процентов
	var u := new_main(NEW, 1)
	u._set_split_frac(35.0)
	var k35: int = u._split_count(300)
	u._set_split_frac(5.0)
	var lo: float = u.split_frac
	u._set_split_frac(99.0)
	check("(е) доля: 35%% от 300 = %d; вне 10-90%% обрезается" % k35, k35 == 105 and is_equal_approx(lo, 0.1) and is_equal_approx(u.split_frac, 0.9))
	# все 8 отрядов заняты
	u.split_frac = 0.5
	for q in 6:
		key(u, KEY_N)
	key(u, KEY_1)
	u.hud_msg = ""
	key(u, KEY_G)
	check("(е) заняты все %d отрядов: отказ с сообщением" % u.SQUAD_MAX, u.squad_n[0] == 300 and u.hud_msg.begins_with("Свободных отрядов нет"), u.hud_msg)
	u.free()
	# в бою: вне паузы отказ, на паузе при врагах рядом — без ошибок
	var m := battle(NEW, 1, 5)
	var t := 0
	while m.contact_tick < 0 and t < 3000:
		m._physics_process(DT)
		t += 1
	for q in 60:
		m._physics_process(DT)
	var near := 0
	for i in m.count:
		if m.team[i] != 0:
			continue
		for j in m.count:
			if m.team[j] == 1 and m.pos[i].distance_to(m.pos[j]) <= m.VIEW_RANGE:
				near += 1
				break
	key(m, KEY_1)
	key(m, KEY_G)
	check("(е) в бою без паузы: отказ с сообщением", m.squad_used[2] == 0 and m.hud_msg == "Поставь паузу (Space)", m.hud_msg)
	key(m, KEY_M)
	key(m, KEY_N)
	check("(е) слияние и новый отряд в бою недоступны", m.squad_used[2] == 0 and m.squad_n[0] > 0)
	key(m, KEY_SPACE)
	var base := save_state(m)
	var errs := PackedStringArray()
	var n0: int = m.squad_n[0]
	for mode in 4:
		load_state(m, base)
		m.paused = true
		m.split_mode = mode
		m.split_frac = 0.4
		key(m, KEY_G)
		var tn: int = m.sel_primary
		if tn < 2 or m.squad_n[tn] != n0 * 40 / 100 or m.squad_n[0] + m.squad_n[tn] != n0 or not slots_full(m, 0) or not slots_full(m, tn):
			errs.append("режим %d: деление" % mode)
		key(m, KEY_SPACE)
		for q in 300:
			m._physics_process(DT)
			var e := integrity(m)
			if e != "":
				errs.append("режим %d, тик %d: %s" % [mode, q, e])
				break
	check("(е) деление на паузе в бою (волна 5, пехоты %d, из них с зомби в VIEW_RANGE %d), режимы 0-3, затем 10 с боя: целостность отрядов каждый тик" % [n0, near],
		errs.is_empty() and near > 0, "; ".join(errs))
	m.free()

# (ж) стрелки: посты.
func test_posts() -> void:
	var names := {1: "←", 0: "↑", 2: "→", -1: "↓"}
	var keys := {1: KEY_LEFT, 0: KEY_UP, 2: KEY_RIGHT, -1: KEY_DOWN}
	var bad := PackedStringArray()
	var notes := PackedStringArray()
	for n in [100, 300, 1200]:
		for side in [1, 0, 2, -1]:
			var m := new_main(NEW, 1)
			var s := 1 if n == 100 else 0
			kill_squad(m, 1 - s)
			if n > 300:
				m._squad_add_units(0, m.infantry_type, n - 300)
				teleport(m)
			var cfg: Dictionary = m.wave_cfg
			var sp := Vector2(cfg.spawn_center_x, cfg.spawn_front_y)
			if side == 1:
				sp = Vector2(cfg.spawn_left_x, cfg.spawn_left_y)
			elif side == 2:
				sp = Vector2(cfg.spawn_right_x, cfg.spawn_right_y)
			var p: Vector2 = m.GATE_POS.lerp(sp, m.SIDE_POST_T)
			var v := (sp - p).normalized()
			if side < 0:
				p = Vector2(m.GATE_POS.x, m.WALL_Y - 90.0)
				v = Vector2.UP
			var w0: int = m.squad_width[s]
			m.squad_order[s] = m.ORDER_HOLD
			key(m, KEY_1 + s)
			key(m, keys[side])
			var tag := "%d %s" % [n, names[side]]
			var face := Vector2.from_angle(m.squad_angle[s])
			var off: float = m._front_centre(s).distance_to(p)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for i in m.count:
				if m.unit_squad[i] == s:
					var q: Vector2 = m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])
					lo = lo.min(q)
					hi = hi.max(q)
			if face.dot(v) <= 0.99:
				bad.append(tag + ": лицо %.3f" % face.dot(v))
			if lo.x < -0.01 or lo.y < -0.01 or hi.x > m.FIELD.x + 0.01 or hi.y > m.WALL_Y - 12.0 + 0.01:
				bad.append(tag + ": вне поля %s..%s" % [lo.round(), hi.round()])
			if m.squad_order[s] != m.ORDER_HOLD or m.squad_n[s] != n or not slots_full(m, s) or m.squad_target[s] != m.squad_pos[s]:
				bad.append(tag + ": приказ, состав или слоты")
			if off > 0.6:
				notes.append("%s сдвиг %.0f px, ширина %d → %d" % [tag, off, w0, m.squad_width[s]])
			elif m.squad_width[s] != w0:
				bad.append(tag + ": ширина %d → %d" % [w0, m.squad_width[s]])
			if side == 0 and n == 300:
				print("      посты: ← %s, ↑ %s, → %s, ↓ %s" % [m._side_post(1)[0].round(), m._side_post(0)[0].round(), m._side_post(2)[0].round(), m._side_post(-1)[0].round()])
			m.free()
	check("(ж) отряды 100, 300, 1200 × ← ↑ → ↓: лицо к стороне (скалярное > 0.99), все слоты в поле и не ниже WALL_Y - 12, приказ и состав те же, середина переднего ряда в точке поста по формуле (или блок сдвинут, см. ниже)",
		bad.is_empty(), "; ".join(bad))
	print("      блок не поместился и сдвинут целиком: %s" % ("нет" if notes.is_empty() else "; ".join(notes)))
	var m := new_main(NEW, 1)
	key(m, KEY_1)
	key(m, KEY_LEFT)
	var took: bool = m._front_centre(0).distance_to(m._side_post(1)[0]) < 0.6
	key(m, KEY_2)
	var was: Vector2 = m.squad_pos[1]
	var ang: float = m.squad_angle[1]
	m.hud_msg = ""
	key(m, KEY_LEFT)
	check("(ж) пост занят чужим блоком: отказ с сообщением, отряд на месте", took and m.squad_pos[1] == was and m.squad_angle[1] == ang and m.hud_msg.begins_with("Блок пересекается"), m.hud_msg)
	kill_squad(m, 1)
	key(m, KEY_UP)
	check("(ж) отряд с 0 юнитов: стрелка игнорируется", m.squad_n[1] == 0 and m.squad_pos[1] == was)
	m.free()

# (з) сценарий: волна 5 слоя 1 с заскриптованными паузами, делениями и стрелками.
func scenario(rng_seed: int) -> Array:
	var m := battle(NEW, rng_seed, 5)
	var err := ""
	var ticks := 0
	var h := 0
	var splits := 0
	var script := {
		100: [KEY_SPACE, KEY_1, KEY_G, KEY_LEFT, KEY_1, KEY_RIGHT, KEY_SPACE],
		250: [KEY_P, KEY_2, KEY_K, KEY_K, KEY_G, KEY_UP, KEY_Y, KEY_P],
		400: [KEY_SPACE, KEY_1, KEY_DOWN, KEY_Q, KEY_3, KEY_F, KEY_K, KEY_G, KEY_SPACE],
		550: [KEY_P, KEY_4, KEY_K, KEY_G, KEY_UP, KEY_2, KEY_T, KEY_LEFT, KEY_P],
		700: [KEY_SPACE, KEY_5, KEY_G, KEY_G, KEY_G, KEY_G, KEY_1, KEY_UP, KEY_SPACE]}
	var fracs := {100: 0.5, 250: 0.3, 400: 0.75, 550: 0.1, 700: 0.9}
	while m.wave_state == m.WS_BATTLE and ticks < 30 * 240:
		if script.has(ticks):
			m.split_frac = fracs[ticks]
			var used := 0
			for s in m.SQUAD_MAX:
				used += m.squad_used[s]
			for c in script[ticks]:
				key(m, c)
			for s in m.SQUAD_MAX:
				used -= m.squad_used[s]
			splits -= used
			if m.paused and err == "":
				err = "тик %d: пауза не снята" % ticks
		m._physics_process(DT)
		ticks += 1
		if err == "":
			err = integrity(m)
			if err != "":
				err = "тик %d: %s" % [ticks, err]
		if ticks % 50 == 0:
			h = hash([h, pos_hash(m)])
	var used_n := 0
	for s in m.SQUAD_MAX:
		used_n += m.squad_used[s]
	var r := [hash([h, snap(m)]), err, ticks, splits, used_n, m.wave_state, m.count]
	m.free()
	return r

func test_scenario() -> void:
	for sd in [1, 2, 3]:
		var a := scenario(sd)
		var b := scenario(sd)
		check("(з) волна 5 слоя 1, seed %d: паузы, деления и стрелки по сценарию — целостность отрядов каждый тик, два прогона одинаковы" % sd,
			a[1] == "" and a == b and a[3] >= 4, "%d тиков, делений %d, отрядов в конце %d, состояние волны %d, юнитов %d, хеш %d; %s" % [a[2], a[3], a[4], a[5], a[6], a[0], a[1]])

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	preload("res://scripts/settings.gd").ensure_code_actions()   # как Settings._ready (задача 10: «Держать» на Y) — до первых тестов
	var args := OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "all"
	if which in ["all", "ident"]:
		test_ident()
	if which in ["all", "pause"]:
		test_pause()
	if which in ["all", "cmds"]:
		test_cmds()
	if which in ["all", "split"]:
		test_split()
	if which in ["all", "posts"]:
		test_posts()
	if which in ["all", "scenario"]:
		test_scenario()
	print("CHECK: провалов %d" % fails)
	quit()
