extends SceneTree
# Тесты v47 (задача 6, этап A: недостающие статы и момент дохода). Сцена боя вне дерева, физика вручную, дары — bench/fixtures_gifts/stats_v47.json.
# Каждый новый стат: income_flat, heal, speed, reload, attack_speed (+12% — примерно на 12% больше ударов за 1000 тиков), range, enemy_hp,
# bounty / knight, unit_cost / archer, grant_units_free; доход в конце волны; пересчёт данных волны от базы (не накопительно); доля HP при смене максимума.
const MAIN := "res://scripts/main.gd"
const FIX := "res://bench/fixtures_gifts/stats_v47.json"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(gifts: Dictionary, rng_seed := 1) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.gifts_path = FIX
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

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	t_income()
	t_unit_stats()
	t_attack_speed()
	t_rebuild()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Доход и лечение — в конце волны.
func t_income() -> void:
	print("доход в конце волны, income_flat, heal")
	var a := make({})
	var b := make({"flat60": 1})
	var c := make({"inc30": 1, "flat60": 1})
	for x in [a, b, c]:
		wave(x)
	var bonus: float = a.wave_cfg.wave_bonus_gold
	check("income_flat +60: в передышке после волны 1 золота на 60 больше, чем без дара (бой тот же)", a.wave_state == a.WS_RESPITE and b.gold == a.gold + 60.0, "%.1f / %.1f" % [a.gold, b.gold])
	check("income +30%% и income_flat +60: в конце волны начислено 0.3 * доход волны (%.1f) + 60" % c.wave_income, is_equal_approx(c.gold, a.gold + 0.3 * c.wave_income + 60.0)
		and is_equal_approx(c.wave_income, a.wave_income) and c.wave_income > bonus, "%.2f" % c.gold)
	var g0: float = c.gold
	c._start_wave()
	check("в начале волны 2 золото не меняется (доход уже начислен)", c.gold == g0)
	var h := make({"heal50": 1})
	h._start_wave()
	var t := 0
	while h.wave_state == h.WS_BATTLE and t < 30 * 600:
		h._physics_process(DT)
		t += 1
	var full := true
	for i in h.count:
		if h.team[i] == 0:
			full = full and h.hp[i] == h.type_hp[h.unit_type[i]]
	check("heal +50%%: база лечения полная (HEAL_BASE %.1f), после волны HP всех своих — максимум (прибавка лечения ничего не меняет)" % h.HEAL_BASE,
		h.wave_state == h.WS_RESPITE and full and h.mods.value("heal", h.HEAL_BASE) == 1.5)
	for x in [a, b, c, h]:
		x.free()

# Статы данных волны.
func t_unit_stats() -> void:
	print("данные волны: speed, reload, range, enemy_hp, bounty / knight, unit_cost / archer, grant_units_free")
	var p := make({})
	var s := make({"spd_inf15": 1})
	check("speed infantry +15%: скорость пехоты x1.15, лучников прежняя, скорость строя отряда 0 x1.15", is_equal_approx(s.type_speed[s.infantry_type], p.type_speed[p.infantry_type] * 1.15)
		and s.type_speed[s.archer_type] == p.type_speed[p.archer_type] and is_equal_approx(s.squad_speed[0], p.squad_speed[0] * 1.15) and s.squad_speed[1] == p.squad_speed[1])
	var s2 := make({"spd_all_m10": 1})
	check("speed all -10%: пехота и лучники x0.9, зомби прежние", is_equal_approx(s2.type_speed[s2.infantry_type], p.type_speed[p.infantry_type] * 0.9)
		and is_equal_approx(s2.type_speed[s2.archer_type], p.type_speed[p.archer_type] * 0.9) and s2.type_speed[s2.zombie_type] == p.type_speed[p.zombie_type])
	var r := make({"reload20": 1})
	check("reload archer +20%%: период залпа 2.5 / 1.2 = %.4f, перезарядка одиночного огня — фактическая / 1.2, натяжение прежнее, остаток переносится" % r.type_volley_period[r.archer_type],
		is_equal_approx(r.type_volley_period[r.archer_type], 2.5 / 1.2) and is_equal_approx(r.type_cooldown[r.archer_type], r._cd_actual(p.type_cooldown[p.archer_type]) / 1.2)
		and r.type_draw_time[r.archer_type] == p.type_draw_time[p.archer_type] and r.type_cd_floor[r.archer_type] < 0.0 and p.type_cd_floor[p.archer_type] == 0.0)
	var g := make({"range15": 1})
	check("range archer +15%%: дальность %.1f -> %.2f, ближняя дальность прежняя" % [p.type_range_far[p.archer_type], g.type_range_far[g.archer_type]],
		is_equal_approx(g.type_range_far[g.archer_type], p.type_range_far[p.archer_type] * 1.15) and g.type_range_sq[g.archer_type] == p.type_range_sq[p.archer_type])
	var e := make({"ehp10": 1})
	var e_ok := true
	for t in [e.zombie_type, e.runner_type, e.knight_type]:
		e_ok = e_ok and is_equal_approx(e.type_hp[t], p.type_hp[t] * 1.1)
	e._start_wave()
	var tw := 0
	while e.zombie_alive == 0 and tw < 30 * 30:   # до появления первых зомби: они ещё не ранены
		e._physics_process(DT)
		tw += 1
	var z_ok := false
	for i in e.count:   # хоть один ещё не раненый зомби — с HP базы x1.1
		if e.team[i] == 1 and is_equal_approx(e.hp[i], p.type_hp[e.unit_type[i]] * 1.1 * e.wave_hp_mult):
			z_ok = true
			break
	check("enemy_hp +10%: HP крестьян, бегунов и рыцарей x1.1, свои прежние; зомби создаются с этим HP", e_ok and e.type_hp[e.infantry_type] == p.type_hp[p.infantry_type] and z_ok)
	var k := make({"bk100": 1})
	check("bounty knight +100%: награда за рыцаря x2, за крестьянина прежняя", is_equal_approx(k.type_bounty_mult[k.knight_type], p.type_bounty_mult[p.knight_type] * 2.0)
		and k.type_bounty_mult[k.zombie_type] == p.type_bounty_mult[p.zombie_type])
	var u := make({"uca25": 1})
	var u2 := make({"uca25": 1, "uc15": 1})
	check("unit_cost archer +25%: лучники 125, пехота 100; вместе с unit_cost -15%: лучники 100 * 0.85 * 1.25 = 106, пехота 85",
		u._price(1) == 125.0 and u._price(0) == 100.0 and u2._price(1) == 106.0 and u2._price(0) == 85.0, "%s %s %s %s" % [u._price(0), u._price(1), u2._price(0), u2._price(1)])
	var f := make({"grant10": 1})
	var n0 := count_type(f, f.infantry_type)
	f._start_wave()
	check("grant_units_free +10: в начале волны в отряд пехоты 0 добавлено 10 юнитов бесплатно", count_type(f, f.infantry_type) == n0 + 10 and f.squad_n[0] == p.squad_n[0] + 10 and f.gold == p.gold)
	var gold_before: float = f.gold
	wave(f)
	f._start_wave()
	check("и в начале волны 2 ещё 10", f.squad_n[0] >= 10 and f.gold >= gold_before)
	for x in [p, s, s2, r, g, e, k, u, u2, f]:
		x.free()

