extends SceneTree
# Тесты v44 (шаг 5: Сияние и магазин даров). Узел Game с временным сохранением в user://bench_v44 (настоящий user://save.json не трогается);
# сцена боя вне дерева или в дереве с выключенным process_mode, физика вручную.
# (а) пустой набор даров — как в эталоне bench/ref/main_ref.gd; (б) награда за забег; (в) покупка; (г) сохранение;
# (д) Game.active_gifts из gift_levels и параметр --gifts; (е) таблица пар stat / target; вкладка «Дары» в хабе.
const MODS := preload("res://scripts/mods.gd")
const GAME := "res://scripts/game.gd"
const MAIN := "res://scripts/main.gd"
const REF := "res://bench/ref/main_ref.gd"
const GIFTS := "res://data/gifts.json"
const FIX_G := "res://bench/fixtures_gifts/"
const FIX_R := "res://bench/fixtures_radiance/"
const DIR := "user://bench_v44"
const SAVE := DIR + "/save.json"
const DT := 1.0 / 30.0
const IDS := ["tempered_steel", "sturdy_shields", "marksmen", "spoils", "mine", "fortress_walls", "reserve",
	"armory", "smith_thomas", "repairers", "watch", "discipline", "radiance_reserve", "infirmary", "war_cry", "spear_wall"]   # data/gifts.json, порядок файла
const SHOWN := ["tempered_steel", "sturdy_shields", "marksmen", "spoils", "mine", "reserve",
	"armory", "smith_thomas", "repairers", "watch", "discipline", "radiance_reserve", "infirmary", "war_cry", "spear_wall"]   # без скрытого fortress_walls
# сохранение до шага 5: полей radiance и gift_levels нет
const OLD_SAVE := "{\"version\": 1, \"unlocked_siege\": 2, \"last_siege\": 2, \"records\": {\"1\": {\"best_wave\": 10, \"wins\": 1, \"runs\": 4}}, \"diary_seen\": [\"intro\"], \"completed\": false, \"runs_total\": 4, \"play_time\": 90.5}"
var fails := 0
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func wipe() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)

func put(text: String) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func on_disk() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE)) if FileAccess.file_exists(SAVE) else null
	return d if d is Dictionary else {}

# Новый узел Game (как при новом запуске игры): сохранение читается из временной папки.
func new_game(gifts := GIFTS, radiance := "") -> void:
	if g != null:
		g.free()
		await step(1)
	g = load(GAME).new()
	g.name = "Game"
	g.save_path = SAVE
	g.gifts_path = gifts
	if radiance != "":
		g.radiance_path = radiance
	root.add_child(g)

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == MAIN:
		n.process_mode = Node.PROCESS_MODE_DISABLED

func run(siege := 1) -> Node2D:
	g.start_run(siege)
	await step(3)
	return current_scene as Node2D

# Конец забега на волне w без боя (как в check_v42).
func finish(m: Node2D, w: int, win := false) -> void:
	m.wave_number = w
	m.wave_state = m.WS_BATTLE
	if win:
		m._on_win()
	else:
		m._on_defeat()

func plain(path: String, rng_seed: int) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func count_type(m: Node2D, type: int) -> int:
	var n := 0
	for i in m.count:
		if m.unit_type[i] == type:
			n += 1
	return n

# Числа старта забега, на которые действуют дары.
# n — сколько типов сравнивать (у эталона нет типа героя задачи 10: в игровом режиме он последний); герой не входит в count.
func start_numbers(m: Node2D, n := -1) -> Array:
	var k: int = m.type_hp.size() if n < 0 else n
	var hero: int = 1 if "hero_idx" in m and m.hero_idx >= 0 else 0
	return [Array(m.type_hp).slice(0, k), Array(m.type_damage).slice(0, k), Array(m.type_arrow_dmg).slice(0, k), Array(m.type_bounty_mult).slice(0, k),
		m.gate_hp, m.gate_hp_max, m.gold, m.income_pct, m.count - hero]

