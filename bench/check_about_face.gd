extends SceneTree
# Тест _about_face: мировые позиции слотов до и после разворота совпадают (допуск 0.01).
var m: Node2D

func world_slots(s: int) -> Dictionary:
	var d := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			d[i] = m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])
	return d

func check(label: String, s: int) -> bool:
	var before := world_slots(s)
	m._about_face(s)
	var after := world_slots(s)
	var worst := 0.0
	for i in before:
		worst = maxf(worst, before[i].distance_to(after[i]))
	var ok := worst <= 0.01 and before.size() == after.size()
	if not ok:
		print("FAIL %s: max_err=%.5f" % [label, worst])
	return ok

func check_compact(s: int) -> String:
	# в каждой колонке ряды 0..n-1 заняты без дыр, слоты уникальны
	var width: int = m.squad_width[s]
	var used := {}
	var per_col := {}
	for i in m.count:
		if m.unit_squad[i] != s:
			continue
		var k: int = m.unit_slot_idx[i]
		if used.has(k):
			return "дубль слота %d" % k
		used[k] = true
		if m.unit_slot[i] != m._slot_vector(k, width):
			return "unit_slot не совпадает с unit_slot_idx"
		var col := k % width
		per_col[col] = per_col.get(col, 0) + 1
	for k in used:
		var row: int = k / width
		var col: int = k % width
		if row >= per_col[col]:
			return "дыра в колонке %d (ряд %d при %d юнитах)" % [col, row, per_col[col]]
	return "ok"

func _initialize() -> void:
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var passed := 0
	for n in 30:
		m.squad_angle[0] = rng.randf_range(-PI, PI)
		m.squad_pos[0] = Vector2(rng.randf_range(200, 1800), rng.randf_range(200, 800))
		if check("угол %d" % n, 0):
			passed += 1
	print("разворот, полный отряд: %d/30 ок" % passed)
	# Убиваем 117 случайных юнитов отряда 0
	var killed := 0
	while killed < 117:
		var i := rng.randi_range(0, m.count - 1)
		if m.unit_squad[i] == 0 and m.hp[i] > 0.0:
			m.hp[i] = 0.0
			killed += 1
	m._remove_dead()
	print("после _remove_dead: живых в отряде 0 = %d, dirty = %d" % [world_slots(0).size(), m.squad_dirty[0]])
	passed = 0
	for n in 30:
		m.squad_angle[0] = rng.randf_range(-PI, PI)
		if check("с убитыми, до перестройки %d" % n, 0):
			passed += 1
	print("разворот, с убитыми (до перестройки): %d/30 ок" % passed)
	m._compact_squad(0)
	print("_compact_squad: " + check_compact(0))
	passed = 0
	for n in 30:
		m.squad_angle[0] = rng.randf_range(-PI, PI)
		if check("с убитыми, после перестройки %d" % n, 0):
			passed += 1
	print("разворот, с убитыми (после перестройки): %d/30 ок" % passed)
	m.free()
	quit()