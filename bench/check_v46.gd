extends SceneTree
# Тесты v46 (задача 6a: статы экономики на лету, Mods.value). Сцена боя вне дерева, физика вручную; узел Game — с временным
# сохранением в user://bench_v46 (настоящий user://save.json не трогается).
# (а) Mods.value для каждого нового стата с цифрами по data/gifts.json; (б) ограничения против накопления и список источников;
# (в) подключение в бою: цены магазина, окно сигнала, разброс; Сияние в Game.run_reward;
# (г) без модификаторов — бит в бит с эталоном bench/ref/main_ref.gd; (д) сохранение со старым набором даров.
const MODS := preload("res://scripts/mods.gd")
const GAME := "res://scripts/game.gd"
const MAIN := "res://scripts/main.gd"
const REF := "res://bench/ref/main_ref.gd"
const GIFTS := "res://data/gifts.json"
const FIX := "res://bench/fixtures_gifts/"
const DIR := "user://bench_v46"
const SAVE := DIR + "/save.json"
const DT := 1.0 / 30.0
# сохранение до задачи 6a: дары 5b (с «Резервом» 1 и скрытыми «Стенами» 2), неизвестный дар; новых шести даров в нём нет
const OLD_SAVE := "{\"version\": 1, \"unlocked_siege\": 1, \"last_siege\": 1, \"records\": {\"1\": {\"best_wave\": 7, \"wins\": 0, \"runs\": 3}}, \"diary_seen\": [\"intro\"], \"completed\": false, \"runs_total\": 3, \"play_time\": 50.0, \"radiance\": 40, \"gift_levels\": {\"tempered_steel\": 1, \"sturdy_shields\": 0, \"marksmen\": 0, \"spoils\": 0, \"mine\": 0, \"fortress_walls\": 2, \"reserve\": 1, \"старый дар\": 1}}"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func make(path: String, gifts: Dictionary, rng_seed := 1) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	if path == MAIN:
		m.active_gifts = gifts
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

func mods_of(active: Dictionary, path := GIFTS) -> RefCounted:
	var m = MODS.new(MODS.load_gifts(path))
	m.build(active)
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # сцена боя вне дерева идёт без синглтона; для Game — свой узел
		await step(1)
	t_value()
	t_limits()
	t_battle()
	t_signal()
	t_reference()
	await t_game()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# (а) Mods.value по каждому новому стату.
func t_value() -> void:
	print("(а) Mods.value: новые статы по data/gifts.json")
	var none = mods_of({})
	check("без даров value возвращает base как есть: 100, 156.00000000000003, 0.08, 1.5, 22", none.value("unit_cost", 100.0) == 100.0 and none.value("repair_cost", 120.0 * 1.3) == 120.0 * 1.3
		and none.value("spread", 0.08) == 0.08 and none.value("signal_window", 1.5) == 1.5 and none.value("radiance_pct", 22.0) == 22.0)
	var cases := [
		["armory", 1, "unit_cost", 100.0, 95.0], ["armory", 2, "unit_cost", 120.0, 108.0], ["armory", 3, "unit_cost", 100.0, 85.0], ["armory", 3, "unit_cost", 120.0, 102.0],
		["smith_thomas", 1, "weapon_cost", 150.0, 143.0], ["smith_thomas", 2, "weapon_cost", 225.0, 203.0], ["smith_thomas", 3, "weapon_cost", 150.0, 128.0],
		["repairers", 1, "repair_cost", 120.0, 102.0], ["repairers", 2, "repair_cost", 156.0, 109.0], ["repairers", 3, "repair_cost", 120.0, 66.0],
		["watch", 1, "signal_window", 1.5, 1.75], ["watch", 2, "signal_window", 1.5, 2.0], ["watch", 3, "signal_window", 2.5, 3.25],
		["discipline", 1, "spread", 0.08, 0.072], ["discipline", 2, "spread", 0.08, 0.064], ["discipline", 3, "spread", 0.08, 0.056],
		["radiance_reserve", 1, "radiance_pct", 100.0, 105.0], ["radiance_reserve", 2, "radiance_pct", 22.0, 24.2], ["radiance_reserve", 3, "radiance_pct", 135.0, 155.25]]
	for c in cases:
		var got: float = mods_of({c[0]: c[1]}).value(c[2], c[3])
		check("%s %d: %s от %s = %s" % [c[0], c[1], c[2], str(c[3]), str(c[4])], is_equal_approx(got, c[4]), str(got))
	check("цены — целые: 142.5 -> 143, 202.5 -> 203, 127.5 -> 128 (половина — вверх)", mods_of({"smith_thomas": 1}).value("weapon_cost", 150.0) == 143.0
		and mods_of({"smith_thomas": 3}).value("weapon_cost", 150.0) == 128.0)
	var other = mods_of({"armory": 3})
	check("armory не трогает другие статы: weapon_cost, repair_cost, spread, signal_window, radiance_pct — base", other.value("weapon_cost", 150.0) == 150.0
		and other.value("repair_cost", 120.0) == 120.0 and other.value("spread", 0.08) == 0.08 and other.value("signal_window", 1.5) == 1.5 and other.value("radiance_pct", 50.0) == 50.0)
	print("  ниже ожидается строка ERROR: недопустимый op у signal_window")
	check("signal_window с add_pct не грузится (STAT_OPS)", MODS.load_gifts(FIX + "bad_signal_op.json").is_empty())

