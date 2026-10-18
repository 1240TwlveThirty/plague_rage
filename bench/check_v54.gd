extends SceneTree
# Тесты задачи 8, этап B: копейщики. Данные (относительно пехоты), товар spear_pack и цена через Mods.value (unit_cost / spearman),
# отряд копейщиков создаётся при первой покупке у своей точки у ворот, точки новых отрядов разнесены, приказы, деление, слияние,
# отдельный счёт, оружие, удар со второго ряда (в контакте участвует больше копейщиков, чем пехотинцев при равной численности).
# Сохранения посреди забега в проекте нет — копейщики, как и остальная армия, в него не попадают (проверяется, что файл армии не хранит).
const MAIN := "res://scripts/main.gd"
const FIX := "res://bench/fixtures_gifts/stats_v47.json"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(gifts := {}) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = 3
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

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	t_data()
	t_buy()
	t_squads()
	t_contact()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные")
	var m := make()
	var i: int = m.infantry_type
	var s: int = m.spearman_type
	# значения после подгонки этапа D (было: урон 0.85, дальность 1.6 пехоты)
	check("spearman: HP как у пехоты, урон 1.0 пехоты, дальность удара 2.5 пехоты, скорость 0.95, щит (block_mult) как у пехоты", m.base_type_hp[s] == m.base_type_hp[i]
		and is_equal_approx(m.base_type_damage[s], m.base_type_damage[i]) and absf(sqrt(m.type_range_sq[s]) / sqrt(m.type_range_sq[i]) - 2.5) < 0.01
		and is_equal_approx(m.base_type_speed[s], m.base_type_speed[i] * 0.95) and m.type_block_mult[s] == m.type_block_mult[i],
		"дальность %.2f / %.2f" % [sqrt(m.type_range_sq[s]), sqrt(m.type_range_sq[i])])
	var k: int = m.SHOP_ITEMS.find("spear_pack")
	var ki: int = m.SHOP_ITEMS.find("inf_pack")
	check("товар spear_pack: +30 за 90 — 3 золота за юнита = 1.5 от пехоты (100 за 50)", m.shop_param[k] == 30.0 and m._price(k) == 90.0
		and is_equal_approx((m._price(k) / m.shop_param[k]) / (m._price(ki) / m.shop_param[ki]), 1.5))
	check("начальная армия без копейщиков: 300 пехоты, 100 лучников", count_type(m, s) == 0 and count_type(m, i) == 300 and count_type(m, m.archer_type) == 100)
	preload("res://scripts/settings.gd").ensure_code_actions()   # как Settings._ready в игре
	check("действие buy_spear, клавиша B", m.SHOP_ACTIONS[k] == "buy_spear" and InputMap.has_action("buy_spear")
		and preload("res://scripts/settings.gd").key_label("buy_spear") == "B")
	var ka: int = m.SHOP_ITEMS.find("archer_pack")
	m.free()
	var c := make({"ucs50": 1})
	check("unit_cost / spearman -50%: копейщики 45, пехота и лучники 100", c._price(k) == 45.0 and c._price(ki) == 100.0 and c._price(ka) == 100.0)
	c.free()

func t_buy() -> void:
	print("покупка")
	var m := make()
	var k: int = m.SHOP_ITEMS.find("spear_pack")
	m.gold = 1000.0
	check("первая покупка: новый отряд копейщиков (индекс 2) у своей точки у ворот, 30 копейщиков, списано 90", m._buy(k) and m.squad_used[2] == 1
		and m.squad_type[2] == m.spearman_type and m.squad_n[2] == 30 and m.gold == 910.0 and m.squad_pos[2] == m.gate_spot(2), str(m.squad_pos[2]))
	check("вторая — в тот же отряд (60), цена выросла до 108", m._buy(k) and m.squad_n[2] == 60 and m.gold == 802.0 and count_type(m, m.spearman_type) == 60)
	m._select_only(0)
	check("выбрана пехота — копейщики всё равно идут в отряд копейщиков", m._buy(k) and m.squad_n[2] == 90 and m.squad_n[0] == 300)
	var d0: float = m.type_damage[m.spearman_type]
	m._buy(m.SHOP_ITEMS.find("weapons"))
	check("оружие действует и на копейщиков (x1.1)", is_equal_approx(m.type_damage[m.spearman_type], d0 * 1.1))
	m.free()

