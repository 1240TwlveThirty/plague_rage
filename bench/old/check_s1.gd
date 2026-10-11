extends SceneTree
# Этап 1: (а) регрессия против bak21 при gate_hp = 1e9; (б) время падения ворот.
func strip_player(m: Node2D) -> void:
	for i in m.count:
		if m.team[i] == 0:
			m.hp[i] = 0.0
	m._remove_dead()
	m.squad_dirty.fill(0)

func regress(label: String, no_player: bool) -> void:
	var a: Node2D = load("res://bench/old/main_bak21.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a._setup_data()
	b._setup_data()
	b.gate_hp = 1e9
	b.gate_hp_max = 1e9
	if no_player:
		strip_player(a)
		strip_player(b)
	var first := -1
	var gate_tick := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if gate_tick < 0:
			for i in b.count:
				var p: Vector2 = b.pos[i]
				if b.team[i] == 1 and p.y >= b.WALL_Y - 7.0 and absf(p.x - b.GATE_POS.x) <= b.gate_half + 6.0:
					gate_tick = t
					break
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp):
			first = t
	print("  %s: %s; первый зомби в зоне ворот: %s; ударов по воротам %d" % [label,
		"совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d (%.1f с)" % [first, first / 30.0],
		"тик %d (%.1f с)" % [gate_tick, gate_tick / 30.0] if gate_tick > 0 else "нет", b.gate_hits])
	a.free()
	b.free()

func fall_time(n: int, ghp: float) -> String:
	var m: Node2D = load("res://bench/old/main_v21_800.gd").new()
	m.record_path = "user://record_bench.json"
	m._setup_data()
	strip_player(m)
	var keep := 0
	for i in m.count:
		if m.team[i] == 1:
			keep += 1
			if keep > n:
				m.hp[i] = 0.0
	m._remove_dead()
	m.gate_hp = ghp
	m.gate_hp_max = ghp
	var first_hit := -1
	for t in range(1, 180 * 30 + 1):
		m._physics_process(1.0 / 30.0)
		if first_hit < 0 and m.gate_hits > 0:
			first_hit = t
		if m.wave_state == m.WS_DEFEAT:
			var res := "%.1f с (первый удар %.1f с, ломают %.1f с)" % [t / 30.0, first_hit / 30.0, (t - first_hit) / 30.0]
			m.free()
			return res
	m.free()
	return "не пали за 180 с"

func _initialize() -> void:
	print("(а) регрессия против bak21, gate_hp = 1e9:")
	regress("с игроком", false)
	regress("без игрока", true)
	print("(б) без игрока, время до падения ворот:")
	for n in [20, 50, 100, 200, 400]:
		print("  %3d зомби: hp 200 — %s; hp 600 — %s" % [n, fall_time(n, 200.0), fall_time(n, 600.0)])
	quit()