func state() -> Array:
	return [g.radiance, g.gift_levels.duplicate()]

func real_stamp() -> String:
	return "%d/%d" % [FileAccess.get_modified_time("user://save.json"), FileAccess.get_file_as_bytes("user://save.json").size()] if FileAccess.file_exists("user://save.json") else "нет"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # автозагрузка проекта: тест ставит свой узел Game с временным сохранением
		await step(1)
	var real := real_stamp()
	DirAccess.make_dir_recursive_absolute(DIR)
	wipe()
	node_added.connect(_on_node_added)
	t_regress()
	t_validation()
	await t_reward()
	await t_buy()
	await t_save()
	await t_active()
	await t_hub()
	if current_scene != null:
		current_scene.queue_free()
	g.queue_free()
	await step(2)
	wipe()
	DirAccess.remove_absolute(DIR)
	check("настоящий user://save.json не тронут, временная папка убрана", real_stamp() == real and not DirAccess.dir_exists_absolute(DIR))
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# (а) пустой набор даров: рабочий main против эталона на каждом тике.
func t_regress() -> void:
	print("(а) регрессия: пустой набор даров")
	print("  эталон: " + FileAccess.get_file_as_string("res://bench/ref/REF.txt").strip_edges())
	var a := plain(REF, 9)
	var b := plain(MAIN, 9)
	check("старт без даров: числа типов, ворота, золото, число юнитов — как в эталоне; active_gifts пуст", start_numbers(a) == start_numbers(b) and b.active_gifts.is_empty() and b.income_pct == 0.0)
	var first := -1
	var ticks := 0
	var buys := [1, 2, 0, 3]
	for w in 2:
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
	check("2 волны с покупками (seed 9, %d тиков, волна %d, юнитов %d): бит в бит как в эталоне на каждом тике" % [ticks, b.wave_number, b.count],
		first < 0 and a.wave_number == 2 and b.wave_number == 2 and ticks > 300, "" if first < 0 else "первое расхождение: тик %d" % first)
	a.free()
	b.free()

