extends SceneTree
# Время тика с бонусом к дальности лучников (задача 6, этап A): 1000 и 3000 лучников в отряде 1, волна 10 слоя 1, ворота бессмертны.
# Без модификатора и с range archer +15% (bench/fixtures_gifts/stats_v47.json, range15). Печатает PERF|лучников|дар|медиана мс|95-й перцентиль мс|выстрелов.
const DT := 1.0 / 30.0
const TICKS := 600

func run(archers: int, gifts: Dictionary) -> String:
	var m: Node2D = load("res://scripts/main.gd").new()
	m.spawn_seed = 3
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.gifts_path = "res://bench/fixtures_gifts/stats_v47.json"
	m.active_gifts = gifts
	m._setup_data()
	m._squad_add_units(1, m.archer_type, archers - m.squad_n[1])
	m.wave_number = 9
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	var times := []
	for i in TICKS:
		var t0 := Time.get_ticks_usec()
		m._physics_process(DT)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	var out := "PERF|%d|%s|%.3f|%.3f|%d" % [archers, "range+15%" if gifts.has("range15") else "без дара", times[TICKS / 2], times[TICKS * 95 / 100], m.arrows_fired]
	m.free()
	return out

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	for n in [1000, 3000]:
		for g in [{}, {"range15": 1}]:
			print(run(n, g))
	quit()
