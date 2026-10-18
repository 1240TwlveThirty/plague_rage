extends SceneTree
# Тесты задачи 7: дар «Клич Благодати» (war_cry, способность). Имя check_v50.gd занято (клавиши), поэтому check_v54_warcry.gd.
# Сцена боя вне дерева, физика вручную. Без дара и в передышке — активации нет; активация на следующем тике после команды;
# действие и перезарядка в тиках с границами; сброс между волнами; скорость ударов пехоты и стрельбы лучников во время действия;
# два одинаковых прогона и воспроизведение по журналу (war_cry_plan) — бит в бит; без дара и с даром без активации — как эталон.
const MAIN := "res://scripts/main.gd"
const REF := "res://bench/ref/main_ref.gd"
const MODS := preload("res://scripts/mods.gd")
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(gifts: Dictionary, rng_seed := 1, path := MAIN) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	if path == MAIN:
		m.active_gifts = gifts
	m._setup_data()
	return m

# Зомби не умирают и не бьют, ворота бессмертны: волна идёт сколько нужно (для проверок в тиках).
func endless(m: Node2D) -> void:
	for t in [m.zombie_type, m.runner_type, m.knight_type]:
		m.base_type_hp[t] = 1e6
		m.base_type_damage[t] = 0.0
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9

func ticks(m: Node2D, n: int) -> void:
	for i in n:
		m._physics_process(DT)

func all_mult(m: Node2D, v: float) -> bool:
	for s in m.SQUAD_MAX:
		if not is_equal_approx(m.squad_atk_speed_mult[s], v):
			return false
	return true

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	t_data()
	t_gates()
	t_timing()
	t_reset()
	t_effect()
	t_determinism()
	t_reference()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные")
	var defs: Dictionary = MODS.load_gifts("res://data/gifts.json")
	var d: Dictionary = defs.get("war_cry", {})
	check("war_cry — способность: +30% / 8 с / 60 с, +30% / 10 с / 50 с, +30% / 12 с / 40 с; цены 120 / 240 / 480; req_sieges 0, 1, 2", d.get("type") == "ability"
		and d.levels == [{"bonus_pct": 30.0, "duration_s": 8.0, "cooldown_s": 60.0}, {"bonus_pct": 30.0, "duration_s": 10.0, "cooldown_s": 50.0},
		{"bonus_pct": 30.0, "duration_s": 12.0, "cooldown_s": 40.0}] and Array(d.prices) == [120, 240, 480] and Array(d.req_sieges) == [0, 1, 2], str(d))
	var path := "user://bench_v54_bad.json"
	print("  ниже ожидаются строки ERROR: способность с плохим уровнем и неизвестный type")
	for bad in [[{"id": "x", "type": "ability", "name_key": "A", "desc_key": "B", "levels": [{"bonus_pct": 30, "duration_s": 0, "cooldown_s": 60}]}],
			[{"id": "x", "type": "spell", "name_key": "A", "desc_key": "B", "levels": [1]}]]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(bad))
		f.close()
		check("не грузится: %s" % JSON.stringify(bad[0]).left(90), MODS.load_gifts(path).is_empty())
	DirAccess.remove_absolute(path)
	var m = MODS.new(defs)
	check("в build способность не даёт модификаторов (набор с war_cry 3 строится, множителей нет)", m.build({"war_cry": 3}) and m.pct.is_empty() and m.mult.is_empty())

func t_gates() -> void:
	print("когда нельзя")
	var none := make({})
	none._start_wave()
	check("без дара: уровень 0, команда отклонена, множители 1.0", none.war_cry_level == 0 and not none.request_war_cry() and all_mult(none, 1.0))
	ticks(none, 5)
	check("без дара тики не трогают клич", none.war_cry_log.is_empty() and all_mult(none, 1.0))
	none.free()
	var m := make({"war_cry": 1})
	check("дар куплен, передышка: команда отклонена", m.war_cry_level == 1 and m.wave_state == m.WS_RESPITE and not m.request_war_cry())
	m.war_cry_request = true   # даже если запрос попал — в передышке тик его не исполнит
	m.tick_counter += 1
	m._tick_war_cry()
	check("запрос в передышке тиком не исполняется", m.war_cry_log.is_empty() and all_mult(m, 1.0))
	m.free()

func t_timing() -> void:
	print("тики: активация, действие, перезарядка (уровень 1: 240 тиков действия, 1800 — перезарядка)")
	var m := make({"war_cry": 1})
	endless(m)
	m._start_wave()
	ticks(m, 10)
	check("уровень 1: длительность 240 тиков, перезарядка 1800", m.war_cry_dur == 240 and m.war_cry_cd == 1800 and is_equal_approx(m.war_cry_mult, 1.3))
	check("команда в бою принята; до следующего тика множитель 1.0", m.request_war_cry() and all_mult(m, 1.0))
	ticks(m, 1)
	var t0: int = m.tick_counter
	check("на следующем тике (%d) активирован: множитель 1.3 у всех отрядов, журнал [%d]" % [t0, t0], m.war_cry_log == [t0] and all_mult(m, 1.3) and m.war_cry_until == t0 + 240)
	check("повтор во время действия отклонён", not m.request_war_cry())
	ticks(m, 238)
	check("тик T+238: ещё действует", m.tick_counter == t0 + 238 and all_mult(m, 1.3))
	ticks(m, 1)
	check("тик T+239 (последний): ещё действует", all_mult(m, 1.3) and m.war_cry_active_ticks == 240)
	ticks(m, 1)
	check("тик T+240: закончился, множитель 1.0, активных тиков 240", all_mult(m, 1.0) and m.war_cry_until == -1 and m.war_cry_active_ticks == 240)
	while m.tick_counter < t0 + 1798:
		m._physics_process(DT)
	check("тик T+1798: перезарядка, команда отклонена (готов с T+1800)", not m.request_war_cry())
	ticks(m, 1)
	check("тик T+1799: команда принята — исполнится на T+1800", m.request_war_cry())
	ticks(m, 1)
	check("активирован на T+1800, активаций 2", m.war_cry_log == [t0, t0 + 1800] and all_mult(m, 1.3) and m.war_cry_uses == 2)
	m.free()