# (е) таблица допустимых пар stat / target.
func t_validation() -> void:
	print("(е) валидация пар stat / target — ниже ожидаются строки ERROR от недопустимых пар")
	var want := {"damage": ["all_units", "infantry", "archer", "spearman"], "hp": ["all_units", "infantry", "archer", "spearman"], "bounty": ["player", "knight"], "income": ["player"],
		"gate_hp": ["gate"], "start_units": ["player"], "unit_cost": ["player", "archer", "spearman"], "weapon_cost": ["player"], "repair_cost": ["player"], "signal_window": ["player"],
		"spread": ["archer"], "radiance_pct": ["player"], "income_flat": ["player"], "heal": ["player"], "speed": ["all_units", "infantry", "archer", "spearman"],
		"reload": ["archer"], "attack_speed": ["infantry"], "range": ["archer"], "enemy_hp": ["enemy"], "grant_units_free": ["player"],
		"block": ["all_units", "infantry", "spearman"], "recover": ["player"], "attack_rate": ["all_units", "infantry", "archer"]}
	check("таблица MODS.PAIRS как в задании, покрывает все stat", MODS.PAIRS == want and MODS.PAIRS.size() == MODS.STATS.size(), str(MODS.PAIRS))
	var wrong := PackedStringArray()
	var allowed := 0
	for stat in MODS.STATS:
		for target in MODS.TARGETS:
			var path := "%s/pair_%s_%s.json" % [DIR, stat, target]
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(JSON.stringify([{"id": "x", "name_key": "X", "desc_key": "X", "stat": stat, "target": target, "op": MODS.STAT_OPS[stat][0], "levels": [5]}]))
			f.close()
			var ok: bool = not MODS.load_gifts(path).is_empty()
			allowed += int(ok)
			if ok != (target in want[stat]):
				wrong.append("%s/%s" % [stat, target])
	check("все %d сочетаний stat x target: грузятся ровно допустимые (%d)" % [MODS.STATS.size() * MODS.TARGETS.size(), allowed], wrong.is_empty() and allowed == want.values().reduce(func(a, v): return a + v.size(), 0), ", ".join(wrong))
	check("bad_pair.json (start_units / all_units) не грузится", MODS.load_gifts(FIX_G + "bad_pair.json").is_empty())
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = 1
	m.record_path = "user://record_bench.json"
	m.gifts_path = FIX_G + "bad_pair.json"
	m._setup_data()
	check("сцена боя с bad_pair.json: остановка (типы сброшены, тик выключен)", m.type_id.is_empty() and not m.is_physics_processing() and not m.is_processing())
	m.free()
	var defs: Dictionary = MODS.load_gifts(GIFTS)
	var ok_data := defs.size() == 16
	for id in IDS:
		if id == "war_cry":   # способность: своих stat / target / op нет, цены свои — вдвое выше общих
			ok_data = ok_data and defs[id].type == "ability" and Array(defs[id].prices) == [120, 240, 480] and Array(defs[id].req_sieges) == [0, 1, 2]
			continue
		ok_data = ok_data and defs.has(id) and Array(defs[id].req_sieges) == [0, 1, 2] and defs[id].prices.is_empty() and defs[id].target in want[defs[id].stat] \
			and defs[id].op in MODS.STAT_OPS[defs[id].stat] and defs[id].hidden == (id == "fortress_walls")
	check("data/gifts.json: 16 даров, пары и op допустимые, req_sieges [0, 1, 2], своих цен нет, кроме Клича Благодати, скрыты только «Стены крепости»", ok_data
		and tr(defs["fortress_walls"].name_key) == "Стены крепости")
	var stat_ops := {"damage": ["add_pct", "mult"], "hp": ["add_pct", "mult"], "bounty": ["add_pct", "mult"], "income": ["add_pct", "mult"], "gate_hp": ["add_pct", "mult"],
		"start_units": ["add_pct", "add_flat"], "unit_cost": ["add_pct"], "weapon_cost": ["add_pct"], "repair_cost": ["add_pct"], "signal_window": ["add_flat"],
		"spread": ["add_pct"], "radiance_pct": ["add_pct"], "income_flat": ["add_flat"], "heal": ["add_pct"], "speed": ["add_pct"], "reload": ["add_pct"],
		"attack_speed": ["add_pct"], "range": ["add_pct"], "enemy_hp": ["add_pct"], "grant_units_free": ["add_flat"], "block": ["add_flat"], "recover": ["add_pct"], "attack_rate": ["add_pct"]}
	check("таблица MODS.STAT_OPS как в задании, покрывает все stat", MODS.STAT_OPS == stat_ops and MODS.STAT_OPS.size() == MODS.STATS.size(), str(MODS.STAT_OPS))
	var wrong_op := PackedStringArray()
	var allowed_op := 0
	for stat in MODS.STATS:
		for op in MODS.OPS:
			var path := "%s/op_%s_%s.json" % [DIR, stat, op]
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(JSON.stringify([{"id": "x", "name_key": "X", "desc_key": "X", "stat": stat, "target": want[stat][0], "op": op, "levels": [5]}]))
			f.close()
			var ok: bool = not MODS.load_gifts(path).is_empty()
			allowed_op += int(ok)
			if ok != (op in stat_ops[stat]):
				wrong_op.append("%s/%s" % [stat, op])
	check("все %d сочетаний stat x op: грузятся ровно допустимые (%d)" % [MODS.STATS.size() * MODS.OPS.size(), allowed_op], wrong_op.is_empty() and allowed_op == stat_ops.values().reduce(func(a, v): return a + v.size(), 0), ", ".join(wrong_op))

	check("req_sieges и prices не той длины или с числом меньше допустимого не грузятся", MODS.load_gifts(FIX_G + "bad_req.json").is_empty() and MODS.load_gifts(FIX_G + "bad_gift_prices.json").is_empty())
	var shop: Dictionary = MODS.load_gifts(FIX_G + "shop.json")
	check("shop.json: свои prices и req_sieges читаются; без полей — req_sieges 0, 1, 2 и пустой prices", shop.size() == 2 and Array(shop["cheap"].prices) == [10, 20, 30]
		and Array(shop["cheap"].req_sieges) == [0, 0, 3] and Array(shop["plain"].req_sieges) == [0, 1, 2] and shop["plain"].prices.is_empty())

