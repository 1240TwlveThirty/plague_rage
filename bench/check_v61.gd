extends SceneTree
# Тесты задачи 11: ручной удар героя на J. Этап A — данные (дуга удара вместо автоатаки), направление взгляда, удар сектором
# (дальность, угол, лимит целей, окно сетки), перезарядка и удержание, ввод hero_feed (движение, взгляд, удар), мёртвый герой и пауза;
# этап C — Ctrl не двигает героя, Клич Благодати и «Оружие» ускоряют удар, клавиша J. Разделы следующих этапов добавляются ниже.
const MAIN := "res://scripts/main.gd"
const FIX := "res://bench/fixtures_hero/"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(path := "", gifts := {}, cards: Array = []) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.active_gifts = gifts
	m.active_cards = cards
	m.spawn_seed = 3
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.hero_mode = 1
	if path != "":
		m.hero_path = path
	m._setup_data()
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await process_frame
	TranslationServer.set_locale("ru")
	t_data()
	t_face()
	t_arc()
	t_cooldown()
	t_feed()
	t_dead_pause()
	await t_keyboard()
	t_rates()
	t_keys()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные удара (этап A)")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	# Балансные значения не фиксируются (задача 14): только типы и пределы.
	check("hero.json: auto_attack false, hold_repeat true, arc_angle %s в (0, 360], arc_range %s, max_targets %s (целое от 0), arc_fx_time больше 0, arc_fx_color — hex" % [d.arc_angle, d.arc_range, d.max_targets],
		d.auto_attack == false and d.hold_repeat == true and d.arc_angle > 0.0 and d.arc_angle <= 360.0 and d.arc_range > 0.0
		and d.max_targets >= 0 and d.max_targets == floorf(d.max_targets) and d.arc_fx_time > 0.0 and Color.html_is_valid(d.arc_fx_color))
	check("attack_range и targets_per_swing убраны (их заменили arc_range и max_targets); attack_interval больше 0, damage от 0",
		not d.has("attack_range") and not d.has("targets_per_swing") and d.attack_interval > 0.0 and d.damage >= 0.0)
	var m := make()
	check("дальность типа героя = arc_range %.1f px" % sqrt(m.type_range_sq[m.hero_type]), is_equal_approx(sqrt(m.type_range_sq[m.hero_type]), d.arc_range))
	m.free()

# n зомби-крестьян в углу поля (после героя: его индекс прежний), HP большое — не умирают от удара.
func zombies(m: Node2D, n: int) -> Array:
	var out := []
	for k in n:
		out.append(m.count)
		m._spawn_zombie(Vector2(5.0 + k, 5.0), m.zombie_type)
		m.hp[m.count - 1] = 100.0
	return out

func hit_list(m: Node2D, z: Array) -> Array:
	var out := []
	for j in z:
		out.append(m.hp[j] < 100.0)
	return out

func swing(m: Node2D) -> void:
	m.hero_attack_in = true
	m.hero_move = Vector2.ZERO
	m.hero_face_in = NAN
	m._build_grid()
	m._update_hero(DT)
	m.hero_attack_in = false

func t_face() -> void:
	print("направление взгляда (этап A)")
	var m := make()
	var h: int = m.hero_idx
	check("старт: взгляд вверх (к зомби), -90°", is_equal_approx(m.hero_face_ang, -PI / 2.0))
	m.hero_feed = func(_t): return Vector2(1, 0)
	m._physics_process(DT)
	var right: float = m.hero_face_ang
	m.hero_feed = func(_t): return Vector2.ZERO
	for t in 10:
		m._physics_process(DT)
	check("движение вправо — взгляд 0°; в покое сохраняется; спрайт смотрит вправо", is_equal_approx(right, 0.0) and is_equal_approx(m.hero_face_ang, 0.0)
		and m.hero_face == 1.0)
	m.hero_feed = func(_t): return Vector2(-1, 1)
	m._physics_process(DT)
	check("влево-вниз — взгляд 135°, спрайт отражён", is_equal_approx(m.hero_face_ang, 0.75 * PI) and m.hero_face == -1.0)
	m.hero_feed = func(_t): return Vector2(0, -1)
	m._physics_process(DT)
	check("строго вверх — спрайт сохраняет прежнее отражение", is_equal_approx(m.hero_face_ang, -PI / 2.0) and m.hero_face == -1.0)
	m.hero_feed = func(_t): return {"move": Vector2(1, 0), "face": PI}
	m._physics_process(DT)
	check("ввод \"face\" (бот, тесты) задаёт взгляд независимо от движения", is_equal_approx(m.hero_face_ang, PI) and h == m.hero_idx)
	m.hp[h] = 0.0
	m._remove_dead()
	m._wave_cleared()
	check("возрождение: взгляд снова вверх", is_equal_approx(m.hero_face_ang, -PI / 2.0))
	m.free()

