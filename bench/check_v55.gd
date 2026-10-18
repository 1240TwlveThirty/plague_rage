extends SceneTree
# Тесты задачи 8, этап C: стат блока и «Стена щитов». Шанс блока = block_chance типа (доля ударов, которые щит отражает по своему правилу)
# + бонус (стат block у типа, бонус отряда по условиям: карточка №9 при «держать», навык копейщиков «Стена щитов» при «держать»), не выше 0.95;
# недостающая доля добирается среди не отражённых по правилу ударов детерминированно (хэш тик / атакующий / цель).
const MAIN := "res://scripts/main.gd"
const REF := "res://bench/ref/main_ref.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

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

# Отряд 0 — копейщики (те же 300).
func to_spear(m: Node2D) -> void:
	m.squad_type[0] = m.spearman_type
	for i in m.count:
		if m.unit_squad[i] == 0:
			m.unit_type[i] = m.spearman_type
			m.hp[i] = m.type_hp[m.spearman_type]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	TranslationServer.set_locale("ru")
	t_data()
	t_bonus()
	t_battle()
	t_reference()
	await t_hud()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные и выпадение")
	var m := make()
	check("block_chance: пехота и копейщики 0.6, лучники 0; навык «Стена щитов» у копейщиков +0.30 (после подгонки этапа D; было 0.15); потолок 0.95", is_equal_approx(m.type_block_chance[m.infantry_type], 0.6)
		and is_equal_approx(m.type_block_chance[m.spearman_type], 0.6) and m.type_block_chance[m.archer_type] == 0.0 and is_equal_approx(m.type_hold_block[m.spearman_type], 0.30)
		and m.type_hold_block[m.infantry_type] == 0.0 and m.BLOCK_CAP == 0.95)
	var sc: GDScript = load(MAIN)
	var sum := 0.0
	var ok := true
	for k in 20000:
		var r: float = sc.block_roll(k / 100, k % 100, k % 37)
		ok = ok and r >= 0.0 and r < 1.0
		sum += r
	check("выпадение: 20000 значений в [0, 1), среднее %.4f (около 0.5), одинаковые аргументы — одно и то же" % (sum / 20000), ok and absf(sum / 20000 - 0.5) < 0.01
		and sc.block_roll(5, 7, 9) == sc.block_roll(5, 7, 9) and sc.block_roll(5, 7, 9) != sc.block_roll(6, 7, 9))
	m.free()

func t_bonus() -> void:
	print("бонусы и границы")
	var m := make({"spear_wall": 3}, [{"id": "shield_wall"}])
	check("дар «Стена щитов» 3: стат block копейщиков +0.15, пехоты 0", is_equal_approx(m.type_block_bonus[m.spearman_type], 0.15) and m.type_block_bonus[m.infantry_type] == 0.0)
	m._start_wave()
	m.squad_order[0] = m.ORDER_ATTACK
	m._update_card_conditions()
	check("пехота на «атаке»: бонус отряда 0", m.squad_block_bonus[0] == 0.0)
	m.squad_order[0] = m.ORDER_HOLD
	m._update_card_conditions()
	check("пехота на «держать»: карточка №9 — +0.15, навыка у пехоты нет", is_equal_approx(m.squad_block_bonus[0], 0.15) and m.squad_skill_on[0] == 0)
	m.gold = 1000.0
	m.wave_state = m.WS_RESPITE
	m._buy(m.SHOP_ITEMS.find("spear_pack"))
	var s := 2
	m._start_wave()
	m.squad_order[s] = m.ORDER_ATTACK
	m._update_card_conditions()
	check("копейщики на «атаке»: навык не действует, бонус отряда 0", m.squad_block_bonus[s] == 0.0 and m.squad_skill_on[s] == 0)
	m.squad_order[s] = m.ORDER_HOLD
	m._update_card_conditions()
	check("копейщики на «держать»: навык +0.30 и карточка №9 +0.15 — бонус отряда 0.45, навык горит", is_equal_approx(m.squad_block_bonus[s], 0.45) and m.squad_skill_on[s] == 1)
	var base: float = m.type_block_chance[m.spearman_type]
	var extra: float = m.type_block_bonus[m.spearman_type] + m.squad_block_bonus[s]
	var p := (minf(base + extra, m.BLOCK_CAP) - base) / (1.0 - base)
	check("сумма: 0.6 + 0.15 (дар) + 0.45 = 1.2 -> потолок 0.95; добор среди не отражённых по правилу %.3f (= 0.35 / 0.4)" % p, is_equal_approx(extra, 0.60)
		and is_equal_approx(p, 0.875))
	m.free()
	var n := make()
	n._start_wave()
	n.squad_order[0] = n.ORDER_HOLD
	n._update_card_conditions()
	check("без копейщиков, карточек и даров: условия не считаются, бонусов нет", n.squad_block_bonus[0] == 0.0 and n.squad_skill_on.count(1) == 0)
	n.free()

