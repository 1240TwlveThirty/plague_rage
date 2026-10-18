extends SceneTree
# Калибровка осады I: один забег бота. Аргументы: <бот B1..B6> <seed> [множитель численности, по умолчанию 1] [--gifts id:уровень,id:уровень].
# Рабочие scripts/main.gd и JSON из data/ (только чтение). Пример замера «потолка»: B5 1 --gifts tempered_steel:3,reserve:2
# Множитель (свип этапа 2) умножает в памяти count_base, count_step и knight_per_wave: число зомби каждого типа растёт в это число раз, доли типов те же.
# Слой 1, синглтона Game нет — волны без предела, до поражения (страховка 40 волн). Отряды стоят на старте, приказ «атака», кликов нет;
# в каждой передышке бот тратит всё золото. Сила игрока и врага — bench/balance/strength.gd.
# Товары: 0 inf_pack, 1 archer_pack, 2 weapons, 3 gate.
const STRENGTH := preload("res://bench/balance/strength.gd")
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
	var args := Array(OS.get_cmdline_user_args())
	var gifts := {}
	var at := args.find("--gifts")
	if at >= 0:
		for part in String(args[at + 1]).split(",", false):
			gifts[part.get_slice(":", 0)] = int(part.get_slice(":", 1))
		args = args.slice(0, at) + args.slice(at + 2)
	var bot: String = args[0]
	var seed := int(args[1])
	var m: Node2D = load("res://scripts/main.gd").new()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = seed
	m.debug_layer = 1
	m.active_gifts = gifts
	m._setup_data()
	if m.type_id.is_empty():
		m.free()
		quit(1)   # данные или набор даров не загрузились: ошибка уже в stderr
		return
	var mult := float(args[2]) if args.size() > 2 else 1.0
	if mult != 1.0:
		for key in ["count_base", "count_step", "knight_per_wave"]:
			m.wave_cfg[key] *= mult
		m.wave_plan_for = -1   # план волны 1 построен до правки: _start_wave построит заново
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
		var gold_bought := floori(m.gold)   # золото в начале волны после покупок
		var inf := count_type(m, m.infantry_type)
		var arch := count_type(m, m.archer_type)
		var gate0 := ceili(maxf(m.gate_hp, 0.0))
		var p: Dictionary = STRENGTH.player(m)
		m._start_wave()
		var e: Dictionary = STRENGTH.enemy(m)
		var ticks := 0
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 1200:
			m._physics_process(1.0 / 30.0)
			ticks += 1
		var lost := inf + arch - count_type(m, m.infantry_type) - count_type(m, m.archer_type)
		# поля 17-18 (с нуля от WAVE): золото после покупок и убито зомби за волну (из e.n в поле 9)
		print("WAVE,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.1f,%d,%d" % [bot, seed, m.wave_number, inf, arch, m.shop_bought[2], gold_start, lost, e.n,
			gate0, ceili(maxf(m.gate_hp, 0.0)), p.hp, p.dps, e.hp, e.dps, ticks / 30.0, gold_bought, m.wave_kills])
		if m.wave_state == m.WS_DEFEAT:
			defeat = m.wave_number
			break
		if m.wave_state == m.WS_BATTLE:
			full = 0
			break
	print("RUN,%s,%d,%d,%d,%d" % [bot, seed, defeat, full, floori(m.gold)])   # последнее поле — золото, не потраченное к концу забега
	m.free()
	quit()
