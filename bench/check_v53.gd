extends SceneTree
# Тесты задачи 8, этап A: приказ «отход». Причина бага: «отход» менял только приказ, цель отряда оставалась на месте —
# на следующем тике отряд «приходил» и приказ сам становился «держать»; к воротам никто не шёл. Теперь отход ведёт отряд к его точке
# у ворот (gate_spot), по приходе — «держать». Сцена боя вне дерева, физика вручную.
const MAIN := "res://scripts/main.gd"
const REF := "res://bench/ref/main_ref.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(path := MAIN, cards: Array = []) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = 2
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	if path == MAIN:
		m.active_cards = cards
	m._setup_data()
	return m

func ticks(m: Node2D, n: int) -> void:
	for i in n:
		m._physics_process(DT)

func units_dist(m: Node2D, s: int) -> float:
	var c := Vector2.ZERO
	var n := 0
	for i in m.count:
		if m.unit_squad[i] == s:
			c += m.pos[i]
			n += 1
	return (c / n).distance_to(m.GATE_POS)

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	print("приказ «отход»")
	var a := make()
	var b := make()
	var d0: float = a.squad_pos[0].distance_to(a.GATE_POS)
	var u0 := units_dist(a, 0)
	a._select_only(0)
	a._set_order(a.ORDER_RETREAT)
	check("отход: цель отряда пехоты — его точка у ворот", a.squad_target[0] == a.gate_spot(0) and a.squad_order[0] == a.ORDER_RETREAT, str(a.squad_target[0]))
	ticks(a, 150)
	ticks(b, 150)
	var d1: float = a.squad_pos[0].distance_to(a.GATE_POS)
	check("за 150 тиков отряд с отходом ближе к воротам (центр строя %.0f -> %.0f, юниты %.0f -> %.0f)" % [d0, d1, u0, units_dist(a, 0)], d1 < d0 - 50.0 and units_dist(a, 0) < u0 - 50.0)
	check("без приказа отряд не сдвинулся (%.0f)" % b.squad_pos[0].distance_to(b.GATE_POS), is_equal_approx(b.squad_pos[0].distance_to(b.GATE_POS), d0))
	ticks(a, 600)
	check("дошёл до точки у ворот — приказ сам стал «держать»", a.squad_order[0] == a.ORDER_HOLD and a.squad_pos[0].distance_to(a.gate_spot(0)) <= a.squad_stop_dist[0] + 1.0)
	check("лучники (без приказа) остались на месте", is_equal_approx(a.squad_pos[1].distance_to(b.squad_pos[1]), 0.0))
	a.free()
	b.free()
	# Эталон с задачи 6d (bench/ref, c9b64be) уже содержит исправление: раньше здесь воспроизводился баг на эталоне до исправления,
	# теперь эталон должен вести себя как рабочий main.
	print("эталон (уже с исправлением)")
	var r := make(REF)
	var r0: float = r.squad_pos[0].distance_to(r.GATE_POS)
	r._select_only(0)
	r._set_order(r.ORDER_RETREAT)
	ticks(r, 150)
	check("в эталоне отход тоже ведёт отряд к его точке у ворот (%.0f -> %.0f)" % [r0, r.squad_pos[0].distance_to(r.GATE_POS)],
		r.squad_pos[0].distance_to(r.GATE_POS) < r0 - 50.0 and r.squad_target[0] == r.gate_spot(0))
	r.free()
	print("отход в бою и карточка №11")
	var c := make(MAIN, [{"id": "mobile_reserve"}])
	c.gate_hp = 1e9
	c.gate_hp_max = 1e9
	c._start_wave()
	var t := 0
	while c.contact_tick < 0 and t < 30 * 60:
		c._physics_process(DT)
		t += 1
	var dc: float = c.squad_pos[0].distance_to(c.GATE_POS)
	c._select_only(0)
	c._set_order(c.ORDER_RETREAT)
	var mult_seen := 0.0
	for i in 30:   # множитель — на тике пересчёта условий (раз в 15), пока отряд ещё отходит
		c._physics_process(DT)
		if c.squad_order[0] == c.ORDER_RETREAT and c.tick_counter % c.COND_EVERY == 0:
			mult_seen = c.squad_speed_mult[0]
	check("в бою после контакта: отряд отходит к воротам (%.0f -> %.0f)" % [dc, c.squad_pos[0].distance_to(c.GATE_POS)], c.squad_pos[0].distance_to(c.GATE_POS) < dc - 10.0)
	check("«Подвижный резерв» (№11): пока отряд отходит — скорость x1.2", is_equal_approx(mult_seen, 1.2)
		and not c.card_defs.mobile_reserve.get("disabled", false))
	c.free()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