# (б) награда за забег.
func t_reward() -> void:
	print("(б) награда — ниже ожидаются строки ERROR от повреждённых radiance.json")
	var gs: GDScript = load(GAME)
	var cfg: Dictionary = gs.load_radiance_cfg("res://data/radiance.json")
	check("data/radiance.json: за волну 3 + номер, за победу 50, цены уровней 60 / 120 / 240", cfg.get("wave_base") == 3 and cfg.get("wave_step") == 1 and cfg.get("win_bonus") == 50
		and Array(cfg.get("gift_prices", [])) == [60, 120, 240], str(cfg))
	for name in ["no_field", "bad_prices", "not_object", "fraction", "missing_file"]:
		check("повреждённый %s.json не грузится" % name, gs.load_radiance_cfg(FIX_R + name + ".json").is_empty())
	wipe()
	await new_game()
	var want := [["loss", 1, 0], ["loss", 5, 22], ["loss", 10, 72], ["win", 10, 135]]
	for c in want:
		check("run_reward: %s на волне %d -> %d" % [c[0], c[1], c[2]], g.run_reward(c[0], c[1]) == c[2], str(g.run_reward(c[0], c[1])))
	var total := 0
	for c in want:
		var m := await run(1)
		finish(m, c[1], c[0] == "win")
		total += c[2]
		check("забег (%s, волна %d): last_run.radiance %d, баланс %d, в файле то же; на экране итога «+%d Сияния», прежние строки баннера на месте" % [c[0], c[1], c[2], total, c[2]],
			g.last_run.radiance == c[2] and g.radiance == total and on_disk().get("radiance") == total and m.banner_radiance == "+%d Сияния" % c[2]
			and m.radiance_label.visible and m.radiance_label.text == m.banner_radiance and m.radiance_label.get_index() == 3 and m.banner_parts[2] != ""
			and m.banner_parts[3].ends_with("Enter — в хаб"), "%s, баланс %d" % [m.banner_radiance, g.radiance])
	var m2 := await run(1)
	check("новый забег: строки Сияния в баннере нет, last_run.radiance 0, баланс прежний", m2.banner_radiance == "" and not m2.radiance_label.visible and g.last_run.radiance == 0 and g.radiance == total)
	wipe()
	await new_game(GIFTS, FIX_R + "alt.json")
	check("числа из json (alt.json: 10 за волну, победа 7): поражение на волне 5 -> 40, победа -> 107", g.run_reward("loss", 5) == 40 and g.run_reward("win", 10) == 107)
	wipe()
	await new_game(GIFTS, FIX_R + "no_field.json")
	g.radiance = 1000
	check("radiance.json не загрузился: награда 0, покупки отклоняются", g.run_reward("win", 10) == 0 and not g.buy_gift("mine") and g.radiance == 1000 and g.buy_block("mine") == g.BLOCK_DATA)

