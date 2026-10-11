extends SceneTree
# Тесты v35 (масштаб мира ×4/3). Режимы:
#   series <main.gd> <файл.txt> — 50 боёв 300 пехоты + 100 лучников против 300 зомби (как baseline_v31), плюс
#       время до первого контакта (первый юнит в ST_ATTACK) и стрелы за бой;
#   dims <main.gd> — длины сеток, размеры строя 300 пехоты, 1400 пехоты + 300 лучников;
#   det <main.gd> — детерминизм 30 с, два прогона (волна 1 слоя 1);
#   tick <main_3000.gd> — средний тик плотной фазы на 3000 юнитах (как time_v31_3000).

func battle(path: String, rng_seed: int) -> Array:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.waves_enabled = false
	m.archers_follow = true
	m.record_path = "user://record_bench.json"
	m._setup_data()
	m.first_death_tick = -1
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
	var contact := -1
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if contact < 0:
			for i in m.count:
				if m.unit_state[i] == m.ST_ATTACK:
					contact = t
					break
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
	var r := [rng_seed, start[0] - a[0], start[1] - a[1], a[0], a[1], end_t / 30.0, why, m.leash_ticks, contact / 30.0, m.arrows_fired, m.arrows_hit]
	m.free()
	return r


func series(path: String, out_name: String) -> void:
	var lines: Array[String] = []
	lines.append("%s: бои %s (орда зомби против отряда), seed 1..50" % [out_name.get_basename(), path])
	lines.append("Конец боя: 3 с без смертей (от первой смерти) / одна сторона уничтожена / 60 с.")
	lines.append("Отношение = потери team 1 (зомби) / потери team 0 (игрок). Контакт = первый юнит в состоянии «бьёт».")
	lines.append("")
	lines.append("seed | потери t0 | потери t1 | отношение | остаток t0 | остаток t1 | конец, с | leash_ret | контакт, с | стрел | попало | причина")
	var ratios := PackedFloat64Array()
	var sums := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # потери t0, остаток t0, остаток t1, контакт, стрел, попало
	for s in range(1, 51):
		var r := battle(path, s)
		var ratio: float = float(r[2]) / maxi(r[1], 1)
		ratios.append(ratio)
		sums[0] += r[1]
		sums[1] += r[3]
		sums[2] += r[4]
		sums[3] += r[8]
		sums[4] += r[9]
		sums[5] += r[10]
		lines.append("%4d | %9d | %9d | %9.3f | %10d | %10d | %8.1f | %9d | %10.2f | %5d | %6d | %s" % [r[0], r[1], r[2], ratio, r[3], r[4], r[5], r[7], r[8], r[9], r[10], r[6]])
	var mean := 0.0
	for x in ratios:
		mean += x
	mean /= ratios.size()
	var sorted := ratios.duplicate()
	sorted.sort()
	lines.append("")
	lines.append("Итог по 50 боям:")
	lines.append("  потери игрока (team 0, из 400 на старте), среднее: %.1f" % (sums[0] / 50.0))
	lines.append("  отношение потерь t1/t0: среднее %.3f, медиана %.3f, min %.3f, max %.3f" % [mean, (sorted[24] + sorted[25]) * 0.5, sorted[0], sorted[49]])
	lines.append("  средний остаток: team 0 (игрок) %.1f, team 1 (зомби) %.1f" % [sums[1] / 50.0, sums[2] / 50.0])
	lines.append("  первый контакт, среднее: %.2f с; стрел за бой: выпущено %.1f, попало %.1f (%.1f%%)" % [sums[3] / 50.0, sums[4] / 50.0, sums[5] / 50.0, 100.0 * sums[5] / maxf(sums[4], 1.0)])
	var f := FileAccess.open("res://bench/" + out_name, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	for k in range(lines.size() - 5, lines.size()):
		print(lines[k])


func new_main(path: String, rng_seed: int) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = rng_seed
	m.record_path = "user://record_bench.json"
	m._setup_data()
	return m


# Границы мировых позиций слотов отряда s: [lo, hi]; и размеры строя в его локальных осях (ширина поперёк лица, глубина).
func extent(m: Node2D, s: int) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var llo := Vector2(INF, INF)
	var lhi := Vector2(-INF, -INF)
	for i in m.count:
		if m.unit_squad[i] == s:
			var w: Vector2 = m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])
			lo = lo.min(w)
			hi = hi.max(w)
			llo = llo.min(m.unit_slot[i])
			lhi = lhi.max(m.unit_slot[i])
	return [lo, hi, lhi.y - llo.y, lhi.x - llo.x]


func fits(m: Node2D, e: Array) -> bool:
	return e[0].x >= -0.02 and e[0].y >= -0.02 and e[1].x <= m.FIELD.x + 0.02 and e[1].y <= m.WALL_Y - 12.0 + 0.02


