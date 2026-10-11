extends SceneTree
func new_main(path: String, seed: int, waves: bool) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m

func run_waves(seed: int) -> PackedVector2Array:
	var m := new_main("res://scripts/main.gd", seed, true)
	var tr := PackedVector2Array()
	var done := 0
	for t in 30 * 900:
		if m.wave_state == m.WS_RESPITE:
			if done == 3:
				break
			m._start_wave()
			done += 1
		m._physics_process(1.0 / 30.0)
		var s := Vector2.ZERO
		for i in m.count:
			s += m.pos[i] * (1.0 + (i % 7)) + Vector2(m.hp[i], m.count)
		tr.append(s)
		if m.wave_state == m.WS_DEFEAT:
			break
	m.free()
	return tr

func _initialize() -> void:
	# (а)
	var a := new_main("res://bench/old/main_bak25.gd", 1, false)
	var b := new_main("res://scripts/main.gd", 1, false)
	var first := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0:
			if a.count != b.count:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i]:
						first = t
						break
	print("(а) waves off против bak25 (оба на текущих JSON, HP зомби 1.8): " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first) + "; ворота %.0f / %.0f" % [a.gate_hp, b.gate_hp])
	a.free()
	b.free()
	# (б)
	var r1 := run_waves(5)
	var r2 := run_waves(5)
	var d := -1
	for k in mini(r1.size(), r2.size()):
		if r1[k] != r2[k]:
			d = k
			break
	print("(б) 3 волны, seed 5: тиков %d / %d, %s" % [r1.size(), r2.size(), "совпадает на каждом тике" if d < 0 and r1.size() == r2.size() else "расходится с тика %d" % d])
	# (в) покупка ворот
	var m := new_main("res://scripts/main.gd", 2, true)
	m.gold = 1e9
	var gain: float = m.shop_param[3]
	var prices := []
	var exact := true
	m.gate_hp = 1000.0   # ворота побиты: покупка чинит до нового максимума
	for k in 20:
		var price: float = m._price(3)
		var expect: float = m.shop_base[3] * (1.0 + m.shop_growth[3] * k)
		var mx0: float = m.gate_hp_max
		var g0: float = m.gold
		m._buy(3)
		exact = exact and is_equal_approx(price, expect) and is_equal_approx(g0 - m.gold, price) and m.gate_hp_max == mx0 + gain and m.gate_hp == m.gate_hp_max
		if k < 4:
			prices.append(price)
	print("(в) gate_max_gain %.0f: цены первых покупок %s (формула 120·(1+0.3·n)); после 20 покупок max %.0f (ожидается %.0f), текущее %.0f; каждая покупка ровно +%.0f и ремонт до максимума: %s" % [
		gain, prices, m.gate_hp_max, 1500.0 + 20.0 * gain, m.gate_hp, gain, exact])
	m.free()
	quit()