# (в) покупка.
func t_buy() -> void:
	print("(в) покупка")
	wipe()
	await new_game()
	check("новая игра: Сияния 0, все 16 даров на уровне 0, пройдено осад 0", g.radiance == 0 and g.gift_levels.size() == 16 and g.owned_gifts().is_empty() and g.sieges_cleared() == 0, str(g.gift_levels))
	check("цены уровней по умолчанию 60 / 120 / 240; уровней 0 и 4 нет (-1)", g.gift_price("mine", 1) == 60 and g.gift_price("mine", 2) == 120 and g.gift_price("mine", 3) == 240
		and g.gift_price("mine", 0) == -1 and g.gift_price("mine", 4) == -1 and g.gift_price("нет такого", 1) == -1)
	g.radiance = 59
	var before := state()
	check("59 Сияния, цена 60: отказ «Не хватает Сияния», ничего не меняется, файл не пишется", tr(g.buy_block("mine")) == "Не хватает Сияния" and not g.buy_gift("mine") and state() == before
		and not FileAccess.file_exists(SAVE))
	g.radiance = 500
	check("500 Сияния: уровень 1 куплен, списано 60, сохранено сразу", g.buy_block("mine") == "" and g.buy_gift("mine") and g.radiance == 440 and g.gift_levels["mine"] == 1
		and on_disk().get("radiance") == 440 and on_disk().get("gift_levels", {}).get("mine") == 1, str(state()))
	before = state()
	check("уровень 2 до победы в осаде I: отказ «Откроется после осады I», ничего не меняется", g.buy_block("mine") == "Откроется после осады I" and not g.buy_gift("mine") and state() == before
		and on_disk().get("radiance") == 440)
	g.records[1].wins = 1
	check("осада I пройдена: уровень 2 куплен за 120", g.sieges_cleared() == 1 and g.buy_gift("mine") and g.radiance == 320 and g.gift_levels["mine"] == 2)
	before = state()
	check("уровень 3 до победы в осаде II: отказ «Откроется после осады II»", g.buy_block("mine") == "Откроется после осады II" and not g.buy_gift("mine") and state() == before)
	g.records[3].wins = 1
	check("победа только в осадах I и III: пройдено подряд 1, уровень 3 закрыт", g.sieges_cleared() == 1 and not g.buy_gift("mine"))
	g.records[3].wins = 0
	g.records[2].wins = 1
	check("осада II пройдена: уровень 3 куплен за 240", g.sieges_cleared() == 2 and g.buy_gift("mine") and g.radiance == 80 and g.gift_levels["mine"] == 3)
	g.radiance = 9999
	before = state()
	check("уровень 3 — последний: отказ «Максимальный уровень», ничего не меняется", tr(g.buy_block("mine")) == "Максимальный уровень" and not g.buy_gift("mine") and state() == before)
	check("неизвестный дар: отказ, ничего не меняется", not g.buy_gift("нет такого") and state() == before)
	check("остальные дары не задеты", g.owned_gifts() == {"mine": 3})
	check("скрытый fortress_walls не продаётся (BLOCK_DATA), ничего не меняется", g.buy_block("fortress_walls") == g.BLOCK_DATA and not g.buy_gift("fortress_walls") and state() == before)
	check("цены reserve общие: 60 / 120 / 240", g.gift_price("reserve", 1) == 60 and g.gift_price("reserve", 2) == 120 and g.gift_price("reserve", 3) == 240)
	wipe()
	await new_game(FIX_G + "shop.json")
	g.radiance = 100
	check("свои цены дара (shop.json, 10 / 20 / 30) важнее общих; свой req_sieges [0, 0, 3]: уровни 1 и 2 без осад, уровень 3 — после осады III", g.gift_price("cheap", 2) == 20
		and g.gift_price("plain", 2) == 120 and g.buy_gift("cheap") and g.buy_gift("cheap") and g.radiance == 70 and g.buy_block("cheap") == "Откроется после осады III", str(state()))

