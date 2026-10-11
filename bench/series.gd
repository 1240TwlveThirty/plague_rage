extends SceneTree
# Серия 50 боёв на рабочем scripts/main.gd: 300 пехоты + 100 лучников против зомби стартового состава без волн
# (UNIT_COUNT), лучники следуют за пехотой, seed 1-50, стартовые позиции сдвинуты на ±1.5 px. Бой до гибели одной
# стороны, 3 с без смертей или 60 с. Печатает потери сторон и стрелы; цель — увидеть сдвиг баланса боя после правок
# (сравнивать с прошлым выводом) и что ни один бой не падает. Аргумент: [число боёв, по умолчанию 50].
func battle(rng_seed: int) -> Dictionary:
	var m: Node2D = load("res://scripts/main.gd").new()
	m.spawn_seed = rng_seed
	m.waves_enabled = false
	m.archers_follow = true
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var start := [0, 0]
	for i in m.count:
		start[m.team[i]] += 1
	var left: Array = start.duplicate()
	var last_death := -1
	var ticks := 0
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		ticks = t
		if m.count < before:
			last_death = t
			left = [0, 0]
			for i in m.count:
				left[m.team[i]] += 1
		if left[0] == 0 or left[1] == 0 or (last_death > 0 and t - last_death >= 90):
			break
	var r := {"start0": start[0], "start1": start[1], "loss0": start[0] - left[0], "loss1": start[1] - left[1], "fired": m.arrows_fired, "hit": m.arrows_hit,
		"kills_arrow": m.kills_by_arrows, "sec": ticks / 30.0}
	m.free()
	return r

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 50
	var sum := {"loss0": 0.0, "loss1": 0.0, "fired": 0.0, "hit": 0.0, "kills_arrow": 0.0, "sec": 0.0}
	var wins := 0
	var lo := 1 << 30
	var hi := 0
	var start := [0, 0]
	for s in range(1, n + 1):
		var r := battle(s)
		start = [r.start0, r.start1]
		for k in sum:
			sum[k] += r[k]
		if r.loss1 == r.start1:
			wins += 1
		lo = mini(lo, r.loss0)
		hi = maxi(hi, r.loss0)
	print("SERIES|боёв %d|игрок %d против %d|побед (все зомби убиты) %d|потери игрока среднее %.1f (от %d до %d)|убито зомби среднее %.1f|стрел %.0f, попало %.0f, убито стрелами %.1f|бой %.1f с" % [
		n, start[0], start[1], wins, sum.loss0 / n, lo, hi, sum.loss1 / n, sum.fired / n, sum.hit / n, sum.kills_arrow / n, sum.sec / n])
	quit()