func t_reset() -> void:
	print("сброс между волнами")
	var m := make({"war_cry": 1})
	m._start_wave()
	ticks(m, 3)
	m.request_war_cry()
	ticks(m, 1)
	var active_before: bool = all_mult(m, 1.3)
	m._wave_cleared()
	check("конец волны: действие снято, в передышке команда отклонена", active_before and all_mult(m, 1.0) and m.war_cry_until == -1 and not m.request_war_cry())
	m.wave_state = m.WS_RESPITE
	m._start_wave()
	check("новая волна: клич готов сразу, хотя перезарядка прошлой волны не прошла", m.request_war_cry())
	ticks(m, 1)
	check("и активируется", m.war_cry_log.size() == 2 and all_mult(m, 1.3))
	m.free()

# Удары пехоты (по урону зомби с бессмертным HP) и выстрелы лучников за 1000 тиков, если клич действует всё время.
func measure(gifts: Dictionary, always: bool) -> Array:
	var m := make(gifts, 2)
	endless(m)
	m.base_type_arrow_dmg[m.archer_type] = 0.0
	m._start_wave()
	if always:
		m.war_cry_dur = 100000   # для замера: действует до конца
		m.request_war_cry()
	ticks(m, 1000)
	var lost := 0.0
	for i in m.count:
		if m.team[i] == 1:
			lost += m.type_hp[m.unit_type[i]] * m.wave_hp_mult - m.hp[i]
	var out := [lost / m.type_damage[m.infantry_type], m.arrows_fired]
	m.free()
	return out

func t_effect() -> void:
	print("действие")
	var a := measure({"war_cry": 1}, false)
	var b := measure({"war_cry": 1}, true)
	check("+30%% скорости ударов: ударов пехоты за 1000 тиков %.0f -> %.0f (x%.3f, ожидается 1.3 +- 0.04)" % [a[0], b[0], b[0] / a[0]], absf(b[0] / a[0] - 1.3) <= 0.04)
	check("лучники стреляют чаще: стрел %d -> %d (x%.3f, больше 1.15)" % [a[1], b[1], float(b[1]) / a[1]], float(b[1]) / a[1] > 1.15)

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func t_determinism() -> void:
	print("детерминизм и воспроизведение")
	var a := make({"war_cry": 3}, 5)
	var b := make({"war_cry": 3}, 5)
	var first := -1
	var t := 0
	for w in 3:
		for x in [a, b]:
			x._buy(w % 2)
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and t < 30 * 900:
			if a.zombie_alive > 20:   # «бот»: при готовности и зомби на поле — команда обоим в одном и том же тике
				for x in [a, b]:
					x.request_war_cry()
			a._physics_process(DT)
			b._physics_process(DT)
			t += 1
			if first < 0 and not same(a, b):
				first = t
	check("два прогона с командами в одних тиках (3 волны, активаций %d): бит в бит на каждом тике" % a.war_cry_uses, first < 0 and a.war_cry_uses >= 3 and a.war_cry_log == b.war_cry_log,
		"" if first < 0 else "расхождение на тике %d" % first)
	var c := make({"war_cry": 3}, 5)
	c.war_cry_plan = a.war_cry_log.duplicate()
	var d := make({"war_cry": 3}, 5)
	first = -1
	t = 0
	for w in 3:
		for x in [c, d]:
			x._buy(w % 2)
			x._start_wave()
		while c.wave_state == c.WS_BATTLE and t < 30 * 900:
			if c.zombie_alive > 20:
				d.request_war_cry()
			c._physics_process(DT)
			d._physics_process(DT)
			t += 1
			if first < 0 and not same(c, d):
				first = t
	check("воспроизведение по журналу (war_cry_plan) = прогон с командами: те же тики активаций, бит в бит", first < 0 and c.war_cry_log == d.war_cry_log and c.war_cry_log == a.war_cry_log,
		"%s / %s" % [str(c.war_cry_log), str(d.war_cry_log)])
	for x in [a, b, c, d]:
		x.free()

func t_reference() -> void:
	print("эталон")
	for gifts in [{}, {"war_cry": 3}]:
		var a := make({}, 7, REF)
		var b := make(gifts, 7)
		var first := -1
		var t := 0
		for w in 2:
			for x in [a, b]:
				x._buy(w)
				x._start_wave()
			while a.wave_state == a.WS_BATTLE and t < 30 * 600:
				a._physics_process(DT)
				b._physics_process(DT)
				t += 1
				if first < 0 and not same(a, b):
					first = t
		check("%s: 2 волны с покупками бит в бит с эталоном (%d тиков)" % ["без дара" if gifts.is_empty() else "дар куплен, клич не нажат", t], first < 0 and t > 300,
			"" if first < 0 else "расхождение на тике %d" % first)
		a.free()
		b.free()
