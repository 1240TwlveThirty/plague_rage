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

func make(mode := 1, path := "", rng_seed := 3) -> Node2D:
	var m: Node2D = load(MAIN).new()
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
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные героя")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	var m := make(1)
	var i: int = m.infantry_type
	var h: int = m.hero_type
	check("hero.json: enabled true (игровой режим), targets_per_swing 2, size_scale 1.6-2, revive_hp_fraction 1.0", d.enabled == true
		and d.targets_per_swing == 2 and d.size_scale >= 1.6 and d.size_scale <= 2.0 and d.revive_hp_fraction == 1.0)
	check("тип hero последним (номера типов из unit_types.json прежние), подпись «Командир»", h == m.type_hp.size() - 1 and h == m.type_id.size() - 1
		and tr(m.type_label[h]) == "Командир")
	check("урон x2 пехоты, интервал удара как у пехоты, HP x5 пехоты", is_equal_approx(m.base_type_damage[h], 2.0 * m.base_type_damage[i])
		and is_equal_approx(m.base_type_cooldown[h], m.base_type_cooldown[i]) and is_equal_approx(m.base_type_hp[h], 5.0 * m.base_type_hp[i]))
	var k: float = m.base_type_speed[h] / m.base_type_speed[i]
	check("скорость %.0f px/с (данные — мировые px/с) = %.2f пехоты (около 1.15)" % [m.base_type_speed[h], k], is_equal_approx(m.base_type_speed[h], d.speed) and absf(k - 1.15) < 0.02)
	check("дальность удара %.1f px (данные — мировые px), больше пехотной %.1f; щита нет, награды нет" % [sqrt(m.type_range_sq[h]), sqrt(m.type_range_sq[i])],
		is_equal_approx(sqrt(m.type_range_sq[h]), d.attack_range) and m.type_range_sq[h] > m.type_range_sq[i] and m.type_block_mult[h] == 1.0 and m.type_bounty_mult[h] == 0.0)
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
	for f in ["no_hp", "bad_targets", "bad_revive", "bad_enabled"]:
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
