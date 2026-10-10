extends SceneTree
# Бенчмарк симуляции боя без окна и без отрисовки.
#   godot --headless --path . --script res://bench/run.gd -- <вариант> <юнитов> <seed_from> <seed_to>
# Вариант = суффикс файла bench/sim_<вариант>.gd (a, b1, b2, ...).
# Одна строка CSV на бой:
#   variant,n,seed,dense_ticks,dense_mean_ms,dense_p99_ms,dense_max_ms,all_mean_ms,ticks,winner,blue,red
# "Плотная фаза" = тики, в начале которых живых >= 50% от старта.

const DELTA := 1.0 / 30.0
const MAX_TICKS := 1800   # 60 с симуляции


func _run(variant: String, n: int, rng_seed: int) -> String:
	var sim: RefCounted = load("res://bench/sim_%s.gd" % variant).new()
	sim.setup(n, rng_seed)
	var dense := PackedFloat64Array()
	var total_us := 0
	var ticks := 0
	var blue := n / 2
	var red := n - n / 2
	while ticks < MAX_TICKS:
		var is_dense: bool = sim.count * 2 >= n
		var t0 := Time.get_ticks_usec()
		sim.tick(DELTA)
		var dt := Time.get_ticks_usec() - t0
		total_us += dt
		if is_dense:
			dense.append(dt / 1000.0)
		ticks += 1
		blue = sim.alive(0)
		red = sim.alive(1)
		if blue == 0 or red == 0:
			break
	var winner := "draw"
	if blue > red:
		winner = "blue"
	elif red > blue:
		winner = "red"
	var mean := 0.0
	var p99 := 0.0
	var mx := 0.0
	if dense.size() > 0:
		for v in dense:
			mean += v
		mean /= dense.size()
		dense.sort()
		p99 = dense[maxi(ceili(dense.size() * 0.99) - 1, 0)]
		mx = dense[dense.size() - 1]
	return "%s,%d,%d,%d,%.3f,%.3f,%.3f,%.3f,%d,%s,%d,%d" % [
		variant, n, rng_seed, dense.size(), mean, p99, mx, total_us / 1000.0 / ticks, ticks, winner, blue, red]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var variant := args[0] if args.size() > 0 else "a"
	var n := int(args[1]) if args.size() > 1 else 3000
	var seed_from := int(args[2]) if args.size() > 2 else 1
	var seed_to := int(args[3]) if args.size() > 3 else seed_from
	for s in range(seed_from, seed_to + 1):
		print(_run(variant, n, s))
	quit()
