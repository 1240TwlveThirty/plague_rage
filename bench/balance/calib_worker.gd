extends SceneTree
# Калибровка осады I: один забег бота. Аргументы: <бот B1..B6> <seed> [множитель численности, по умолчанию 1] [--gifts id:уровень,id:уровень]
# [--cards id,id] [--pick random] [--variants путь] [--war-cry on|off] [--hp-spread s].
# --hp-spread — разброс HP зомби s (data/waves.json hp_spread заменяется в памяти; 0 — без разброса).
# Рабочие scripts/main.gd и JSON из data/ (только чтение). Пример замера «потолка»: B5 1 --gifts tempered_steel:3,reserve:2
# --cards — карточки с начала забега (разовые эффекты сразу; случайный результат карточки 30 — генератор забега бенча, seed = seed бота).
# --pick random — настоящий выбор: после волн pick_after_waves бот берёт случайную карточку из тройки (тот же генератор забега).
# --variants — файл с дополнительными карточками (варианты для сравнения, bench/card_variants.json): они добавляются к пулу data/cards.json
# во временный файл user://, в выбор (--pick) не попадают, задаются через --cards.
# --war-cry (по умолчанию on): если дар war_cry в наборе, бот жмёт Клич Благодати, когда он готов и хоть один зомби ближе WAR_CRY_DIST
# к центру любого своего отряда (проверка раз в WAR_CRY_EVERY тиков); off — не жмёт. В конце строка WARCRY: активаций, тиков с бонусом, тиков боя.
# Множитель (свип этапа 2) умножает в памяти count_base, count_step и knight_per_wave: число зомби каждого типа растёт в это число раз, доли типов те же.
# Слой 1, синглтона Game нет — волны без предела, до поражения (страховка 40 волн). Отряды стоят на старте, приказ «атака», кликов нет;
# в каждой передышке бот тратит всё золото. Сила игрока и врага — bench/balance/strength.gd.
# Товары: 0 inf_pack, 1 archer_pack, 2 weapons, 3 gate.
const STRENGTH := preload("res://bench/balance/strength.gd")
const CARDS := preload("res://scripts/cards.gd")
const WAR_CRY_DIST := 400.0
const WAR_CRY_EVERY := 5

# Хоть один живой зомби ближе WAR_CRY_DIST к центру любого занятого отряда игрока.
func zombie_near(m: Node2D) -> bool:
	var d2 := WAR_CRY_DIST * WAR_CRY_DIST
	for s in m.SQUAD_MAX:
		if m.squad_used[s] != 1 or m.squad_n[s] == 0:
			continue
		var c: Vector2 = m.squad_pos[s]
		for i in m.count:
			if m.team[i] == 1 and m.pos[i].distance_squared_to(c) < d2:
				return true
	return false