# (г) сохранение.
func t_save() -> void:
	print("(г) сохранение")
	wipe()
	await new_game()
	g.radiance = 777
	g.records[1].wins = 1
	g.buy_gift("spoils")
	g.buy_gift("spoils")
	g.buy_gift("reserve")
	var levels: Dictionary = g.gift_levels.duplicate()
	check("запись: в файле radiance 537 и gift_levels со всеми 16 дарами", g.save() and on_disk().get("radiance") == 537 and on_disk().get("gift_levels", {}).size() == 16
		and on_disk().gift_levels.get("spoils") == 2 and on_disk().gift_levels.get("tempered_steel") == 0, str(on_disk().get("gift_levels")))
	await new_game()
	check("загрузка новым узлом Game: те же radiance и gift_levels, предупреждений нет", g.radiance == 537 and g.gift_levels == levels and g.gift_levels["spoils"] == 2
		and g.gift_levels["reserve"] == 1 and g.save_warning == "", str(state()))
	check("уровни после загрузки — целые числа (сцена боя их примет)", typeof(g.gift_levels["spoils"]) == TYPE_INT and typeof(g.radiance) == TYPE_INT)
	wipe()
	put(OLD_SAVE)
	await new_game()
	check("старый файл без radiance и gift_levels грузится: Сияния 0, дары на уровне 0, остальное из файла, файл не признан повреждённым",
		g.radiance == 0 and g.gift_levels.size() == 16 and g.owned_gifts().is_empty() and g.unlocked_siege == 2 and g.runs_total == 4 and g.records[1].wins == 1
		and g.diary_seen == ["intro"] and g.save_warning == "" and DirAccess.get_files_at(DIR).size() == 1, "%s, файлов %d" % [str(state()), DirAccess.get_files_at(DIR).size()])
	check("пройденные осады берутся из рекордов старого файла: 1", g.sieges_cleared() == 1)
	check("после первой записи в старом файле появляются оба поля", g.save() and on_disk().get("radiance") == 0 and on_disk().get("gift_levels") is Dictionary and on_disk().get("version") == 1)
	wipe()
	put(OLD_SAVE.replace("\"runs_total\": 4", "\"runs_total\": 4, \"radiance\": \"много\", \"gift_levels\": {\"mine\": 9, \"spoils\": -1, \"reserve\": 1.5, \"нет такого\": 2, \"tempered_steel\": 2}"))
	await new_game()
	check("кривые значения полей: radiance не число — 0; уровень выше числа уровней — 3; отрицательный, дробный и неизвестный дар отброшены",
		g.radiance == 0 and g.owned_gifts() == {"mine": 3, "tempered_steel": 2} and g.save_warning == "" and g.runs_total == 4, str(state()))
	wipe()
	put(OLD_SAVE.replace("\"runs_total\": 4", "\"runs_total\": 4, \"radiance\": 30, \"gift_levels\": {\"fortress_walls\": 2, \"mine\": 1}"))
	await new_game()
	check("старый файл с купленными «Стенами крепости» 2: грузится без предупреждения, уровень хранится, но не действует (в owned_gifts только mine)",
		g.save_warning == "" and g.radiance == 30 and g.gift_levels["fortress_walls"] == 2 and g.owned_gifts() == {"mine": 1} and DirAccess.get_files_at(DIR).size() == 1, str(state()))
	check("после записи уровень скрытого дара в файле прежний (покупка не пропадает)", g.save() and on_disk().gift_levels.get("fortress_walls") == 2 and on_disk().gift_levels.get("mine") == 1)

