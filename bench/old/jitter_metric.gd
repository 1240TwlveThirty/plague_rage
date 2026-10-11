extends SceneTree
# Метрика дёрганья строя пехоты. Аргументы: <res://скрипт> <файл итога в bench/> [метка]
# Окно: от первой смерти до конца боя (3 с без смертей / одна сторона уничтожена / 60 с), seed 1–10.
# Группы: первые 3 занятых ряда (ряд = slot_idx / ширина, от переднего занятого) и остальные.
#  (а) доля юнито-тиков, где dot(p[t]-p[t-3], p[t-3]-p[t-6]) < 0 (оба смещения > 0.01 px)
#  (б) средняя |p[t] - 2p[t-1] + p[t-2]|, px
#  (в) скачок слота (мир) при смене slot_idx: средний и максимальный, px
#  (г) доля юнитов отряда, сменивших slot_idx за одно назначение (среднее по назначениям)
const H := 7

func run(script_path: String, rng_seed: int, acc: Dictionary) -> void:
	var m: Node2D = load(script_path).new()
	m.spawn_seed = rng_seed
	m._setup_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var N: int = m.UNIT_COUNT
	var hist := PackedVector2Array()
	hist.resize(N * H)
	var age := PackedInt32Array()
	age.resize(N)
	var prev_idx := PackedInt32Array()
	prev_idx.resize(N)
	prev_idx.fill(-1)
	var prev_slot := PackedVector2Array()
	prev_slot.resize(N)
	var has_target := "unit_slot_target" in m
	var prev_tgt := PackedVector2Array()
	prev_tgt.resize(N)
	var started := false
	var last_death := -1
	var prev_assign: int = m.bench_assign_n
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if m.count < before:
			started = true
			last_death = t
		var assigned: bool = m.bench_assign_n != prev_assign
		prev_assign = m.bench_assign_n
		var width: int = m.squad_width[0]
		var front := 1 << 30
		for i in m.count:
			if m.unit_squad[i] == 0:
				front = mini(front, m.unit_slot_idx[i] / width)
		var sq_n := 0
		var changed := 0
		var a := [0, 0]
		for i in m.count:
			a[m.team[i]] += 1
			if m.unit_squad[i] != 0:
				continue
			var u: int = m.unit_uid[i]
			var p: Vector2 = m.pos[i]
			var k := t % H
			hist[u * H + k] = p
			age[u] += 1
			var idx: int = m.unit_slot_idx[i]
			var slot_w: Vector2 = m.squad_pos[0] + m.unit_slot[i].rotated(m.squad_angle[0])
			var tgt_w: Vector2 = m.squad_pos[0] + m.unit_slot_target[i].rotated(m.squad_angle[0]) if has_target else slot_w
			sq_n += 1
			if started:
				var g := "front" if idx / width < front + 3 else "rest"
				acc[g + "_ticks"] += 1
				if age[u] >= 7:
					var d1: Vector2 = p - hist[u * H + (t - 3) % H]
					var d0: Vector2 = hist[u * H + (t - 3) % H] - hist[u * H + (t - 6) % H]
					if d1.length() > 0.01 and d0.length() > 0.01 and d1.dot(d0) < 0.0:
						acc[g + "_flip"] += 1
					acc[g + "_acc_n"] += 1
					acc[g + "_acc"] += (p - 2.0 * hist[u * H + (t - 1) % H] + hist[u * H + (t - 2) % H]).length()
				if prev_idx[u] != -1 and prev_idx[u] != idx:
					var jump := tgt_w.distance_to(prev_tgt[u]) if has_target else slot_w.distance_to(prev_slot[u])
					acc.jump_n += 1
					acc.jump_sum += jump
					acc.jump_max = maxf(acc.jump_max, jump)
					if has_target:
						var jc := slot_w.distance_to(prev_slot[u])
						acc.jumpc_sum += jc
						acc.jumpc_max = maxf(acc.jumpc_max, jc)
			if prev_idx[u] != -1 and prev_idx[u] != idx:
				changed += 1
			prev_idx[u] = idx
			prev_slot[u] = slot_w
			prev_tgt[u] = tgt_w
		if started and assigned and sq_n > 0:
			acc.assign_n += 1
			acc.assign_frac += float(changed) / sq_n
		if a[0] == 0 or a[1] == 0 or (last_death > 0 and t - last_death >= 90):
			break
	m.free()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var acc := {"front_ticks": 0, "front_flip": 0, "front_acc": 0.0, "front_acc_n": 0,
		"rest_ticks": 0, "rest_flip": 0, "rest_acc": 0.0, "rest_acc_n": 0,
		"jump_n": 0, "jump_sum": 0.0, "jump_max": 0.0, "jumpc_sum": 0.0, "jumpc_max": 0.0,
		"assign_n": 0, "assign_frac": 0.0}
	for s in range(1, 11):
		run(args[0], s, acc)
	var lines: Array[String] = []
	lines.append("Метрика дёрганья пехоты: %s (%s), seed 1–10, от первой смерти до конца боя" % [args[2] if args.size() > 2 else "", args[0]])
	for g in ["front", "rest"]:
		lines.append("  %s: (а) доля смен направления за 3 тика %.4f; (б) средняя вторая разность %.4f px  [юнито-тиков %d]" % [
			"первые 3 ряда" if g == "front" else "остальные ряды", float(acc[g + "_flip"]) / maxi(acc[g + "_acc_n"], 1),
			acc[g + "_acc"] / maxi(acc[g + "_acc_n"], 1), acc[g + "_ticks"]])
	lines.append("  (в) скачок слота при смене slot_idx: средний %.2f px, максимальный %.2f px (смен %d)%s" % [
		acc.jump_sum / maxi(acc.jump_n, 1), acc.jump_max, acc.jump_n,
		"" if acc.jumpc_max == 0.0 else "; скачок slot_current (по нему идут юниты): средний %.3f, max %.3f px" % [acc.jumpc_sum / maxi(acc.jump_n, 1), acc.jumpc_max]])
	lines.append("  (г) доля юнитов, сменивших slot_idx за назначение: %.3f (назначений %d)" % [acc.assign_frac / maxi(acc.assign_n, 1), acc.assign_n])
	var f := FileAccess.open("res://bench/" + args[1], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	for l in lines:
		print(l)
	quit()