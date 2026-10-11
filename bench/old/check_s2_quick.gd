extends SceneTree
func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i]:
			return false
	return true

func _initialize() -> void:
	var a: Node2D = load("res://bench/old/main_bak22.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	b.waves_enabled = false
	a._setup_data()
	b._setup_data()
	var first := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and not same(a, b):
			first = t
	print("(а) waves off против bak22: " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first))
	a.free()
	b.free()
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	print("волны: состояние %d, юнитов %d, золото %.0f" % [m.wave_state, m.count, m.gold])
	m._start_wave()
	var spawned_max := 0
	for t in range(1, 60 * 30 + 1):
		m._physics_process(1.0 / 30.0)
		spawned_max = maxi(spawned_max, m.zombie_alive)
		if m.wave_state != m.WS_BATTLE:
			break
	print("волна 1 (ожидается %d зомби): состояние %d, убито %d, золото %.0f, ворота %.0f, юнитов %d, max живых зомби %d" % [m._wave_count(1), m.wave_state, m.wave_kills, m.gold, m.gate_hp, m.count, spawned_max])
	print("покупка пехоты: %s, юнитов %d, ширина %d" % [m._buy(0), m.count, m.squad_width[0]])
	m.free()
	quit()