extends SceneTree
# Тесты (а) и (б): разворот при центрированном якоре.
var m: Node2D

func world_slots(s: int) -> Dictionary:
	var d := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			d[i] = m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])
	return d

func structure(s: int) -> String:
	var width: int = m.squad_width[s]
	var used := {}
	var c := Vector2.ZERO
	var n := 0
	for i in m.count:
		if m.unit_squad[i] != s:
			continue
		var k: int = m.unit_slot_idx[i]
		if used.has(k):
			return "дубль слота %d" % k
		used[k] = true
		if m.unit_slot[i].distance_to(m._slot_vector(k, width) - m.squad_center_off[s]) > 0.001:
			return "unit_slot != _slot_vector - squad_center_off"
		c += m.unit_slot[i]
		n += 1
	if n > 0 and (c / n).length() > 0.001:
		return "центр слотов не 0: %s" % (c / n)
	return "ok"

func series(label: String, rng: RandomNumberGenerator) -> void:
	var worst := 0.0
	var worst_anchor := 0.0
	var worst_center := 0.0
	var st_fail := ""
	for n in 30:
		m.squad_angle[0] = rng.randf_range(-PI, PI)
		m.squad_pos[0] = Vector2(rng.randf_range(300, 1700), rng.randf_range(300, 700))
		m._compact_squad(0)   # то же сжатие, что делает _about_face в начале
		var before := world_slots(0)
		var anchor: Vector2 = m.squad_pos[0]
		var cb := Vector2.ZERO
		for i in before:
			cb += before[i]
		cb /= maxi(before.size(), 1)
		m._about_face(0)
		var after := world_slots(0)
		var ca := Vector2.ZERO
		for i in before:
			worst = maxf(worst, before[i].distance_to(after[i]))
			ca += after[i]
		ca /= maxi(after.size(), 1)
		worst_anchor = maxf(worst_anchor, anchor.distance_to(m.squad_pos[0]))
		worst_center = maxf(worst_center, cb.distance_to(ca))
		var st := structure(0)
		if st != "ok" and st_fail == "":
			st_fail = st
	print("%s: 30 углов — max сдвиг слота %.5f, max сдвиг squad_pos %.5f, сдвиг центра группы %.5f px — %s; структура: %s" % [
		label, worst, worst_anchor, worst_center, "OK" if worst <= 0.01 and worst_anchor <= 0.01 else "FAIL", "ok" if st_fail == "" else st_fail])

func kill_until(s: int, alive: int, rng: RandomNumberGenerator) -> void:
	while true:
		var n := 0
		for i in m.count:
			if m.unit_squad[i] == s:
				n += 1
		if n <= alive:
			break
		var i := rng.randi_range(0, m.count - 1)
		if m.unit_squad[i] == s:
			m.hp[i] = 0.0
			m._remove_dead()

func _initialize() -> void:
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	print("после _setup_data: структура %s, squad_pos[0]=%s, squad_pos[1]=%s" % [structure(0), m.squad_pos[0], m.squad_pos[1]])
	series("(а) полный отряд, 300", rng)
	kill_until(0, 183, rng)
	series("(а) 117 убитых, 183", rng)
	kill_until(0, 3, rng)
	series("(а)+(б) 3 юнита", rng)
	m.free()
	quit()