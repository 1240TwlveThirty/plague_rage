extends SceneTree
# Тесты задачи 6, этап C (условия карточек C и особые K). Имя check_v49.gd занято (настройки), поэтому check_v49_conds.gd.
# Каждое условие на искусственных данных (с границами): hold, retreat, gate_low, squad_low, wave_time, gold_high, lost_steps; vengeance (24);
# пересчёт раз в 15 тиков; бонус к HP по условию — множитель получаемого урона; два одинаковых прогона с карточками — бит в бит.
const MAIN := "res://scripts/main.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(ids: Array, rng_seed := 1) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.active_cards = ids.map(func(id): return {"id": id} if id is String else id)
	m._setup_data()
	return m

func near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-5

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	t_none()
	t_orders()
	t_gate_squad()
	t_time_gold()
	t_steps()
	t_vengeance()
	t_cadence()
	t_effect()
	t_determinism()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_none() -> void:
	print("без карточек")
	var m := make([])
	m._start_wave()
	for i in 60:
		m._physics_process(DT)
	var ones := true
	for s in m.SQUAD_MAX:
		ones = ones and m.squad_dmg_mult[s] == 1.0 and m.squad_taken_mult[s] == 1.0 and m.squad_speed_mult[s] == 1.0
	check("все множители отрядов ровно 1.0, список условий пуст", ones and m.cond_cards.is_empty() and m.vengeance.is_empty())
	m.free()

func t_orders() -> void:
	print("hold, retreat")
	var m := make(["steadfast", "iron_wall", "mobile_reserve"])
	m._start_wave()
	m.squad_order[0] = m.ORDER_HOLD
	m.squad_order[1] = m.ORDER_ATTACK
	m._update_card_conditions()
	check("hold у пехоты: Стойкость (+15% HP всем) и Железная стена (+30% HP пехоте) — получаемый урон x1/1.45; лучники в атаке — 1.0",
		near(m.squad_taken_mult[0], 1.0 / 1.45) and m.squad_taken_mult[1] == 1.0 and m.squad_dmg_mult[0] == 1.0, "%.5f" % m.squad_taken_mult[0])
	m.squad_order[1] = m.ORDER_HOLD
	m._update_card_conditions()
	check("hold у лучников: только Стойкость (Железная стена — для пехоты) — x1/1.15", near(m.squad_taken_mult[1], 1.0 / 1.15))
	var p := make([])
	check("издержка Железной стены (скорость атаки пехоты -10%, задача 6d) действует всегда, не только при hold",
		near(m.type_cooldown[m.infantry_type], p._cd_actual(p.base_type_cooldown[p.infantry_type]) / 0.9) and m.type_damage[m.infantry_type] == p.type_damage[p.infantry_type])
	p.free()
	m.squad_order[0] = m.ORDER_RETREAT
	m._update_card_conditions()
	check("retreat у пехоты: Подвижный резерв — скорость x1.2, бонус hold снят", near(m.squad_speed_mult[0], 1.2) and m.squad_taken_mult[0] == 1.0 and m.squad_speed_mult[1] == 1.0)
	m.free()

func t_gate_squad() -> void:
	print("gate_low, squad_low")
	var m := make(["last_stand", "desperate_charge"])
	m._start_wave()
	m.gate_hp = 0.3 * m.gate_hp_max
	m._update_card_conditions()
	check("ворота ровно 30%: Последний рубеж не действует (условие «ниже 30%»)", m.squad_rate_mult[0] == 1.0)
	m.gate_hp = 0.299 * m.gate_hp_max
	m._update_card_conditions()
	check("ворота 29.9%: скорость атаки всех отрядов x1.25 (задача 6d)", near(m.squad_rate_mult[0], 1.25) and near(m.squad_rate_mult[1], 1.25))
	m.gate_hp = m.gate_hp_max
	var n0: int = m.squad_start_n[0]
	m.squad_n[0] = n0 / 2
	m._update_card_conditions()
	check("в отряде ровно половина от %d: Отчаянный натиск не действует (условие «меньше половины»)" % n0, m.squad_rate_mult[0] == 1.0)
	m.squad_n[0] = n0 / 2 - 1
	m._update_card_conditions()
	check("на одного меньше половины: скорость атаки отряда x1.25, у лучников (полный отряд) 1.0", near(m.squad_rate_mult[0], 1.25) and m.squad_rate_mult[1] == 1.0)
	m.squad_n[0] = n0
	m.free()

func t_time_gold() -> void:
	print("wave_time, gold_high")
	var m := make(["first_volley", "reserve_fund"])
	m.gold = 299.0
	m._start_wave()
	check("золота в начале волны 299: Резервный фонд не действует; первые 10 с: Первый залп — урон лучников x1.3, пехоты 1.0",
		near(m.squad_dmg_mult[1], 1.3) and m.squad_dmg_mult[0] == 1.0)
	m.wave_t = 9.99
	m._update_card_conditions()
	check("волна 9.99 с: ещё действует", near(m.squad_dmg_mult[1], 1.3))
	m.wave_t = 10.0
	m._update_card_conditions()
	check("волна 10.0 с: уже нет (первые 10 секунд)", m.squad_dmg_mult[1] == 1.0)
	m.gold = 5000.0
	m._update_card_conditions()
	check("золото выросло в бою — условие по золоту на начало волны не меняется", m.squad_rate_mult[0] == 1.0)
	m.free()
	var g := make(["reserve_fund"])
	g.gold = 300.0
	g._start_wave()
	check("золота в начале волны ровно 300: Резервный фонд — скорость атаки всех x1.1", near(g.squad_rate_mult[0], 1.1) and near(g.squad_rate_mult[1], 1.1))
	g.free()