func t_arc() -> void:
	print("удар сектором (этап A)")
	var m := make()
	var h: int = m.hero_idx
	var p: Vector2 = m.pos[h]
	m.hero_face_ang = 0.0   # вправо
	var z := zombies(m, 7)
	var at := [Vector2(20, 0), Vector2(27.5, 0), Vector2(29, 0), Vector2.from_angle(deg_to_rad(54)) * 20.0,
		Vector2.from_angle(deg_to_rad(-56)) * 20.0, Vector2(-15, 0), Vector2.ZERO]
	for k in z.size():
		m.pos[z[k]] = p + at[k]
	swing(m)
	var hits := hit_list(m, z)
	check("вперёд 20 и 27.5 px — задеты, 29 px (дальше arc_range 28) — нет; 54° от взгляда — задет, -56° (больше 55°) — нет; сзади — нет; в точке героя — задет",
		hits == [true, true, false, true, false, false, true], str(hits))
	check("урон каждой цели — урон героя %.1f; счётчики: удар 1, попаданий 4" % m.type_damage[m.hero_type],
		is_equal_approx(100.0 - m.hp[z[0]], m.type_damage[m.hero_type]) and m.hero_swings == 1 and m.hero_hits == 4 and m.hero_swing_n == 1)
	check("задетые записаны для мигания (индексы и позиции)", m.hero_hit_idx.size() == 4 and m.hero_hit_pos[0] == m.pos[m.hero_hit_idx[0]])
	m.free()
	# Лимит: max_targets 6 из 10 в секторе — ближайшие.
	var l := make()
	h = l.hero_idx
	p = l.pos[h]
	var zl := zombies(l, 10)
	for k in zl.size():
		l.pos[zl[k]] = p + Vector2(0, -(2.0 + 2.5 * k))   # вверх, по взгляду; 2..24.5 px
	swing(l)
	hits = hit_list(l, zl)
	check("10 зомби в секторе, max_targets 6: задеты 6 ближайших", hits == [true, true, true, true, true, true, false, false, false, false], str(hits))
	l.hero_cfg.max_targets = 0
	l.cooldown[h] = 0.0
	swing(l)
	var all := true
	for j in zl:
		all = all and l.hp[j] < 100.0
	check("max_targets 0 — без лимита: задеты все 10", all)
	# Окно сетки по arc_range: 60 px -> ±3 клетки.
	l.type_range_sq[l.hero_type] = 60.0 * 60.0
	l.pos[zl[9]] = p + Vector2(0, -55)
	var before: float = l.hp[zl[9]]
	l.cooldown[h] = 0.0
	swing(l)
	check("дальность 60 px: окно обхода ±%d клетки (CELL_SIZE %.0f), цель в 55 px задета" % [ceili(60.0 / l.CELL_SIZE), l.CELL_SIZE], l.hp[zl[9]] < before)
	l.free()
	# Мёртвые не цели.
	var d := make()
	var zd := zombies(d, 2)
	d.pos[zd[0]] = d.pos[d.hero_idx] + Vector2(0, -5)
	d.pos[zd[1]] = d.pos[d.hero_idx] + Vector2(0, -10)
	d.hp[zd[0]] = 0.0
	swing(d)
	check("мёртвый (HP 0, ещё не удалён) не цель: задет следующий", d.hp[zd[0]] == 0.0 and d.hp[zd[1]] < 100.0 and d.hero_hits == 1)
	d.free()

