extends SceneTree
# Тесты задачи 6b, этап 3: разброс HP зомби (data/waves.json hp_spread). При s = 0 — бит в бит с эталоном; при s > 0 — множители в [1 − s, 1 + s],
# воспроизводимы (тот же seed, волна и номер зомби — тот же множитель), среднее около 1, разные seed — разные множители;
# HP появившихся зомби — HP типа x рост волны x множитель; два одинаковых прогона с разбросом — бит в бит; ГСЧ симуляции не сдвигается.
const MAIN := "res://scripts/main.gd"
const REF := "res://bench/ref/main_ref.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(path: String, spread: float, rng_seed := 3) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m._setup_data()
	if path == MAIN:
		m.wave_cfg.hp_spread = spread
	return m

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func lockstep(a: Node2D, b: Node2D, waves: int) -> int:
	var t := 0
	for w in waves:
		for x in [a, b]:
			x._buy(w % 2)
			x._start_wave()
		while a.wave_state == a.WS_BATTLE and t < 30 * 600:
			a._physics_process(DT)
			b._physics_process(DT)
			t += 1
			if not same(a, b):
				return t
	return -1

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	print("разброс HP зомби")
	var m := make(MAIN, 0.0)
	check("в data/waves.json hp_spread = 0 (выключено)", m.wave_cfg.hp_spread == 0.0)
	m.free()
	var a := make(REF, 0.0)
	var b := make(MAIN, 0.0)
	var first := lockstep(a, b, 2)
	check("s = 0: 2 волны с покупками бит в бит с эталоном", first < 0, "расхождение на тике %d" % first)
	a.free()
	b.free()
	var main_script: GDScript = load(MAIN)
	var ok_range := true
	var sum := 0.0
	var n := 0
	var lo := 9.0
	var hi := 0.0
	for w in range(1, 11):
		for k in 400:
			var f: float = main_script.hp_spread_factor(0.15, 7, w, k)
			ok_range = ok_range and f >= 0.85 and f <= 1.15
			sum += f
			n += 1
			lo = minf(lo, f)
			hi = maxf(hi, f)
	check("s = 0.15: 4000 множителей в [0.85, 1.15], крайние %.3f и %.3f" % [lo, hi], ok_range and lo < 0.86 and hi > 1.14)
	check("среднее множителей около 1: %.4f (допуск 0.01)" % (sum / n), absf(sum / n - 1.0) < 0.01)
	check("воспроизводимы: те же аргументы — тот же множитель; другой seed, волна или номер — другой",
		main_script.hp_spread_factor(0.15, 7, 3, 12) == main_script.hp_spread_factor(0.15, 7, 3, 12)
		and main_script.hp_spread_factor(0.15, 8, 3, 12) != main_script.hp_spread_factor(0.15, 7, 3, 12)
		and main_script.hp_spread_factor(0.15, 7, 4, 12) != main_script.hp_spread_factor(0.15, 7, 3, 12)
		and main_script.hp_spread_factor(0.15, 7, 3, 13) != main_script.hp_spread_factor(0.15, 7, 3, 12))
	var z := make(MAIN, 0.2)
	z._start_wave()
	var t := 0
	while z.zombie_alive == 0 and t < 30 * 30:
		z._physics_process(DT)
		t += 1
	var spawned := []
	for i in z.count:
		if z.team[i] == 1:
			spawned.append(z.hp[i] / (z.type_hp[z.unit_type[i]] * z.wave_hp_mult))
	var all_in: bool = not spawned.is_empty() and spawned.all(func(f): return f >= 0.8 - 1e-5 and f <= 1.2 + 1e-5)
	var distinct := {}
	for f in spawned:
		distinct[snappedf(f, 0.0001)] = true
	check("s = 0.2 в бою: у %d появившихся зомби HP = HP типа x множитель в [0.8, 1.2], множители разные (%d разных)" % [spawned.size(), distinct.size()],
		all_in and distinct.size() > spawned.size() / 2 and z.wave_spawned == spawned.size())
	z.free()
	var c := make(MAIN, 0.15, 5)
	var d := make(MAIN, 0.15, 5)
	first = lockstep(c, d, 3)
	check("s = 0.15: два одинаковых прогона (3 волны с покупками) бит в бит", first < 0, "расхождение на тике %d" % first)
	var e := make(MAIN, 0.0, 5)
	var f2 := make(MAIN, 0.15, 5)
	for x in [e, f2]:
		x._start_wave()
	for i in 60:
		e._physics_process(DT)
		f2._physics_process(DT)
	var pos_same: bool = e.count == f2.count
	for i in mini(e.count, f2.count):
		pos_same = pos_same and e.pos[i] == f2.pos[i]
	check("разброс не сдвигает ГСЧ симуляции: первые 60 тиков (до боя) позиции и число юнитов как при s = 0", pos_same)
	for x in [c, d, e, f2]:
		x.free()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
