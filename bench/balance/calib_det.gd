extends SceneTree
# Калибровка осады I, этап 2: детерминизм на рабочих данных. Два экземпляра scripts/main.gd с одним seed идут бок о бок,
# pos, hp, cooldown, count, золото, ворота, стрелы сравниваются на каждом тике (как в bench/regress.gd).
# (1) волны 1-3 с покупками бота B5 (пехота, лучники по кругу), seed 4; (2) волна 10, seed 2, до конца (не дольше 120 с).
const MAIN := "res://scripts/main.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(rng_seed: int) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()   # бенч без каркаса забега: слой DEBUG_LAYER, волны без предела
	var a := make(4)
	var b := make(4)
	var first := -1
	var ticks := 0
	for w in 3:
		for x in [a, b]:
			var k := 0
			while x._buy(k % 2) or x._buy((k + 1) % 2):
				k += 1
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 600:
			a._physics_process(DT)
			b._physics_process(DT)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
	check("волны 1-3 с покупками (seed 4, %d тиков, волна %d, зомби в волне 3: %d, юнитов %d): два прогона бит в бит на каждом тике" % [ticks, b.wave_number, b._wave_count(3), b.count],
		first < 0 and a.wave_number == 3 and b.wave_number == 3 and ticks > 300, "" if first < 0 else "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	a = make(2)
	b = make(2)
	for x in [a, b]:
		x.wave_number = 9
		x.wave_plan_for = -1
		x.gate_hp = 1e9
		x.gate_hp_max = 1e9
		x._start_wave()
	first = -1
	ticks = 0
	while a.wave_state == a.WS_BATTLE and ticks < 3600:
		a._physics_process(DT)
		b._physics_process(DT)
		ticks += 1
		if first < 0 and not same(a, b):
			first = ticks
	check("волна 10 (seed 2, %d тиков, зомби в волне %d, юнитов в конце %d): два прогона бит в бит на каждом тике" % [ticks, b._wave_count(10), b.count], first < 0 and ticks > 300,
		"" if first < 0 else "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	print("DET: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
