extends SceneTree
# Бой main.gd: аргументы <секунд> [секунда_клика x y]. Отчёт каждые 3 с + поиск «застываний».
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 60
	var click_tick := int(args[1]) * 30 if args.size() > 3 else -1
	var click_pos := Vector2(float(args[2]), float(args[3])) if args.size() > 3 else Vector2.ZERO
	var m: Node2D = load("res://scripts/main.gd").new()
	m._setup_data()
	var max_ms := 0.0
	var first_death := -1
	var last_death := -1
	var freezes: Array[String] = []
	var a := [0, 0]
	for t in range(1, secs * 30 + 1):
		if t == click_tick:
			m.squad_target[0] = click_pos
			print("  -- t=%.1f s: отряд 0 получил цель %s" % [t / 30.0, click_pos])
		var before: int = m.count
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		max_ms = maxf(max_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		a = [0, 0]
		for i in m.count:
			a[m.team[i]] += 1
		if m.count < before:
			if first_death < 0:
				first_death = t
			elif t - last_death >= 90:
				freezes.append("%.1f–%.1f с (%.1f с), остатки до паузы %d:%d" % [last_death / 30.0, t / 30.0, (t - last_death) / 30.0, a[0], a[1]])
			last_death = t
		if t % 90 == 0:
			print("t=%2d s  team0=%3d team1=%3d  squad0=%s squad1=%s" % [t / 30, a[0], a[1], m.squad_pos[0].round(), m.squad_pos[1].round()])
		if a[0] == 0 or a[1] == 0:
			print("t=%.1f s: одна команда уничтожена, team0=%d team1=%d" % [t / 30.0, a[0], a[1]])
			break
	var tail := ""
	if last_death > 0 and a[0] > 0 and a[1] > 0:
		tail = "; после последней смерти (%.1f с) до конца прогона без смертей %.1f с, остатки %d:%d" % [last_death / 30.0, secs - last_death / 30.0, a[0], a[1]]
	print("first_death=%.1f s  max_tick=%.2f ms" % [first_death / 30.0, max_ms])
	print("паузы >= 3 с без смертей посреди боя: %s%s" % ["нет" if freezes.is_empty() else "; ".join(freezes), tail])
	m.free()
	quit()