extends SceneTree
func _initialize() -> void:
	var sim: RefCounted = load("res://bench/sim_prof.gd").new()
	sim.setup(3000, 1)
	for t in 400:
		sim.tick(1.0 / 30.0)
		if t % 10 == 0 or (t > 150 and t < 260 and t % 5 == 0):
			print("t=%d alive=%d grid=%.1fms upd=%.1fms iters=%d in_view=%d ns/iter=%.0f" % [t, sim.count, sim.grid_us / 1000.0, sim.upd_us / 1000.0, sim.iters, sim.hits, sim.upd_us * 1000.0 / maxi(sim.iters, 1)])
	quit()