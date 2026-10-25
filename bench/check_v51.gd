extends SceneTree
# Тесты задачи 6b, этап 1: видимость карточек. Индикаторы условий (card_state, пишет _update_card_conditions раз в 15 тиков),
# строки и подсказки списка карточек в HUD, результат «Жертвы ради победы» (запись, сообщение, строка). Данные искусственные:
# приказ, численность отряда, павшие, время волны выставляются прямо в сцене.
const MAIN := "res://scripts/main.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func make(ids: Array, in_tree := false) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = 1
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.active_cards = ids.map(func(id): return {"id": id} if id is String else id)
	if in_tree:
		m.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(m)   # _ready: данные и HUD
	else:
		m._setup_data()
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	TranslationServer.set_locale("ru")
	t_state()
	t_text()
	await t_hud()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func on(m: Node2D, id: String) -> bool:
	return m.card_state.get(id, {}).get("on", false)

func t_state() -> void:
	print("индикаторы условий")
	var none := make(["meteor_blades"])
	none._start_wave()
	check("без условных карточек индикаторов нет", none.card_state.is_empty())
	none.free()
	var m := make(["steadfast", "blood_for_blood", "vow_of_vengeance", "first_volley", "meteor_blades"])
	m._start_wave()
	check("начало волны: индикаторы у 4 условных (не у Клинков); Первый залп горит (первые 10 с), Стойкость нет (приказ «атака»)",
		m.card_state.size() == 4 and not m.card_state.has("meteor_blades") and on(m, "first_volley") and not on(m, "steadfast"), str(m.card_state))
	m.squad_order[0] = m.ORDER_HOLD
	m._update_card_conditions()
	check("«Держать» у пехоты: Стойкость горит", on(m, "steadfast"))
	m.squad_order[0] = m.ORDER_ATTACK
	m._update_card_conditions()
	check("приказ снят: гаснет", not on(m, "steadfast"))
	var n0: int = m.squad_start_n[0]
	m.squad_n[0] = n0 - roundi(n0 * 0.35)
	m._update_card_conditions()
	check("потеряно 35%: Кровь за кровь горит, бонус +15% (3 ступени)", on(m, "blood_for_blood") and is_equal_approx(m.card_state.blood_for_blood.pct, 15.0), str(m.card_state.blood_for_blood))
	m.squad_n[0] = n0
	m._update_card_conditions()
	check("потерь нет: гаснет, бонус 0", not on(m, "blood_for_blood") and m.card_state.blood_for_blood.pct == 0.0)
	m.wave_fallen = 100
	m._update_card_conditions()
	check("100 павших: Обет мести горит, +30%", on(m, "vow_of_vengeance") and is_equal_approx(m.card_state.vow_of_vengeance.pct, 30.0))
	m.wave_fallen = 1000
	m._update_card_conditions()
	check("1000 павших: не больше +50%", is_equal_approx(m.card_state.vow_of_vengeance.pct, 50.0))
	m.wave_t = 10.0
	m._update_card_conditions()
	check("волна 10 с: Первый залп гаснет", not on(m, "first_volley"))
	m._wave_cleared()
	check("конец волны: все индикаторы выключены", m.card_state.values().all(func(st): return not st.on and st.pct == 0.0))
	m.free()
	var c := make(["steadfast"])
	c._start_wave()
	while (c.tick_counter + 1) % c.COND_EVERY != 1:
		c._physics_process(DT)
	c.squad_order[0] = c.ORDER_HOLD
	var changes := []
	for k in c.COND_EVERY:
		c._physics_process(DT)
		changes.append(on(c, "steadfast"))
	check("индикатор обновляется вместе с условиями — только на тике, кратном 15", changes.count(true) == 1 and changes[-1])
	c.free()

