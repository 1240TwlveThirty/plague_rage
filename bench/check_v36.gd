extends SceneTree
# Тесты v36 (масштаб как параметр). Режимы:
#   ident — (а) регрессия: main_v36_rel1.gd против main_v36_before.gd (155d844) на каждом тике;
#   consts <main.gd> — значения масштабируемых констант и типов.
# Остальное — прежние скрипты с путём к main: check_v35.gd (series, dims, det, tick), time_v35.gd, bots_v36.gd, smoke_v36.gd.
const OLD := "res://bench/main_v36_before.gd"
const NEW := "res://bench/main_v36_rel1.gd"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func new_main(path: String, rng_seed: int, waves: bool) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i] or a.unit_state[i] != b.unit_state[i]:
			return false
	return true

func ident() -> void:
	var a := new_main(OLD, 5, false)
	var b := new_main(NEW, 5, false)
	var first := -1
	for t in 900:
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and not same(a, b):
			first = t
	check("(а) 30 с без волн (seed 5, в конце юнитов %d): совпадает с 155d844 на каждом тике" % b.count, first < 0, "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	a = new_main(OLD, 7, true)
	b = new_main(NEW, 7, true)
	first = -1
	var ticks := 0
	var buys := [0, 1, 2, 0, 1, 3]
	for w in 3:
		for x in [a, b]:
			x._buy(buys[w * 2])
			x._buy(buys[w * 2 + 1])
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 600:
			a._physics_process(1.0 / 30.0)
			b._physics_process(1.0 / 30.0)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
		if first < 0 and (a.wave_state != b.wave_state or a.wave_number != b.wave_number):
			first = ticks
	check("(а) 3 волны с покупками (seed 7, %d тиков, волна %d, юнитов %d): совпадает на каждом тике" % [ticks, b.wave_number, b.count], first < 0 and b.wave_number == 3, "первое расхождение: тик %d" % first)
	a.free()
	b.free()

func consts(path: String) -> void:
	var m := new_main(path, 1, true)
	print("CONSTS %s: SCALE_REL %s, SPEED_REL %s, RENDER_JITTER %s" % [path, m.SCALE_REL, m.SPEED_REL, m.RENDER_JITTER])
	print("  SLOT_SPACING %s, MIN_DIST %s, CELL_SIZE %s, VIEW_RANGE %s, ARCHER_GAP %s, NEAR_RANGE %s, MODE_HYST %s, ARROW_HIT_R %s, ARROW_SPEED %s" % [
		m.SLOT_SPACING, m.MIN_DIST, m.CELL_SIZE, m.VIEW_RANGE, m.ARCHER_GAP, m.NEAR_RANGE, m.MODE_HYST, m.ARROW_HIT_R, m.ARROW_SPEED])
	print("  SLOT_NEAR_SQ %s, GATE_SIDE_MARGIN %s, GOAL_STOP %s, SPAWN_JITTER %s, UNIT_QUAD %s, PLAYER_START %s, spawn_spacing %s, spawn_columns %s" % [
		m.SLOT_NEAR_SQ, m.GATE_SIDE_MARGIN, m.GOAL_STOP, m.SPAWN_JITTER, m.UNIT_QUAD, m.PLAYER_START, m.wave_cfg.spawn_spacing, m.wave_cfg.spawn_columns])
	for t in m.type_hp.size():
		print("  %s: range %.4f, range_far %.2f, speed %.2f" % [m.type_label[t], sqrt(m.type_range_sq[t]), m.type_range_far[t], m.type_speed[t]])
	# блоки появления: 250 юнитов (самый большой всплеск: 2000 / 8) с каждой стороны — до прижатия к полю
	var lim := Vector2(m.FIELD.x, m.WALL_Y - 20.0)
	for side in 3:
		var cols := int(m.wave_cfg.spawn_columns)
		var sp: float = m.wave_cfg.spawn_spacing
		var centre := Vector2(m.wave_cfg.spawn_left_x, m.wave_cfg.spawn_left_y) if side == 1 else Vector2(m.wave_cfg.spawn_right_x, m.wave_cfg.spawn_right_y)
		var face: Vector2 = Vector2.DOWN if side == 0 else (m.HORDE_GOAL - centre).normalized()
		var lat := Vector2(-face.y, face.x)
		var out := 0
		var fit := 0
		var counting := true
		for q in 2000:
			var col := q % cols
			var row := q / cols
			var p: Vector2 = Vector2(m.wave_cfg.spawn_center_x + (col - (cols - 1) * 0.5) * sp, m.wave_cfg.spawn_front_y - row * sp) if side == 0 else centre + lat * ((col - (cols - 1) * 0.5) * sp) - face * (row * sp)
			var inside: bool = p.x - m.SPAWN_JITTER >= 0.0 and p.y - m.SPAWN_JITTER >= 0.0 and p.x + m.SPAWN_JITTER <= lim.x and p.y + m.SPAWN_JITTER <= lim.y
			if not inside:
				counting = false
				if q < 250:
					out += 1
			elif counting:
				fit += 1
		print("  блок появления, сторона %d: колонок %d, помещается без прижатия к краю %d (целых рядов %d); из 250 вне поля %d" % [side, cols, fit, fit / cols, out])
	m.free()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args[0] == "ident":
		ident()
		print("CHECK: провалов %d" % fails)
	else:
		consts(args[1])
	quit()
