extends SceneTree
# Тесты задачи 10: экспериментальный герой. Этап A — данные data/hero.json, включение (hero_mode, enabled, игровой режим),
# тип героя последним в таблице типов. Разделы следующих этапов добавляются ниже.
const MAIN := "res://scripts/main.gd"
const FIX := "res://bench/fixtures_hero/"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(mode := 1, path := "", rng_seed := 3, gifts := {}, cards: Array = []) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.active_gifts = gifts
	m.active_cards = cards
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.hero_mode = mode
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
	t_move()
	await t_keys()
	t_combat()
	t_mods()
	t_death()
	await t_death_hud()
	t_replay()
	t_reference()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные героя")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	var m := make(1)
	var i: int = m.infantry_type
	var h: int = m.hero_type
	check("hero.json: enabled true (игровой режим), автоатака выключена (задача 11), size_scale 1.6-2, revive_hp_fraction 1.0", d.enabled == true
		and d.auto_attack == false and d.size_scale >= 1.6 and d.size_scale <= 2.0 and d.revive_hp_fraction == 1.0)
	check("тип hero последним (номера типов из unit_types.json прежние), подпись «Командир»", h == m.type_hp.size() - 1 and h == m.type_id.size() - 1
		and tr(m.type_label[h]) == "Командир")
	check("урон x2 пехоты, интервал удара как у пехоты, HP x5 пехоты", is_equal_approx(m.base_type_damage[h], 2.0 * m.base_type_damage[i])
		and is_equal_approx(m.base_type_cooldown[h], m.base_type_cooldown[i]) and is_equal_approx(m.base_type_hp[h], 5.0 * m.base_type_hp[i]))
	var k: float = m.base_type_speed[h] / m.base_type_speed[i]
	check("скорость %.0f px/с (данные — мировые px/с) = %.2f пехоты (около 1.15)" % [m.base_type_speed[h], k], is_equal_approx(m.base_type_speed[h], d.speed) and absf(k - 1.15) < 0.02)
	check("дальность удара %.1f px (данные — мировые px), больше пехотной %.1f; щита нет, награды нет" % [sqrt(m.type_range_sq[h]), sqrt(m.type_range_sq[i])],
		is_equal_approx(sqrt(m.type_range_sq[h]), d.arc_range) and m.type_range_sq[h] > m.type_range_sq[i] and m.type_block_mult[h] == 1.0 and m.type_bounty_mult[h] == 0.0)
	m.free()
	var off := make(0)
	check("hero_mode 0 без синглтона Game (бенчи, регрессия): героя нет, типов столько же, сколько в unit_types.json", not off.hero_on and off.hero_type == -1
		and off.type_hp.size() == JSON.parse_string(FileAccess.get_file_as_string("res://data/unit_types.json")).size())
	off.free()
	var neg := make(-1)
	check("hero_mode -1: героя нет", not neg.hero_on and neg.hero_type == -1)
	neg.free()
	var dis := make(0, FIX + "disabled.json")
	check("enabled false: героя нет и в игровом режиме (проверка флага без Game — hero_on false)", not dis.hero_on)
	dis.free()
	print("  ниже ожидаются строки ERROR от повреждённых файлов")
	for f in ["no_hp", "bad_targets", "bad_revive", "bad_enabled", "bad_arc"]:
		var b := make(1, FIX + f + ".json")
		check("%s.json: данные не загружены" % f, b.type_id.is_empty() or not b.is_physics_processing())
		b.free()

func run_feed(m: Node2D, v: Vector2, ticks: int) -> void:
	m.hero_feed = func(_t): return v
	for t in ticks:
		m._physics_process(DT)