func t_cooldown() -> void:
	print("перезарядка, удержание, мимо (этап A)")
	var m := make()
	var h: int = m.hero_idx
	var z := zombies(m, 1)
	m.pos[z[0]] = m.pos[h] + Vector2(0, -10)
	m._build_grid()
	m._update_hero(DT)
	check("без ввода удара автоатаки нет (auto_attack false)", m.hero_swing_n == 0 and m.hp[z[0]] == 100.0)
	swing(m)
	var first: float = m.hp[z[0]]
	swing(m)
	check("второе нажатие сразу — перезарядка, удара нет", m.hero_swing_n == 1 and m.hp[z[0]] == first)
	var ticks := 1
	while m.hero_swing_n == 1 and ticks < 100:
		swing(m)   # удержание: ввод удара каждый тик
		ticks += 1
	var want := ceili(m.type_cooldown[m.hero_type] / DT - 1e-4)
	check("удержание: следующий удар через %d тиков (attack_interval %.2f с = %d тиков)" % [ticks, m.type_cooldown[m.hero_type], want], ticks == want and m.hero_swing_n == 2)
	for t in 10:
		m._build_grid()
		m._update_hero(DT)   # отпустил: перезарядка идёт, удара нет
	var n0: int = m.hero_swing_n
	for t in 30:
		m._build_grid()
		m._update_hero(DT)
	check("нажатие во время перезарядки не копится: после неё без нового нажатия удара нет", m.hero_swing_n == n0)
	m.pos[z[0]] = m.pos[h] + Vector2(0, 50)
	swing(m)
	check("удар мимо (никого в секторе): исполняется и тратит перезарядку; в счёт ударов с целью не идёт", m.hero_swing_n == n0 + 1 and m.hero_swings == 2
		and m.cooldown[h] > 0.7 and m.hero_hit_idx.is_empty())
	m.free()
	var a := make(FIX + "auto.json")
	var za := zombies(a, 1)
	a.pos[za[0]] = a.pos[a.hero_idx] + Vector2(0, 10)   # сзади (взгляд вверх)
	a._build_grid()
	a._update_hero(DT)
	check("auto_attack true (код автоатаки оставлен): бьёт сам и по кругу", a.hp[za[0]] < 100.0 and a.hero_swing_n == 1)
	a.free()

func t_feed() -> void:
	print("ввод hero_feed: движение, взгляд, удар (этап A)")
	var m := make()
	var z := zombies(m, 1)
	m.pos[z[0]] = m.pos[m.hero_idx] + Vector2(-12, 0)
	m.hero_feed = func(t: int): return {"move": Vector2.ZERO, "face": PI, "attack": t == m.tick_counter}
	m._build_grid()
	m._physics_process(DT)
	check("feed {face: 180°, attack}: удар влево по зомби слева", m.hp[z[0]] < 100.0 and m.hero_attack_in and is_equal_approx(m.hero_swing_ang, PI))
	m.hero_feed = func(_t): return Vector2(0, -1)
	m._physics_process(DT)
	check("feed Vector2 (как в задаче 10) — только движение, удара нет", not m.hero_attack_in and m.hero_move == Vector2(0, -1))
	m.free()

func t_dead_pause() -> void:
	print("мёртвый герой и пауза (этап A)")
	var m := make()
	m._start_wave()
	m.hp[m.hero_idx] = 0.0
	m._remove_dead()
	m.hero_feed = func(_t): return {"attack": true}
	var n0: int = m.hero_swing_n
	for t in 30:
		m._physics_process(DT)
	check("мёртвый герой не бьёт (ввод удара есть, ударов нет)", m.hero_swing_n == n0 and m.hero_idx == -1)
	m.free()
	var p := make()
	p._start_wave()
	p.hero_feed = func(_t): return {"attack": true}
	p._set_paused(true)
	var tick: int = p.tick_counter
	for t in 30:
		p._physics_process(DT)
	check("пауза: тики стоят, удар не обрабатывается", p.paused and p.tick_counter == tick and p.hero_swing_n == 0)
	p.hero_attack_latch = true
	p._set_paused(false)
	check("нажатие J до паузы сбрасывается при её смене", not p.hero_attack_latch)
	p.free()

func key(code: Key, pressed: bool, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	e.ctrl_pressed = ctrl
	Input.parse_input_event(e)
	Input.flush_buffered_events()   # состояние клавиш (is_key_pressed) — сразу

func t_keyboard() -> void:
	print("клавиатура: J, удержание, Ctrl (этапы A, C)")
	var ST := preload("res://scripts/settings.gd")
	ST.ensure_code_actions()
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = 3
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.hero_mode = 1
	m.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m)
	await process_frame
	m._start_wave()
	Input.action_press("hero_attack")
	m._physics_process(DT)
	var held: bool = m.hero_attack_in
	m._physics_process(DT)
	var held2: bool = m.hero_attack_in
	Input.action_release("hero_attack")
	m._physics_process(DT)
	check("J удерживается (hold_repeat true) — ввод удара каждый тик; отпущена — нет", held and held2 and not m.hero_attack_in and m.hero_swing_n == 1)
	m.hero_cfg.hold_repeat = false
	Input.action_press("hero_attack")
	m._physics_process(DT)
	check("hold_repeat false: удержание без нажатия удара не даёт", not m.hero_attack_in)
	Input.action_release("hero_attack")
	m.hero_cfg.hold_repeat = true
	var e := InputEventKey.new()
	e.keycode = KEY_J
	e.physical_keycode = KEY_J
	e.pressed = true
	m._unhandled_input(e)
	var latched: bool = m.hero_attack_latch
	m._physics_process(DT)
	check("короткое нажатие J между тиками (событие) попадает во ввод ближайшего тика и сбрасывается", latched and m.hero_attack_in and not m.hero_attack_latch)
	m._physics_process(DT)
	check("следующий тик без нажатия — ввода удара нет", not m.hero_attack_in)
	# Ctrl+A: выбрать все, герой не двигается
	key(KEY_CTRL, true)
	Input.action_press("move_left")   # A зажата вместе с Ctrl
	m._physics_process(DT)
	var ctrl_move: Vector2 = m.hero_move
	key(KEY_CTRL, false)
	m._physics_process(DT)
	var plain: Vector2 = m.hero_move
	Input.action_release("move_left")
	check("Ctrl зажат + A: движение героя не читается (%s); без Ctrl — влево (%s)" % [ctrl_move, plain], ctrl_move == Vector2.ZERO and plain == Vector2(-1, 0))
	m.queue_free()
	await process_frame

