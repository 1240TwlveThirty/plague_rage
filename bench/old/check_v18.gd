extends SceneTree
# v18: (а) детерминизм; (б) залп по плотному/разреженному кластеру, смена режима у границы 30–40 px.
var m: Node2D

func kill_where(cond: Callable) -> void:
	for i in m.count:
		if cond.call(i):
			m.hp[i] = 0.0
	m._remove_dead()
	m.squad_dirty.fill(0)

# Сцена: только лучники и n неподвижных живучих зомби (скорость 0, hp 1000).
func setup_scene(n_zombies: int) -> void:
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	var pz: int = m.type_id["peasant"]
	m.type_speed[pz] = 0.0
	kill_where(func(i): return m.unit_squad[i] == 0)   # пехоту убираем
	var keep := 0   # лямбда захватывает переменные по значению, поэтому отбор — обычным циклом
	for i in m.count:
		if m.team[i] == 1:
			if keep < n_zombies:
				keep += 1
			else:
				m.hp[i] = 0.0
	m._remove_dead()
	m.squad_dirty.fill(0)
	for i in m.count:
		if m.team[i] == 1:
			m.hp[i] = 1000.0

func volley_test(label: String, spacing: float, ahead: float) -> void:
	setup_scene(100)
	var c: Vector2 = m.squad_pos[1]
	var fwd := Vector2.from_angle(m.squad_angle[1])
	var side := fwd.orthogonal()
	var k := 0
	for i in m.count:
		if m.team[i] == 1:
			var gx := k % 10 - 4.5
			var gy := k / 10 - 4.5
			m.pos[i] = c + fwd * (ahead + gx * spacing) + side * gy * spacing
			k += 1
	var fired_at_3 := -1
	for t in range(1, 30 * 12 + 1):
		m._physics_process(1.0 / 30.0)
		if fired_at_3 < 0 and m.arrows_fired >= 300:
			fired_at_3 = t
		if fired_at_3 > 0 and t > fired_at_3 + 30:
			break
	print("  %s: %d зомби, шаг %.0f px, центр в %.0f px перед лучниками — выпущено %d, попало %d (%.1f%%), режим %s" % [
		label, k, spacing, ahead, m.arrows_fired, m.arrows_hit, 100.0 * m.arrows_hit / maxi(m.arrows_fired, 1),
		"одиночный" if m.squad_volley_mode[1] == 1 else "залп"])
	m.free()

# Один неподвижный зомби перед фронтом лучников, расстояние до прямоугольника слотов задаёт dist_fn(t).
func mode_test(label: String, dist_fn: Callable) -> void:
	setup_scene(1)
	var z := -1
	for i in m.count:
		if m.team[i] == 1:
			z = i
	var front := -INF
	for i in m.count:
		if m.unit_squad[i] == 1:
			front = maxf(front, m.unit_slot[i].x)
	var fwd := Vector2.from_angle(m.squad_angle[1])
	var single_thr := 0
	var prev_single := false
	var have_prev := false
	for t in range(1, 30 * 10 + 1):
		var d: float = dist_fn.call(t)
		m.pos[z] = m.squad_pos[1] + fwd * (front + d)
		m._physics_process(1.0 / 30.0)
		if t % m.COARSE_EVERY == 1:   # в эти тики режим пересчитывается; для сравнения — один порог 35 px
			var s := d < 35.0
			if have_prev and s != prev_single:
				single_thr += 1
			prev_single = s
			have_prev = true
	print("  %s: смен режима за 10 с — %d (с одним порогом 35 px было бы %d)" % [label, m.mode_switches, single_thr])
	m.free()

func _initialize() -> void:
	# (а) детерминизм
	var a: Node2D = load("res://scripts/main.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a.spawn_seed = 7
	b.spawn_seed = 7
	a._setup_data()
	b._setup_data()
	var first := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp or a.arrows_hit != b.arrows_hit):
			first = t
	print("(а) детерминизм 30 с, seed 7: " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first) + " (стрел %d / %d)" % [a.arrows_fired, b.arrows_fired])
	a.free()
	b.free()
	# (б) залпы
	print("(б) залп, 3 залпа:")
	volley_test("плотный кластер", 5.0, 75.0)
	volley_test("разреженный", 12.0, 110.0)
	volley_test("очень разреженный", 25.0, 165.0)
	# (б) смена режима у границы
	print("(б) режим у границы 30–40 px:")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	mode_test("шум 28–42 px каждый тик", func(t): return rng.randf_range(28.0, 42.0))
	mode_test("внутри полосы 31–39 px", func(t): return rng.randf_range(31.0, 39.0))
	mode_test("медленно 20→50→20 px", func(t): return 35.0 - 15.0 * cos(t / 300.0 * TAU))
	quit()