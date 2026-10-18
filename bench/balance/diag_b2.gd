extends SceneTree
# Диагностика абляции (задача 6a, пункт 6): почему у бота B2 «Закалённая сталь» 1-3 даёт сдвиг волны смерти ровно 0.00.
# Запуск из корня проекта: <godot> --headless --path . -s res://bench/balance/diag_b2.gd   (итог — bench/balance/diag_b2.txt)
# 1) сырые непрерывные волны смерти B2 по seed 1-5: база и tempered_steel 3 из прогона v3 (bench/balance/ablation_v3_runs/), сила P по волнам;
# 2) удары до убийства по волнам: урон пехоты (1.1 за каждое купленное оружие, x1.18 с даром) против HP зомби волны;
# 3) пошаговое сравнение: два забега B2 (без дара и tempered_steel 3) одновременно, первый тик, где расходятся события боя
#    (позиции, число юнитов, убитые, золото, ворота); остаток HP раненых зомби с даром другой с первого удара — он не сравнивается.
const RUNS := "res://bench/balance/ablation_v3_runs/"
const OUT := "res://bench/balance/diag_b2.txt"
const SEEDS := [1, 2, 3, 4, 5]
const CYCLE := [0, 2]   # B2: по кругу пехота, оружие (как в calib_worker.gd)
const DT := 1.0 / 30.0
var L: Array[String] = []

func rows(cfg: String, seed: int) -> Array:
	var out := []
	for line in FileAccess.get_file_as_string("%s%s_B2_s%d.txt" % [RUNS, cfg, seed]).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE":
			out.append({"w": int(f[3]), "inf": int(f[4]), "weapons": int(f[6]), "n": int(f[9]), "p": sqrt(float(f[12]) * float(f[13])), "kills": int(f[18])})
	return out

func death(r: Array) -> float:
	var last: Dictionary = r[-1]
	return last.w + minf(float(last.kills) / last.n, 0.99)

func make(gifts: Dictionary, seed: int) -> Node2D:
	var m: Node2D = load("res://scripts/main.gd").new()
	m.record_path = "user://record_bench.json"
	m.spawn_seed = seed
	m.debug_layer = 1
	m.active_gifts = gifts
	m._setup_data()
	return m

func buy(m: Node2D, ptr: int) -> int:
	while true:
		var bought := false
		for k in CYCLE.size():
			if m._buy(CYCLE[(ptr + k) % CYCLE.size()]):
				ptr = (ptr + k + 1) % CYCLE.size()
				bought = true
				break
		if not bought:
			return ptr
	return ptr

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.wave_kills != b.wave_kills:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i]:
			return false
	return true

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	L.append("diag_b2: бот B2, база против tempered_steel 3 (урон пехоты +18%), осада I (слой 1). Данные 1) — прогон v3 (bench/gift_ablation_v3.txt).")
	L.append("")
	L.append("1. Непрерывная волна смерти (волна + доля убитых), по seed:")
	L.append("  seed | база  | сталь 3 | разница")
	for s in SEEDS:
		var a := death(rows("none", s))
		var b := death(rows("tempered_steel_3", s))
		L.append("  %4d | %5.2f | %7.2f | %+.2f" % [s, a, b, b - a])
	L.append("  Сила P = sqrt(H * D) на старте волны после покупок (seed 1), база / сталь 3 / отношение; убито / всего в волне:")
	var ra := rows("none", 1)
	var rb := rows("tempered_steel_3", 1)
	for k in mini(ra.size(), rb.size()):
		L.append("    волна %d: P %.0f / %.0f / x%.3f; убито %d/%d и %d/%d; пехоты %d и %d; оружия куплено %d и %d" % [ra[k].w, ra[k].p, rb[k].p, rb[k].p / ra[k].p,
			ra[k].kills, ra[k].n, rb[k].kills, rb[k].n, ra[k].inf, rb[k].inf, ra[k].weapons, rb[k].weapons])
	L.append("")
	L.append("2. Удары пехоты до убийства зомби (HP x (1 + 0.04 * (волна - 1)); урон пехоты 1.0 x 1.1^оружие, с даром ещё x1.18). Рыцари — с волны 7.")
	var m := make({}, 1)
	var types := {"крестьянин": m.zombie_type, "бегун": m.runner_type, "рыцарь": m.knight_type}
	var inf_dmg: float = m.type_damage[m.infantry_type]
	var gain: float = m.shop_param[2]
	L.append("  волна | оружие | урон база / сталь | крестьянин   | бегун | рыцарь")
	for k in ra.size():
		var w: int = ra[k].w
		var n: int = ra[k].weapons
		var d0 := inf_dmg * pow(gain, n)
		var d1 := d0 * 1.18
		var cells := PackedStringArray()
		for name in types:
			var hp: float = m.type_hp[types[name]] * (1.0 + m.wave_cfg.hp_growth * (w - 1))
			if name == "рыцарь" and w < int(m.wave_cfg.knight_from_wave):
				cells.append("—")
			else:
				cells.append("%d / %d" % [ceili(hp / d0), ceili(hp / d1)])
		L.append("  %5d | %6d | %.3f / %.3f      | %-12s | %-5s | %s" % [w, n, d0, d1, cells[0], cells[1], cells[2]])
	m.free()
	L.append("")
	L.append("3. Пошаговое сравнение двух забегов B2 (те же покупки, физика вручную): первый тик расхождения событий (позиции, число юнитов, золото, ворота, убитые;
  остаток HP раненых зомби не сравнивается — с даром он другой с первого удара).")
	for s in SEEDS:
		var a := make({}, s)
		var b := make({"tempered_steel": 3}, s)
		var pa := 0
		var pb := 0
		var diverged := ""
		while a.wave_number < 40 and diverged == "":
			pa = buy(a, pa)
			pb = buy(b, pb)
			a._start_wave()
			b._start_wave()
			var t := 0
			while a.wave_state == a.WS_BATTLE and b.wave_state == b.WS_BATTLE and t < 30 * 1200:
				a._physics_process(DT)
				b._physics_process(DT)
				t += 1
				if not same(a, b):
					diverged = "волна %d, тик волны %d (%.1f с)" % [a.wave_number, t, t * DT]
					break
			if a.wave_state != a.WS_RESPITE or b.wave_state != b.WS_RESPITE:
				break
		L.append("  seed %d: %s; база дошла до волны %d" % [s, diverged if diverged != "" else "не расходятся до конца забега", a.wave_number])
		a.free()
		b.free()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