func t_rates() -> void:
	print("скорость удара: Mods, Клич, «Оружие» (этап C)")
	var base := make()
	var cd0: float = base.type_cooldown[base.hero_type]
	base.free()
	var g := make("", {"war_cry": 1})
	var h: int = g.hero_idx
	g._start_wave()
	g.war_cry_until = g.tick_counter + 100   # клич действует
	var z := zombies(g, 1)
	g.pos[z[0]] = g.pos[h] + Vector2(0, -10)
	g.cooldown[h] = 0.0
	swing(g)
	var with_cry: float = g.cooldown[h]
	g._end_war_cry()
	g.cooldown[h] = 0.0
	swing(g)
	check("Клич Благодати (+%d%%): перезарядка удара %.4f = %.2f / %.2f; без клича %.4f" % [roundi((g.war_cry_mult - 1.0) * 100.0), with_cry, cd0, g.war_cry_mult, g.cooldown[h]],
		is_equal_approx(with_cry, cd0 / g.war_cry_mult) and is_equal_approx(g.cooldown[h], cd0) and is_equal_approx(g.war_cry_mult, 1.3))
	g.free()
	var c := make("", {}, [{"id": "long_spears"}])
	check("attack_rate all_units через Mods (карточка №27, +15%%): интервал %.4f" % c.type_cooldown[c.hero_type], is_equal_approx(c.type_cooldown[c.hero_type], cd0 / 1.15))
	c.free()
	var w := make()
	var wk: int = w.SHOP_ITEMS.find("weapons")
	w.gold = 1e6
	var ok: bool = w._buy(wk) and w._buy(wk)
	var k: float = w.shop_param[wk]
	check("«Оружие» (stat %s) x2: интервал героя %.4f = %.2f / %.2f^2" % [w.weapon_stat, w.type_cooldown[w.hero_type], cd0, k], ok and w.weapon_stat == "attack_rate"
		and is_equal_approx(w.type_cooldown[w.hero_type], cd0 / (k * k)))
	w.free()

func t_keys() -> void:
	print("клавиша J (этап C)")
	var ST := preload("res://scripts/settings.gd")
	ST.ensure_code_actions()
	check("удар — J по умолчанию, переназначается (REBINDABLE)", ST.key_label("hero_attack") == "J" and "hero_attack" in ST.REBINDABLE)
	check("подписи: «Командир: удар» / «Commander: strike»", ST.action_title("hero_attack") == "Командир: удар" and _en(ST) == "Commander: strike")
	var keys := {}
	var dup := []
	for a in ST.REBINDABLE + ST.FIXED_ACTIONS:
		var e = ST.action_key_event(a)
		if e == null or e.ctrl_pressed:
			continue
		if keys.has(e.keycode):
			dup.append("%s/%s" % [keys[e.keycode], a])
		keys[e.keycode] = a
	check("J не занята другим действием; ни одна клавиша без модификатора не занята двумя", keys.get(KEY_J, "") == "hero_attack" and dup.is_empty(), str(dup))
	check("J не постоянная клавиша (Esc, F1–F12) и не занята фиксированным действием", not KEY_J in ST.RESERVED_KEYS and ST._fixed_owner(KEY_J) == "")
	var cfg := ConfigFile.new()
	cfg.set_value("input", "war_cry", "D")
	var st: Node = root.get_node_or_null("Settings")
	if st != null:
		st._load_keys(cfg)
		check("старый файл настроек (без hero_attack): удар получает J", ST.key_label("hero_attack") == "J")
		st._load_keys(ConfigFile.new())

func _en(ST) -> String:
	TranslationServer.set_locale("en")
	var s: String = ST.action_title("hero_attack")
	TranslationServer.set_locale("ru")
	return s