const WAVE_CAP := 40
const CYCLES := {"B1": [0, 2, 1, 3], "B2": [0, 2], "B3": [3], "B5": [0, 1], "B6": [2, 0, 2, 1], "B7": [0, 1], "B8": [0, 1, 4, 1]}
# B8 (задача 8): как B7, но по кругу пехота, лучники, копейщики, лучники — половина «пехотных» покупок уходит на копейщиков; «держать» —
# отрядам пехоты и копейщиков. --army spear (равный бюджет): стартовые 300 пехоты заменяются копейщиками на ту же цену (200 при цене
# 3 против 2 золота за юнита), а «пехотные» покупки бота (товар 0) идут на копейщиков (товар 4). --hold off — бот не ставит «держать».
# B7 (задача 6b): покупки как у B5 (по кругу пехота, лучники); перед ними — ремонт ворот, если их HP ниже B7_REPAIR_BELOW от максимума и хватает
# золота; перед стартом каждой волны — приказ «держать» всем отрядам пехоты. На сигнал всплеска не реагирует. Пишет строки лога B7,...
const B7_REPAIR_BELOW := 0.6

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
	var opt := {}   # --gifts, --cards, --pick, --variants -> значение
	for key in ["--gifts", "--cards", "--pick", "--variants", "--war-cry", "--hp-spread", "--army", "--hold"]:
		var at := args.find(key)
		if at >= 0:
			opt[key] = String(args[at + 1]) if at + 1 < args.size() else ""
			args = args.slice(0, at) + args.slice(at + 2)
	var gifts := {}
	for part in String(opt.get("--gifts", "")).split(",", false):
		gifts[part.get_slice(":", 0)] = int(part.get_slice(":", 1))
	var bot: String = args[0]
	var seed := int(args[1])
	var m: Node2D = load("res://scripts/main.gd").new()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = seed
	m.debug_layer = 1
	m.active_gifts = gifts
	var rng := RandomNumberGenerator.new()   # генератор забега бенча: результат карточки 30, тройки и выбор бота; не ГСЧ симуляции
	rng.seed = seed
	if opt.has("--variants"):
		var merged: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json")) + JSON.parse_string(FileAccess.get_file_as_string(opt["--variants"]))
		var path := "user://cards_variants_%d_%d.json" % [OS.get_process_id(), seed]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(merged))
		f.close()
		m.cards_path = path
	var defs := CARDS.load_cards(m.cards_path)
	for id in String(opt.get("--cards", "")).split(",", false):
		if not defs.has(id):
			push_error("--cards: нет карточки %s" % id)
			m.free()
			quit(1)
			return
		m.active_cards.append(CARDS.make_record(defs[id], rng))
	if opt.get("--pick", "") == "random":
		m.card_pick_auto = "random"
		m.bench_card_rng = rng
	m._setup_data()
	if opt.has("--variants"):
		DirAccess.remove_absolute(m.cards_path)
	if opt.has("--hp-spread") and not m.type_id.is_empty():
		m.wave_cfg.hp_spread = float(opt["--hp-spread"])
	var army_spear: bool = opt.get("--army", "inf") == "spear"
	var holds: bool = bot in ["B7", "B8"] and opt.get("--hold", "on") != "off"
	if army_spear and not m.type_id.is_empty():
		var ki: int = m.SHOP_ITEMS.find("inf_pack")
		var ks: int = m.SHOP_ITEMS.find("spear_pack")
		var keep := roundi(m.squad_n[0] * (m.shop_base[ki] / m.shop_param[ki]) / (m.shop_base[ks] / m.shop_param[ks]))   # 300 x 2 / 3 = 200
		var seen := 0
		for i in m.count:
			if m.unit_squad[i] == 0:
				m.unit_type[i] = m.spearman_type
				m.hp[i] = m.type_hp[m.spearman_type]
				seen += 1
				if seen > keep:
					m.hp[i] = 0.0
		m._remove_dead()
		m.squad_type[0] = m.spearman_type
		m.squad_speed[0] = 0.75 * m.type_speed[m.spearman_type]
		print("ARMY,spear,%d" % m.squad_n[0])
	if m.type_id.is_empty():
		m.free()
		quit(1)   # данные или набор даров не загрузились: ошибка уже в stderr
		return
	var mult := float(args[2]) if args.size() > 2 else 1.0
	if mult != 1.0:
		for key in ["count_base", "count_step", "knight_per_wave"]:
			m.wave_cfg[key] *= mult
		m.wave_plan_for = -1   # план волны 1 построен до правки: _start_wave построит заново
	var war_cry_on: bool = opt.get("--war-cry", "on") != "off"
	var battle_ticks := 0
	var ptr := 0
	var defeat := 0
	var full := 1
	while m.wave_number < WAVE_CAP:
		if not m.pending_offer.is_empty():   # --pick random: после волн выбора бот берёт случайную карточку тройки
			m.choose_card(m.pending_offer[rng.randi_range(0, m.pending_offer.size() - 1)])
		var gold_start := floori(m.gold)
		if bot == "B4":
			# оружие, пока хватает золота; остаток — в пехоту
			while m._buy(2):
				pass
			while m._buy(0):
				pass
		else:
			if bot in ["B7", "B8"] and m.gate_hp < B7_REPAIR_BELOW * m.gate_hp_max:
				var price: float = m._price(3)
				var hp0: float = m.gate_hp
				if m._buy(3):
					print("%s,%d,repair,ворота %.0f/%.0f -> %.0f/%.0f, цена %.0f" % [bot, m.wave_number, hp0, m.gate_hp_max - m.shop_param[3], m.gate_hp, m.gate_hp_max, price])
				else:
					print("%s,%d,repair_skip,ворота %.0f/%.0f, золота %.0f < %.0f" % [bot, m.wave_number, hp0, m.gate_hp_max, m.gold, price])
			var cycle: Array = CYCLES[bot]
			while true:
				var bought := false
				for k in cycle.size():
					var item: int = cycle[(ptr + k) % cycle.size()]
					if army_spear and item == 0:
						item = 4   # равный бюджет: вместо пехоты — копейщики
					if m._buy(item):
						ptr = (ptr + k + 1) % cycle.size()
						bought = true
						break
				if not bought:
					break
		var gold_bought := floori(m.gold)   # золото в начале волны после покупок
		var p_bp: Dictionary = STRENGTH.player(m, true)   # сила игрока по порогам урона
		var inf := count_type(m, m.infantry_type)
		var arch := count_type(m, m.archer_type)
		var gate0 := ceili(maxf(m.gate_hp, 0.0))
		var p: Dictionary = STRENGTH.player(m)
		if holds:
			var held := PackedStringArray()
			for sq in m.SQUAD_MAX:
				if m.squad_used[sq] == 1 and m.squad_n[sq] > 0 and (m.squad_type[sq] == m.infantry_type or m.squad_type[sq] == m.spearman_type):
					m.squad_order[sq] = m.ORDER_HOLD
					held.append("%d (%d)" % [sq, m.squad_n[sq]])
			print("%s,%d,hold,отряды пехоты и копейщиков: %s" % [bot, m.wave_number + 1, ", ".join(held)])
		m._start_wave()
		var e: Dictionary = STRENGTH.enemy(m)
		var ticks := 0
		while m.wave_state == m.WS_BATTLE and ticks < 30 * 1200:
			if war_cry_on and m.war_cry_level > 0 and ticks % WAR_CRY_EVERY == 0 and m.war_cry_can() and zombie_near(m):
				m.request_war_cry()
			m._physics_process(1.0 / 30.0)
			ticks += 1
		battle_ticks += ticks
		var lost := inf + arch - count_type(m, m.infantry_type) - count_type(m, m.archer_type)
		# поля 17-18 (с нуля от WAVE): золото после покупок и убито зомби за волну (из e.n в поле 9); 19 — dps игрока по порогам урона
		print("WAVE,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.1f,%d,%d,%.4f" % [bot, seed, m.wave_number, inf, arch, m.shop_bought[2], gold_start, lost, e.n,
			gate0, ceili(maxf(m.gate_hp, 0.0)), p.hp, p.dps, e.hp, e.dps, ticks / 30.0, gold_bought, m.wave_kills, p_bp.dps])
		if m.wave_state == m.WS_DEFEAT:
			defeat = m.wave_number
			break
		if m.wave_state == m.WS_BATTLE:
			full = 0
			break
	print("RUN,%s,%d,%d,%d,%d" % [bot, seed, defeat, full, floori(m.gold)])
	print("WARCRY,%d,%d,%d" % [m.war_cry_uses, m.war_cry_active_ticks, battle_ticks])   # последнее поле — золото, не потраченное к концу забега
	print("CARDS," + ",".join(m.active_cards.map(func(r): return r.id + ("" if not r.has("result") else ":" + r.result.good))))   # выбранные карточки (30 — с целью x1.5)
	m.free()
	quit()
