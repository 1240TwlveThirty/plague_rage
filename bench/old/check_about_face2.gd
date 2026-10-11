extends SceneTree
# Тесты разворота и _compact_squad (main.gd.bak7 -> новая версия).
var m: Node2D
const S := 6.0

func world_slots(s: int) -> Dictionary:
	var d := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			d[i] = m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])
	return d

# (б): уникальность, нет дыр в колонках, unit_slot == _slot_vector, колонки подряд по центру
func structure(s: int) -> String:
	var width: int = m.squad_width[s]
	var used := {}
	var height := {}
	for i in m.count:
		if m.unit_squad[i] != s:
			continue
		var k: int = m.unit_slot_idx[i]
		if used.has(k):
			return "дубль слота %d" % k
		used[k] = true
		if m.unit_slot[i] != m._slot_vector(k, width):
			return "unit_slot != _slot_vector(unit_slot_idx)"
		height[k % width] = height.get(k % width, 0) + 1
	for k in used:
		if k / width >= height[k % width]:
			return "дыра в колонке %d" % (k % width)
	var cols := height.keys()
	cols.sort()
	var n := cols.size()
	var offset := (width - n) / 2
	for idx in n:
		if cols[idx] != offset + idx:
			return "колонки не подряд по центру: %s" % [cols]
	return "ok"

# (а): одна проверка разворота. Возвращает [точно, сдвинуто_финальным_сжатием, ошибок, max_err_точных]
func about_face_case(s: int) -> Array:
	m._compact_squad(s)                 # то же сжатие, что делает _about_face в начале
	var before := world_slots(s)
	m._compact_squad(s)                 # идемпотентность: повторное сжатие ничего не двигает
	var again := world_slots(s)
	for i in before:
		if before[i].distance_to(again[i]) > 0.0001:
			return [0, 0, -1, 0.0]
	m._about_face(s)
	var after := world_slots(s)
	var new_angle: float = m.squad_angle[s]
	var exact := 0
	var moved := 0
	var bad := 0
	for i in before:
		var dl: Vector2 = (after[i] - before[i]).rotated(-new_angle)   # в осях нового строя: +x = вперёд
		if dl.length() <= 0.01:
			exact += 1
			continue
		var rows_fwd := dl.x / S
		var cols_side := dl.y / S
		var ok := absf(rows_fwd - roundf(rows_fwd)) < 0.01 and roundf(rows_fwd) >= 0.0 \
			and absf(cols_side - roundf(cols_side)) < 0.01 and absf(roundf(cols_side)) <= 1.0
		if ok:
			moved += 1
		else:
			bad += 1
	return [exact, moved, bad, 0.0]

func run_series(label: String, rng: RandomNumberGenerator) -> void:
	var tot := [0, 0, 0]
	var struct_fail := ""
	for n in 30:
		m.squad_angle[0] = rng.randf_range(-PI, PI)
		m.squad_pos[0] = Vector2(rng.randf_range(300, 1700), rng.randf_range(300, 700))
		var r := about_face_case(0)
		if r[2] == -1:
			print("FAIL %s: _compact_squad не идемпотентен" % label)
			return
		tot[0] += r[0]; tot[1] += r[1]; tot[2] += r[2]
		var st := structure(0)
		if st != "ok" and struct_fail == "":
			struct_fail = "угол %d: %s" % [n, st]
	print("%s: 30 углов, юнитов-проверок %d — совпали точно %d, сдвинуты финальным сжатием %d, НЕОБЪЯСНИМЫХ %d; структура: %s" % [
		label, tot[0] + tot[1] + tot[2], tot[0], tot[1], tot[2], "ok" if struct_fail == "" else struct_fail])

func _initialize() -> void:
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	print("структура после _setup_data: " + structure(0))
	run_series("полный отряд (300)", rng)
	var killed := 0
	while killed < 117:
		var i := rng.randi_range(0, m.count - 1)
		if m.unit_squad[i] == 0 and m.hp[i] > 0.0:
			m.hp[i] = 0.0
			killed += 1
	m._remove_dead()
	m._compact_squad(0)
	print("после 117 убитых и _compact_squad: структура " + structure(0))
	run_series("отряд с 117 убитыми (183)", rng)
	# Отдельно: целая колонка выбита — схлопывание должно убрать дыру и отцентровать
	var victims := 0
	for i in m.count:
		if m.unit_squad[i] == 0 and m.unit_slot_idx[i] % 20 == 7:
			m.hp[i] = 0.0
			victims += 1
	m._remove_dead()
	m._compact_squad(0)
	print("выбита колонка 7 (%d юн.): структура %s" % [victims, structure(0)])
	run_series("отряд без колонки", rng)
	m.free()
	quit()