func t_move() -> void:
	print("движение героя (этап B)")
	var m := make(1)
	var h: int = m.hero_idx
	check("герой появился последним юнитом у ворот: команда игрока, без отряда, полное HP", h == m.count - 1 and m.pos[h] == m.HERO_SPAWN
		and m.team[h] == 0 and m.unit_squad[h] == -1 and m.unit_type[h] == m.hero_type and m.hp[h] == m.type_hp[m.hero_type])
	var p0: Vector2 = m.pos[m.hero_idx]
	run_feed(m, Vector2(1, 0), 30)
	var dx: float = m.pos[m.hero_idx].x - p0.x
	check("вправо 30 тиков (1 с): сдвиг %.2f px = скорость %.0f px/с (толчки соседей героя не сдвигают)" % [dx, m.type_speed[m.hero_type]], absf(dx - m.type_speed[m.hero_type]) < 0.5
		and absf(m.pos[m.hero_idx].y - p0.y) < 0.01)
	p0 = m.pos[m.hero_idx]
	run_feed(m, Vector2(-1, -1), 30)
	var dd: float = m.pos[m.hero_idx].distance_to(p0)
	check("диагональ (-1, -1) нормализуется: за 1 с %.2f px — та же скорость" % dd, absf(dd - m.type_speed[m.hero_type]) < 0.5)
	p0 = m.pos[m.hero_idx]
	run_feed(m, Vector2(3, 0), 10)
	check("ввод длиннее 1 обрезается до 1", absf(m.pos[m.hero_idx].x - p0.x - m.type_speed[m.hero_type] / 3.0) < 0.5)
	run_feed(m, Vector2(0, 1), 90)
	check("вниз 3 с: не ниже стены WALL_Y (%.1f, пол юнитов)" % m.pos[m.hero_idx].y, m.pos[m.hero_idx].y <= m.WALL_Y)
	run_feed(m, Vector2(-1, 0), 600)
	check("влево 20 с: не за краем поля (x = %.1f)" % m.pos[m.hero_idx].x, m.pos[m.hero_idx].x >= 0.0)
	run_feed(m, Vector2(0, -1), 600)
	check("вверх 20 с: не за краем поля (y = %.1f)" % m.pos[m.hero_idx].y, m.pos[m.hero_idx].y >= 0.0)
	m.free()
	# Перенос индекса: удалённый юнит заменяется последним (героем) — индекс героя едет вместе с ним.
	var r := make(1)
	var hp_before: float = r.hp[r.hero_idx]
	var pos_before: Vector2 = r.pos[r.hero_idx]
	r.hp[0] = 0.0
	r._remove_dead()
	check("удаление юнита 0: герой переехал на индекс 0, его позиция и HP те же, счёт павших отрядов не считает героя", r.hero_idx == 0
		and r.unit_type[0] == r.hero_type and r.pos[0] == pos_before and r.hp[0] == hp_before and r.wave_fallen == 1)
	r.free()

