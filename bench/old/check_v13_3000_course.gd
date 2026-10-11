extends SceneTree
# Ход боя на 3000 юнитах (копии main.gd в bench/): живые каждые 3 с до 60 с.
# Варианты: ширина отряда игрока 20 (leash 24, 12, 100000) и 60 (leash 12, 24). Привязь задаётся поверх JSON.
func course(script_path: String, leash: float) -> void:
	var m: Node2D = load(script_path).new()
	m._setup_data()
	m.type_leash_sq[m.type_id["infantry"]] = leash * leash
	var a := [0, 0]
	for i in m.count:
		a[m.team[i]] += 1
	print("== %s, leash %s: игрок %d (отряд %d x %d рядов), зомби %d" % [
		script_path.get_file().get_basename(), "без привязи" if leash >= 100000.0 else "%d" % leash,
		a[0], m.squad_width[0], m.squad_rows[0], a[1]])
	var line := ""
	var end_note := ""
	for t in range(1, 60 * 30 + 1):
		m._physics_process(1.0 / 30.0)
		if t % 90 == 0:
			a = [0, 0]
			for i in m.count:
				a[m.team[i]] += 1
			line += " %d:%d" % [a[0], a[1]]
			if t % 900 == 0:
				print("   %2d–%2d с:%s" % [t / 30 - 27, t / 30, line])
				line = ""
	print("   leash_returns=%d, удары %d, блоков %.1f%%" % [m.leash_returns, m.total_hits, 100.0 * m.blocked_hits / maxi(m.total_hits, 1)])
	m.free()

func _initialize() -> void:
	course("res://bench/old/main_v13_3000_w20.gd", 24.0)
	course("res://bench/old/main_v13_3000_w20.gd", 12.0)
	course("res://bench/old/main_v13_3000_w20.gd", 100000.0)
	course("res://bench/old/main_v13_3000_w60.gd", 12.0)
	course("res://bench/old/main_v13_3000_w60.gd", 24.0)
	quit()