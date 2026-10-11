extends SceneTree
# Время _process и _draw (v40, этап 2), с окном: <old | new>. old — bench/main_v40_before.gd (этап 1), new — scripts/main.gd.
# Передышка, армия 3000 юнитов в 8 отрядах (6 пехоты, 2 лучников), все идут к новым целям; в new выбраны все 8.
# 400 кадров: медиана _process, медиана _draw (среди кадров, где он был), число перерисовок и сумма (_process + _draw) на кадр.
const WRAP := """extends "%s"
var t_proc := PackedFloat64Array()
var t_draw := PackedFloat64Array()
func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	super._process(delta)
	t_proc.append((Time.get_ticks_usec() - t0) / 1000.0)
func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	super._draw()
	t_draw.append((Time.get_ticks_usec() - t0) / 1000.0)
"""

func med(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]

func total(a: PackedFloat64Array) -> float:
	var x := 0.0
	for v in a:
		x += v
	return x

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var is_new := OS.get_cmdline_user_args()[0] == "new"
	var script := GDScript.new()
	script.source_code = WRAP % ("res://scripts/main.gd" if is_new else "res://bench/main_v40_before.gd")
	script.reload()
	var m := Node2D.new()
	m.set_script(script)
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	for i in 5:
		await process_frame
	m._squad_add_units(0, m.infantry_type, 1950)
	m._squad_add_units(1, m.archer_type, 650)
	m.split_frac = 0.5
	for src in [0, 0, 2, 0, 2, 1]:   # отряды 0, 2, 3, 4, 5, 6 — пехота, 1 и 7 — лучники
		if is_new:
			m._select_only(src)
		else:
			m.selected_squad = src
		m._cmd_split()
	var k := 0
	for s in m.SQUAD_MAX:
		if m.squad_used[s] == 1:
			var c := Vector2(420 + (k % 4) * 440, 150 + (k / 4) * 300)
			m._place_formation(s, c - Vector2(150, 0), c + Vector2(150, 0))
			k += 1
	for i in m.count:
		if m.unit_squad[i] >= 0:
			m.pos[i] = m.squad_pos[m.unit_squad[i]] + m.unit_slot[i].rotated(m.squad_angle[m.unit_squad[i]])
			m.prev_pos[i] = m.pos[i]
	if is_new:
		m._select_all()
	for s in m.SQUAD_MAX:
		m.squad_target[s] = m.squad_pos[s] + Vector2(0, 220)   # все идут: контуры выбранных перерисовываются каждый тик
	for i in 30:
		await process_frame
	m.t_proc.clear()
	m.t_draw.clear()
	var frames := 400
	var tick0: int = m.tick_counter
	for i in frames:
		await process_frame
	print("DRAW|%s|%d|%d|%.3f|%.3f|%d|%.3f|%d" % ["new" if is_new else "old", m.count, k, med(m.t_proc), med(m.t_draw), m.t_draw.size(),
		(total(m.t_proc) + total(m.t_draw)) / m.t_proc.size(), m.tick_counter - tick0])
	quit()
