extends SceneTree
# (г) детерминизм: два прогона 30 с с одним seed, сравнение pos/hp/count и prev_pos на каждом тике.
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
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp or a.prev_pos != b.prev_pos):
			first = t
	print("(г) детерминизм 30 с, seed 7: " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first))
	a.free()
	b.free()
	quit()