func t_keys() -> void:
	print("клавиши (этап B)")
	var ST := preload("res://scripts/settings.gd")
	ST.ensure_code_actions()
	check("движение WASD по умолчанию, подписи key_label", ST.key_label("move_up") == "W" and ST.key_label("move_left") == "A" and ST.key_label("move_down") == "S"
		and ST.key_label("move_right") == "D")
	check("конфликты сняты: Клич Благодати — U, «Держать» — Y (была W)", ST.key_label("war_cry") == "U" and ST.key_label("order_hold") == "Y")
	check("движение переназначается (в REBINDABLE), «Держать» по-прежнему фиксирована", "move_up" in ST.REBINDABLE and "move_right" in ST.REBINDABLE
		and "order_hold" in ST.FIXED_ACTIONS and ST._fixed_owner(KEY_W) == "" and ST._fixed_owner(KEY_Y) == "order_hold")
	check("подписи действий ru: «Командир: вверх»", ST.action_title("move_up") == "Командир: вверх")
	TranslationServer.set_locale("en")
	check("подписи действий en: «Commander: right»", ST.action_title("move_right") == "Commander: right")
	TranslationServer.set_locale("ru")
	var keys := {}
	var dup := []
	for a in ST.REBINDABLE + ST.FIXED_ACTIONS:
		var e = ST.action_key_event(a)
		if e == null or e.ctrl_pressed:
			continue
		if keys.has(e.keycode):
			dup.append("%s/%s" % [keys[e.keycode], a])
		keys[e.keycode] = a
	check("ни одна клавиша без модификатора не занята двумя действиями", dup.is_empty(), str(dup))
	var cfg := ConfigFile.new()
	cfg.set_value("input", "war_cry", "D")
	var st: Node = root.get_node_or_null("Settings")
	if st != null:
		st._load_keys(cfg)
		check("старый файл настроек (Клич на D, без move_*): Клич получает новое умолчание U, D — движение вправо", ST.key_label("war_cry") == "U" and ST.key_label("move_right") == "D")
		var cfg2 := ConfigFile.new()
		cfg2.set_value("input", "war_cry", "D")
		cfg2.set_value("input", "move_right", "L")
		cfg2.set_value("input", "move_up", "W")
		st._load_keys(cfg2)
		check("новый файл (с move_*): Клич на D из файла сохраняется, движение вправо — L", ST.key_label("war_cry") == "D" and ST.key_label("move_right") == "L")
		st._load_keys(ConfigFile.new())
	# Ввод с клавиатуры — раз в тик: действие нажато -> ввод тика.
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = 3
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.hero_mode = 1
	m.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m)
	await process_frame
	Input.action_press("move_right")
	Input.action_press("move_up")
	m._physics_process(DT)
	var v: Vector2 = m.hero_move
	Input.action_release("move_right")
	Input.action_release("move_up")
	m._physics_process(DT)
	check("клавиатура: вправо + вверх -> ввод тика %s (длина 1), отпущены -> 0" % str(v), v.is_equal_approx(Vector2(1, -1).normalized()) and m.hero_move == Vector2.ZERO)
	m.queue_free()
	await process_frame

# n новых зомби (крестьяне) в углу поля; их индексы. Создаются после героя — индекс героя не меняется.
func zombies(m: Node2D, n: int) -> Array:
	var out := []
	for k in n:
		out.append(m.count)
		m._spawn_zombie(Vector2(5.0 + k, 5.0), m.zombie_type)
	return out

