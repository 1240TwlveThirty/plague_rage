extends SceneTree
# arrow_lead: что даёт лучникам больше — упреждение или более частый залп. Волны 1-5, seed 1-3,
# стартовая армия (пехота 300 + лучники 100) стоит на месте, покупок нет. Копия main: bench/main_lead.gd.
# Итог: bench/arrow_lead.txt.
const VARIANTS := [["текущая версия", 0, 0.0], ["упреждение по vel зомби", 1, 0.0], ["упреждение по средней vel клетки", 2, 0.0], ["volley_period 1.5 с", 0, 1.5],
	["упреждение по vel зомби + период 1.5 с", 1, 1.5], ["упреждение по средней vel клетки + период 1.5 с", 2, 1.5]]

func run(seed: int, lead: int, period: float) -> Dictionary:
	var m: Node2D = load("res://bench/main_lead.gd").new()
	m.spawn_seed = seed
	m.record_path = "user://record_bench.json"
	m._setup_data()
	m.lead_on = lead
	if period > 0.0:
		m.type_volley_period[m.archer_type] = period   # только в памяти, JSON не трогаем
	var r := {"fired": 0, "hit": 0, "out": 0, "kills": 0, "kills_arrow": 0, "waves": 0, "ticks": 0, "volleys": 0}
	var army0: int = m.count
	for wave in 5:
		if m.wave_state != m.WS_RESPITE:
			break
		m._start_wave()
		var t := 0
		var prev: int = m.squad_volley_fired[1]
		while m.wave_state == m.WS_BATTLE and t < 3600:
			m._physics_process(1.0 / 30.0)
			t += 1
			if m.squad_volley_fired[1] == 1 and prev == 0:
				r.volleys += 1
			prev = m.squad_volley_fired[1]
		r.fired += m.arrows_fired
		r.hit += m.arrows_hit
		r.out += m.arrows_out_of_range
		r.kills += m.wave_kills
		r.ticks += t
		if m.wave_state == m.WS_RESPITE:
			r.waves += 1
	r.kills_arrow = m.kills_arrow
	var army := 0
	for i in m.count:
		if m.team[i] == 0:
			army += 1
	r.loss = army0 - army
	m.free()
	return r

func _initialize() -> void:
	var lines: Array[String] = []
	lines.append("arrow_lead: волны 1-5, seed 1-3, армия 300 пехоты + 100 лучников стоит на старте, покупок нет. Суммы по трём seed.")
	lines.append("вариант | выпущено | попало | доля попаданий | вне дальности | залпов | убито стрелами | убито всего | доля стрел в убийствах | потери игрока | пройдено волн | время боя, с")
	var best := ""
	var best_kills := -1
	var base_kills := 0
	var rows := []
	for v in VARIANTS:
		var s := {"fired": 0, "hit": 0, "out": 0, "kills": 0, "kills_arrow": 0, "waves": 0, "ticks": 0, "volleys": 0, "loss": 0}
		for seed in [1, 2, 3]:
			var r := run(seed, v[1], v[2])
			for k in s:
				s[k] += r[k]
		rows.append([v[0], s])
		if v[0] == "текущая версия":
			base_kills = s.kills_arrow
		elif s.kills_arrow > best_kills:
			best_kills = s.kills_arrow
			best = v[0]
		var line := "%s | %d | %d | %.1f%% | %d | %d | %d | %d | %.1f%% | %d | %d из 15 | %.0f" % [v[0], s.fired, s.hit, 100.0 * s.hit / maxi(s.fired, 1), s.out, s.volleys,
			s.kills_arrow, s.kills, 100.0 * s.kills_arrow / maxi(s.kills, 1), s.loss, s.waves, s.ticks / 30.0]
		lines.append(line)
		print(line)
	var c: Dictionary = rows[0][1]
	var l1: Dictionary = rows[1][1]
	var l2: Dictionary = rows[2][1]
	var p: Dictionary = rows[3][1]
	var lead_best: Dictionary = l1 if l1.kills_arrow >= l2.kills_arrow else l2
	var verdict := "Вывод: больше даёт %s: убито стрелами %d у текущей версии, %d с периодом 1.5 с (%+d), %d и %d с упреждением (по vel зомби %+d, по средней vel клетки %+d); доля попаданий %.1f%% / %.1f%% / %.1f%% и %.1f%%." % [
		"частый залп (volley_period 1.5 с)" if p.kills_arrow >= lead_best.kills_arrow else "упреждение", c.kills_arrow, p.kills_arrow, p.kills_arrow - c.kills_arrow, l1.kills_arrow, l2.kills_arrow,
		l1.kills_arrow - c.kills_arrow, l2.kills_arrow - c.kills_arrow, 100.0 * c.hit / maxi(c.fired, 1), 100.0 * p.hit / maxi(p.fired, 1), 100.0 * l1.hit / maxi(l1.fired, 1), 100.0 * l2.hit / maxi(l2.fired, 1)]
	lines.append("")
	lines.append(verdict)
	print(verdict)
	var f := FileAccess.open("res://bench/arrow_lead.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