# (б) ограничения и источники.
func t_limits() -> void:
	print("(б) ограничения против накопления, список источников")
	var defs: Dictionary = MODS.load_gifts(FIX + "stack.json")
	var m = MODS.new(defs)
	check("-50% и -45% одного стата складываются до -95%: цена 100 -> не ниже 20% базы = 20", m.build({"u50": 1, "u45": 1}) and m.value("unit_cost", 100.0) == 20.0, str(m.value("unit_cost", 100.0)))
	check("-90%: цена 150 -> 30 (20%), 3 -> 1 (0.6 округляется до 1), 1 -> 1 (минимум 1)", m.build({"w90": 1}) and m.value("weapon_cost", 150.0) == 30.0
		and m.value("weapon_cost", 3.0) == 1.0 and m.value("weapon_cost", 1.0) == 1.0)
	check("разброс -150%: 0.08 -> 0 (не ниже 0)", m.build({"sp150": 1}) and m.value("spread", 0.08) == 0.0)
	check("окно сигнала -10 с: 1.5 -> 0 (не ниже 0)", m.build({"sw10": 1}) and m.value("signal_window", 1.5) == 0.0)
	check("модификатор 0%: цена округляется (156.00000000000003 -> 156)", m.build({"zero": 1}) and m.value("repair_cost", 120.0 * 1.3) == 156.0)
	var two := [MODS.gifts_source(defs, {"u50": 1}), {"name": "cards", "defs": defs, "levels": {"u45": 1}}]
	check("два источника (дары и «карточки» той же формы): суммы общие, -95% -> 20; sources хранит оба", m.build_sources(two) and m.value("unit_cost", 100.0) == 20.0 and m.sources.size() == 2)
	check("один источник после двух: прежнее не копится, -50% -> 50", m.build({"u50": 1}) and m.value("unit_cost", 100.0) == 50.0 and m.sources.size() == 1)
	print("  ниже ожидается строка ERROR: неизвестный дар во втором источнике")
	check("ошибка во втором источнике: build_sources false, сумм нет", not m.build_sources([MODS.gifts_source(defs, {"u50": 1}), {"name": "cards", "defs": defs, "levels": {"нет": 1}}])
		and m.value("unit_cost", 100.0) == 100.0)