func t_combat() -> void:
	print("бой героя (этап C): автоатака — fixtures_hero/auto.json (auto_attack true, дальность 21, 2 цели, как в задаче 10)")
	var m := make(1, FIX + "auto.json")
	var h: int = m.hero_idx
	var hp0: Vector2 = m.pos[h]
	var z := zombies(m, 4)
	var full: float = m.hp[z[0]]
	m.pos[z[0]] = hp0 + Vector2(16, 0)
	m.pos[z[1]] = hp0 + Vector2(0, -6)
	m.pos[z[2]] = hp0 + Vector2(-10, 0)
	m.pos[z[3]] = hp0 + Vector2(0, -22)   # дальше attack_range 21
	m._build_grid()
	m._update_hero(DT)
	var lost := []
	for j in z:
		lost.append(full - m.hp[j])
	var dmg: float = m.type_damage[m.hero_type]
	check("удар: 2 ближайших в дальности (6 и 10 px) получают урон героя %.1f, третий (16 px) и дальний (22 px) — нет" % dmg, is_equal_approx(lost[1], dmg)
		and is_equal_approx(lost[2], dmg) and lost[0] == 0.0 and lost[3] == 0.0, str(lost))
	m._update_hero(DT)
	check("сразу после удара — перезарядка, второго удара нет", is_equal_approx(full - m.hp[z[1]], dmg) and m.hero_swings == 1 and m.hero_hits == 2)
	var ticks := 1
	while m.hero_swings == 1 and ticks < 100:
		m._update_hero(DT)
		ticks += 1
	check("следующий удар через %d тиков (attack_interval 0.8 с = 24 тика)" % ticks, ticks == 24 and m.hero_swings == 2)
	m.hp[z[1]] = 0.0
	m.hp[z[2]] = 0.0
	m.cooldown[h] = 0.0
	m._update_hero(DT)
	check("мёртвые (HP <= 0, ещё не удалены) не цели: удар идёт по следующей ближайшей (16 px)", is_equal_approx(full - m.hp[z[0]], dmg))
	# Окно сетки шире 3x3, если дальность больше клетки: дальность 60 px -> окно ±3 клетки.
	m.type_range_sq[m.hero_type] = 60.0 * 60.0
	m.pos[z[3]] = hp0 + Vector2(-55, 0)
	var before: float = m.hp[z[3]]
	m.cooldown[h] = 0.0
	m._build_grid()
	m._update_hero(DT)
	check("дальность 60 px (больше клетки %.0f): окно обхода расширено только для героя, цель в 55 px задета" % m.CELL_SIZE, m.hp[z[3]] < before)
	m.free()
	# Зомби бьют героя через общий механизм (цель — ближайший враг в окне); вдали от героя орда идёт к воротам.
	var b := make(1, FIX + "auto.json")
	b.hero_feed = func(_t): return Vector2.ZERO
	var zb := zombies(b, 2)
	for i in b.count:
		if b.team[i] == 1:
			b.hp[i] = 1e6
	var hh: int = b.hero_idx
	b.pos[hh] = Vector2(500, 500)
	b.pos[zb[0]] = Vector2(510, 500)
	b.pos[zb[1]] = Vector2(500, 300)
	var far0: Vector2 = b.pos[zb[1]]
	b.wave_state = b.WS_BATTLE
	for t in 60:
		b._physics_process(DT)
	var lost_hp: float = b.type_hp[b.hero_type] - b.hp[b.hero_idx]
	var mv: Vector2 = b.pos[zb[1]] - far0
	check("зомби рядом (10 px) бьёт героя: за 2 с герой потерял %.1f HP" % lost_hp, lost_hp > 0.0)
	check("зомби в 200 px от героя идёт к воротам, а не к герою: сдвиг %s (к воротам — вправо-вниз)" % str(mv), mv.x > 5.0 and mv.y > 0.0)
	b.free()

func t_mods() -> void:
	print("модификаторы героя (этап C)")
	var base := make(1)
	var h: int = base.hero_type
	var hp0: float = base.type_hp[h]
	var dmg0: float = base.type_damage[h]
	var cd0: float = base.type_cooldown[h]
	var sp0: float = base.type_speed[h]
	base.free()
	var m := make(1, "", 3, {"sturdy_shields": 3, "tempered_steel": 3, "marksmen": 3, "spear_wall": 3}, [{"id": "long_spears"}])
	check("all_units: HP +18%% («Крепкие щиты» 3) — %.2f; враги крепче на 10%% (№27) на героя не действуют" % m.type_hp[h], is_equal_approx(m.type_hp[h], hp0 * 1.18))
	check("all_units: скорость атаки +15%% (№27) — интервал %.4f = 0.8 / 1.15; пехотная «Закалённая сталь» на героя не действует" % m.type_cooldown[h],
		is_equal_approx(m.type_cooldown[h], cd0 / 1.15))
	check("урон лучников («Меткие стрелки») на героя не действует; скорость прежняя", is_equal_approx(m.type_damage[h], dmg0) and is_equal_approx(m.type_speed[h], sp0))
	check("блок all_units («Сомкнутые щиты» 3): бонус начислен 0.15, но щита у героя нет (block_mult 1.0) — как у лучников, не действует",
		is_equal_approx(m.type_block_bonus[h], 0.15) and m.type_block_mult[h] == 1.0)
	check("HP живого героя — по новому максимуму", is_equal_approx(m.hp[m.hero_idx], m.type_hp[h]))
	m.free()

