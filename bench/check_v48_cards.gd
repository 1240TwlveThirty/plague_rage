extends SceneTree
# Тесты задачи 6, этап B (данные карточек и состояние забега). Имя check_v48.gd занято (слой замка), поэтому check_v48_cards.gd.
# data/cards.json и cards_rules.json грузятся и сходятся с таблицей задания; валидатор отклоняет неизвестные статы, цели, операции, ключи перевода,
# условия и поля с понятным текстом (bench/fixtures_cards/); источник карточек для Mods; Game.run_cards, pick_card, run_rng; сцена боя с карточками.
const CARDS := preload("res://scripts/cards.gd")
const MODS := preload("res://scripts/mods.gd")
const GAME := "res://scripts/game.gd"
const MAIN := "res://scripts/main.gd"
const FIX := "res://bench/fixtures_cards/"
const DIR := "user://bench_v48c"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func make(cards: Array, rng_seed := 1) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.active_cards = cards
	m._setup_data()
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	TranslationServer.set_locale("ru")
	t_data()
	t_validator()
	t_source()
	t_battle()
	await t_game()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("data/cards.json и cards_rules.json")
	var defs := CARDS.load_cards("res://data/cards.json")
	var active := CARDS.active_ids(defs)
	var disabled := defs.keys().filter(func(id): return defs[id].get("disabled", false))
	check("40 карточек, 39 активных; выключена «Кипящая смола» (13), с причиной; «Строй щитов» (9) включён в задаче 8 (стат block)", defs.size() == 40
		and active.size() == 39 and disabled == ["boiling_pitch"] and defs.boiling_pitch.disabled_reason != "" and defs.shield_wall.when.cond == "hold", str(disabled))
	var nums := defs.keys().map(func(id): return int(defs[id].num))
	var keys_ok := true
	for id in defs:
		keys_ok = keys_ok and defs[id].name_key == "CARD_%s_NAME" % id.to_upper() and defs[id].desc_key == "CARD_%s_DESC" % id.to_upper()
	check("номера 1..40 по порядку, id латиницей, ключи CARD_<ID>_NAME / _DESC", nums == range(1, 41) and keys_ok)
	var cost := []
	for id in defs:
		if defs[id].mods.any(func(x): return x.get("cost", false)):
			cost.append(int(defs[id].num))
	check("издержка (\"cost\": true) ровно у 15 карточек: 5, 6, 7, 8, 14, 18, 26, 27, 28, 29, 31, 33, 34, 35, 38", cost == [5, 6, 7, 8, 14, 18, 26, 27, 28, 29, 31, 33, 34, 35, 38], str(cost))
	var kinds := {"M": [], "C": [], "K": []}
	for id in defs:
		kinds[defs[id].kind].append(int(defs[id].num))
	check("типы: C — 9, 10, 11, 17, 25, 31, 32, 36, 37; K — 13, 24, 30; остальные M", kinds.C == [9, 10, 11, 17, 25, 31, 32, 36, 37] and kinds.K == [13, 24, 30] and kinds.M.size() == 28,
		"C %s, K %s" % [str(kinds.C), str(kinds.K)])
	var long := []
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		for id in defs:
			var words := String(TranslationServer.translate(defs[id].desc_key)).split(" ", false).size()
			if words > 12:
				long.append("%s:%s (%d)" % [loc, id, words])
	TranslationServer.set_locale("ru")
	check("описания не длиннее 12 слов на ru и en", long.is_empty(), ", ".join(long))
	check("тексты из таблицы задания: «Клинки из метеоритного железа», «Тёмный обет»; en — свои", tr(defs.meteor_blades.name_key) == "Клинки из метеоритного железа"
		and tr(defs.dark_vow.name_key) == "Тёмный обет")
	check("карточка 30: on_pick random_split damage пехота / лучники x1.5 / x0.85; 29: on_pick +20 юнитов; 24: vengeance 0.3%, до 50%",
		defs.victory_sacrifice.on_pick.random_split.good == 1.5 and defs.victory_sacrifice.on_pick.random_split.bad == 0.85 and defs.heavy_baggage.on_pick.grant_units == 20
		and defs.vow_of_vengeance.special == "vengeance" and defs.vow_of_vengeance.max_pct == 50)
	var rules := CARDS.load_rules("res://data/cards_rules.json")
	check("правила: выбор после волн 2, 5, 8; тройка; продолжение билда 0.5", Array(rules.pick_after_waves) == [2, 5, 8] and rules.offer_count == 3 and rules.pick_build_continue_chance == 0.5)

func t_validator() -> void:
	print("валидатор — ниже ожидаются строки ERROR с текстом причины")
	for name in ["bad_stat", "bad_target", "bad_op", "bad_key", "bad_cond", "bad_cond_param", "bad_cond_stat", "when_on_m", "bad_kind", "bad_build", "k_empty",
			"disabled_no_reason", "unknown_field", "bad_on_pick", "bad_mod_field", "dup_id", "нет_файла"]:
		check("%s.json не грузится" % name, CARDS.load_cards(FIX + name + ".json").is_empty())
	check("правила с убывающими волнами и с вероятностью 1.5 не грузятся", CARDS.load_rules(FIX + "rules_bad_waves.json").is_empty() and CARDS.load_rules(FIX + "rules_bad_chance.json").is_empty())
	check("проверка модификатора называет причину: неизвестный stat / цель / операция", CARDS.check_mod({"stat": "luck", "target": "player", "op": "add_pct", "value": 1}).begins_with("неизвестный stat")
		and CARDS.check_mod({"stat": "damage", "target": "gate", "op": "add_pct", "value": 1}).begins_with("недопустимая цель")
		and CARDS.check_mod({"stat": "heal", "target": "player", "op": "mult", "value": 1}).begins_with("недопустимая операция"))
	var m: Node2D = load(MAIN).new()
	m.record_path = "user://record_bench.json"
	m.cards_path = FIX + "bad_stat.json"
	m._setup_data()
	check("сцена боя с повреждённым cards.json: остановка (типы сброшены, тик выключен)", m.type_id.is_empty() and not m.is_physics_processing())
	m.free()