# (д) набор даров забега.
func t_active() -> void:
	print("(д) active_gifts")
	var gs: GDScript = load(GAME)
	check("parse_gifts_arg: параметра нет — null; «--gifts mine:2,reserve:1» среди других аргументов; пустое значение — пустой набор",
		gs.parse_gifts_arg(PackedStringArray(["B5", "1"])) == null and gs.parse_gifts_arg(PackedStringArray(["B5", "1", "--gifts", "mine:2,reserve:1"])) == {"mine": 2, "reserve": 1}
		and gs.parse_gifts_arg(PackedStringArray(["--gifts", ""])) == {} and gs.parse_gifts_arg(PackedStringArray(["--gifts"])) == {})
	wipe()
	await new_game()
	check("у теста параметра --gifts нет: gifts_override null", g.gifts_override == null)
	var m := await run(1)
	var base := start_numbers(m)
	var r := plain(REF, m.spawn_seed)
	check("ничего не куплено: active_gifts пуст, старт забега через Game — те же числа, что у эталона", g.active_gifts.is_empty() and m.active_gifts.is_empty() and start_numbers(r) == start_numbers(m, r.type_hp.size()))
	r.free()
	g.gift_levels["fortress_walls"] = 2
	g.gift_levels["reserve"] = 1
	g.gift_levels["tempered_steel"] = 3
	m = await run(1)
	check("куплены fortress_walls 2 (скрыт), reserve 1, tempered_steel 3: active_gifts — reserve и tempered_steel (дары уровня 0 и скрытые не входят)",
		g.active_gifts == {"reserve": 1, "tempered_steel": 3} and m.active_gifts == g.active_gifts, str(g.active_gifts))
	check("в бою: ворота прежние, удары пехоты x1.18 (задача 6d: скорость атаки), урон прежний, +10% в стартовых отрядах (+30 и +10), HP прежние", m.gate_hp_max == base[5]
		and absf(m._cd_actual(m.base_type_cooldown[m.infantry_type]) / m.type_cooldown[m.infantry_type] - 1.18) < 1e-4 and Array(m.type_damage) == base[1] and m.count == base[8] + 40
		and Array(m.type_hp) == base[0],
		"ворота %.0f, юнитов %d" % [m.gate_hp_max, m.count])
	g.gifts_override = gs.parse_gifts_arg(PackedStringArray(["B5", "1", "--gifts", "mine:2"]))
	m = await run(1)
	check("--gifts mine:2 важнее сохранения: active_gifts {mine 2}, купленные дары не действуют, gift_levels не тронут",
		g.active_gifts == {"mine": 2} and m.active_gifts == {"mine": 2} and is_equal_approx(m.income_pct, 0.10) and m.gate_hp_max == base[5] and m.count == base[8]
		and g.gift_levels["fortress_walls"] == 2 and g.gift_levels["mine"] == 0, str(g.active_gifts))
	g.gifts_override = gs.parse_gifts_arg(PackedStringArray(["--gifts", ""]))
	m = await run(1)
	check("--gifts с пустым значением: забег без даров при купленных", g.active_gifts.is_empty() and start_numbers(m) == base)
	g.gifts_override = null
	m = await run(1)
	check("без параметра снова действуют купленные", g.active_gifts.size() == 2 and m.count == base[8] + 40)
	g.gifts_override = gs.parse_gifts_arg(PackedStringArray(["--gifts", "fortress_walls:3"]))
	m = await run(1)
	check("--gifts fortress_walls:3 (скрыт): забег идёт без ошибок, как без даров", m.type_id.size() > 0 and start_numbers(m) == base)
	g.gifts_override = null
	check("в сохранении набора забега нет, купленные уровни есть", g.save() and not on_disk().has("active_gifts") and on_disk().gift_levels.get("tempered_steel") == 3)

