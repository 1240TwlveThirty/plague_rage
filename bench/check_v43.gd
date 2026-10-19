extends SceneTree
# Тесты v43 (движок модификаторов, этап 1: дары на старте забега). Сцена боя вне дерева, физика вручную; для связки с Game — узел Game
# с временным сохранением в user://bench_v43 (настоящий user://save.json не трогается).
# (б) формула Mods; (в) каждый дар на каждом уровне меняет свою величину и ничего другого; действие даров в бою;
# (г) детерминизм с дарами; загрузчик gifts.json и остановка сцены при ошибке; Game.active_gifts.
const MODS := preload("res://scripts/mods.gd")
const GAME := "res://scripts/game.gd"
const MAIN := "res://scripts/main.gd"
const GIFTS := "res://data/gifts.json"
const FIX := "res://bench/fixtures_gifts/"
const DIR := "user://bench_v43"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func make(gifts: Dictionary, rng_seed := 1, path := GIFTS) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.gifts_path = path
	m.active_gifts = gifts
	m._setup_data()
	return m

func count_type(m: Node2D, type: int) -> int:
	var n := 0
	for i in m.count:
		if m.unit_type[i] == type:
			n += 1
	return n

func wave(m: Node2D) -> void:
	m._start_wave()
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 600:
		m._physics_process(DT)
		t += 1

# Всё, на что дар мог бы повлиять при старте забега: числа типов, ворота, золото, состав армии, магазин, план волны 1.
func snap(m: Node2D) -> Dictionary:
	var d := {}
	for key in ["type_hp", "type_damage", "type_arrow_dmg", "type_bounty_mult", "type_cooldown", "type_speed", "type_range_sq", "type_block_mult", "type_range_far",
			"type_volley_period", "type_draw_time", "type_spread", "wave_spread", "shop_base", "shop_growth", "shop_param", "shop_cap"]:
		d[key] = Array(m.get(key))
	for key in ["gate_hp", "gate_hp_max", "gate_half", "gate_dmg_mult", "gold", "income_pct", "wave_income", "count", "zombie_alive", "wave_number", "wave_state", "wave_hp_mult", "wave_signal_lead"]:
		d[key] = m.get(key)
	d["team_dmg_mult"] = Array(m.team_dmg_mult)
	d["infantry"] = count_type(m, m.infantry_type)
	d["archers"] = count_type(m, m.archer_type)
	d["squad_n"] = [m.squad_n[0], m.squad_n[1]]
	d["wave_plan"] = str(m.wave_plan)
	d["wave_cfg"] = str(m.wave_cfg)
	return d

