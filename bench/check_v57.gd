extends SceneTree
# Тесты задачи 6d, этап A: стат recover — возврат павших после побеждённой волны. По каждому своему отряду
# floor(павшие x доля + остаток) юнитов того же типа бесплатно с полным HP; дробный остаток переносится на следующие волны,
# новый забег (новая сцена) начинает с нуля; отряд не больше, чем в начале волны; погибший целиком отряд не получает никого;
# при поражении возврата нет. «Лазарет» 10/20/30%, карточка №40 «Полевой госпиталь» +20%.
const MAIN := "res://scripts/main.gd"
const REF := "res://bench/ref/main_ref.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(gifts := {}, cards: Array = [], path := MAIN, rng_seed := 3) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	if path == MAIN:
		m.active_gifts = gifts
		m.active_cards = cards
	m._setup_data()
	return m

# Убить n своих юнитов отряда s (с конца массива) и убрать мёртвых.
func kill(m: Node2D, s: int, n: int) -> void:
	var k := 0
	for i in range(m.count - 1, -1, -1):
		if k < n and m.team[i] == 0 and m.unit_squad[i] == s:
			m.hp[i] = 0.0
			k += 1
	m._remove_dead()

func full_hp(m: Node2D, s: int) -> bool:
	for i in m.count:
		if m.team[i] == 0 and m.unit_squad[i] == s and m.hp[i] != m.type_hp[m.unit_type[i]]:
			return false
	return true

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await process_frame
	TranslationServer.set_locale("ru")
	t_data()
	t_squads()
	t_cap_and_wipe()
	t_defeat()
	t_battle()
	t_reference()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные")
	var gifts: Dictionary = {}
	for g in JSON.parse_string(FileAccess.get_file_as_string("res://data/gifts.json")):
		gifts[g.id] = g
	var inf: Dictionary = gifts.infirmary
	check("«Лазарет»: recover / player / add_pct 10, 20, 30; цена и req_sieges прежние (0, 1, 2)", inf.stat == "recover" and inf.target == "player" and inf.op == "add_pct"
		and inf.levels == [10.0, 20.0, 30.0] and inf.req_sieges == [0.0, 1.0, 2.0] and not inf.has("prices"))
	var desc := tr(inf.desc_key) % str(int(inf.levels[2]))
	check("описание «Лазарета» с числом из данных: «%s»" % desc, desc == "После волны возвращает 30% павших")
	var card: Dictionary = {}
	for c in JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json")):
		if c.id == "field_kitchen":
			card = c
	check("карточка №40: «Полевой госпиталь», name_key прежний, common, M, recover +20 без издержки", card.num == 40.0 and card.name_key == "CARD_FIELD_KITCHEN_NAME"
		and tr(card.name_key) == "Полевой госпиталь" and card.builds == ["common"] and card.kind == "M" and card.mods.size() == 1
		and card.mods[0].stat == "recover" and card.mods[0].value == 20.0 and not card.mods[0].get("cost", false))
	check("описание №40 не длиннее 12 слов: «%s»" % tr(card.desc_key), tr(card.desc_key).split(" ").size() <= 12)
	check("стат heal и heal_base остались", "heal" in preload("res://scripts/mods.gd").STATS and FileAccess.get_file_as_string("res://data/waves.json").contains("heal_base"))
	var a := make({"infirmary": 1})
	var b := make({"infirmary": 3}, [{"id": "field_kitchen"}])
	var c := make()
	check("доля: ур.1 0.10, ур.3 + №40 0.50, без них 0", is_equal_approx(a.recover_fraction(), 0.10) and is_equal_approx(b.recover_fraction(), 0.50) and c.recover_fraction() == 0.0)
	for x in [a, b, c]:
		x.free()

