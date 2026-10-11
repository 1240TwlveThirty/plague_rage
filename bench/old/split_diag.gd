extends SceneTree
# split_diag: почему три отряда пехоты по 100 слабее одного блока 300 (тест (з) этапа v28).
# 400 игрока (300 пехоты + 100 лучников) против 300 зомби, без волн, seed 1..20, конец боя как в тесте (з).
# Итог: bench/split_diag.txt. Копия main со счётчиками: bench/main_diag28.gd.
const MAIN := "res://bench/old/main_diag28.gd"
const SEEDS := 20
const NAMES := ["V0", "V1", "V2", "V0x", "V1x", "V2x"]
const DESC := {
	"V0": "один отряд 300, блок 20 × 15 (база)",
	"V1": "три отряда по 100 друг за другом (20 × 5 каждый), как в тесте (з)",
	"V2": "три отряда из V0 делением по колонкам 7/7/6, слоты и позиции те же",
	"V0x": "V0 без _compact_squad и _reflow_squad",
	"V1x": "V1 без _compact_squad и _reflow_squad",
	"V2x": "V2 без _compact_squad и _reflow_squad"}

func slot_world(m: Node2D, i: int) -> Vector2:
	var s: int = m.unit_squad[i]
	return m.squad_pos[s] + m.unit_slot[i].rotated(m.squad_angle[s])

func units_of(m: Node2D, s: int) -> Array:
	var ids := []
	for i in m.count:
		if m.unit_squad[i] == s:
			ids.append(i)
	return ids

func teleport(m: Node2D, s: int) -> void:
	for i in units_of(m, s):
		m.pos[i] = slot_world(m, i)
		m.prev_pos[i] = m.pos[i]

# V1: как в тесте (з): гибель 100, деление, новый отряд, покупка 100, три строя 20 × 5 друг за другом.
func setup_v1(m: Node2D) -> Array:
	m.wave_state = m.WS_RESPITE
	m.gold = 1e9
	var ids := units_of(m, 0)
	for q in range(200, 300):
		m.hp[ids[q]] = 0.0
	m._remove_dead()
	m._update_squads(0.6)
	m.first_death_tick = -1
	m._select_squad(0)
	m._cmd_split()
	var b: int = m.selected_squad
	m._cmd_new_squad()
	var c: int = m.selected_squad
	m._buy(0)
	m._buy(0)
	m._select_squad(0)
	m.wave_state = m.WS_BATTLE
	for s in [0, b, c]:
		m.squad_pos[s] = Vector2(1010, 740)
	m._place_formation(0, Vector2(953, 598), Vector2(1067, 598))
	m._place_formation(b, Vector2(953, 628), Vector2(1067, 628))
	m._place_formation(c, Vector2(953, 658), Vector2(1067, 658))
	for s in [0, b, c]:
		teleport(m, s)
	return [0, b, c]

# V2: блок V0 делится по колонкам 0-6 / 7-13 / 14-19; мировые позиции слотов и юнитов не меняются.
# Пропорция строя каждого отряда = (ширина, 15), чтобы авто-перестройка считала ширину так же, как у V0.
func setup_v2(m: Node2D) -> Array:
	var width: int = m.squad_width[0]
	var angle: float = m.squad_angle[0]
	var origin: Vector2 = m.squad_pos[0] - m.squad_center_off[0].rotated(angle)   # мир слот-вектора 0 (середина переднего ряда)
	var ids := units_of(m, 0)
	var old_world := {}
	var cols := {}
	var rows := {}
	for i in ids:
		old_world[i] = slot_world(m, i)
		cols[i] = m.unit_slot_idx[i] % width
		rows[i] = m.unit_slot_idx[i] / width
	var b: int = m._squad_create(0)
	var c: int = m._squad_create(0)
	var parts := [[0, 0, 7], [b, 7, 14], [c, 14, 20]]
	for part in parts:
		var s: int = part[0]
		var w: int = part[2] - part[1]
		m.squad_angle[s] = angle
		m.squad_center_off[s] = Vector2.ZERO
		m.squad_width[s] = w
		m.squad_rows[s] = 15
		m.squad_aspect[s] = Vector2(w, 15)
		m.squad_user_width[s] = 0
		m.squad_dirty[s] = 0
		var lat: float = ((part[1] + part[2] - 1) * 0.5 - (width - 1) * 0.5) * m.SLOT_SPACING
		m.squad_pos[s] = origin + Vector2(0.0, lat).rotated(angle)
		m.squad_target[s] = m.squad_pos[s]
		var n := 0
		for i in ids:
			if cols[i] >= part[1] and cols[i] < part[2]:
				m.unit_squad[i] = s
				m._set_line_slot(i, rows[i] * w + cols[i] - part[1], w)
				n += 1
		m.squad_n[s] = n
		m.squad_reflow_n[s] = n
		m._reanchor(s)
	var err := 0.0
	for i in ids:
		err = maxf(err, slot_world(m, i).distance_to(old_world[i]))
	if err > 0.01:
		print("ОШИБКА V2: слоты сдвинулись на %.3f px" % err)
	return [0, b, c]

