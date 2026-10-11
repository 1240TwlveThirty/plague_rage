extends SceneTree
# (б) бой: <секунд> [click сек x y].
# Серия: series <seed_from> <seed_to> <файл.txt> — стартовые смещения ±1.5 px, seed же для unit_rand.
#   Конец боя: 3 с без смертей (считая от первой смерти) ИЛИ одна сторона уничтожена ИЛИ 60 с.
#   Итог серии пишется в res://bench/<файл.txt> (имя обязательно, чтобы не затереть прошлую базовую линию).
#   Опции после имени файла: leash=<px> (привязь infantry, вместо значения из JSON),
#   players=<N> (оставить N юнитов игрока: убираются задние ряды до начала боя),
#   main=<res://...gd> (какой скрипт симуляции взять вместо scripts/main.gd, например копию со счётчиками),
#   lstart=<px> lend=<px> (мягкая привязь infantry поверх JSON, для main.gd с leash_start/leash_end),
#   archers=0 (убрать отряд лучников, отряд 1, до начала боя).
func run(secs: int, click_tick: int, click_pos: Vector2, rng_seed: int, verbose: bool) -> String:
	var m: Node2D = load("res://scripts/main.gd").new()
	m.spawn_seed = rng_seed
	m._setup_data()
	if rng_seed > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed
		for i in m.count:
			m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var max_ms := 0.0
	var last_death := 0
	var first_death := -1
	var freezes: Array[String] = []
	var a := [0, 0]
	var end_t := secs * 30
	for t in range(1, secs * 30 + 1):
		if t == click_tick:
			m.squad_target[0] = click_pos
			if verbose:
				print("  -- t=%.1f с: отряд 0 получил цель %s" % [t / 30.0, click_pos])
		var before: int = m.count
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		max_ms = maxf(max_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		a = [0, 0]
		var zc := Vector2.ZERO
		for i in m.count:
			a[m.team[i]] += 1
			if m.team[i] == 1:
				zc += m.pos[i]
		if m.count < before:
			if first_death < 0:
				first_death = t
			elif t - last_death >= 90:
				freezes.append("%.1f–%.1f с (%d:%d)" % [last_death / 30.0, t / 30.0, a[0], a[1]])
			last_death = t
		if verbose and t % 90 == 0:
			print("t=%2d с  team0=%3d team1=%3d  squad0=%s  центр зомби=%s" % [t / 30, a[0], a[1], m.squad_pos[0].round(), (zc / maxi(a[1], 1)).round()])
		if a[0] == 0 or a[1] == 0:
			end_t = t
			break
	var winner := "draw"
	if a[0] > a[1]:
		winner = "blue"
	elif a[1] > a[0]:
		winner = "red"
	var how := "wipe" if (a[0] == 0 or a[1] == 0) else "time"
	if verbose:
		var tail := ""
		if how == "time" and last_death > 0:
			tail = "; с %.1f с до конца без смертей, остаток %d:%d" % [last_death / 30.0, a[0], a[1]]
		print("конец на %.1f с (%s), %d:%d; first_death=%.1f с  max_tick=%.2f мс  паузы >= 3 с посреди боя: %s%s" % [
			end_t / 30.0, how, a[0], a[1], first_death / 30.0, max_ms, "нет" if freezes.is_empty() else "; ".join(freezes), tail])
	m.free()
	return "%d,%s,%s,%d,%d,%d" % [rng_seed, winner, how, a[0], a[1], end_t]

# Один бой серии: [seed, потери team0, потери team1, остаток team0, остаток team1, время конца (с), причина, удары, заблокировано, leash_returns]
func series_battle(rng_seed: int, opts: Dictionary) -> Array:
	var m: Node2D = load(opts.get("main", "res://scripts/main.gd")).new()
	m.spawn_seed = rng_seed
	if "waves_enabled" in m:
		m.waves_enabled = false   # серия — старый бой без волн
	if "archers_follow" in m:
		m.archers_follow = true   # регрессия: лучники следуют за пехотой
	m._setup_data()
	if opts.has("leash"):
		m.type_leash_sq[m.type_id["infantry"]] = opts.leash * opts.leash
	if opts.has("lstart"):
		var inf: int = m.type_id["infantry"]
		m.type_leash_start[inf] = opts.lstart
		m.type_leash_start_sq[inf] = opts.lstart * opts.lstart
		m.type_leash_end[inf] = opts.lend
	if opts.has("archers") and opts.archers == 0.0:
		for i in m.count:
			if m.unit_squad[i] == 1:
				m.hp[i] = 0.0
		m._remove_dead()
		m.squad_dirty.fill(0)
	if opts.has("players"):
		# Меньше игроков: убираем задние ряды (слоты >= N), строй уплотняется до начала боя.
		for i in m.count:
			if m.unit_squad[i] == 0 and m.unit_slot_idx[i] >= opts.players:
				m.hp[i] = 0.0
		m._remove_dead()
		m._compact_squad(0)
		m.squad_dirty[0] = 0
		m.squad_reflow_n[0] = int(opts.players)
	if "first_death_tick" in m:
		m.first_death_tick = -1   # убитые при подготовке (players=, archers=0) — не начало боя
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var start := [0, 0]
	for i in m.count:
		start[m.team[i]] += 1
	var a: Array = start.duplicate()
	var last_death := -1
	var end_t := 60 * 30
	var why := "60 с"
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if m.count < before:
			last_death = t
			a = [0, 0]
			for i in m.count:
				a[m.team[i]] += 1
		if a[0] == 0 or a[1] == 0:
			end_t = t
			why = "уничтожена team %d" % (0 if a[0] == 0 else 1)
			break
		if last_death > 0 and t - last_death >= 90:
			end_t = t
			why = "3 с без смертей"
			break
	var hits: int = m.get("total_hits") if "total_hits" in m else 0
	var blocked: int = m.get("blocked_hits") if "blocked_hits" in m else 0
	var leash_ret: int = 0   # leash_ticks (мягкая привязь) или leash_returns (жёсткая)
	if "leash_ticks" in m:
		leash_ret = m.leash_ticks
	elif "leash_returns" in m:
		leash_ret = m.leash_returns
	var arrows := [0, 0, 0.0, 0.0]   # выпущено, попало, средние reach и расстояние до фронта (если скрипт стреляет)
	if "arrows_fired" in m:
		arrows = [m.arrows_fired, m.arrows_hit, 0.0, 0.0]
	if "reach_n" in m and m.reach_n > 0:
		arrows[2] = m.reach_sum / m.reach_n
		arrows[3] = m.reach_dist_sum / m.reach_n
	var rows := [0, 0, 0, 0]   # перед: всего, блок; остальные: всего, блок (если скрипт их считает)
	if "inf_front_total" in m:
		rows = [m.inf_front_total, m.inf_front_blocked, m.inf_rest_total, m.inf_rest_blocked]
	m.free()
	return [rng_seed, start[0] - a[0], start[1] - a[1], a[0], a[1], end_t / 30.0, why, hits, blocked, leash_ret, rows, arrows, start[0]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args[0] != "series":
		var click_tick := int(args[2]) * 30 if args.size() > 4 else -1
		var click_pos := Vector2(float(args[3]), float(args[4])) if args.size() > 4 else Vector2.ZERO
		run(int(args[0]), click_tick, click_pos, 0, true)
		quit()
		return
	if args.size() < 4:
		print("нужно имя файла итога: series <seed_from> <seed_to> <файл.txt>")
		quit()
		return
	var out_name := args[3]
	var opts := {}
	for k in range(4, args.size()):
		var kv := args[k].split("=")
		opts[kv[0]] = kv[1] if kv[0] == "main" else float(kv[1])
	var lines: Array[String] = []
	lines.append("%s: бои main.gd (орда зомби против отряда), seed %s..%s%s" % [out_name.get_basename(), args[1], args[2], "" if opts.is_empty() else ", опции %s" % opts])
	lines.append("Конец боя: 3 с без смертей (от первой смерти) / одна сторона уничтожена / 60 с.")
	lines.append("Отношение = потери team 1 (зомби) / потери team 0 (игрок).")
	lines.append("")
	lines.append("seed | потери t0 | потери t1 | отношение | остаток t0 | остаток t1 | конец, с | leash_ret | причина")
	var ratios := PackedFloat64Array()
	var inf_count := 0
	var sum_left := [0, 0]
	var wins := [0, 0, 0]   # team 0, team 1, ничья (по остатку)
	var sum_hits := 0
	var sum_blocked := 0
	var sum_loss0 := 0
	var sum_leash := 0
	var sum_rows := [0, 0, 0, 0]
	var sum_arrows := [0, 0, 0.0, 0.0]
	var start0 := 0
	var n := 0
	for s in range(int(args[1]), int(args[2]) + 1):
		var r := series_battle(s, opts)
		var ratio: float = INF if r[1] == 0 else float(r[2]) / r[1]
		if is_inf(ratio):
			inf_count += 1
		else:
			ratios.append(ratio)
		sum_left[0] += r[3]
		sum_left[1] += r[4]
		wins[0 if r[3] > r[4] else (1 if r[4] > r[3] else 2)] += 1
		sum_hits += r[7]
		sum_blocked += r[8]
		sum_loss0 += r[1]
		sum_leash += r[9]
		for q in 4:
			sum_rows[q] += r[10][q]
		sum_arrows[0] += r[11][0]
		sum_arrows[1] += r[11][1]
		sum_arrows[2] += r[11][2]
		sum_arrows[3] += r[11][3]
		start0 = r[12]
		n += 1
		var line := "%4d | %9d | %9d | %9s | %10d | %10d | %8.1f | %9d | %s" % [r[0], r[1], r[2], "inf" if is_inf(ratio) else "%.3f" % ratio, r[3], r[4], r[5], r[9], r[6]]
		lines.append(line)
		print(line)
	ratios.sort()
	var mean := 0.0
	for x in ratios:
		mean += x
	mean /= maxi(ratios.size(), 1)
	var k := ratios.size()
	var median := 0.0
	if k > 0:
		median = ratios[k / 2] if k % 2 == 1 else (ratios[k / 2 - 1] + ratios[k / 2]) / 2.0
	lines.append("")
	lines.append("Итог по %d боям:" % n)
	lines.append("  потери игрока (team 0, из %d на старте), среднее: %.1f" % [start0, float(sum_loss0) / n])
	lines.append("  отношение потерь t1/t0: среднее %.3f, медиана %.3f, min %.3f, max %.3f%s" % [
		mean, median, ratios[0] if k > 0 else 0.0, ratios[k - 1] if k > 0 else 0.0,
		"" if inf_count == 0 else " (ещё %d боёв без потерь t0 — отношение inf, в статистику не вошли)" % inf_count])
	lines.append("  средний остаток: team 0 (игрок) %.1f, team 1 (зомби) %.1f" % [float(sum_left[0]) / n, float(sum_left[1]) / n])
	lines.append("  победы (по остатку): team 0 %d, team 1 %d, ничьи %d" % wins)
	lines.append("  удары (total_hits): %d, заблокировано щитом %d (%.1f%%)" % [sum_hits, sum_blocked, 100.0 * sum_blocked / maxi(sum_hits, 1)])
	lines.append("  привязь на бой (leash_ticks у мягкой, leash_returns у жёсткой): %.0f" % [float(sum_leash) / n])
	if sum_arrows[0] > 0:
		lines.append("  стрелы: выпущено %d, попало %d (%.1f%%), на бой %.0f выпущено" % [sum_arrows[0], sum_arrows[1], 100.0 * sum_arrows[1] / sum_arrows[0], float(sum_arrows[0]) / n])
		if sum_arrows[3] != 0.0:
			lines.append("  досягаемость (первые 10 с до контакта): центр лучников -> передний ряд пехоты %.1f px, reach = range_far - это = %.1f px" % [sum_arrows[3] / n, sum_arrows[2] / n])
	if sum_rows[0] + sum_rows[2] > 0:
		lines.append("  удары по infantry, передний занятый ряд: %d, заблокировано %d (%.1f%%)" % [sum_rows[0], sum_rows[1], 100.0 * sum_rows[1] / maxi(sum_rows[0], 1)])
		lines.append("  удары по infantry, остальные ряды: %d, заблокировано %d (%.1f%%)" % [sum_rows[2], sum_rows[3], 100.0 * sum_rows[3] / maxi(sum_rows[2], 1)])
	var f := FileAccess.open("res://bench/" + out_name, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	var shown := 0
	for i in range(lines.size() - 1, -1, -1):   # печатаем итог: строки после "Итог по"
		if lines[i].begins_with("Итог по"):
			shown = i
			break
	for i in range(shown, lines.size()):
		print(lines[i])
	quit()