func dims(path: String) -> void:
	var m := new_main(path, 1)
	print("DIMS сетка: CELL_SIZE %.2f, GRID %d x %d, CELL_COUNT %d, cell_start %d, cursor %d; COARSE %d x %d = %d (клетка %.2f), coarse_start %d, coarse_zcount %d, coarse_sum %d, coarse_cursor %d; FIELD %s" % [
		m.CELL_SIZE, m.GRID_W, m.GRID_H, m.CELL_COUNT, m.cell_start.size(), m.cursor.size(), m.COARSE_W, m.COARSE_H, m.COARSE_COUNT, m.COARSE_SIZE,
		m.coarse_start.size(), m.coarse_zcount.size(), m.coarse_sum.size(), m.coarse_cursor.size(), m.FIELD])
	print("DIMS покрытие: GRID_W*CELL %.2f >= %.0f, GRID_H*CELL %.2f >= %.0f; COARSE_W*SIZE %.2f, COARSE_H*SIZE %.2f" % [
		m.GRID_W * m.CELL_SIZE, m.FIELD.x, m.GRID_H * m.CELL_SIZE, m.FIELD.y, m.COARSE_W * m.COARSE_SIZE, m.COARSE_H * m.COARSE_SIZE])
	var e := extent(m, 0)
	print("DIMS300 пехота 300: сетка %d x %d, ширина %.4f px, глубина %.4f px, squad_depth %.2f; слоты y %.2f..%.2f; в поле и не ниже WALL_Y-12: %s" % [
		m.squad_width[0], m.squad_rows[0], e[2], e[3], m.squad_depth[0], e[0].y, e[1].y, fits(m, e)])
	e = extent(m, 1)
	print("DIMS300 лучники 100: сетка %d x %d, ширина %.4f px, глубина %.4f px; слоты y %.2f..%.2f; в поле и не ниже WALL_Y-12: %s" % [
		m.squad_width[1], m.squad_rows[1], e[2], e[3], e[0].y, e[1].y, fits(m, e)])
	# 1400 пехоты + 300 лучников в обход магазина, на стартовых местах
	m._squad_add_units(0, m.infantry_type, 1100)
	m._squad_add_units(1, m.archer_type, 200)
	for s in 2:
		e = extent(m, s)
		print("DIMS1400 отряд %d на старте: %d юн., сетка %d x %d, ширина %.2f, глубина %.2f; слоты x %.2f..%.2f, y %.2f..%.2f; в поле и не ниже WALL_Y-12 (%.0f): %s" % [
			s, m.squad_n[s], m.squad_width[s], m.squad_rows[s], e[2], e[3], e[0].x, e[1].x, e[0].y, e[1].y, m.WALL_Y - 12.0, fits(m, e)])
	# расстановка протяжкой у стены и у краёв: блок сдвигается внутрь
	var bad := 0
	var cases := [[Vector2(700, 740), Vector2(1300, 740)], [Vector2(5, 400), Vector2(5, 700)], [Vector2(2200, 300), Vector2(2200, 700)], [Vector2(900, 5), Vector2(300, 5)], [Vector2(900, 600), Vector2(1100, 600)]]
	for c in cases:
		for s in 2:
			m._place_formation(s, c[0], c[1])
			if not fits(m, extent(m, s)):
				bad += 1
				print("  не помещается: отряд %d, протяжка %s -> %s, %s" % [s, c[0], c[1], extent(m, s)])
	print("DIMS1400 расстановка протяжкой (5 случаев × 2 отряда): не помещается %d" % bad)
	m.free()


func trace(path: String) -> PackedVector2Array:
	var m := new_main(path, 5)
	var tr := PackedVector2Array()
	m._start_wave()
	for t in 900:
		m._physics_process(1.0 / 30.0)
		var s := Vector2.ZERO
		for i in m.count:
			s += m.pos[i] * (1.0 + (i % 7)) + Vector2(m.hp[i], m.count)
		tr.append(s)
	tr.append(Vector2(m.count, m.arrows_fired))
	m.free()
	return tr


func det(path: String) -> void:
	var r1 := trace(path)
	var r2 := trace(path)
	var d := -1
	for k in mini(r1.size(), r2.size()):
		if r1[k] != r2[k]:
			d = k
			break
	print("DET 30 с (волна 1, seed 5), два прогона: %s; в конце юнитов %d, стрел %d" % ["совпадает на каждом тике" if d < 0 and r1.size() == r2.size() else "РАСХОДИТСЯ с тика %d" % d, r1[r1.size() - 1].x, r1[r1.size() - 1].y])


func tick(path: String) -> void:
	var m: Node2D = load(path).new()
	m.waves_enabled = false
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var n: int = m.count
	var dense := PackedFloat64Array()
	for t in 600:
		var is_dense: bool = m.count * 2 >= n
		var t0 := Time.get_ticks_usec()
		m._physics_process(1.0 / 30.0)
		if is_dense:
			dense.append((Time.get_ticks_usec() - t0) / 1000.0)
	var mean := 0.0
	for x in dense:
		mean += x
	var sorted := dense.duplicate()
	sorted.sort()
	print("TICK,%s,%d,%d,%.4f,%.4f,%d" % [path, n, dense.size(), mean / dense.size(), sorted[sorted.size() / 2], m.count])
	m.free()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	match args[0]:
		"series":
			series(args[1], args[2])
		"dims":
			dims(args[1])
		"det":
			det(args[1])
		"tick":
			tick(args[1])
	quit()