# Вкладка «Дары» в хабе.
func t_hub() -> void:
	print("хаб: вкладка «Дары»")
	wipe()
	await new_game()
	g.radiance = 200
	g.go_hub()
	await step(3)
	var h := current_scene
	check("в хабе две вкладки: «Осада» (открыта, фокус на «Начать забег») и «Дары»", h != null and h.name == "Hub" and h.tabs.get_tab_count() == 2 and tr(h.tabs.get_tab_title(0)) == "Осада"
		and tr(h.tabs.get_tab_title(1)) == "Дары" and h.tabs.current_tab == 0 and h.start_button.has_focus())
	h.tabs.current_tab = 1
	await step(1)
	var names := PackedStringArray()
	var icons := true
	var grid: GridContainer = h.gift_rows["mine"].button.get_parent()
	for c in grid.get_children():
		if c is TextureRect:
			icons = icons and c.texture != null
	for id in h.gift_rows:
		names.append(tr(g.gift_defs[id].name_key))
	check("15 строк даров в порядке файла (скрытых «Стен крепости» нет), у каждой иконка; баланс «Сияние: 200»", Array(h.gift_rows.keys()) == SHOWN and icons and grid.get_child_count() == 16 * 7
		and tr(h.radiance_label.text) == "Сияние: 200" and h.radiance_label.is_visible_in_tree() and not "Стены крепости" in names and "Меткие стрелки" in names, ", ".join(names))
	var row: Dictionary = h.gift_rows["tempered_steel"]
	check("строка дара: уровень «0 / 3», эффект следующего уровня «+6% к скорости атаки пехоты», цена 60, «Купить» активна, причины нет",
		tr(row.level.text) == "0 / 3" and tr(row.effect.text) == "+6% к скорости атаки пехоты" and tr(row.price.text) == "60" and tr(row.button.text) == "Купить" and not row.button.disabled and tr(row.reason.text) == "",
		"%s | %s | %s" % [row.level.text, row.effect.text, row.price.text])
	var texts := PackedStringArray()
	for id in SHOWN:
		texts.append(h.gift_rows[id].effect.text)
	check("эффекты одной строкой у всех даров", Array(texts) == ["+6% к скорости атаки пехоты", "+6% к здоровью всех воинов", "+8% к урону лучников", "+10% золота за убитых",
		"+5% к доходу волны в конце каждой волны", "+10% воинов в каждом стартовом отряде (не меньше +1)", "-5% к цене наборов пехоты и лучников",
		"-5% к цене улучшения оружия", "-15% к цене ремонта ворот", "+0.25 с к окну сигнала всплеска", "-10% к разбросу стрел", "+5% Сияния за забег", "После волны возвращает 10% павших",
		"Кнопка в бою: всем +30% скорости ударов на 8 с, перезарядка 60 с", "+5 п. п. к шансу блока у всех воинов со щитом"], " | ".join(texts))
	check("цена «Резерва» в строке — общая: 60", tr(h.gift_rows["reserve"].price.text) == "60")
	row.button.pressed.emit()
	check("«Купить»: уровень «1 / 3», баланс 140, сохранено; следующий уровень +12% за 120 закрыт: «Откроется после осады I»", g.gift_levels["tempered_steel"] == 1 and g.radiance == 140
		and tr(h.radiance_label.text) == "Сияние: 140" and tr(row.level.text) == "1 / 3" and tr(row.effect.text) == "+12% к скорости атаки пехоты" and tr(row.price.text) == "120" and row.button.disabled
		and tr(row.reason.text) == "Откроется после осады I" and on_disk().get("radiance") == 140, row.reason.text)
	h.gift_rows["mine"].button.pressed.emit()
	h.gift_rows["spoils"].button.pressed.emit()
	var poor: Dictionary = h.gift_rows["reserve"]
	check("после ещё двух покупок Сияния 20: у некупленных кнопка неактивна, «Не хватает Сияния»", g.radiance == 20 and poor.button.disabled and tr(poor.reason.text) == "Не хватает Сияния"
		and tr(poor.level.text) == "0 / 3" and tr(h.gift_rows["marksmen"].reason.text) == "Не хватает Сияния")
	poor.button.pressed.emit()
	check("нажатие неактивной покупки ничего не меняет", g.radiance == 20 and g.gift_levels["reserve"] == 0)
	g.records[1].wins = 1
	g.records[2].wins = 1
	g.radiance = 1000
	h._refresh_gifts()
	row.button.pressed.emit()
	row.button.pressed.emit()
	check("после осад I и II: уровни 2 и 3 куплены (120 + 240), строка «3 / 3», эффект и цена «—», причина «Максимальный уровень»", g.gift_levels["tempered_steel"] == 3 and g.radiance == 640
		and tr(row.level.text) == "3 / 3" and tr(row.effect.text) == "—" and tr(row.price.text) == "—" and row.button.disabled and tr(row.reason.text) == "Максимальный уровень")
	h.tabs.current_tab = 0
	await step(1)
	check("назад на «Осада»: фокус на «Начать забег»", h.start_button.has_focus() and h.start_button.is_visible_in_tree())
	h.start_button.pressed.emit()
	await step(3)
	var m := current_scene as Node2D
	check("«Начать забег» из хаба: купленные дары действуют (tempered_steel 3, mine 1, spoils 1)", m != null and m.active_gifts == {"tempered_steel": 3, "mine": 1, "spoils": 1}
		and is_equal_approx(m.income_pct, 0.05), "" if m == null else str(m.active_gifts))
