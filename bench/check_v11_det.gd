extends SceneTree
# (а) детерминизм: два прогона 30 с с одним seed, сравнение pos/hp/count на каждом тике.
func run_pair(seed_a: int, seed_b: int) -> String:
	var a: Node2D = load("res://scripts/main.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a.spawn_seed = seed_a
	b.spawn_seed = seed_b
	a._setup_data()
	b._setup_data()
	var first := -1
	for t in range(1, 30 * 30 + 1):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp):
			first = t
	var res := "совпадают на всех 900 тиках" if first < 0 else "расходятся с тика %d" % first
	a.free()
	b.free()
	return res

func _initialize() -> void:
	print("(а) seed 7 vs seed 7: " + run_pair(7, 7))
	print("    контроль, seed 7 vs seed 8: " + run_pair(7, 8))
	quit()