func t_death() -> void:
	print("смерть и возрождение (этап D)")
	var m := make(1, "", 3, {"war_cry": 1})
	m._select_only(0)
	m._set_order(m.ORDER_HOLD)
	m._start_wave()
	for t in 30:
		m._physics_process(DT)
	var gold0: float = m.gold
	var target0: Vector2 = m.squad_target[0]
	m.hp[m.hero_idx] = 0.0
	m._remove_dead()
	check("герой пал: его нет в массивах, hero_dead, приказы заблокированы; золото то же (штрафа нет)", m.hero_idx == -1 and m.hero_dead and m._orders_locked()
		and m.gold == gold0 and m.wave_fallen == 0)
	m._set_order(m.ORDER_ATTACK)
	check("смена приказа отклонена: отряд 0 по-прежнему «держать»", m.squad_order[0] == m.ORDER_HOLD)
	check("Клич Благодати отклонён (кнопка неактивна: war_cry_can false)", not m.request_war_cry() and not m.war_cry_can())
	check("ПКМ-цель, группа, построение, поворот, разворот, посты, деление отклонены; цель отряда прежняя", not m._cmd_move(0, target0 + Vector2(100, 0))
		and not m._cmd_move_group(PackedInt32Array([0, 1]), target0 + Vector2(100, 0)) and not m._place_formation_multi(PackedInt32Array([0]), target0, target0 + Vector2(200, 0))
		and not m._cmd_rotate(1) and not m._cmd_about_face() and not m._cmd_side_post(m.SIDE_LEFT) and not m._cmd_split() and m.squad_target[0] == target0)
	m._select_only(1)
	check("выбор отрядов работает", m.sel_primary == 1)
	var n0: int = m.squad_n[0]
	for t in 60:
		m._physics_process(DT)
	check("армия продолжает бой по последним приказам (отряд 0 на «держать», %d -> %d)" % [n0, m.squad_n[0]], m.squad_order[0] == m.ORDER_HOLD and m.hero_idx == -1)
	m._wave_cleared()
	var h: int = m.hero_idx
	check("начало передышки: герой возрождён у ворот с полным HP (revive_hp_fraction 1.0), управление вернулось", h >= 0 and m.pos[h] == m.HERO_SPAWN
		and is_equal_approx(m.hp[h], m.type_hp[m.hero_type]) and not m.hero_dead and not m._orders_locked())
	m._select_only(0)
	m._set_order(m.ORDER_ATTACK)
	check("приказ снова принимается", m.squad_order[0] == m.ORDER_ATTACK)
	m.free()
	var half := make(1, FIX + "revive_half.json")
	half._start_wave()
	half.hp[half.hero_idx] = -1.0
	half._remove_dead()
	half._wave_cleared()
	check("revive_hp_fraction 0.5: возрождение с половиной HP", is_equal_approx(half.hp[half.hero_idx], 0.5 * half.type_hp[half.hero_type]))
	half.free()
	var d := make(1)
	d._start_wave()
	d.hp[d.hero_idx] = 0.0
	d._remove_dead()
	d.gate_hp = 0.0
	d._physics_process(DT)
	check("поражение (ворота пали) — как раньше, при павшем герое", d._run_over())
	d.free()
	var alive := make(1)
	alive._start_wave()
	alive.hp[alive.hero_idx] = 5.0
	alive._wave_cleared()
	check("живой герой в передышке не возрождается: лечится, как все юниты (heal), остаётся на месте", alive.hero_idx >= 0 and alive.hp[alive.hero_idx] > 5.0
		and alive.hp[alive.hero_idx] < alive.type_hp[alive.hero_type])
	alive.free()

func t_death_hud() -> void:
	print("метка «Командир пал»")
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = 3
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.hero_mode = 1
	m.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m)
	await process_frame
	m._update_ui()
	var before: bool = m.hero_fallen_label.visible
	m._start_wave()
	m.hp[m.hero_idx] = 0.0
	m._remove_dead()
	m._update_ui()
	check("после смерти в бою метка видна: «%s»" % tr(m.hero_fallen_label.text), not before and m.hero_fallen_label.visible and tr(m.hero_fallen_label.text).begins_with("Командир пал"))
	TranslationServer.set_locale("en")
	check("en: «%s»" % tr(m.hero_fallen_label.text), tr(m.hero_fallen_label.text).begins_with("The Commander has fallen"))
	TranslationServer.set_locale("ru")
	m._wave_cleared()
	m._update_ui()
	check("передышка: метки нет", not m.hero_fallen_label.visible)
	m.queue_free()
	await process_frame

