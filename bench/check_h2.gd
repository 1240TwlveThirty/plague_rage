extends SceneTree
# Проверки H2' (bench/main_h2.gd).
var m: Node2D

func structure(s: int) -> String:
	var width: int = m.squad_width[s]
	var used := {}
	var h := {}
	for i in m.count:
		if m.unit_squad[i] != s:
			continue
		var k: int = m.unit_slot_idx[i]
		if used.has(k):
			return "дубль слота %d" % k
		used[k] = true
		h[k % width] = h.get(k % width, 0) + 1
		if m.unit_slot_target[i].distance_to(m._slot_vector(k, width) - m.squad_center_off[s]) > 0.001:
			return "slot_target не соответствует slot_idx"
	for k in used:
		if k / width >= h[k % width]:
			return "дыра в колонке %d" % (k % width)
	var cols := h.keys()
	cols.sort()
	for q in cols.size():
		if cols[q] != cols[0] + q:
			return "колонки не подряд: %s" % [cols]
	var lo := 1 << 30
	var hi := 0
	for c in h:
		lo = mini(lo, h[c])
		hi = maxi(hi, h[c])
	if hi - lo > 1:
		return "глубины колонок отличаются на %d" % (hi - lo)
	return "ok"

func world(arr: PackedVector2Array, s: int) -> Dictionary:
	var d := {}
	for i in m.count:
		if m.unit_squad[i] == s:
			d[i] = m.squad_pos[s] + arr[i].rotated(m.squad_angle[s])
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

func about_face_series(label: String, rng: RandomNumberGenerator) -> void:
	var worst_t := 0.0
	var worst_c := 0.0
	var st := "ok"
	for n in 30:
		m.squad_angle[0] = rng.randf_range(-PI, PI)
		m.squad_pos[0] = Vector2(rng.randf_range(300, 1700), rng.randf_range(300, 700))
		# слот_current не совпадает с целью — как в движении
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.unit_slot[i] = m.unit_slot_target[i] + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		var bt := world(m.unit_slot_target, 0)
		var bc := world(m.unit_slot, 0)
		m._about_face(0)
		var at := world(m.unit_slot_target, 0)
		var ac := world(m.unit_slot, 0)
		for i in bt:
			worst_t = maxf(worst_t, bt[i].distance_to(at[i]))
			worst_c = maxf(worst_c, bc[i].distance_to(ac[i]))
		m._assign_slots(0)   # как в _update_squads: назначение сразу после разворота
		var r := structure(0)
		if r != "ok" and st == "ok":
			st = r
	print("  %s: 30 углов — max сдвиг slot_target %.5f, slot_current %.5f px — %s; структура после назначения: %s" % [
		label, worst_t, worst_c, "OK" if worst_t <= 0.01 and worst_c <= 0.01 else "FAIL", st])

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# 1) Структура и гистерезис в статичном строю: 10 назначений подряд, без боя
	m = load("res://bench/main_h2.gd").new()
	m._setup_data()
	m.count = 300   # только отряд игрока, зомби убраны
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))   # не идеальная сетка
	var fr := []
	for r in 10:
		var prev: PackedInt32Array = m.unit_slot_idx.duplicate()
		m._assign_slots(0)
		var ch := 0
		for i in m.count:
			if m.unit_slot_idx[i] != prev[i]:
				ch += 1
		fr.append("%.3f" % (ch / 300.0))
		for t in 15:   # полсекунды «жизни» строя между назначениями
			m._physics_process(1.0 / 30.0)
	print("статичный строй (смещения ±1.5 px), доля сменивших slot_idx по назначениям: %s; структура: %s" % [", ".join(fr), structure(0)])
	m.free()
	# 2) Инвариант разворота
	print("разворот (_about_face), мировые позиции slot_target и slot_current до/после:")
	m = load("res://bench/main_h2.gd").new()
	m._setup_data()
	about_face_series("полный отряд 300", rng)
	kill_until(0, 183, rng)
	m._assign_slots(0)
	about_face_series("117 убитых, 183", rng)
	kill_until(0, 3, rng)
	m._assign_slots(0)
	about_face_series("3 юнита", rng)
	m.free()
	# 3) Структура во время боя: проверка после каждого назначения, 60 с
	m = load("res://bench/main_h2.gd").new()
	m._setup_data()
	var prev_n: int = m.bench_assign_n
	var checks := 0
	var bad := ""
	var skipped := 0
	for t in 1800:
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if m.bench_assign_n != prev_n:
			prev_n = m.bench_assign_n
			if m.count != before:
				skipped += 1   # в этом тике после назначения кто-то погиб: дыра законна до следующего назначения
				continue
			checks += 1
			var r := structure(0)
			if r != "ok" and bad == "":
				bad = "тик %d: %s" % [t, r]
	print("бой 60 с: проверок структуры после назначений %d (пропущено %d — в том же тике были смерти) — %s" % [checks, skipped, "ok" if bad == "" else bad])
	m.free()
	# 4) Детерминизм 30 с
	var a: Node2D = load("res://bench/main_h2.gd").new()
	var b: Node2D = load("res://bench/main_h2.gd").new()
	a._setup_data()
	b._setup_data()
	var first := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp):
			first = t
	print("детерминизм 30 с: " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first))
	a.free()
	b.free()
	quit()