func near(a, b) -> bool:
	if a is Array:
		if not b is Array or a.size() != b.size():
			return false
		for k in a.size():
			if not near(a[k], b[k]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(a - b) <= 1e-5 * maxf(1.0, absf(b))
	return a == b

# Ключи снимка, где got отличается от want.
func diff(got: Dictionary, want: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key in want:
		if not near(got[key], want[key]):
			out.append(key)
	return out

func scaled(arr: Array, idx: Array, k: float) -> Array:
	var out := arr.duplicate()
	for t in idx:
		out[t] *= k
	return out

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # автозагрузка проекта: сцена боя вне дерева идёт без синглтона
		await step(1)
	t_formula()
	t_loader()
	t_each_gift()
	t_battle()
	t_determinism()
	await t_game()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# (б) формула.
func t_formula() -> void:
	print("(б) формула Mods")
	var defs: Dictionary = MODS.load_gifts(FIX + "formula.json")
	var m = MODS.new(defs)
	check("пустой набор: get_mult ровно 1.0, get_flat 0, has_rule false", m.build({}) and m.get_mult("damage", "all_units") == 1.0 and m.get_mult("hp", "infantry") == 1.0
		and m.get_flat("start_units", "player") == 0.0 and not m.has_rule("tempered_steel"))
	check("до build: тоже ровно 1.0", MODS.new(defs).get_mult("damage", "all_units") == 1.0 and MODS.new().get_mult("hp", "gate") == 1.0)
	check("16% + 20% одного ключа складываются: 1.36", m.build({"a16": 1, "a20": 2}) and is_equal_approx(m.get_mult("damage", "all_units"), 1.36), "%.6f" % m.get_mult("damage", "all_units"))
	check("другой ключ не задет: damage/infantry и hp/all_units ровно 1.0", m.get_mult("damage", "infantry") == 1.0 and m.get_mult("hp", "all_units") == 1.0)
	check("mult x add: (1 + 0.20) * 1.5 = 1.8", m.build({"a20": 2, "m15": 1}) and is_equal_approx(m.get_mult("damage", "all_units"), 1.8), "%.6f" % m.get_mult("damage", "all_units"))
	check("только mult: 2.0; два ключа раздельно: all_units 1.1, infantry 1.5", m.build({"m15": 2}) and is_equal_approx(m.get_mult("damage", "all_units"), 2.0)
		and m.build({"a20": 1, "inf": 1}) and is_equal_approx(m.get_mult("damage", "all_units"), 1.1) and is_equal_approx(m.get_mult("damage", "infantry"), 1.5))
	check("add_flat одного ключа складывается: 40 + 25 = 65; на get_mult не влияет", m.build({"f40": 1, "f25": 1}) and m.get_flat("start_units", "player") == 65.0
		and m.get_mult("start_units", "player") == 1.0)
	check("add_pct счётного стата (get_count): 5% от 300 = +15, 15% = +45, от 7 вниз до 0 — всё равно +1; без даров 0; вместе с add_flat 40 — +55",
		m.build({"p5": 1}) and m.get_count("start_units", "player", 300) == 15 and m.get_count("start_units", "player", 7) == 1
		and m.build({"p5": 3}) and m.get_count("start_units", "player", 300) == 45 and m.build({}) and m.get_count("start_units", "player", 300) == 0
		and m.build({"p5": 1, "f40": 1}) and m.get_count("start_units", "player", 300) == 55, str(m.get_count("start_units", "player", 300)))
	check("скрытый дар (hidden) пропускается молча при любом уровне: build true, множитель 1.0", m.build({"hid": 1}) and m.build({"hid": 7}) and m.get_mult("damage", "all_units") == 1.0
		and defs["hid"].hidden and not defs["a16"].hidden)
	print("  ниже ожидаются строки ERROR: неизвестный дар и уровни вне диапазона")
	check("неизвестный id, уровень 0, уровень больше числа уровней, дробный уровень: build false, сумм нет", not m.build({"нет такого": 1}) and not m.build({"a16": 0})
		and not m.build({"a16": 2}) and not m.build({"a20": 1.5}) and m.get_mult("damage", "all_units") == 1.0)
	check("после неудачи новый build работает; повторный build не копит прошлое", m.build({"a16": 1}) and m.build({"a16": 1}) and is_equal_approx(m.get_mult("damage", "all_units"), 1.16))

# Загрузчик gifts.json.
func t_loader() -> void:
	print("загрузчик gifts.json — ниже ожидаются строки ERROR от повреждённых файлов")
	var defs: Dictionary = MODS.load_gifts(GIFTS)
	var want := {"tempered_steel": ["attack_rate", "infantry", "add_pct"], "sturdy_shields": ["hp", "all_units", "add_pct"], "marksmen": ["damage", "archer", "add_pct"],
		"spoils": ["bounty", "player", "add_pct"], "mine": ["income", "player", "add_pct"], "fortress_walls": ["gate_hp", "gate", "add_pct"], "reserve": ["start_units", "player", "add_pct"],
		"armory": ["unit_cost", "player", "add_pct"], "smith_thomas": ["weapon_cost", "player", "add_pct"], "repairers": ["repair_cost", "player", "add_pct"],
		"watch": ["signal_window", "player", "add_flat"], "discipline": ["spread", "archer", "add_pct"], "radiance_reserve": ["radiance_pct", "player", "add_pct"],
		"infirmary": ["recover", "player", "add_pct"], "war_cry": ["", "", ""], "spear_wall": ["block", "all_units", "add_flat"]}
	var ok := defs.size() == want.size()
	for id in want:
		ok = ok and defs.has(id) and [defs[id].stat, defs[id].target, defs[id].op] == want[id] and defs[id].levels.size() == 3 and defs[id].name_key != "" and defs[id].desc_key != ""
	check("data/gifts.json грузится: 16 даров (с Кличем Благодати — способность без stat), stat / target / op как в задании, по 3 уровня", ok, str(defs.keys()))
	var hidden := defs.keys().filter(func(id): return defs[id].hidden)
	check("скрыт ровно fortress_walls", hidden == ["fortress_walls"], str(hidden))
	for name in ["bad_stat", "bad_target", "bad_op", "bad_stat_op", "bad_hidden", "no_field", "bad_levels", "dup_id", "not_array", "missing_file"]:
		check("повреждённый %s.json не грузится" % name, MODS.load_gifts(FIX + name + ".json").is_empty())
	for name in ["bad_stat", "bad_target"]:
		var m := make({}, 1, FIX + name + ".json")
		check("сцена боя с %s.json: остановка (типы сброшены, тик выключен)" % name, m.type_id.is_empty() and not m.is_physics_processing() and not m.is_processing())
		m.free()
	var bad := make({"нет такого": 1})
	check("сцена боя с неизвестным активным даром: остановка", bad.type_id.is_empty() and not bad.is_physics_processing())
	bad.free()

# (в) каждый дар на каждом уровне: своя величина меняется на значение уровня, остальной снимок прежний.
func t_each_gift() -> void:
	print("(в) дары по одному")
	var raw: Array = JSON.parse_string(FileAccess.get_file_as_string(GIFTS))
	var b := make({})
	var base := snap(b)
	var units := {"all_units": [b.infantry_type, b.archer_type, b.spearman_type], "infantry": [b.infantry_type], "archer": [b.archer_type], "spearman": [b.spearman_type]}
	var all_types := range(b.type_hp.size())
	var cda := []   # фактический интервал удара без модификаторов (attack_rate: интервал = он / множитель)
	for t in all_types:
		cda.append(b._cd_actual(b.base_type_cooldown[t]))
	var rate_units := {"all_units": [b.infantry_type, b.archer_type, b.spearman_type], "infantry": [b.infantry_type, b.spearman_type], "archer": [b.archer_type]}
	b.free()
	var none := make({})
	check("пустой набор дважды: снимки равны", diff(snap(none), base).is_empty())
	none.free()
	for g in raw:
		if g.get("type", "mods") == "ability":
			continue   # способность (Клич Благодати) данных старта не меняет — она в check_v54_warcry
		for lvl in range(1, g.levels.size() + 1):
			var v: float = g.levels[lvl - 1]
			var k := 1.0 + v / 100.0
			var want := base.duplicate(true)
			match "hidden" if g.get("hidden", false) else g.stat:
				"hidden", "unit_cost", "weapon_cost", "repair_cost", "radiance_pct", "heal", "block":
					pass   # скрытый дар не действует; цены и Сияние читаются на лету (check_v46): снимок как без даров
				"spread":
					want.wave_spread = scaled(base.wave_spread, units[g.target], k)
				"signal_window":
					want.wave_signal_lead = base.wave_signal_lead + v
				"attack_rate":   # задача 6d: скорость боя — интервал удара (infantry: пехота и копейщики) короче в k раз
					var cd: Array = base.type_cooldown.duplicate()
					for t in rate_units[g.target]:
						cd[t] = cda[t] / k
					want.type_cooldown = cd
				"damage":
					want.type_damage = scaled(base.type_damage, units[g.target], k)
					want.type_arrow_dmg = scaled(base.type_arrow_dmg, units[g.target], k)
				"hp":
					want.type_hp = scaled(base.type_hp, units[g.target], k)
				"bounty":
					want.type_bounty_mult = scaled(base.type_bounty_mult, all_types, k)
				"income":
					want.income_pct = v / 100.0
				"gate_hp":
					want.gate_hp = base.gate_hp * k
					want.gate_hp_max = base.gate_hp_max * k
				"start_units":
					var add := [maxi(1, floori(base.squad_n[0] * v / 100.0)), maxi(1, floori(base.squad_n[1] * v / 100.0))]
					want.infantry = base.infantry + add[0]
					want.archers = base.archers + add[1]
					want.count = base.count + add[0] + add[1]
					want.squad_n = [base.squad_n[0] + add[0], base.squad_n[1] + add[1]]
			var m := make({g.id: lvl})
			var got := snap(m)
			var changed := diff(got, base)
			var hp_ok := true
			for i in m.count:
				hp_ok = hp_ok and m.team[i] == 0 and m.hp[i] == m.type_hp[m.unit_type[i]]
			var hid: bool = g.get("hidden", false) or g.stat in ["unit_cost", "weapon_cost", "repair_cost", "radiance_pct", "heal", "block", "recover"]
			check("%s, уровень %d (%s %s %s %s%s): меняется только своё — %s; юниты созданы с HP своего типа" % [g.id, lvl, g.stat, g.target, g.op, str(v),
				", скрыт или на лету — снимок прежний" if hid else "", ", ".join(changed)],
				diff(got, want).is_empty() and changed.is_empty() == hid and hp_ok, "не как ожидалось: " + ", ".join(diff(got, want)) if not diff(got, want).is_empty() else "")
			m.free()

# Действие даров в бою: волна 1 с даром и без (seed один).
func t_battle() -> void:
	print("дары в бою")
	var a := make({})
	var gold0: float = a.gold
	var bonus: float = a.wave_cfg.wave_bonus_gold
	wave(a)
	var earned: float = a.gold - gold0 - bonus
	var b := make({"spoils": 3})
	wave(b)
	check("spoils 3: за волну 1 золота за убитых в 1.3 раза больше (%d против %d), бонус волны прежний" % [roundi(b.gold - gold0 - bonus), roundi(earned)],
		a.wave_state == a.WS_RESPITE and b.wave_state == b.WS_RESPITE and earned > 0.0 and absf((b.gold - gold0 - bonus) - 1.3 * earned) < 0.01)
	b.free()
	var c := make({"mine": 3})
	c._start_wave()
	check("mine 3: в начале волны 1 начисления нет (дохода ещё не было)", c.gold == gold0)
	var t := 0
	while c.wave_state == c.WS_BATTLE and t < 30 * 600:
		c._physics_process(DT)
		t += 1
	var income: float = c.wave_income
	var after: float = c.gold
	check("mine 3: доход волны 1 = убитые + бонус (%d), в конце волны 1 (до магазина) начислено 15%% от него (%.1f)" % [roundi(income), after - gold0 - income],
		c.wave_state == c.WS_RESPITE and absf(income - (earned + bonus)) < 0.01 and absf((after - gold0 - income) - 0.15 * income) < 0.01)
	c._start_wave()
	check("mine 3: в начале волны 2 золото не меняется", c.gold == after and c.gold == c.gold_wave_start)
	c.free()
	var gold_a: float = a.gold
	a._start_wave()
	check("без даров в начале волны золото не меняется", a.gold == gold_a and a.income_pct == 0.0)
	a.free()
	var d := make({"sturdy_shields": 2})
	var hp_inf: float = d.type_hp[d.infantry_type]
	var n0: int = d.count
	d._buy(0)
	var bought_ok: bool = d.count > n0
	for i in range(n0, d.count):
		bought_ok = bought_ok and d.hp[i] == hp_inf
	wave(d)
	var healed := true
	var zombie_types := true
	for i in d.count:   # лечение между волнами возвращает половину потерянного HP (heal_base 0.5): HP от половины до максимума типа
		healed = healed and d.team[i] == 0 and d.hp[i] <= d.type_hp[d.unit_type[i]] and d.hp[i] >= 0.5 * d.type_hp[d.unit_type[i]]
	var plain := make({})
	for t2 in [plain.zombie_type, plain.runner_type, plain.knight_type]:
		zombie_types = zombie_types and d.type_hp[t2] == plain.type_hp[t2] and d.type_damage[t2] == plain.type_damage[t2]
	check("sturdy_shields 2: купленная пехота создаётся с HP x1.12 (%.2f), лечение после волны — не выше него (половина потерянного); HP и урон зомби прежние" % hp_inf,
		bought_ok and healed and zombie_types and is_equal_approx(hp_inf, plain.type_hp[plain.infantry_type] * 1.12))
	var e := make({"tempered_steel": 1})
	var dmg0: float = e.type_damage[e.infantry_type]
	e.gold = 1000.0
	var cdi: float = e._cd_actual(e.base_type_cooldown[e.infantry_type])
	var cdr: float = e._cd_actual(e.base_type_cooldown[e.archer_type])
	check("tempered_steel 1 и покупка оружия (задача 6d: обе — скорость атаки) перемножаются: удары пехоты x1.06 x1.1, стрельба лучников только x1.1, урон прежний",
		e._buy(2) and dmg0 == plain.type_damage[plain.infantry_type] and absf(cdi / e.type_cooldown[e.infantry_type] - 1.06 * e.shop_param[2]) < 1e-4
		and absf(cdr / e.type_cooldown[e.archer_type] - e.shop_param[2]) < 1e-4 and e.type_damage[e.infantry_type] == dmg0 and e.type_arrow_dmg[e.archer_type] == plain.type_arrow_dmg[plain.archer_type])
	var f := make({"fortress_walls": 3})
	f.gold = 1000.0
	check("fortress_walls 3 скрыт: ворота как без даров, ремонт — 1500 + прибавка магазина", f.gate_hp_max == plain.gate_hp_max and f._buy(3)
		and is_equal_approx(f.gate_hp_max, plain.gate_hp_max + f.shop_param[3]) and f.gate_hp == f.gate_hp_max)
	for x in [d, plain, e, f]:
		x.free()

# (г) детерминизм: все дары на уровне 3, два прогона бит в бит на каждом тике.
func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func t_determinism() -> void:
	print("(г) детерминизм")
	var gifts := {"tempered_steel": 3, "sturdy_shields": 3, "marksmen": 3, "spoils": 3, "mine": 3, "fortress_walls": 3, "reserve": 3,
		"armory": 3, "smith_thomas": 3, "repairers": 3, "watch": 3, "discipline": 3, "radiance_reserve": 3, "infirmary": 3}
	var a := make(gifts, 6)
	var b := make(gifts, 6)
	var first := -1
	var ticks := 0
	for w in 3:
		for x in [a, b]:
			x._buy(w % 2)
			x._buy(2)
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 900:
			a._physics_process(DT)
			b._physics_process(DT)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
	check("все 14 даров уровня 3 (fortress_walls скрыт), волны 1-3 с покупками (seed 6, %d тиков, юнитов на старте %d): два прогона бит в бит на каждом тике" % [ticks, 520],
		first < 0 and a.wave_number == 3 and b.wave_number == 3 and ticks > 300, "" if first < 0 else "первое расхождение: тик %d" % first)
	a.free()
	b.free()

# Game.gift_levels -> Game.active_gifts -> сцена боя; в сохранении — купленные уровни (gift_levels), набора забега (active_gifts) нет.
func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == MAIN:
		n.process_mode = Node.PROCESS_MODE_DISABLED

func t_game() -> void:
	print("Game.active_gifts")
	var real := "%d" % FileAccess.get_modified_time("user://save.json") if FileAccess.file_exists("user://save.json") else "нет"
	DirAccess.make_dir_recursive_absolute(DIR)
	node_added.connect(_on_node_added)
	var g: Node = load(GAME).new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	check("Game.active_gifts по умолчанию пуст", g.active_gifts is Dictionary and g.active_gifts.is_empty())
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	check("забег без даров: ворота 1500, пехоты 300, income_pct 0", m != null and m.gate_hp_max == 1500.0 and count_type(m, m.infantry_type) == 300 and m.income_pct == 0.0)
	g.gift_levels["fortress_walls"] = 2
	g.gift_levels["reserve"] = 1
	g.start_run(1)
	await step(3)
	m = current_scene as Node2D
	check("забег с купленными fortress_walls 2 (скрыт) и reserve 1 (Game.active_gifts собран из gift_levels): ворота 1500, пехоты 330, лучников 110, в наборе только reserve",
		m != null and m.gate_hp_max == 1500.0 and count_type(m, m.infantry_type) == 330 and count_type(m, m.archer_type) == 110 and g.active_gifts == {"reserve": 1},
		"" if m == null else "ворота %.0f, пехоты %d, лучников %d" % [m.gate_hp_max, count_type(m, m.infantry_type), count_type(m, m.archer_type)])
	g.end_run("loss", 2, 5)
	var text := FileAccess.get_file_as_string(g.save_path)
	var saved = JSON.parse_string(text)
	check("сохранение записано: в нём gift_levels с купленными уровнями (и скрытого дара), active_gifts нет", saved is Dictionary and saved.get("gift_levels") is Dictionary
		and saved.gift_levels.get("fortress_walls") == 2 and saved.gift_levels.get("reserve") == 1 and not "active_gifts" in text)
	m.queue_free()
	g.queue_free()
	await step(2)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)
	var now := "%d" % FileAccess.get_modified_time("user://save.json") if FileAccess.file_exists("user://save.json") else "нет"
	check("настоящий user://save.json не тронут, временная папка убрана", now == real and not DirAccess.dir_exists_absolute(DIR))