# attack_speed: число ударов пехоты за 1000 тиков.
func hits(gifts: Dictionary) -> float:
	var m := make(gifts, 2)
	for t in [m.zombie_type, m.runner_type, m.knight_type]:
		m.base_type_hp[t] = 1e6        # зомби не умирают: строй и цели одни и те же в обоих прогонах
		m.base_type_damage[t] = 0.0    # и не бьют
	m.base_type_arrow_dmg[m.archer_type] = 0.0
	m.base_type_damage[m.archer_type] = 0.0
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	for i in 1000:
		m._physics_process(DT)
	var lost := 0.0
	for i in m.count:
		if m.team[i] == 1:
			lost += m.type_hp[m.unit_type[i]] * m.wave_hp_mult - m.hp[i]
	var dmg: float = m.type_damage[m.infantry_type]
	m.free()
	return lost / dmg

func t_attack_speed() -> void:
	print("attack_speed")
	var a := hits({})
	var b := hits({"as12": 1})
	var m := make({"as12": 1})
	check("attack_speed infantry +12%%: фактический интервал без дара %.4f с (13 шагов по 2 тика), с даром / 1.12 = %.4f с, остаток переносится (предел cooldown -%.4f)" % [
		m._cd_actual(0.8), m.type_cooldown[m.infantry_type], m.CD_CARRY], is_equal_approx(m._cd_actual(0.8), 13.0 * 2.0 / 30.0)
		and is_equal_approx(m.type_cooldown[m.infantry_type], 13.0 * 2.0 / 30.0 / 1.12) and is_equal_approx(m.type_cd_floor[m.infantry_type], -m.CD_CARRY) and m.type_cd_floor[m.zombie_type] == 0.0)
	m.free()
	check("за 1000 тиков ударов пехоты %.0f без дара и %.0f с +12%%: x%.3f (ожидается 1.12 +- 0.03)" % [a, b, b / a], a > 100.0 and absf(b / a - 1.12) <= 0.03)

# Пересчёт данных волны от базы и доля HP.
func t_rebuild() -> void:
	print("пересчёт от базы, доля HP, ворота")
	var m := make({"hp12": 1})
	var base: float = m.base_type_hp[m.infantry_type]
	m._start_wave()
	m.wave_state = m.WS_RESPITE
	m._start_wave()
	check("hp infantry +12%%, две волны подряд: максимум %.3f = база x1.12, не x1.12^2" % m.type_hp[m.infantry_type], is_equal_approx(m.type_hp[m.infantry_type], base * 1.12))
	var i0 := -1
	for i in m.count:
		if m.unit_type[i] == m.infantry_type:
			i0 = i
			break
	m.hp[i0] = m.type_hp[m.infantry_type] * 0.5
	m.active_gifts = {"hp12": 2}   # набор сменился (как карточка, выбранная в передышке)
	m.wave_state = m.WS_RESPITE
	m._start_wave()
	check("максимум сменился на x1.5: у раненого HP по-прежнему половина максимума (%.3f из %.3f)" % [m.hp[i0], m.type_hp[m.infantry_type]],
		is_equal_approx(m.type_hp[m.infantry_type], base * 1.5) and is_equal_approx(m.hp[i0], m.type_hp[m.infantry_type] * 0.5))
	m.free()
	var g := make({})
	g.gate_hp = g.gate_hp_max * 0.5
	g.active_gifts = {"gate40": 1}
	g._start_wave()
	check("gate_hp +40%% в начале волны: максимум 1500 -> 2100, ворота сохраняют долю 50%% (%.0f)" % g.gate_hp, is_equal_approx(g.gate_hp_max, 2100.0) and is_equal_approx(g.gate_hp, 1050.0))
	g.free()
	var w := make({})
	w.gold = 1000.0
	w._buy(2)
	w._buy(2)
	var d: float = w.type_damage[w.infantry_type]
	w._start_wave()
	check("две покупки оружия переживают пересчёт волны: урон пехоты тот же (%.4f)" % d, w.type_damage[w.infantry_type] == d and is_equal_approx(d, w.base_type_damage[w.infantry_type] * 1.21))
	w.free()