# Промежутки между соседними отрядами пехоты по оси (0 = x, 1 = y), по мировым слотам; 6 px = вплотную.
func gaps(m: Node2D, squads: Array, axis: int) -> Array:
	var spans := []
	for s in squads:
		var lo := INF
		var hi := -INF
		for i in units_of(m, s):
			var v: float = slot_world(m, i)[axis]
			lo = minf(lo, v)
			hi = maxf(hi, v)
		if hi >= lo:
			spans.append([lo, hi])
	spans.sort_custom(func(p, q): return p[0] < q[0])
	var out := []
	for k in range(1, spans.size()):
		out.append(spans[k][0] - spans[k - 1][1])
	return out

func battle(seed: int, variant: String) -> Dictionary:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = seed
	m.waves_enabled = false
	m.record_path = "user://record_bench.json"
	m._setup_data()
	var squads := [0]
	if variant.begins_with("V1"):
		squads = setup_v1(m)
	elif variant.begins_with("V2"):
		squads = setup_v2(m)
	var axis := 0 if variant.begins_with("V2") else 1
	for i in m.MAX_UNITS:
		m.diag_uid[i] = i
	m.diag_compact.fill(0)
	m.diag_reflow.fill(0)
	m.diag_touched = {}
	m.diag_contact = -1
	m.total_hits = 0
	m.blocked_hits = 0
	m.diag_no_reform = variant.ends_with("x")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in m.count:
		m.pos[i] += Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var start := [0, 0]
	var start_sq := []
	for i in m.count:
		start[m.team[i]] += 1
	for s in squads:
		start_sq.append(m.squad_n[s])
	var arch0: int = m.squad_n[1]
	var left: Array = start.duplicate()
	var last_death := -1
	var r := {"front_w": 0.0, "front_n": 0, "gap5": [], "gap10": [], "gap10_ok": 0, "end_t": 60 * 30}
	var seen_contact := false
	for t in range(1, 60 * 30 + 1):
		var before: int = m.count
		m._physics_process(1.0 / 30.0)
		if not seen_contact and m.diag_contact >= 0:
			seen_contact = true
			# передний ряд пехоты в момент контакта: юниты не дальше 3 px по y от самого переднего
			var ymin := INF
			for i in m.count:
				if m.unit_type[i] == m.infantry_type:
					ymin = minf(ymin, m.pos[i].y)
			var xlo := INF
			var xhi := -INF
			for i in m.count:
				if m.unit_type[i] == m.infantry_type and m.pos[i].y <= ymin + 3.0:
					xlo = minf(xlo, m.pos[i].x)
					xhi = maxf(xhi, m.pos[i].x)
					r.front_n += 1
			r.front_w = xhi - xlo
		if seen_contact and m.tick_counter == m.diag_contact + 150:
			r.gap5 = gaps(m, squads, axis)
		if seen_contact and m.tick_counter == m.diag_contact + 300:
			r.gap10 = gaps(m, squads, axis)
			r.gap10_ok = 1
		if m.count < before:
			last_death = t
			left = [0, 0]
			for i in m.count:
				left[m.team[i]] += 1
		if left[0] == 0 or left[1] == 0 or (last_death > 0 and t - last_death >= 90):
			r.end_t = t
			break
	if r.gap10_ok == 0:
		r.gap10 = gaps(m, squads, axis)   # бой кончился раньше 10 с после контакта: замер в конце боя
	r.loss0 = start[0] - left[0]
	r.loss1 = start[1] - left[1]
	r.loss_arch = arch0 - m.squad_n[1]
	r.loss_sq = []
	r.compact = []
	r.reflow = []
	for q in squads.size():
		r.loss_sq.append(start_sq[q] - m.squad_n[squads[q]])
		r.compact.append(m.diag_compact[squads[q]])
		r.reflow.append(m.diag_reflow[squads[q]])
	r.hits = m.total_hits
	r.blocked = m.blocked_hits
	r.contact = m.diag_contact
	# затронутые за 5 с после контакта: пехота игрока, нанёсшая или получившая удар; ширина зоны по x
	var tx_lo := INF
	var tx_hi := -INF
	r.touched_inf = 0
	r.touched_arch = 0
	r.touched_z = 0
	for uid in m.diag_touched:
		var v: Vector3 = m.diag_touched[uid]
		if int(v.x) == m.infantry_type:
			r.touched_inf += 1
			tx_lo = minf(tx_lo, v.y)
			tx_hi = maxf(tx_hi, v.y)
		elif int(v.x) == m.archer_type:
			r.touched_arch += 1
		else:
			r.touched_z += 1
	r.zone_w = tx_hi - tx_lo if tx_hi >= tx_lo else 0.0
	m.free()
	return r

func avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxi(a.size(), 1)

func list_avg(rows: Array, key: String) -> String:
	var n := 0
	for r in rows:
		n = maxi(n, r[key].size())
	var out := []
	for q in n:
		var vals := []
		for r in rows:
			if q < r[key].size():
				vals.append(r[key][q])
		out.append("%.1f" % avg(vals))
	return "—" if out.is_empty() else " / ".join(out)

func _initialize() -> void:
	var lines: Array[String] = []
	lines.append("split_diag: 300 пехоты + 100 лучников против 300 зомби, без волн, seed 1..%d; конец боя: одна сторона уничтожена / 3 с без смертей / 60 с." % SEEDS)
	lines.append("ratio = потери зомби / потери игрока (среднее по боям). Средние по %d боям. Копия main: bench/main_diag28.gd." % SEEDS)
	lines.append("Отряды в списках: V1 — передний / средний / задний; V2 — левый / средний / правый.")
	lines.append("")
	var ratio0 := {}
	for name in NAMES:
		var rows := []
		for seed in range(1, SEEDS + 1):
			rows.append(battle(seed, name))
		var ratios := []
		var col := {}
		for key in ["loss0", "loss1", "loss_arch", "hits", "blocked", "touched_inf", "touched_arch", "touched_z", "front_w", "front_n", "zone_w", "contact", "end_t", "gap10_ok"]:
			var vals := []
			for r in rows:
				vals.append(r[key])
			col[key] = avg(vals)
		for r in rows:
			ratios.append(r.loss1 / float(maxi(r.loss0, 1)))
		var ratio := avg(ratios)
		ratio0[name] = ratio
		var base: String = "V0x" if name.ends_with("x") else "V0"
		lines.append("%s — %s" % [name, DESC[name]])
		lines.append("  потери: игрок %.1f (пехота %.1f, лучники %.1f), зомби %.1f; ratio %.3f%s" % [col.loss0, col.loss0 - col.loss_arch, col.loss_arch, col.loss1, ratio,
			"" if name == base else " (%+.1f%% к %s)" % [(ratio / ratio0[base] - 1.0) * 100.0, base]])
		lines.append("  потери пехоты по отрядам: %s" % list_avg(rows, "loss_sq"))
		lines.append("  удары по пехоте: %.0f, заблокировано %.0f (%.1f%%)" % [col.hits, col.blocked, 100.0 * col.blocked / maxf(col.hits, 1.0)])
		lines.append("  за 5 с после контакта нанесли или получили удар: пехота %.1f, лучники %.1f, зомби %.1f; ширина зоны боя по x %.0f px" % [col.touched_inf, col.touched_arch, col.touched_z, col.zone_w])
		lines.append("  передний ряд пехоты в момент контакта: ширина %.0f px, юнитов %.1f; контакт на %.1f с, конец боя на %.1f с" % [col.front_w, col.front_n, col.contact / 30.0, col.end_t / 30.0])
		lines.append("  вызовы за бой по отрядам: _compact_squad %s; _reflow_squad %s" % [list_avg(rows, "compact"), list_avg(rows, "reflow")])
		lines.append("  промежуток между соседними блоками по слотам (6 px = вплотную): через 5 с после контакта %s; через 10 с %s (до 10 с дожило боёв: %d из %d, остальные замерены в конце)" % [
			list_avg(rows, "gap5"), list_avg(rows, "gap10"), roundi(col.gap10_ok * SEEDS), SEEDS])
		lines.append("")
		print(lines[lines.size() - 9])
		print(lines[lines.size() - 8])
	var f := FileAccess.open("res://bench/old/split_diag.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
