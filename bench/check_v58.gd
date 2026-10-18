extends SceneTree
# Тесты задачи 6d, этап B: стат attack_rate — скорость боя. infantry — удары пехоты и копейщиков, archer — стрельба лучников
# (одиночная и цикл залпа), all_units — обе; проценты складываются с attack_speed (пехота) и reload (лучники); готовые интервалы
# в _apply_wave_data, остаток переносится (type_cd_floor). Условные карточки дают множитель отряда squad_rate_mult, он перемножается
# с Кличем Благодати в squad_atk_speed_mult; без карточек и клича ровно 1.0. «Оружие» со stat attack_rate — x1.1 к скорости за покупку.
# Тестовые карточки — пул data/cards.json + карточки ниже во временном файле user://.
const MAIN := "res://scripts/main.gd"
const REF := "res://bench/ref/main_ref.gd"
const CARDS := preload("res://scripts/cards.gd")
const DT := 1.0 / 30.0
const FIX := "user://cards_v58.json"
const EXTRA := [
	{"id": "t_rate_inf", "mods": [{"stat": "attack_rate", "target": "infantry", "op": "add_pct", "value": 12}]},
	{"id": "t_rate_arch", "mods": [{"stat": "attack_rate", "target": "archer", "op": "add_pct", "value": 12}]},
	{"id": "t_rate_all", "mods": [{"stat": "attack_rate", "target": "all_units", "op": "add_pct", "value": 12}]},
	{"id": "t_as_inf", "mods": [{"stat": "attack_speed", "target": "infantry", "op": "add_pct", "value": 12}]},
	{"id": "t_reload", "mods": [{"stat": "reload", "target": "archer", "op": "add_pct", "value": 12}]},
	{"id": "t_hold_rate", "kind": "C", "when": {"cond": "hold"}, "mods": [{"stat": "attack_rate", "target": "all_units", "op": "add_pct", "value": 20}]},
	{"id": "t_hold_rate_arch", "kind": "C", "when": {"cond": "hold"}, "mods": [{"stat": "attack_rate", "target": "archer", "op": "add_pct", "value": 10}]},
]
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func write_fixture() -> void:
	var pool: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json"))
	var num := 300
	for e in EXTRA:
		var c: Dictionary = {"num": num, "name_key": "CARD_METEOR_BLADES_NAME", "desc_key": "CARD_METEOR_BLADES_DESC", "builds": ["common"], "kind": "M"}
		c.merge(e, true)
		pool.append(c)
		num += 1
	var f := FileAccess.open(FIX, FileAccess.WRITE)
	f.store_string(JSON.stringify(pool))
	f.close()

func make(cards: Array = [], gifts := {}, path := MAIN, rng_seed := 3) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	if path == MAIN:
		m.cards_path = FIX
		m.active_gifts = gifts
		m.active_cards = cards.map(func(id): return {"id": id})
	m._setup_data()
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await process_frame
	write_fixture()
	t_data()
	t_numbers()
	t_battle()
	t_cond()
	t_weapons()
	t_reference()
	DirAccess.remove_absolute(FIX)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные и валидатор")
	var mods := preload("res://scripts/mods.gd")
	check("attack_rate: цели all_units, infantry, archer; только add_pct", mods.PAIRS.attack_rate == ["all_units", "infantry", "archer"] and mods.STAT_OPS.attack_rate == ["add_pct"])
	var defs := CARDS.load_cards(FIX)
	check("пул с тестовыми карточками (и условной attack_rate) проходит валидатор", defs.has("t_hold_rate") and defs.has("t_rate_all"))
	check("attack_rate / spearman и attack_rate add_flat — ошибка", CARDS.check_mod({"stat": "attack_rate", "target": "spearman", "op": "add_pct", "value": 1}) != ""
		and CARDS.check_mod({"stat": "attack_rate", "target": "infantry", "op": "add_flat", "value": 1}) != "")