func t_source() -> void:
	print("источник карточек для Mods")
	var defs := CARDS.load_cards("res://data/cards.json")
	var recs := [{"id": "meteor_blades"}, {"id": "iron_wall"}, {"id": "victory_sacrifice", "result": {"good": "infantry", "bad": "archer"}}, {"id": "shield_wall"}]
	var src := CARDS.source(defs, recs)
	var mods = MODS.new({})
	mods.build_sources([src])
	check("M — все модификаторы; C — только издержка (Железная стена: урон пехоты -10%, без +30% HP); disabled — ничего; K30 — mult по записи",
		is_equal_approx(mods.get_mult("damage", "infantry"), (1.0 + 0.12 - 0.10) * 1.5) and is_equal_approx(mods.get_mult("damage", "archer"), 0.85)
		and mods.get_mult("hp", "infantry") == 1.0 and src.mods.size() == 4, str(src.mods))
	var both = MODS.new({})
	both.build_sources([MODS.gifts_source(MODS.load_gifts("res://data/gifts.json"), {"armory": 1}), CARDS.source(defs, [{"id": "armorer_discount"}])])
	check("дары и карточки — два источника одного Mods: Оружейная 1 (-5%) и Скидка оружейника (-15%) — набор пехоты 100 -> 80, оружие 150 -> 128",
		both.value("unit_cost", 100.0) == 80.0 and both.value("weapon_cost", 150.0) == 128.0)
	var rng := RandomNumberGenerator.new()
	var results := {}
	for s in 20:
		rng.seed = s
		results[CARDS.make_record(defs.victory_sacrifice, rng).result.good] = true
	rng.seed = 7
	var a := CARDS.make_record(defs.victory_sacrifice, rng)
	rng.seed = 7
	var b := CARDS.make_record(defs.victory_sacrifice, rng)
	check("карточка 30: результат от генератора забега, при одном seed одинаковый, за 20 seed выпадают обе цели", a == b and results.size() == 2, str(a))

func t_battle() -> void:
	print("сцена боя с карточками (active_cards)")
	var p := make([])
	var c := make([{"id": "meteor_blades"}, {"id": "heavy_shields"}, {"id": "dark_vow"}])
	check("Клинки (урон пехоты +12%), Тяжёлые щиты (HP +20%, скорость -10%), Тёмный обет (награда +40%, HP зомби +15%) — в данных волны",
		is_equal_approx(c.type_damage[c.infantry_type], p.type_damage[p.infantry_type] * 1.12) and is_equal_approx(c.type_hp[c.archer_type], p.type_hp[p.archer_type] * 1.2)
		and is_equal_approx(c.type_speed[c.infantry_type], p.type_speed[p.infantry_type] * 0.9) and is_equal_approx(c.type_bounty_mult[c.zombie_type], p.type_bounty_mult[p.zombie_type] * 1.4)
		and is_equal_approx(c.type_hp[c.knight_type], p.type_hp[p.knight_type] * 1.15))
	c.active_cards.append({"id": "silver_vs_dead"})
	c._start_wave()
	check("карточка, выбранная в передышке, действует со следующей волны: урон пехоты x1.12 (своя цель) x1.10 (все)", is_equal_approx(c.type_damage[c.infantry_type], p.type_damage[p.infantry_type] * 1.12 * 1.1))
	p.free()
	c.free()

func t_game() -> void:
	print("Game.run_cards, run_rng")
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load(GAME).new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	check("Game загрузил 40 карточек и правила; run_cards пуст", g.card_defs.size() == 40 and not g.card_rules.is_empty() and g.run_cards.is_empty())
	g.run_cards = [{"id": "purse"}]
	g.run_seed = 11
	g.cfg_ok = false   # start_run без смены сцены: здесь проверяется только сброс состояния
	g.start_run(1)
	g.cfg_ok = true
	g.run_cards = []
	g.run_rng.seed = 11
	var r: Dictionary = g.pick_card("victory_sacrifice")
	check("pick_card: запись добавлена, у карточки 30 есть результат; повтор, disabled и неизвестная — отказ", not r.is_empty() and r.has("result") and g.run_cards.size() == 1
		and g.pick_card("victory_sacrifice").is_empty() and g.pick_card("boiling_pitch").is_empty() and g.pick_card("нет").is_empty() and g.run_cards.size() == 1)
	check("mod_sources: дары и карточки (2 источника)", g.mod_sources().size() == 2 and g.mod_sources()[1].name == "cards")
	g.run_cards = [{"id": "grace_blessing"}]
	check("Благословение Благодати (+10% Сияния) в run_reward: поражение на волне 5 — 22 -> 24", g.run_reward("loss", 5) == 24)
	g.run_cards = []
	check("без карточек — 22", g.run_reward("loss", 5) == 22)
	var o: Array = g.card_offer()
	check("card_offer: тройка из разных основных билдов", o.size() == 3 and o.map(func(id): return g.card_defs[id].builds[0]).reduce(func(acc, b): return acc if b in acc else acc + [b], []).size() == 3, str(o))
	g.queue_free()
	await step(2)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)