# (в) магазин и разброс в бою.
func t_battle() -> void:
	print("(в) магазин и разброс в бою")
	var a := make(MAIN, {"armory": 3, "smith_thomas": 3, "repairers": 3, "discipline": 3})
	var plain := make(MAIN, {})
	check("цены передышки: пехота 85, лучники 85, оружие 128 (127.5), ремонт 66; без даров 100 / 100 / 150 / 120", a._price(0) == 85.0 and a._price(1) == 85.0 and a._price(2) == 128.0
		and a._price(3) == 66.0 and plain._price(0) == 100.0 and plain._price(2) == 150.0 and plain._price(3) == 120.0, "%s %s %s %s" % [a._price(0), a._price(1), a._price(2), a._price(3)])
	a.gold = 1000.0
	var ok: bool = a._buy(0) and a.gold == 915.0 and a._price(0) == 102.0
	ok = ok and a._buy(2) and a.gold == 787.0 and a._price(2) == 191.0   # 225 * 0.85 = 191.25
	ok = ok and a._buy(3) and a.gold == 721.0 and a._price(3) == 86.0    # 156 * 0.55 = 85.8
	check("покупки списывают цену со скидкой; следующая цена растёт от базы: пехота 102, оружие 191, ремонт 86", ok, "золото %.2f" % a.gold)
	check("разброс лучников на волну: 0.08 * 0.7 = 0.056, у других типов прежний; без даров wave_spread = type_spread",
		is_equal_approx(a.wave_spread[a.archer_type], 0.056) and a.wave_spread[a.infantry_type] == a.type_spread[a.infantry_type] and a.type_spread[a.archer_type] == plain.type_spread[a.archer_type]
		and plain.wave_spread == plain.type_spread, str(a.wave_spread[a.archer_type]))
	a._start_wave()
	check("после старта волны значения те же (читаются заново из Mods)", is_equal_approx(a.wave_spread[a.archer_type], 0.056) and a.wave_signal_lead == plain.wave_signal_lead)
	a.free()
	plain.free()

# (в) окно сигнала: сигналы раньше на 0.75 с, бой тот же.
func signal_times(m: Node2D) -> Array:
	var out := []
	var n := 0
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 120:
		m._physics_process(DT)
		t += 1
		while n < m.burst_signal_n:
			out.append(m.wave_t)
			n += 1
	return out

func t_signal() -> void:
	print("(в) окно сигнала всплеска")
	var a := make(MAIN, {})
	var b := make(MAIN, {"watch": 3})
	check("wave_signal_lead: без дара 1.5 (signal_lead слоя 1), Дозор 3 — 2.25", a.wave_signal_lead == 1.5 and b.wave_signal_lead == 2.25, "%s / %s" % [a.wave_signal_lead, b.wave_signal_lead])
	a._start_wave()
	b._start_wave()
	var ta := signal_times(a)
	var tb := signal_times(b)
	var ok: bool = ta.size() == tb.size() and ta.size() >= 2
	var shown := PackedStringArray()
	for k in mini(ta.size(), tb.size()):
		var want := maxf(ta[k] - 0.75, DT)   # раньше начала волны сигнал не даётся: первый тик
		ok = ok and absf(tb[k] - want) <= DT + 1e-6
		shown.append("%.2f/%.2f" % [ta[k], tb[k]])
	check("за 120 с волны 1 все сигналы Дозора 3 на 0.75 с раньше (с точностью до тика)", ok, ", ".join(shown))
	var c := make(MAIN, {})
	var d := make(MAIN, {"watch": 3})
	c._start_wave()
	d._start_wave()
	var first := -1
	for t in 30 * 60:
		c._physics_process(DT)
		d._physics_process(DT)
		if first < 0 and not same(c, d):
			first = t
	check("окно сигнала не меняет бой: 60 с волны 1 бит в бит с боем без дара", first < 0, "расхождение на тике %d" % first)
	for x in [a, b, c, d]:
		x.free()