# Доля отражённых ударов по отряду 0 из копейщиков за волну 1 (зомби бессмертны, ворота бессмертны).
func block_rate(hold: bool, skill: bool, gifts := {}) -> float:
	var m := make(gifts, [], MAIN, 5)
	for t in [m.zombie_type, m.runner_type, m.knight_type]:
		m.base_type_hp[t] = 1e6
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	to_spear(m)
	if not skill:
		m.type_hold_block[m.spearman_type] = 0.0
	m.squad_order[0] = m.ORDER_HOLD if hold else m.ORDER_ATTACK
	m._start_wave()
	for t in 30 * 40:
		m._physics_process(DT)
	var r := float(m.blocked_hits) / maxf(m.total_hits, 1)
	m.free()
	return r

func t_battle() -> void:
	print("в бою")
	var a := block_rate(true, false)
	var b := block_rate(true, true)
	var c := block_rate(false, true)
	var d := block_rate(false, true, {"spear_wall": 3})
	check("копейщики на «держать»: без навыка блок %.3f, с навыком %.3f (+%.3f, ожидается около +0.30)" % [a, b, b - a], b - a > 0.22 and b - a < 0.38)
	check("на «атаке» навык не действует: %.3f (как без навыка, около %.3f)" % [c, a], absf(c - a) < 0.05)
	check("дар «Стена щитов» 3 действует и без «держать»: %.3f (+%.3f)" % [d, d - c], d - c > 0.10)
	var e := block_rate(true, true)
	check("воспроизводимость: тот же прогон — та же доля (%.6f)" % e, e == b)

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
	for w in 2:
		for x in [a, b]:
			x.squad_order[0] = x.ORDER_HOLD
			x._buy(w)
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and t < 30 * 600:
			a._physics_process(DT)
			b._physics_process(DT)
			t += 1
			if first < 0 and not same(a, b):
				first = t
	check("без копейщиков и бонусов (пехота на «держать», 2 волны с покупками): бит в бит с эталоном", first < 0 and t > 300, "расхождение на тике %d" % first)
	a.free()
	b.free()

func t_hud() -> void:
	print("HUD")
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = 3
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m)
	await step(2)
	m.gold = 1000.0
	m._buy(m.SHOP_ITEMS.find("spear_pack"))
	m._start_wave()
	m.squad_order[2] = m.ORDER_HOLD
	m._update_card_conditions()
	m._update_squad_panel()
	var t: String = m.squad_buttons[2].text
	check("строка отряда копейщиков на «держать»: «● Стена щитов», золотой цвет", t.ends_with("● Стена щитов") and m.squad_buttons[2].get_theme_color("font_color") == m.CARD_ON, t)
	m.squad_order[2] = m.ORDER_ATTACK
	m._update_card_conditions()
	m._update_squad_panel()
	check("на «атаке» отметки нет", not m.squad_buttons[2].text.contains("Стена щитов"), m.squad_buttons[2].text)
	m.queue_free()
	await step(2)
