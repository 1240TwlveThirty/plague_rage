extends SceneTree
# Кривые роста ботов по слою 1. Аргументы: <бот B1..B6> <seed>. Копия main: bench/balance/main_bal_curves.gd,
# рабочие JSON из data/ (только чтение). Волны до поражения, лимит 40. Отряды стоят на старте, приказ «атака».
# Товары: 0 inf_pack, 1 archer_pack, 2 weapons, 3 gate.
const WAVE_CAP := 40
const CYCLES := {"B1": [0, 2, 1, 3], "B2": [0, 2], "B3": [3], "B5": [0, 1], "B6": [2, 0, 2, 1]}

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
	var m: Node2D = load("res://bench/balance/main_bal_curves.gd").new()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = seed
	m.debug_layer = 1
	m._setup_data()
	var ptr := 0
	var defeat := 0
	var full := 1
	while m.wave_number < WAVE_CAP:
		var gold_start := floori(m.gold)
		if bot == "B4":
			# оружие, пока хватает золота; остаток — в пехоту
			while m._buy(2):
				pass
			while m._buy(0):
				pass
		else:
			var cycle: Array = CYCLES[bot]
			while true:
				var bought := false
				for k in cycle.size():
					if m._buy(cycle[(ptr + k) % cycle.size()]):
						ptr = (ptr + k + 1) % cycle.size()
						bought = true
						break
				if not bought:
					break
		var inf := count_type(m, m.infantry_type)
		var arch := count_type(m, m.archer_type)
		var gate0 := ceili(maxf(m.gate_hp, 0.0))
		# индекс силы игрока: сумма по юнитам hp * урон (пехота — удар, лучники — стрела), с покупками оружия
		var p_idx: float = inf * m.type_hp[m.infantry_type] * m.type_damage[m.infantry_type] + arch * m.type_hp[m.archer_type] * m.type_arrow_dmg[m.archer_type]
		m._start_wave()
		# индекс врага: сумма по типам число * (hp типа * hp_mult) * (урон типа * dmg_mult)
		var e_idx := 0.0
		var zombies := 0
		for r in m.wave_plan:
			zombies += r.count
			e_idx += r.count * m.type_hp[r.type] * m.wave_hp_mult * m.type_damage[r.type] * m.team_dmg_mult[1]
		var ticks := 0
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 1200:
			m._physics_process(1.0 / 30.0)
			ticks += 1
		var lost := inf + arch - count_type(m, m.infantry_type) - count_type(m, m.archer_type)
		print("WAVE,%s,%d,%d,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%d,%d,%.6f,%.6f,%d,%d,%.1f" % [bot, seed, m.wave_number, inf, arch, m.shop_bought[2], gold_start, lost, zombies,
			m.wave_hp_mult, m.team_dmg_mult[1], gate0, ceili(maxf(m.gate_hp, 0.0)), p_idx, e_idx, m.wave_kills_by_type[m.runner_type], m.wave_kills_by_type[m.knight_type], ticks / 30.0])
		if m.wave_state == m.WS_DEFEAT:
			defeat = m.wave_number
			break
		if m.wave_state == m.WS_BATTLE:
			full = 0
			break
	print("RUN,%s,%d,%d,%d" % [bot, seed, defeat, full])
	m.free()
	quit()
