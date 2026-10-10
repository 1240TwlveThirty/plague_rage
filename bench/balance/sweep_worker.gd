extends SceneTree
# Свип баланса: исполнитель. Аргументы: <id исполнителя> <число исполнителей> <дедлайн, unix-время>.
# Берёт точки из bench/balance/points.txt с id % N == id_исполнителя, пишет JSON точки в points/pNN/,
# играет ботами. Вывод: RUN,точка,бот,seed,волна_поражения(0 = не проиграл),полный(1/0) и WAVE-строки.
const WAVE_CAP := 40
const BOTS := {"B1": [0, 2, 1, 3], "B2": [0, 2], "B3": [3]}   # индексы SHOP_ITEMS: inf, archer, weapons, gate
var deadline := 0.0

func write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func make_point(id: int, p: Array) -> String:
	var dir := "res://bench/balance/points/p%02d" % id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var types = JSON.parse_string(FileAccess.get_file_as_string("res://data/unit_types.json"))
	for e in types:
		if e.name == "peasant":
			e.hp = 3.0 * float(p[1])
	write_json(dir + "/unit_types.json", types)
	var waves = JSON.parse_string(FileAccess.get_file_as_string("res://data/waves.json"))
	waves.hp_growth = float(p[2])
	waves.dmg_growth = float(p[3])
	waves.count_step = float(p[4])
	waves.gold_per_kill = float(p[5])
	write_json(dir + "/waves.json", waves)
	var castle = JSON.parse_string(FileAccess.get_file_as_string("res://data/castle.json"))
	castle.gate_hp = float(p[6])
	write_json(dir + "/castle.json", castle)
	write_json(dir + "/shop.json", JSON.parse_string(FileAccess.get_file_as_string("res://data/shop.json")))
	return dir

# Возвращает [волна поражения (0 = дошёл до WAVE_CAP), полный прогон, строки волн]
func play(dir: String, pid: int, bot: String, seed: int, cap: int) -> Array:
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
	var rows := []
	var defeat := 0
	var complete := true
	while m.wave_number < cap:
		if Time.get_unix_time_from_system() > deadline:
			complete = false
			break
		while true:   # на всё золото: по кругу первый доступный товар
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
		rows.append("WAVE,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d" % [pid, bot, seed, m.wave_number, m._wave_count(m.wave_number), army, army - army_end,
			floori(m.gold), ceili(maxf(m.gate_hp, 0.0)), roundi(m.gate_hp_max)])
		if m.wave_state == m.WS_DEFEAT:
			defeat = m.wave_number
			break
		if m.wave_state == m.WS_BATTLE:   # волна не кончилась за 20 мин симуляции
			complete = false
			break
	m.free()
	return [defeat, complete, rows]

func emit(pid: int, bot: String, seed: int, r: Array) -> void:
	for row in r[2]:
		print(row)
	print("RUN,%d,%s,%d,%d,%d" % [pid, bot, seed, r[0], 1 if r[1] else 0])

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var wid := int(args[0])
	var nw := int(args[1])
	deadline = float(args[2])
	for line in FileAccess.get_file_as_string("res://bench/balance/points.txt").split("\n"):
		if line.is_empty() or line.begins_with("#"):
			continue
		var p := line.split(",")
		var pid := int(p[0])
		if pid % nw != wid:
			continue
		if Time.get_unix_time_from_system() > deadline:
			print("SKIP,%d,бюджет времени" % pid)
			continue
		var dir := make_point(pid, p)
		var r := play(dir, pid, "B1", 1, WAVE_CAP)
		emit(pid, "B1", 1, r)
		if r[0] != 0 and r[0] < 6:
			print("REJECT,%d,B1 проиграл на волне %d" % [pid, r[0]])
			continue
		for job in [["B3", 1], ["B3", 2], ["B1", 2], ["B2", 1], ["B2", 2]]:
			emit(pid, job[0], job[1], play(dir, pid, job[0], job[1], WAVE_CAP))
	quit()