extends SceneTree
# balance_gap: откуда разрыв B1/B2. Аргументы: <бот B1|B2|B4|B5|B6|B7> <seed>.
# Параметры — рабочие JSON из data/ (p31, gate_max_gain 300), только чтение.
const WAVE_CAP := 40
# Товары: 0 inf_pack, 1 archer_pack, 2 weapons, 3 gate. B6 покупает случайно, см. ниже.
const BOTS := {"B1": [0, 2, 1, 3], "B2": [0, 2], "B4": [0, 2, 1], "B5": [0, 1, 3], "B6": [], "B7": [0, 2, 1, 3]}
const B6_MAX_BUYS := 2
const B7_ADVANCE := 150.0

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
	var m: Node2D = load("res://bench/balance/main_gap28.gd").new()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = seed
	m._setup_data()
	var cycle: Array = BOTS[bot]
	var ptr := 0
	var defeat := 0
	var full := 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 6
	while m.wave_number < WAVE_CAP:
		var gold_start := floori(m.gold)
		var before: PackedInt32Array = m.shop_bought.duplicate()
		if bot == "B6":
			# «Ближе к человеку»: случайный доступный товар, не больше 2 за передышку, остаток золота лежит.
			for n in B6_MAX_BUYS:
				var avail := []
				for k in 4:
					if m.gold >= m._price(k) and not m._at_cap(k):
						avail.append(k)
				if avail.is_empty():
					break
				m._buy(avail[rng.randi_range(0, avail.size() - 1)])
		else:
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
		var buys := []
		var total := []
		for k in 4:
			buys.append(m.shop_bought[k] - before[k])
			total.append(m.shop_bought[k])
		var inf := count_type(m, m.infantry_type)
		var arch := count_type(m, m.archer_type)
		var gold_after := floori(m.gold)
		if bot == "B7":
			# Пехота: приказ «атака» к точке на оси дороги, 150 px впереди стартовой позиции.
			m.squad_order[0] = m.ORDER_ATTACK
			m.squad_target[0] = Vector2(m.ROAD_X, m.PLAYER_START.y - B7_ADVANCE)
		m._start_wave()
		var ticks := 0
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 1200:
			m._physics_process(1.0 / 30.0)
			ticks += 1
		print("WAVE,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%d" % [bot, seed, m.wave_number, m._wave_count(m.wave_number),
			inf, arch, count_type(m, m.infantry_type), count_type(m, m.archer_type), gold_start, gold_after,
			"-".join(buys), "-".join(total), m.kills_arrow, m.kills_melee[m.infantry_type], m.kills_melee[m.archer_type], m.wave_kills,
			ceili(maxf(m.gate_hp, 0.0)), roundi(m.gate_hp_max), ticks])
		if m.wave_state == m.WS_DEFEAT:
			defeat = m.wave_number
			break
		if m.wave_state == m.WS_BATTLE:
			full = 0
			break
	print("RUN,%s,%d,%d,%d" % [bot, seed, defeat, full])
	m.free()
	quit()