func t_text() -> void:
	print("строки и подсказки")
	var vs := {"id": "victory_sacrifice", "result": {"good": "infantry", "bad": "archer"}}
	var m := make(["blood_for_blood", "heavy_shields", "steadfast", vs, "vow_of_vengeance"])
	m._start_wave()
	check("«Жертва ради победы»: «пехота ×1.5, лучники ×0.85» в строке и в подсказке («Выпало»)", m.card_split_text(vs) == "пехота ×1.5, лучники ×0.85"
		and m.card_row_text(vs) == "Жертва ради победы (пехота ×1.5, лучники ×0.85)" and m.card_tooltip(vs).contains("Выпало: пехота ×1.5"), m.card_row_text(vs))
	var n0: int = m.squad_start_n[0]
	m.squad_n[0] = n0 - roundi(n0 * 0.5)
	m.wave_fallen = 50
	m._update_card_conditions()
	check("строки со ступенями и павшими: «Кровь за кровь +25%», «Обет мести +15%»", m.card_row_text({"id": "blood_for_blood"}) == "Кровь за кровь +25%"
		and m.card_row_text({"id": "vow_of_vengeance"}) == "Обет мести +15%", "%s | %s" % [m.card_row_text({"id": "blood_for_blood"}), m.card_row_text({"id": "vow_of_vengeance"})])
	var tip: String = m.card_tooltip({"id": "heavy_shields"})
	check("подсказка Тяжёлых щитов: название, описание без издержки, «Издержка: -10% к скорости», без условия", tip.split("\n").size() == 3
		and tip.begins_with("Тяжёлые щиты\n+20% к здоровью всех воинов") and tip.ends_with("Издержка: -10% к скорости"), tip)
	check("подсказка Стойкости: «Условие: у отряда приказ «Держать»»", m.card_tooltip({"id": "steadfast"}).ends_with("Условие: у отряда приказ «Держать»"), m.card_tooltip({"id": "steadfast"}))
	var tips := []
	for id in ["last_stand", "desperate_charge", "first_volley", "reserve_fund", "blood_for_blood", "mobile_reserve", "vow_of_vengeance"]:
		tips.append(m.card_tooltip({"id": id}).split("\n")[-1])
	check("условия с числами из данных: ворота 30%, 50% состава, 10 с, 300 золота, 10% потерь, отход, павшие", tips == ["Условие: ворота ниже 30%",
		"Условие: в отряде меньше 50% состава на начало волны", "Условие: первые 10 с волны", "Условие: в начале волны золота не меньше 300",
		"Условие: бонус за каждые 10% потерь отряда", "Условие: отряд отходит", "Условие: бонус растёт с каждым своим павшим в волне"], " | ".join(tips))
	m.free()
	var p := make([])
	p.card_pick_auto = "random"
	p.bench_card_rng = RandomNumberGenerator.new()
	p.bench_card_rng.seed = 3
	p.pending_offer = ["victory_sacrifice"]
	p.choose_card("victory_sacrifice")
	var r: Dictionary = p.active_cards[0]
	check("после выбора «Жертвы» — сообщение в HUD с результатом из записи", r.has("result") and p.hud_msg == "Жертва ради победы: " + p.card_split_text(r) and p.hud_msg_t > 0.0, p.hud_msg)
	p.free()

func t_hud() -> void:
	print("список карточек в HUD")
	var m := make(["steadfast", "meteor_blades", {"id": "victory_sacrifice", "result": {"good": "archer", "bad": "infantry"}}], true)
	await step(2)
	m._start_wave()
	m._update_ui()
	var tips_ok := true
	for l in m.cards_rows:
		tips_ok = tips_ok and l.tooltip_text != "" and l.mouse_filter == Control.MOUSE_FILTER_STOP
	check("заголовок и три строки, подсказки у всех строк", m.cards_label.visible and m.cards_rows.size() == 3 and tips_ok)
	check("Стойкость не горит: бледная, без «●»; Клинки — белые", not m.cards_rows[0].text.begins_with("●") and m.cards_rows[0].get_theme_color("font_color") == m.CARD_IDLE
		and m.cards_rows[1].get_theme_color("font_color") == Color.WHITE)
	m.squad_order[0] = m.ORDER_HOLD
	m._update_card_conditions()
	m._update_ui()
	check("Стойкость горит: «● Стойкость», цвет CARD_ON", m.cards_rows[0].text == "● Стойкость" and m.cards_rows[0].get_theme_color("font_color") == m.CARD_ON, m.cards_rows[0].text)
	check("строка Жертвы: «Жертва ради победы (лучники ×1.5, пехота ×0.85)»", m.cards_rows[2].text == "Жертва ради победы (лучники ×1.5, пехота ×0.85)", m.cards_rows[2].text)
	m.queue_free()
	await step(2)