# (г) без модификаторов — как эталон.
func t_reference() -> void:
	print("(г) без модификаторов — бит в бит с эталоном")
	print("  эталон: " + FileAccess.get_file_as_string("res://bench/ref/REF.txt").strip_edges())
	var a := make(REF, {}, 4)
	var b := make(MAIN, {}, 4)
	var first := -1
	var ticks := 0
	var prices_ok := true
	var buys := [[0, 2], [1, 3], [2, 0]]
	for w in 3:
		for k in 4:
			prices_ok = prices_ok and a._price(k) == b._price(k)
		for x in [a, b]:
			x.gold += 500.0   # хватает на все покупки списка: ремонт и оружие тоже проходят
			for k in buys[w]:
				x._buy(k)
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 900:
			a._physics_process(DT)
			b._physics_process(DT)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
	check("цены всех товаров до каждой покупки равны эталону (бит в бит)", prices_ok)
	check("3 волны с покупками всех четырёх товаров (seed 4, %d тиков, волна %d): бит в бит с эталоном на каждом тике" % [ticks, b.wave_number],
		first < 0 and b.wave_number == 3 and ticks > 300, "" if first < 0 else "первое расхождение: тик %d" % first)
	a.free()
	b.free()

# (в) Сияние и (д) старое сохранение.
func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == MAIN:
		n.process_mode = Node.PROCESS_MODE_DISABLED

func t_game() -> void:
	print("(в) Сияние, (д) старое сохранение")
	var real := "%d" % FileAccess.get_modified_time("user://save.json") if FileAccess.file_exists("user://save.json") else "нет"
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	node_added.connect(_on_node_added)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(OLD_SAVE)
	f.close()
	var g: Node = load(GAME).new()
	g.name = "Game"
	g.save_path = SAVE
	root.add_child(g)
	check("старое сохранение (дары 5b, неизвестный дар): грузится без предупреждения, новые дары на уровне 0, купленные уровни прежние",
		g.save_warning == "" and g.radiance == 40 and g.gift_levels.size() == 14 and g.gift_levels["armory"] == 0 and g.gift_levels["radiance_reserve"] == 0
		and g.gift_levels["reserve"] == 1 and g.gift_levels["fortress_walls"] == 2 and not g.gift_levels.has("старый дар") and DirAccess.get_files_at(DIR).size() == 1, str(g.gift_levels))
	check("набор забега из старого сохранения: tempered_steel 1 и reserve 1 (скрытые не входят)", g.owned_gifts() == {"tempered_steel": 1, "reserve": 1})
	check("Сияние без даров: поражение на волне 5 — 22, победа на волне 10 — 135", g.run_reward("loss", 5) == 22 and g.run_reward("win", 10) == 135)
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	check("забег со старым набором стартует: пехоты 330, лучников 110 (Резерв 1: +10%), цены без скидок", m != null and count_type(m, m.infantry_type) == 330
		and count_type(m, m.archer_type) == 110 and m._price(0) == 100.0, "" if m == null else "пехоты %d, лучников %d" % [count_type(m, m.infantry_type), count_type(m, m.archer_type)])
	g.active_gifts = {"radiance_reserve": 3}
	check("Резерв Сияния 3 в Game.run_reward: 22 * 1.15 = 25.3 -> 25, 135 * 1.15 = 155.25 -> 155", g.run_reward("loss", 5) == 25 and g.run_reward("win", 10) == 155,
		"%d / %d" % [g.run_reward("loss", 5), g.run_reward("win", 10)])
	g.active_gifts = {"radiance_reserve": 1}
	var before: int = g.radiance
	g.end_run("loss", 5, 10)
	check("end_run начисляет Сияние с даром (Резерв Сияния 1: 22 * 1.05 = 23.1 -> 23) и сохраняет", g.last_run.radiance == 23 and g.radiance == before + 23
		and JSON.parse_string(FileAccess.get_file_as_string(SAVE)).radiance == before + 23)
	if m != null:
		m.queue_free()
	g.queue_free()
	await step(2)
	for x in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + x)
	DirAccess.remove_absolute(DIR)
	var now := "%d" % FileAccess.get_modified_time("user://save.json") if FileAccess.file_exists("user://save.json") else "нет"
	check("настоящий user://save.json не тронут, временная папка убрана", now == real and not DirAccess.dir_exists_absolute(DIR))
