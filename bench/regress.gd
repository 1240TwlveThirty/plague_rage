extends SceneTree
# Регрессия состояния против эталона: рабочий scripts/main.gd и bench/ref/main_ref.gd (python bench/make_ref.py) бок о бок,
# без команд игрока; pos, hp, cooldown, count, золото, ворота, стрелы сравниваются на каждом тике.
# (1) 30 с без волн, seed 5; (2) 3 волны слоя по умолчанию с покупками, seed 7; (3) волна 10, seed 3, до конца (не дольше 60 с).
# Расходится — значит правка изменила симуляцию: либо это ошибка, либо так задумано и эталон пора обновить.
const REF := "res://bench/ref/main_ref.gd"
const NEW := "res://scripts/main.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func plain(path: String, rng_seed: int, waves: bool) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.waves_enabled = waves
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
	print("эталон: " + FileAccess.get_file_as_string("res://bench/ref/REF.txt").strip_edges())
	var a := plain(REF, 5, false)
	var b := plain(NEW, 5, false)
	var first := -1
	for t in 900:
		a._physics_process(DT)
		b._physics_process(DT)
		if first < 0 and not same(a, b):
			first = t
	check("30 с без волн (seed 5, юнитов %d): как в эталоне на каждом тике" % b.count, first < 0, "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	a = plain(REF, 7, true)
	b = plain(NEW, 7, true)
	first = -1
	var ticks := 0
	var buys := [0, 1, 2, 0, 1, 3]
	for w in 3:
		for x in [a, b]:
			x._buy(buys[w * 2])
			x._buy(buys[w * 2 + 1])
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and ticks < 30 * 600:
			a._physics_process(DT)
			b._physics_process(DT)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
	check("3 волны с покупками (seed 7, %d тиков, волна %d, юнитов %d): как в эталоне на каждом тике" % [ticks, b.wave_number, b.count],
		first < 0 and b.wave_number == 3 and a.wave_number == 3, "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	a = plain(REF, 3, true)
	b = plain(NEW, 3, true)
	for x in [a, b]:
		x.wave_number = 9
		x.wave_plan_for = -1
		x.gate_hp = 1e9
		x.gate_hp_max = 1e9
		x._start_wave()
	first = -1
	ticks = 0
	while a.wave_state == a.WS_BATTLE and ticks < 1800:
		a._physics_process(DT)
		b._physics_process(DT)
		ticks += 1
		if first < 0 and not same(a, b):
			first = ticks
	check("волна 10 (seed 3, %d тиков, юнитов в конце %d): как в эталоне на каждом тике" % [ticks, b.count], first < 0 and ticks > 300, "первое расхождение: тик %d" % first)
	a.free()
	b.free()
	print("REGRESS: провалов %d" % fails)
	quit()