func t_numbers() -> void:
	print("готовые интервалы")
	var b := make()
	var ci: float = b._cd_actual(b.base_type_cooldown[b.infantry_type])
	var cs: float = b._cd_actual(b.base_type_cooldown[b.spearman_type])
	var ca: float = b._cd_actual(b.base_type_cooldown[b.archer_type])
	var va: float = b.type_volley_period[b.archer_type]
	check("без модификаторов: интервалы базовые, без переноса остатка", b.type_cooldown[b.infantry_type] == b.base_type_cooldown[b.infantry_type]
		and b.type_cd_floor[b.infantry_type] == 0.0 and b.type_cd_floor[b.spearman_type] == 0.0 and b.type_cd_floor[b.archer_type] == 0.0)
	b.free()
	var cases := [[["t_rate_inf"], 1.12, 1.12, 1.0], [["t_rate_arch"], 1.0, 1.0, 1.12], [["t_rate_all"], 1.12, 1.12, 1.12],
		[["t_rate_inf", "t_as_inf"], 1.24, 1.12, 1.0], [["t_rate_all", "t_reload"], 1.12, 1.12, 1.24], [["t_rate_all", "t_rate_inf", "t_as_inf"], 1.36, 1.24, 1.12]]
	for c in cases:
		var m := make(c[0])
		var ki: float = ci / m.type_cooldown[m.infantry_type] if m.type_cd_floor[m.infantry_type] < 0.0 else 1.0
		var ks: float = cs / m.type_cooldown[m.spearman_type] if m.type_cd_floor[m.spearman_type] < 0.0 else 1.0
		var ka: float = ca / m.type_cooldown[m.archer_type] if m.type_cd_floor[m.archer_type] < 0.0 else 1.0
		var kv: float = va / m.type_volley_period[m.archer_type]
		check("%s: пехота x%.2f, копейщики x%.2f, лучники x%.2f (залп x%.2f)" % [",".join(c[0]), ki, ks, ka, kv], absf(ki - c[1]) < 1e-4 and absf(ks - c[2]) < 1e-4
			and absf(ka - c[3]) < 1e-4 and absf(kv - c[3]) < 1e-4)
		m.free()

# Удары отряда 0 (пехота или копейщики) и выстрелы лучников за ticks тиков после 300 тиков подхода; зомби бессмертны и не бьют.
# Стрельба лучников идёт залпами по ~100 стрел (около 13 за 1000 тиков, ±1 залп — ±8%), поэтому выстрелы сравниваются за 4000 тиков.
func strikes(cards: Array, spear := false, rng_seed := 5, ticks := 1000) -> Vector2i:
	var m := make(cards, {}, MAIN, rng_seed)
	for t in [m.zombie_type, m.runner_type, m.knight_type]:
		m.base_type_hp[t] = 1e7
		m.base_type_damage[t] = 0.0
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	if spear:
		m.squad_type[0] = m.spearman_type
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.unit_type[i] = m.spearman_type
				m.hp[i] = m.type_hp[m.spearman_type]
	m.squad_order[0] = m.ORDER_HOLD
	m._start_wave()
	for t in 300:
		m._physics_process(DT)
	var hits := 0
	var a0: int = m.arrows_fired
	var prev: PackedFloat32Array = m.cooldown.duplicate()
	for t in ticks:
		m._physics_process(DT)
		for i in m.count:
			if m.team[i] == 0 and m.unit_squad[i] == 0 and m.cooldown[i] > prev[i] + 1e-6:
				hits += 1
		prev = m.cooldown.duplicate()
	var r := Vector2i(hits, m.arrows_fired - a0)
	m.free()
	return r

func t_battle() -> void:
	print("в бою")
	var b := strikes([], false, 5, 4000)
	var i := strikes(["t_rate_inf"], false, 5, 4000)
	var a := strikes(["t_rate_arch"], false, 5, 4000)
	var l := strikes(["t_rate_all"], false, 5, 4000)
	var s := strikes(["t_rate_inf", "t_as_inf"], false, 5, 4000)
	var r := strikes(["t_rate_all", "t_reload"], false, 5, 4000)
	var b1 := strikes([])
	var i1 := strikes(["t_rate_inf"])
	print("    база за 4000 тиков: ударов %d, выстрелов %d" % [b.x, b.y])
	check("1000 тиков: ударов пехоты %d -> %d, x%.3f (около 1.12)" % [b1.x, i1.x, float(i1.x) / b1.x], absf(float(i1.x) / b1.x - 1.12) < 0.04)
	var ri := float(i.x) / b.x
	var ra := float(a.y) / b.y
	check("+12%% пехоте: ударов x%.3f (около 1.12), выстрелы x%.3f (как без него)" % [ri, float(i.y) / b.y], absf(ri - 1.12) < 0.04 and absf(float(i.y) / b.y - 1.0) < 0.03)
	check("+12%% лучникам: выстрелов x%.3f (около 1.12), удары x%.3f" % [ra, float(a.x) / b.x], absf(ra - 1.12) < 0.04 and absf(float(a.x) / b.x - 1.0) < 0.03)
	check("+12%% всем: удары x%.3f, выстрелы x%.3f" % [float(l.x) / b.x, float(l.y) / b.y], absf(float(l.x) / b.x - 1.12) < 0.04 and absf(float(l.y) / b.y - 1.12) < 0.04)
	check("+12%% attack_rate и +12%% attack_speed пехоте складываются: ударов x%.3f (около 1.24)" % (float(s.x) / b.x), absf(float(s.x) / b.x - 1.24) < 0.05)
	check("+12%% всем и +12%% reload: выстрелов x%.3f (около 1.24)" % (float(r.y) / b.y), absf(float(r.y) / b.y - 1.24) < 0.05)
	var sb := strikes([], true)
	var si := strikes(["t_rate_inf"], true)
	check("копейщики: цель infantry ускоряет их удары x%.3f" % (float(si.x) / sb.x), absf(float(si.x) / sb.x - 1.12) < 0.04)
	var i2 := strikes(["t_rate_inf"], false, 5, 4000)
	check("воспроизводимость: тот же прогон — те же числа (%s)" % str(i2), i2 == i)

