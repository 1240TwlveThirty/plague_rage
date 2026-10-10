extends SceneTree
# (д) Кривая баланса: бот покупает по кругу inf_pack, weapons, archer_pack, gate; до поражения или волны 30.
# Аргумент: seed. Строка на волну: W,seed,волна,зомби,армия_старт,потери,золото_конец,ворота_конец,ворота_макс,длительность_с,макс_юнитов,покупки
const CYCLE := [0, 2, 1, 3]

func _initialize() -> void:
	var seed := int(OS.get_cmdline_user_args()[0])
	var m: Node2D = load("res://scripts/main.gd").new()
	m.spawn_seed = seed
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var ptr := 0
	while m.wave_number < 30:
		var bought := []
		while true:
			if not m._buy(CYCLE[ptr]):
				break
			bought.append(["inf", "arch", "weap", "gate"][CYCLE[ptr]])
			ptr = (ptr + 1) % CYCLE.size()
		var army := 0
		for i in m.count:
			if m.team[i] == 0:
				army += 1
		m._start_wave()
		var ticks := 0
		var max_count: int = m.count
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 900:
			m._physics_process(1.0 / 30.0)
			ticks += 1
			max_count = maxi(max_count, m.count)
		var army_end := 0
		for i in m.count:
			if m.team[i] == 0:
				army_end += 1
		print("W,%d,%d,%d,%d,%d,%d,%d,%d,%.1f,%d,%s" % [seed, m.wave_number, m._wave_count(m.wave_number), army, army - army_end,
			floori(m.gold), ceili(maxf(m.gate_hp, 0.0)), roundi(m.gate_hp_max), ticks / 30.0, max_count, "+".join(bought)])
		if m.wave_state == m.WS_DEFEAT:
			print("END,%d,поражение на волне %d" % [seed, m.wave_number])
			break
	if m.wave_state != m.WS_DEFEAT:
		print("END,%d,дошли до волны %d" % [seed, m.wave_number])
	m.free()
	quit()