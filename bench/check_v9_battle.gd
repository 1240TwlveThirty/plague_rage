extends SceneTree
# Бой main.gd. Аргументы: <секунд> [click|behind] [секунда] [x y]
#   click: в заданную секунду squad_target[0] = (x, y)
#   behind: в заданную секунду отряд 0 получает цель в 150 px за спиной; следим за отрядом 1 следующие 5 с
func shape(m: Node2D, s: int) -> String:
	var width: int = m.squad_width[s]
	var h := {}
	var n := 0
	for i in m.count:
		if m.unit_squad[i] == s:
			var c: int = m.unit_slot_idx[i] % width
			h[c] = h.get(c, 0) + 1
			n += 1
	var lo := 999
	var hi := 0
	for c in h:
		lo = mini(lo, h[c])
		hi = maxi(hi, h[c])
	return "отряд %d: живых %d, сетка %d x %d, колонок занято %d, глубина колонок min %d / max %d" % [s, n, width, m.squad_rows[s], h.size(), lo, hi]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0])
	var mode := args[1] if args.size() > 1 else ""
	var ev_tick := int(args[2]) * 30 if args.size() > 2 else -1
	var click_pos := Vector2(float(args[3]), float(args[4])) if args.size() > 4 else Vector2.ZERO
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	var max_ms := 0.0
	var first_death := -1
	var last_death := -1
	var freezes: Array[String] = []
	var shape_done := [false, false]
	var a := [0, 0]
	var ref_angle := 0.0
	var turns := 0
	var flips := 0
	var max_dev := 0.0
	var over := false
	var prev_angle: float = m.squad_angle[1]
	for t in range(1, secs * 30 + 1):
		if t == ev_tick:
			if mode == "click":
				m.squad_target[0] = click_pos
				print("  -- t=%.1f с: отряд 0 получил цель %s" % [t / 30.0, click_pos])
			elif mode == "behind":
				var tgt: Vector2 = m.squad_pos[0] - Vector2.from_angle(m.squad_angle[0]) * 150.0
				m.squad_target[0] = tgt
				ref_angle = m.squad_angle[1]
				print("  -- t=%.1f с: отряд 0 получил цель сзади %s; живых %d:%d; контакт отряда 1 = %.2f" % [t / 30.0, tgt.round(), a[0], a[1], m.squad_contact_t[1]])
		var before: int = m.count
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		max_ms = maxf(max_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		var ang: float = m.squad_angle[1]
		if mode == "behind" and t > ev_tick and t <= ev_tick + 150:
			if absf(angle_difference(prev_angle, ang)) > 2.0:
				flips += 1
			var dev := absf(angle_difference(ref_angle, ang))
			max_dev = maxf(max_dev, dev)
			if dev > 0.3 and not over:
				turns += 1
			over = dev > 0.3
		prev_angle = ang
		a = [0, 0]
		for i in m.count:
			a[m.team[i]] += 1
		for s in 2:
			if not shape_done[s] and a[s] <= 80 and a[s] > 0:
				shape_done[s] = true
				print("  (д) t=%.1f с, %s" % [t / 30.0, shape(m, s)])
		if m.count < before:
			if first_death < 0:
				first_death = t
			elif t - last_death >= 90:
				freezes.append("%.1f–%.1f с, остаток до паузы %d:%d" % [last_death / 30.0, t / 30.0, a[0], a[1]])
			last_death = t
		if t % 90 == 0:
			print("t=%2d с  team0=%3d team1=%3d  squad0=%s squad1=%s" % [t / 30, a[0], a[1], m.squad_pos[0].round(), m.squad_pos[1].round()])
		if a[0] == 0 or a[1] == 0:
			print("t=%.1f с: одна команда уничтожена, %d:%d" % [t / 30.0, a[0], a[1]])
			break
	if mode == "behind":
		print("(в) отряд 1 за 5 с после приказа: отклонений угла > 0.3 рад: %d (max %.3f рад), разворотов «кругом»: %d" % [turns, max_dev, flips])
	var tail := ""
	if last_death > 0 and a[0] > 0 and a[1] > 0:
		tail = "; с %.1f с до конца без смертей, остаток %d:%d" % [last_death / 30.0, a[0], a[1]]
	print("first_death=%.1f с  max_tick=%.2f мс  паузы >= 3 с посреди боя: %s%s" % [first_death / 30.0, max_ms, "нет" if freezes.is_empty() else "; ".join(freezes), tail])
	m.free()
	quit()