extends SceneTree
# Этап 3: (а) приказы модульно; (в) регрессия против bak23 (archers_follow, атака, без волн).
func new_main() -> Node2D:
	var m: Node2D = load("res://scripts/main.gd").new()
	m.record_path = "user://record_bench.json"
	m._setup_data()   # волны включены: зомби нет, передышка
	return m

# Неподвижный живучий зомби на расстоянии d перед передним юнитом пехоты (по центру фронта).
func setup_enemy(m: Node2D, d: float) -> Array:
	m.type_speed[m.zombie_type] = 0.0
	var fwd := Vector2.from_angle(m.squad_angle[0])
	var best := -1
	var best_x := -INF
	for i in m.count:
		if m.unit_squad[i] == 0:
			var lx: float = m.unit_slot[i].x - absf(m.unit_slot[i].y) * 0.01   # передний ряд, ближе к центру
			if lx > best_x:
				best_x = lx
				best = i
	var zp: Vector2 = m.pos[best] + fwd * d
	m._spawn_zombie(zp)
	m.hp[m.count - 1] = 1e9
	return [best, zp]

func order_case(o: int) -> float:
	var m := new_main()
	var r := setup_enemy(m, 10.0)
	var u: int = r[0]
	m.squad_order[0] = o
	var p0: Vector2 = m.pos[u]
	for t in 30:
		m._physics_process(1.0 / 30.0)
	var moved: float = m.pos[u].distance_to(p0)
	m.free()
	return moved

func _initialize() -> void:
	print("(а) зомби в 10 px перед передним пехотинцем (в VIEW, вне дальности 7), 1 с:")
	print("  держать: юнит сместился на %.2f px" % order_case(1))
	print("  атака:   юнит сместился на %.2f px" % order_case(0))
	# Отход: зомби вплотную (в дальности), цель 200 px назад
	var m := new_main()
	var r := setup_enemy(m, 5.0)
	var z: int = m.count - 1
	var zhp: float = m.hp[z]
	var back := -Vector2.from_angle(m.squad_angle[0]) * 200.0
	for s in 2:
		m.squad_target[s] = m.squad_pos[s] + back
		m.squad_order[s] = 2
	var fired0: int = m.arrows_fired
	var p0: Vector2 = m.squad_pos[0]
	var t_arrive := -1
	var speed_sum := 0.0
	var speed_n := 0
	var prev: Vector2 = m.squad_pos[0]
	for t in range(1, 30 * 10):
		m._physics_process(1.0 / 30.0)
		var step: float = m.squad_pos[0].distance_to(prev)
		prev = m.squad_pos[0]
		if m.squad_order[0] == 2 and step > 0.0:
			speed_sum += step * 30.0
			speed_n += 1
		if t_arrive < 0 and m.squad_order[0] == 1:
			t_arrive = t
	print("  отход: урон зомби %.0f (0 = никто не бил), стрел выпущено %d; скорость отряда %.1f px/с (обычная %.1f, x1.5 = %.1f); приказ после прихода: %s (на %.1f с)" % [
		zhp - m.hp[z], m.arrows_fired - fired0, speed_sum / maxi(speed_n, 1), m.squad_speed[0], m.squad_speed[0] * 1.5,
		m.ORDER_NAMES[m.squad_order[0]], t_arrive / 30.0])
	m.free()
	# (в) регрессия
	var a: Node2D = load("res://bench/main_bak23.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a.waves_enabled = false
	b.waves_enabled = false
	b.archers_follow = true
	a.record_path = "user://record_bench.json"
	b.record_path = "user://record_bench.json"
	a._setup_data()
	b._setup_data()
	var first := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0:
			if a.count != b.count:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i]:
						first = t
						break
	print("(в) регрессия против bak23 (лучники следуют, атака, без волн): " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first))
	a.free()
	b.free()
	quit()