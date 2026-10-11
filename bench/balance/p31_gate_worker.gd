extends SceneTree
# Свип p31 x gate_max_gain. Аргументы: <gate_max_gain> <бот B1|B2|B3> <seed>.
# Рабочие JSON (уже p31) копируются в bench/balance/p31_gate/g<gain>/ с заменой gate_max_gain.
const WAVE_CAP := 40
const BOTS := {"B1": [0, 2, 1, 3], "B2": [0, 2], "B3": [3]}

func write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var args := OS.get_cmdline_user_args()
	var gain := float(args[0])
	var bot := args[1]
	var seed := int(args[2])
	var dir := "res://bench/balance/p31_gate/g%d" % int(gain)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for n in ["unit_types", "waves", "castle"]:
		write_json("%s/%s.json" % [dir, n], JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % n)))
	var shop = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop.json"))
	shop.gate.gate_max_gain = gain
	write_json(dir + "/shop.json", shop)
	var m: Node2D = load("res://bench/balance/main_bal.gd").new()
	m.UNIT_TYPES_PATH = dir + "/unit_types.json"
	m.WAVES_PATH = dir + "/waves.json"
	m.CASTLE_PATH = dir + "/castle.json"
	m.SHOP_PATH = dir + "/shop.json"
	m.record_path = "user://record_bench.json"
	m.spawn_seed = seed
	m._setup_data()
	var cycle: Array = BOTS[bot]
	var ptr := 0
	var defeat := 0
	var full := 1
	while m.wave_number < WAVE_CAP:
		while true:
			var bought := false
			for k in cycle.size():
				var idx: int = cycle[(ptr + k) % cycle.size()]
				if m._buy(idx):
					ptr = (ptr + k + 1) % cycle.size()
					bought = true
					break
			if not bought:
				break
		var army := 0
		for i in m.count:
			if m.team[i] == 0:
				army += 1
		m._start_wave()
		var ticks := 0
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 1200:
			m._physics_process(1.0 / 30.0)
			ticks += 1
		var army_end := 0
		for i in m.count:
			if m.team[i] == 0:
				army_end += 1
		print("WAVE,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d" % [int(gain), bot, seed, m.wave_number, m._wave_count(m.wave_number), army, army - army_end,
			floori(m.gold), ceili(maxf(m.gate_hp, 0.0)), roundi(m.gate_hp_max)])
		if m.wave_state == m.WS_DEFEAT:
			defeat = m.wave_number
			break
		if m.wave_state == m.WS_BATTLE:
			full = 0
			break
	print("RUN,%d,%s,%d,%d,%d" % [int(gain), bot, seed, defeat, full])
	m.free()
	quit()