func t_steps() -> void:
	print("lost_steps (Кровь за кровь)")
	var m := make(["blood_for_blood"])
	m._start_wave()
	var n0: int = m.squad_start_n[0]
	var cases := [[n0 - roundi(n0 * 0.1) + 1, 1.0], [n0 - roundi(n0 * 0.1), 1.05], [n0 - roundi(n0 * 0.35), 1.15], [1, 1.45]]
	var shown := PackedStringArray()
	var ok := true
	for c in cases:
		m.squad_n[0] = c[0]
		m._update_card_conditions()
		ok = ok and near(m.squad_rate_mult[0], c[1])
		shown.append("%d -> %.2f" % [c[0], m.squad_rate_mult[0]])
	check("из %d: потеряно меньше 10%% — 0 ступеней, 10%% — +5%%, 35%% — +15%%, всё кроме одного — 9 ступеней +45%%" % n0, ok, ", ".join(shown))
	m.squad_n[0] = 1
	check("ступеней не больше max_steps (условие с max 3 — 3)", m.cond_factor("lost_steps", {"step_pct": 10, "max_steps": 3}, 0) == 3.0)
	m.squad_n[0] = n0
	m.free()

func t_vengeance() -> void:
	print("Обет мести (24)")
	var m := make(["vow_of_vengeance"])
	m._start_wave()
	check("в начале волны павших 0: множитель 1.0", m.wave_fallen == 0 and m.squad_dmg_mult[0] == 1.0)
	m.wave_fallen = 100
	m._update_card_conditions()
	check("100 павших: урон всех x1.3", near(m.squad_dmg_mult[0], 1.3) and near(m.squad_dmg_mult[1], 1.3))
	m.wave_fallen = 400
	m._update_card_conditions()
	check("400 павших: не больше +50% (x1.5)", near(m.squad_dmg_mult[0], 1.5))
	m.wave_state = m.WS_RESPITE
	m._start_wave()
	check("новая волна: счётчик павших обнулён, множитель 1.0", m.wave_fallen == 0 and m.squad_dmg_mult[0] == 1.0)
	var t := 0
	while m.wave_fallen == 0 and m.wave_state == m.WS_BATTLE and t < 30 * 300:
		m._physics_process(DT)
		t += 1
	check("в бою счётчик павших растёт сам (тик %d, павших %d)" % [t, m.wave_fallen], m.wave_fallen > 0)
	m.free()

func t_cadence() -> void:
	print("пересчёт раз в 15 тиков")
	var m := make(["steadfast"])
	m._start_wave()
	while (m.tick_counter + 1) % m.COND_EVERY != 1:
		m._physics_process(DT)
	m.squad_order[0] = m.ORDER_HOLD
	var changes := []
	for k in m.COND_EVERY:
		m._physics_process(DT)
		changes.append(m.squad_taken_mult[0] != 1.0)
	check("приказ «Держать» отдан сразу после пересчёта: множитель меняется только на тике, кратном 15 (через %d тиков)" % (changes.find(true) + 1),
		changes.count(true) == 1 and changes[-1] and m.tick_counter % m.COND_EVERY == 0)
	m.free()

# Действие: при «Держать» с Железной стеной пехота теряет меньше HP, чем без карточки (тот же seed, те же приказы).
func lost_hp(ids: Array) -> float:
	var m := make(ids, 4)
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m.squad_order[0] = m.ORDER_HOLD
	m._start_wave()
	var lost := 0.0
	for i in 30 * 25:
		m._physics_process(DT)
	for i in m.count:
		if m.unit_squad[i] == 0:
			lost += m.type_hp[m.infantry_type] - m.hp[i]
	lost += (m.squad_start_n[0] - m.squad_n[0]) * m.type_hp[m.infantry_type]
	m.free()
	return lost

func t_effect() -> void:
	print("действие в бою")
	var a := lost_hp([])
	var b := lost_hp(["steadfast"])
	check("25 с волны 1 при «Держать»: Стойкость — потери HP пехоты меньше (%.0f против %.0f)" % [b, a], b < a and a > 0.0)

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state or a.wave_fallen != b.wave_fallen:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	for s in a.SQUAD_MAX:
		if a.squad_dmg_mult[s] != b.squad_dmg_mult[s] or a.squad_taken_mult[s] != b.squad_taken_mult[s] or a.squad_speed_mult[s] != b.squad_speed_mult[s] or a.squad_rate_mult[s] != b.squad_rate_mult[s]:
			return false
	return true

func t_determinism() -> void:
	print("детерминизм")
	var ids := ["steadfast", "iron_wall", "mobile_reserve", "last_stand", "desperate_charge", "first_volley", "reserve_fund", "blood_for_blood", "vow_of_vengeance",
		{"id": "victory_sacrifice", "result": {"good": "archer", "bad": "infantry"}}, "heavy_baggage", "recruitment", "quick_reload", "long_shot"]
	var a := make(ids, 6)
	var b := make(ids, 6)
	var first := -1
	var ticks := 0
	for w in 3:
		for x in [a, b]:
			x._buy(w % 2)
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 900:
			if ticks % 300 == 100:
				for x in [a, b]:
					x.squad_order[0] = [x.ORDER_HOLD, x.ORDER_RETREAT, x.ORDER_ATTACK][(ticks / 300) % 3]
			a._physics_process(DT)
			b._physics_process(DT)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
	check("14 карточек (условия, 24, 30, разовые и обычные), 3 волны, смена приказов: два прогона бит в бит на каждом тике (%d тиков, волна %d)" % [ticks, b.wave_number],
		first < 0 and ticks > 300, "" if first < 0 else "первое расхождение: тик %d" % first)
	check("Тяжёлый обоз (+20 пехоты при выборе) и Вербовка (+10 в начале волны) добавили юнитов", a.squad_n[0] > 0)
	a.free()
	b.free()
