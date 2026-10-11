extends SceneTree
# Старый (bench/main_old.gd = main.gd.bak8) и новый main.gd бок о бок; сравнение состояния каждый тик.
# Аргументы: <секунд> [секунда_клика x y]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 60
	var click_tick := int(args[1]) * 30 if args.size() > 3 else -1
	var click_pos := Vector2(float(args[2]), float(args[3])) if args.size() > 3 else Vector2.ZERO
	var a: Node2D = load("res://bench/old/main_old.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a._setup_data()
	b._setup_data()
	var first_diff := -1
	for t in range(1, secs * 30 + 1):
		if t == click_tick:
			a.squad_target[0] = click_pos
			b.squad_target[0] = click_pos
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first_diff < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp or a.squad_pos != b.squad_pos):
			first_diff = t
		if t % 90 == 0:
			var ca := [0, 0]
			var cb := [0, 0]
			for i in a.count:
				ca[a.team[i]] += 1
			for i in b.count:
				cb[b.team[i]] += 1
			print("t=%2d s  старая %3d:%3d   новая %3d:%3d  %s" % [t / 30, ca[0], ca[1], cb[0], cb[1], "=" if ca == cb else "РАЗНИЦА"])
	print("полное состояние (pos, hp, count, squad_pos): " + ("совпадает на всех %d тиках" % (secs * 30) if first_diff < 0 else "впервые расходится на тике %d" % first_diff))
	a.free()
	b.free()
	quit()