extends SceneTree
# v19: (а) детерминизм; (б) залп по неподвижным и идущим зомби; (в) расстановка лучников.
var m: Node2D

func setup_scene(n_zombies: int, freeze: bool) -> void:
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	if freeze:
		m.type_speed[m.type_id["peasant"]] = 0.0
	var keep := 0
	for i in m.count:
		if m.unit_squad[i] == 0:
			m.hp[i] = 0.0   # пехоту убираем
		elif m.team[i] == 1:
			if keep < n_zombies:
				keep += 1
			else:
				m.hp[i] = 0.0
	m._remove_dead()
	m.squad_dirty.fill(0)
	for i in m.count:
		if m.team[i] == 1:
			m.hp[i] = 1000.0   # живучие: плотность скопления не меняется

func place_block(spacing: float, ahead: float) -> void:
	var c: Vector2 = m.squad_pos[1]
	var fwd := Vector2.from_angle(m.squad_angle[1])
	var side := fwd.orthogonal()
	var k := 0
	for i in m.count:
		if m.team[i] == 1:
			m.pos[i] = c + fwd * (ahead + (k / 10 - 4.5) * spacing) + side * (k % 10 - 4.5) * spacing
			k += 1

func volley_static(spacing: float) -> void:
	setup_scene(100, true)
	var ahead := 4.5 * spacing + 55.0   # ближний ряд блока в 55 px перед центром лучников: режим залпа
	place_block(spacing, ahead)
	var done := -1
	for t in range(1, 30 * 14 + 1):
		m._physics_process(1.0 / 30.0)
		if done < 0 and m.arrows_fired >= 300:
			done = t
		if done > 0 and t > done + 30:
			break
	print("  неподвижные, шаг %2.0f px: выпущено %d, попало %d (%.1f%%), режим %s" % [spacing, m.arrows_fired, m.arrows_hit,
		100.0 * m.arrows_hit / maxi(m.arrows_fired, 1), "одиночный" if m.squad_volley_mode[1] == 1 else "залп"])
	m.free()

func volley_moving() -> void:
	setup_scene(100, false)
	place_block(12.0, 200.0)   # орда идёт к HORDE_GOAL, то есть прямо на лучников
	var stop_t := -1
	for t in range(1, 30 * 20 + 1):
		m._physics_process(1.0 / 30.0)
		if stop_t < 0 and m.squad_volley_mode[1] == 1:
			stop_t = t
			m.squad_ranged[1] = 0   # дальше не стреляем: считаем только залпы, долетающие стрелы падают
		if stop_t > 0 and t > stop_t + 45:
			break
	print("  идущая орда (шаг 12 px, скорость из JSON ±10%%): выпущено %d, попало %d (%.1f%%) до перехода на одиночный огонь на %.1f с" % [
		m.arrows_fired, m.arrows_hit, 100.0 * m.arrows_hit / maxi(m.arrows_fired, 1), stop_t / 30.0])
	m.free()

func min_dist(mm: Node2D) -> float:
	var d := INF
	for i in mm.count:
		if mm.unit_squad[i] == 1:
			for j in mm.count:
				if mm.unit_squad[j] == 0:
					d = minf(d, mm.pos[i].distance_to(mm.pos[j]))
	return d

func placement(path: String, label: String) -> void:
	var mm: Node2D = load(path).new()
	mm._setup_data()
	var d0 := min_dist(mm)
	for t in 90:
		mm._physics_process(1.0 / 30.0)
	var d3 := min_dist(mm)
	for t in 210:
		mm._physics_process(1.0 / 30.0)
	var reach: float = mm.reach_sum / maxi(mm.reach_n, 1)
	var dist: float = mm.reach_dist_sum / maxi(mm.reach_n, 1)
	print("  пехота %4s: глубина %.0f px; min лучник–пехотинец: старт %.1f px, через 3 с %.1f px; до фронта %.1f px, reach %.1f px (тиков %d)" % [
		label, mm.squad_depth[0], d0, d3, dist, reach, mm.reach_n])
	mm.free()

func _initialize() -> void:
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
	print("(б) залп, 100 зомби:")
	for sp in [5.0, 12.0, 25.0, 40.0]:
		volley_static(sp)
	volley_moving()
	print("(в) расстановка, 100 лучников:")
	placement("res://bench/old/main_v19_inf100.gd", "100")
	placement("res://scripts/main.gd", "300")
	placement("res://bench/old/main_v19_inf600.gd", "600")
	placement("res://bench/old/main_v19_inf1400.gd", "1400")
	quit()