# Один прогон волны 3 (seed 7) с героем: ввод — feed; журнал hero_move по тикам и хэши состояния по тикам.
func battle_run(feed: Callable) -> Array:
	var m := make(1, "", 7)
	m.hero_feed = feed
	m.wave_number = 2
	m.wave_plan_for = -1
	m._start_wave()
	var log := []
	var hashes := []
	for t in 30 * 40:
		m._physics_process(DT)
		log.append({"move": m.hero_move, "attack": m.hero_attack_in})
		hashes.append(hash([m.count, m.pos.slice(0, m.count), m.hp.slice(0, m.count), m.cooldown.slice(0, m.count), m.gold, m.gate_hp, m.hero_idx]))
	var out := [log, hashes, m.hero_swings, m.hero_kills, m.hero_deaths, m.wave_kills]
	m.free()
	return out

func t_replay() -> void:
	print("детерминизм: записанный ввод (этап G)")
	# «Живой» ввод: смена направления по своему расписанию (как игрок), к орде и обратно; удар J (задача 11) — то нажатие, то удержание.
	var live := func(t: int) -> Dictionary:
		var at := t % 7 == 0 or (t / 45) % 3 == 1
		if t < 150:
			return {"move": Vector2(0, -1) if t < 45 else Vector2.ZERO, "attack": at}   # 1.5 с вверх, затем ждёт орду и бьёт вверх
		return {"move": [Vector2(-1, 0), Vector2(1, -1), Vector2(1, 0), Vector2(0, 1), Vector2.ZERO, Vector2(-1, -1)][(t / 30) % 6], "attack": at}
	var a := battle_run(live)
	var rec: Array = a[0]
	var b := battle_run(func(t: int) -> Dictionary: return rec[t - 1] if t - 1 < rec.size() else {})
	var first := -1
	for t in a[1].size():
		if a[1][t] != b[1][t]:
			first = t
			break
	check("воспроизведение записанной последовательности (1200 тиков боя): то же состояние на каждом тике; герой ударил %d раз, добил %d, пал %d раз, волна: убито %d" % [a[2], a[3], a[4], a[5]],
		first < 0 and a[2] > 0 and a.slice(2) == b.slice(2), "первое расхождение: тик %d" % first)
	var c := battle_run(live)
	check("тот же ввод ещё раз — тот же результат", c[1] == a[1])

func t_reference() -> void:
	print("эталон при выключенном герое (этап G)")
	for mode in [-1, 0]:
		var a: Node2D = load("res://bench/ref/main_ref.gd").new()
		var b := make(mode, "", 7)
		a.spawn_seed = 7
		a.debug_layer = 1
		a.record_path = "user://record_bench.json"
		a._setup_data()
		var first := -1
		for w in 2:
			for x in [a, b]:
				x._buy(0)
				x._start_wave()
			var t := 0
			while a.wave_state == a.WS_BATTLE and t < 30 * 300:
				a._physics_process(DT)
				b._physics_process(DT)
				if first < 0 and (a.count != b.count or a.pos.slice(0, a.count) != b.pos.slice(0, b.count) or a.hp.slice(0, a.count) != b.hp.slice(0, b.count) or a.gold != b.gold):
					first = t
				t += 1
		check("hero_mode %d (%s): 2 волны с покупками — бит в бит с эталоном" % [mode, "выключен" if mode < 0 else "по данным, без Game"], first < 0 and not b.hero_on, "расхождение на тике %d" % first)
		a.free()
		b.free()