func t_cond() -> void:
	print("условия и Клич")
	var n := make([], {"war_cry": 1})
	n._start_wave()
	n._update_card_conditions()
	check("без карточек и клича: множители отрядов ровно 1.0", n.squad_atk_speed_mult.count(1.0) == n.SQUAD_MAX and n.squad_rate_mult.count(1.0) == n.SQUAD_MAX)
	n.free()
	var m := make(["t_hold_rate", "t_hold_rate_arch"], {"war_cry": 1})
	m._start_wave()
	m.squad_order[0] = m.ORDER_HOLD
	m.squad_order[1] = m.ORDER_HOLD
	m._update_card_conditions()
	check("«держать», +20% всем: пехота x1.20, лучники +20 +10 = x1.30", is_equal_approx(m.squad_atk_speed_mult[0], 1.2) and is_equal_approx(m.squad_atk_speed_mult[1], 1.3))
	check("индикатор карточки горит с бонусом 20", m.card_state.t_hold_rate.on and m.card_state.t_hold_rate.pct == 20.0)
	m.request_war_cry()
	m._physics_process(DT)
	check("Клич x1.3 перемножается: пехота %.3f (1.56), лучники %.3f (1.69)" % [m.squad_atk_speed_mult[0], m.squad_atk_speed_mult[1]], absf(m.squad_atk_speed_mult[0] - 1.56) < 1e-5
		and absf(m.squad_atk_speed_mult[1] - 1.69) < 1e-5)
	m.squad_order[0] = m.ORDER_ATTACK
	m._update_card_conditions()
	check("пехота на «атаке» при Кличе: x1.30", absf(m.squad_atk_speed_mult[0] - 1.3) < 1e-5)
	m._end_war_cry()
	check("Клич кончился: пехота 1.0, лучники 1.3", m.squad_atk_speed_mult[0] == 1.0 and is_equal_approx(m.squad_atk_speed_mult[1], 1.3))
	m.free()

func t_weapons() -> void:
	print("«Оружие» на скорости боя")
	var m := make()
	m.weapon_stat = "attack_rate"
	var d0: float = m.type_damage[m.infantry_type]
	var c0: float = m._cd_actual(m.base_type_cooldown[m.infantry_type])
	var a0: float = m._cd_actual(m.base_type_cooldown[m.archer_type])
	m.gold = 5000.0
	m.wave_state = m.WS_RESPITE
	var k: int = m.SHOP_ITEMS.find("weapons")
	m._buy(k)
	m._buy(k)
	check("две покупки: урон прежний, удары пехоты и копейщиков, стрельба x1.21 (умножение)", m.type_damage[m.infantry_type] == d0
		and absf(c0 / m.type_cooldown[m.infantry_type] - 1.21) < 1e-4 and absf(a0 / m.type_cooldown[m.archer_type] - 1.21) < 1e-4
		and absf(m._cd_actual(m.base_type_cooldown[m.spearman_type]) / m.type_cooldown[m.spearman_type] - 1.21) < 1e-4)
	m._start_wave()
	check("в начале волны пересчёт от базы даёт то же", absf(c0 / m.type_cooldown[m.infantry_type] - 1.21) < 1e-4 and m.type_damage[m.infantry_type] == d0)
	m.free()

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func t_reference() -> void:
	print("эталон")
	var a: Node2D = load(REF).new()
	a.spawn_seed = 7
	a.debug_layer = 1
	a.record_path = "user://record_bench.json"
	a._setup_data()
	var b := make([], {}, MAIN, 7)
	var first := -1
	var t := 0
	for w in 3:
		for x in [a, b]:
			x._buy(w)
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and t < 30 * 900:
			a._physics_process(DT)
			b._physics_process(DT)
			t += 1
			if first < 0 and not same(a, b):
				first = t
	check("без attack_rate (3 волны с покупками): бит в бит с эталоном", first < 0 and t > 300 and same(a, b), "расхождение на тике %d" % first)
	a.free()
	b.free()
