extends SceneTree
# v10: (б) развороты отряда 0 после прихода к цели; (в) цель движущегося отряда при _reanchor; (г) мировые слоты при _reanchor.
var m: Node2D

func world_slots(s: int) -> Dictionary:
	var d := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			d[i] = m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])
	return d

func kill_until(s: int, alive: int, rng: RandomNumberGenerator) -> void:
	while true:
		var n := 0
		for i in m.count:
			if m.unit_squad[i] == s:
				n += 1
		if n <= alive:
			return
		var i := rng.randi_range(0, m.count - 1)
		if m.unit_squad[i] == s:
			m.hp[i] = 0.0
			m._remove_dead()

func reanchor_case(label: String, rng: RandomNumberGenerator) -> void:
	# Сдвигаем слоты на случайный v (мир сохраняем через squad_pos), чтобы _reanchor было что делать.
	var worst := 0.0
	var max_shift := 0.0
	for n in 30:
		m.squad_angle[0] = rng.randf_range(-PI, PI)
		var v := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.unit_slot[i] += v
		m.squad_center_off[0] -= v
		m.squad_pos[0] -= v.rotated(m.squad_angle[0])
		var before := world_slots(0)
		var p0: Vector2 = m.squad_pos[0]
		m._reanchor(0)
		max_shift = maxf(max_shift, p0.distance_to(m.squad_pos[0]))
		var after := world_slots(0)
		for i in before:
			worst = maxf(worst, before[i].distance_to(after[i]))
	print("(г) %s: 30 случаев, сдвиг якоря до %.1f px, max расхождение слота %.5f — %s" % [label, max_shift, worst, "OK" if worst <= 0.01 else "FAIL"])

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# --- (в) ---
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	m.squad_target[0] = Vector2(1500, 800)   # отряд «в движении»: цель далеко
	kill_until(0, 230, rng)
	var tgt: Vector2 = m.squad_target[0]
	var p0: Vector2 = m.squad_pos[0]
	m._compact_squad(0)
	print("(в) в движении: якорь сдвинулся на %.2f px, squad_target %s (было %s) — %s" % [p0.distance_to(m.squad_pos[0]), m.squad_target[0], tgt, "OK" if m.squad_target[0] == tgt else "FAIL"])
	m.squad_target[0] = m.squad_pos[0]   # «пришёл»
	kill_until(0, 160, rng)
	p0 = m.squad_pos[0]
	m._compact_squad(0)
	var shift: Vector2 = m.squad_pos[0] - p0
	print("(в) контроль, стоит у цели: якорь сдвинулся на %.2f px, цель сдвинулась на %.2f px, |pos - target| = %.4f" % [shift.length(), (m.squad_target[0] - p0).length(), m.squad_pos[0].distance_to(m.squad_target[0])])
	m.free()
	# --- (г) ---
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	reanchor_case("полный отряд 300", rng)
	kill_until(0, 183, rng)
	reanchor_case("117 убитых, 183", rng)
	kill_until(0, 3, rng)
	reanchor_case("3 юнита", rng)
	m.free()
	# --- (б) ---
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	var arrived_t := -1
	var flips := 0
	var prev: float = m.squad_angle[0]
	var maxd := 0.0
	for t in range(1, 60 * 30 + 1):
		if t == 6 * 30:
			m.squad_target[0] = Vector2(500, 500)
		m._physics_process(1.0 / 30.0)
		if t > 6 * 30 and arrived_t < 0 and m.squad_pos[0].distance_to(m.squad_target[0]) <= 1.0:
			arrived_t = t
		if arrived_t > 0:
			if absf(angle_difference(prev, m.squad_angle[0])) > 2.0:
				flips += 1
			maxd = maxf(maxd, m.squad_pos[0].distance_to(Vector2(500, 500)))
		prev = m.squad_angle[0]
		if m.count == 0:
			break
	print("(б) отряд 0 дошёл на %.1f с; разворотов «кругом» после прихода: %d; max уход якоря от (500,500): %.1f px" % [arrived_t / 30.0, flips, maxd])
	m.free()
	quit()