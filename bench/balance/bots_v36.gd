extends SceneTree
# Боты после этапа v34 (всплески по слоям): <бот B1|B2> <seed> <слой 1-3> <main.gd>. Рабочие JSON и scripts/main.gd, только чтение.
# Покупки на всё золото по кругу, отряды стоят на старте, приказ «атака», лимит 40 волн. PROFILE включён ради arrivals_10s_max.
const WAVE_CAP := 40
const BOTS := {"B1": [0, 2, 1, 3], "B2": [0, 2]}

func count_type(m: Node2D, type: int) -> int:
	var n := 0
	for i in m.count:
		if m.unit_type[i] == type:
			n += 1
	return n

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var bot := args[0]
	var seed := int(args[1])
	var m: Node2D = load(args[3]).new()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = seed
	m.debug_layer = int(args[2])
	m.profile = true
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
		var inf := count_type(m, m.infantry_type)
		var arch := count_type(m, m.archer_type)
		var bursts: int = m.wave_bursts.size()
		m._start_wave()
		var ticks := 0
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 1200:
			m._physics_process(1.0 / 30.0)
			ticks += 1
		print("WAVE,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.1f" % [bot, seed, int(args[2]), m.wave_number, m._wave_count(m.wave_number), inf, arch, bursts, m.arrivals_10s_max,
			ceili(maxf(m.gate_hp, 0.0)), ticks / 30.0])
		if m.wave_state == m.WS_DEFEAT:
			defeat = m.wave_number
			break
		if m.wave_state == m.WS_BATTLE:
			full = 0
			break
	print("RUN,%s,%d,%d,%d,%d" % [bot, seed, int(args[2]), defeat, full])
	m.free()
	quit()
