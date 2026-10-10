extends SceneTree
# Эксперимент: серия 50 боёв (300 пехоты + 100 лучников против 300 зомби, как bench/check_v11_battle.gd series)
# с volley_period лучников 1.5 с против рабочих 2.5 с. JSON с 1.5 — копия bench/unit_types_volley15.json.
# Копия main со счётчиком убитых стрелами: bench/main_v31_kills.gd. Итог: bench/series_v31_volley15.txt.
const CONFIGS := [["рабочий JSON (volley_period 2.5 с)", "res://data/unit_types.json"], ["volley_period 1.5 с", "res://bench/unit_types_volley15.json"]]

func battle(seed: int, types_path: String) -> Dictionary:
	var m: Node2D = load("res://bench/main_v31_kills.gd").new()
	m.UNIT_TYPES_PATH = types_path
	m.spawn_seed = seed
	m.waves_enabled = false
	m.archers_follow = true   # как в серии: лучники следуют за пехотой
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var start := [0, 0]
	for i in m.count:
		start[m.team[i]] += 1
	var left: Array = start.duplicate()
	var last_death := -1
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if m.count < before:
			last_death = t
			left = [0, 0]
			for i in m.count:
				left[m.team[i]] += 1
		if left[0] == 0 or left[1] == 0 or (last_death > 0 and t - last_death >= 90):
			break
	var r := {"loss0": start[0] - left[0], "loss1": start[1] - left[1], "fired": m.arrows_fired, "hit": m.arrows_hit, "kills_arrow": m.kills_arrow,
		"period": m.type_volley_period[m.archer_type]}
	m.free()
	return r

func _initialize() -> void:
	var lines: Array[String] = []
	lines.append("series_v31_volley15: 50 боёв, 300 пехоты + 100 лучников против 300 зомби, без волн, seed 1..50; условия конца боя как в серии baseline.")
	lines.append("вариант | ratio (среднее по боям) | потери игрока | потери зомби | стрел выпущено на бой | попало | доля попаданий | убито стрелами на бой | доля стрел в убийствах")
	for c in CONFIGS:
		var s := {"loss0": 0, "loss1": 0, "fired": 0, "hit": 0, "kills_arrow": 0}
		var ratio := 0.0
		var period := 0.0
		for seed in range(1, 51):
			var r := battle(seed, c[1])
			for k in s:
				s[k] += r[k]
			ratio += r.loss1 / float(maxi(r.loss0, 1)) / 50.0
			period = r.period
		var line := "%s | %.3f | %.1f | %.1f | %.1f | %.1f | %.1f%% | %.1f | %.1f%%" % [c[0], ratio, s.loss0 / 50.0, s.loss1 / 50.0, s.fired / 50.0, s.hit / 50.0,
			100.0 * s.hit / maxi(s.fired, 1), s.kills_arrow / 50.0, 100.0 * s.kills_arrow / maxi(s.loss1, 1)]
		lines.append(line)
		print(line + "  [volley_period в бою: %.1f]" % period)
	var f := FileAccess.open("res://bench/series_v31_volley15.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