func t_squads() -> void:
	print("по отрядам и перенос остатка")
	var m := make({"infirmary": 3})   # 30%
	m._start_wave()
	var n0: int = m.squad_n[0]
	var n1: int = m.squad_n[1]
	kill(m, 0, 10)
	kill(m, 1, 7)
	m._wave_cleared()
	check("пехота: 10 павших -> вернулось 3 (%d -> %d)" % [n0 - 10, m.squad_n[0]], m.squad_n[0] == n0 - 7 and full_hp(m, 0))
	check("лучники: 7 павших -> 2.1 -> вернулось 2, остаток 0.1 (%.3f)" % m.squad_recover_carry[1], m.squad_n[1] == n1 - 5 and absf(m.squad_recover_carry[1] - 0.1) < 1e-6)
	check("вернувшиеся — того же типа, в том же отряде, полное HP; учёт wave_recovered 5", full_hp(m, 1) and m.wave_recovered == 5 and m.run_recovered == 5)
	var c := 0
	for i in m.count:
		if m.team[i] == 0 and m.unit_squad[i] == 1 and m.unit_type[i] == m.archer_type:
			c += 1
	check("число лучников в отряде 1 совпадает со счётчиком отряда", c == m.squad_n[1])
	m._start_wave()
	check("в начале волны павшие отряда с нуля, остаток сохранён", m.squad_fallen.count(0) == m.SQUAD_MAX and absf(m.squad_recover_carry[1] - 0.1) < 1e-6)
	var k1: int = m.squad_n[1]
	kill(m, 1, 3)
	m._wave_cleared()
	check("следующая волна: 3 павших лучника -> 0.9 + 0.1 = 1 юнит, остаток 0", m.squad_n[1] == k1 - 2 and m.squad_recover_carry[1] < 1e-6 and m.run_recovered == 6)
	m.free()
	var r := make({"infirmary": 3})
	check("новый забег (новая сцена): остатки нулевые", r.squad_recover_carry.count(0.0) == r.SQUAD_MAX and r.run_recovered == 0)
	r.free()

func t_cap_and_wipe() -> void:
	print("предел и отряд, погибший целиком")
	var m := make({"infirmary": 3}, [{"id": "field_kitchen"}])   # 50%
	m.gold = 1000.0
	m.wave_state = m.WS_RESPITE
	m.shop_enabled[m.SHOP_ITEMS.find("spear_pack")] = 1   # в данных v1 копейщики выключены (задача 9): включаем в экземпляре
	m._buy(m.SHOP_ITEMS.find("spear_pack"))   # отряд 2 — 30 копейщиков
	m._start_wave()
	kill(m, 0, 20)
	m.squad_start_n[0] = m.squad_n[0] + 4   # предел: как если бы на начало волны отряд был на 4 меньше
	kill(m, 2, 30)
	m._wave_cleared()
	check("предел: 20 павших x 0.5 = 10, но отряд не больше, чем в начале волны — вернулось 4", m.squad_n[0] == m.squad_start_n[0])
	check("копейщики погибли все: никто не вернулся, отряд удалён в начале передышки", m.squad_used[2] == 0 and m.squad_n[2] == 0 and m.squad_recover_carry[2] == 0.0)
	m.free()

func t_defeat() -> void:
	print("поражение")
	var m := make({"infirmary": 3}, [{"id": "field_kitchen"}])
	for t in [m.zombie_type, m.runner_type, m.knight_type]:
		m.base_type_hp[t] = 1e6   # зомби не убить: волна не будет побеждена
	m._start_wave()
	kill(m, 0, 50)
	var n: int = m.squad_n[0]
	m.gate_hp = 0.5
	for t in 30 * 120:
		m._physics_process(DT)
		if m.wave_state != m.WS_BATTLE:
			break
	check("ворота пали: возврата нет (было %d, стало %d)" % [n, m.squad_n[0]], m.wave_state == m.WS_DEFEAT and m.squad_n[0] <= n and m.run_recovered == 0)
	m.free()

# Три волны с «Лазаретом» 3 и №40 подряд; итог в строку.
func play(rng_seed: int) -> String:
	var m := make({"infirmary": 3}, [{"id": "field_kitchen"}], MAIN, rng_seed)
	m.card_rules = {}
	var out := []
	var exact := true
	for w in 3:
		m.wave_state = m.WS_RESPITE
		m._start_wave()
		var t := 0
		while m.wave_state == m.WS_BATTLE and t < 30 * 600:
			m._physics_process(DT)
			t += 1
		for s in m.SQUAD_MAX:
			if m.squad_used[s] == 1 and m.squad_fallen[s] > 0:
				var lost: int = m.squad_start_n[s] - m.squad_fallen[s]
				exact = exact and m.squad_n[s] >= lost and m.squad_n[s] <= m.squad_start_n[s]
		out.append("%d/%d/%d/%.4f" % [m.count, m.run_recovered, m.squad_n[0], m.squad_recover_carry[0]])
	var r := "%s %s" % [" ".join(out), "ok" if exact else "bad"]
	m.free()
	return r

func t_battle() -> void:
	print("в бою")
	var a := play(11)
	var b := play(11)
	check("три волны: вернулись павшие, отряды в пределах «начало волны минус павшие .. начало волны»: %s" % a, a.ends_with("ok") and not a.contains("/0/"))
	check("воспроизводимость: тот же сид — тот же итог", a == b)

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func t_reference() -> void:
	print("эталон")
	var a := make({}, [], REF, 7)
	var b := make({}, [], MAIN, 7)
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
	check("без recover (3 волны с покупками): бит в бит с эталоном", first < 0 and t > 300 and same(a, b), "расхождение на тике %d" % first)
	a.free()
	b.free()
