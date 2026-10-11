extends SceneTree
# Боты после этапа v32 (бегуны, рыцари, три стороны): <бот B1|B2> <seed>. Рабочие JSON и scripts/main.gd, только чтение.
# Покупки на всё золото по кругу, отряды стоят на старте, приказ «атака», лимит 40 волн.
const WAVE_CAP := 40
const BOTS := {"B1": [0, 2, 1, 3], "B2": [0, 2]}

func count_type(m: Node2D, type: int) -> int:
	var n := 0
	for i in m.count:
		if m.unit_type[i] == type:
			n += 1
	return n

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var args := OS.get_cmdline_user_args()
	var bot := args[0]
	var seed := int(args[1])
	var m: Node2D = load("res://scripts/main.gd").new()
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
		var inf := count_type(m, m.infantry_type)
		var arch := count_type(m, m.archer_type)
		var sides := [0, 0, 0]
		for r in m.wave_plan:
			sides[r.side] += r.count
		m._start_wave()
		var ticks := 0
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 1200:
			m._physics_process(1.0 / 30.0)
			ticks += 1
		print("WAVE,%s,%d,%d,%d,%d,%d,%d,%d,%s,%d,%d,%d,%d" % [bot, seed, m.wave_number, m._wave_count(m.wave_number), inf, arch,
			inf - count_type(m, m.infantry_type), arch - count_type(m, m.archer_type), "/".join(sides), m.wave_kills_by_type[m.runner_type], m.wave_kills_by_type[m.knight_type],
			ceili(maxf(m.gate_hp, 0.0)), roundi(m.gate_hp_max)])
		if m.wave_state == m.WS_DEFEAT:
			defeat = m.wave_number
			break
		if m.wave_state == m.WS_BATTLE:
			full = 0
			break
	print("RUN,%s,%d,%d,%d" % [bot, seed, defeat, full])
	m.free()
	quit()