func t_squads() -> void:
	print("отряды")
	var m := make()
	m.gold = 5000.0
	m._buy(m.SHOP_ITEMS.find("spear_pack"))
	m._select_only(0)
	m._cmd_new_squad()   # новый пустой отряд пехоты
	var a: int = m.sel_primary
	check("новые отряды появляются в разных точках у ворот: копейщики %s, пехота %s" % [str(m.squad_pos[2]), str(m.squad_pos[a])], a == 3 and m.squad_pos[2] != m.squad_pos[a])
	m._select_only(2)
	m._set_order(m.ORDER_HOLD)
	check("приказ «держать» отряду копейщиков", m.squad_order[2] == m.ORDER_HOLD and m.squad_order[0] == m.ORDER_ATTACK)
	check("подпись отряда «Копейщики», цвет типа", m._squad_label(2) == "Копейщики" and m.type_color[m.spearman_type] == Color.html("#c9a24a"), m._squad_label(2))
	m._select_only(2)
	check("деление: часть копейщиков уходит в новый отряд копейщиков", m._cmd_split() and m.squad_type[m.sel_primary] == m.spearman_type and m.sel_primary != 2
		and m.squad_n[2] + m.squad_n[m.sel_primary] == 30)
	var other: int = m.sel_primary
	m._select_only(other)
	check("слияние двух отрядов копейщиков", m._cmd_merge() and (m.squad_n[2] == 30 or m.squad_n[other] == 30))
	m._select_only(2)
	m._set_order(m.ORDER_RETREAT)
	for i in 120:
		m._physics_process(DT)
	check("отход копейщиков — к их точке у ворот", m.squad_pos[2].distance_to(m.gate_spot(2)) < 5.0 or m.squad_order[2] == m.ORDER_HOLD)
	check("отдельный счёт: копейщиков 30, пехоты 300", count_type(m, m.spearman_type) == 30 and count_type(m, m.infantry_type) == 300)
	m.free()
	var g: Node = load("res://scripts/game.gd").new()
	var save_text := JSON.stringify({"version": g.SAVE_VERSION})
	check("сохранения посреди забега нет (save пишет только мету): копейщики в него не попадают — как и вся армия", not "squad" in save_text)
	g.free()

# Сколько юнитов отряда 0 хоть раз стояли в дальности атаки за 900 тиков (зомби бессмертны и не бьют, ворота бессмертны).
func attackers(spear: bool) -> int:
	var m := make()
	for t in [m.zombie_type, m.runner_type, m.knight_type]:
		m.base_type_hp[t] = 1e6
		m.base_type_damage[t] = 0.0
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	if spear:   # отряд 0 — те же 300, но копейщики
		m.squad_type[0] = m.spearman_type
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.unit_type[i] = m.spearman_type
				m.hp[i] = m.type_hp[m.spearman_type]
	m.squad_order[0] = m.ORDER_HOLD
	m._start_wave()
	var seen := {}
	for t in 900:
		m._physics_process(DT)
		for i in m.count:
			if m.unit_squad[i] == 0 and m.unit_state[i] == m.ST_ATTACK:
				seen[i] = true
	m.free()
	return seen.size()

func t_contact() -> void:
	print("удар со второго ряда")
	var a := attackers(false)
	var b := attackers(true)
	check("300 в строю на «держать»: в дальности атаки побывало пехотинцев %d, копейщиков %d — больше" % [a, b], b > a and a > 0)
