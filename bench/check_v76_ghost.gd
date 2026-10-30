extends SceneTree
# Задача 26, этап 6 (без окна): призрак блока при ПКМ-клике. Сцена в дереве (мышь переводится в мир через make_input_local),
# физика вручную.
#   Пока ПКМ зажата и протяжка короче drag_min (data/ui_layout.json) — призрак: якорь блока каждого приказываемого отряда там,
#   куда его поставит клик; он нарисован. Длиннее — призрака нет (предпросмотр строя). Отпустили — призрака нет, цель отряда
#   (squad_target) совпадает с якорем призрака (один отряд и несколько). Приказ не пройдёт (блок пересечётся со своим
#   отрядом) — призрак красный с сообщением, цель не меняется.
#   Симуляция не меняется: те же нажатия и тики у эталона bench/ref/main_ref.gd и рабочего main — pos, hp, цели совпадают.
const REF := "res://bench/ref/main_ref.gd"
const DT := 1.0 / 30.0
var fails := 0
var lay: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func scene(script_path := "") -> Node2D:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	if script_path != "":
		m.set_script(load(script_path))
	m.spawn_seed = 4
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	m.set_physics_process(false)
	await process_frame
	return m

func mouse(m: Node2D, btn: MouseButton, w: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = m.get_global_transform_with_canvas() * w
	m._unhandled_input(e)

func motion(m: Node2D, w: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = m.get_global_transform_with_canvas() * w
	m._unhandled_input(e)

func through_screen(m: Node2D, w: Vector2) -> Vector2:
	var e := InputEventMouseButton.new()
	e.position = m.get_global_transform_with_canvas() * w
	return (m.make_input_local(e) as InputEventMouseButton).position

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	lay = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	if root.has_node("Game"):
		root.get_node("Game").free()   # бой без каркаса забега
		await step(1)
	var dmin := float(lay.drag_min)
	var m := await scene()
	check("порог протяжки из data/ui_layout.json drag_min (%s)" % dmin, m.ui_layout.drag_min == dmin)
	print("один отряд")
	m._select_only(0)
	var w: Vector2 = m.squad_pos[0] + Vector2(-260, -160)
	check("до нажатия призрака нет", m.ghost_plan().is_empty())
	mouse(m, MOUSE_BUTTON_RIGHT, w, true)
	m.queue_redraw()
	var f0 := Engine.get_process_frames()
	await step(2)
	var g: Dictionary = m.ghost_plan()
	var anchor: Vector2 = g.get("anchors", {}).get(0, Vector2.INF)
	check("ПКМ зажата: призрак отряда 1 в точке под курсором, нарисован", g.get("ok", false) and g.anchors.size() == 1
		and anchor.is_equal_approx(through_screen(m, w)) and m.ghost_frame >= f0, "%s, кадр %d" % [str(g), m.ghost_frame])
	motion(m, w + Vector2(dmin * 0.5, 0))
	check("сдвиг короче drag_min — призрак на месте нажатия", m.ghost_plan().get("anchors", {}).get(0, Vector2.INF) == anchor)
	motion(m, w + Vector2(dmin + 10.0, 0))
	check("протяжка длиннее drag_min — призрака нет (предпросмотр строя)", m.ghost_plan().is_empty())
	motion(m, w + Vector2(2, 1))
	check("вернулись ближе порога — призрак снова", not m.ghost_plan().is_empty())
	mouse(m, MOUSE_BUTTON_RIGHT, w + Vector2(2, 1), false)
	m.queue_redraw()
	var f1 := Engine.get_process_frames()
	await step(2)
	check("отпустили: призрака нет, не рисуется; цель отряда = якорь призрака", m.ghost_plan().is_empty() and m.ghost_frame < f1
		and m.squad_target[0] == anchor, "цель %s, призрак %s" % [m.squad_target[0], anchor])
	print("несколько отрядов")
	m._select_all()
	var list: PackedInt32Array = m._order_list()
	var w2: Vector2 = m.squad_pos[list[0]] + Vector2(220, -200)
	mouse(m, MOUSE_BUTTON_RIGHT, w2, true)
	g = m.ghost_plan()
	var anchors: Dictionary = g.get("anchors", {})
	mouse(m, MOUSE_BUTTON_RIGHT, w2, false)
	var same := anchors.size() == list.size() and list.size() > 1
	for s in list:
		same = same and anchors.has(s) and m.squad_target[s] == anchors[s]
	check("отрядов %d: у каждого призрак, после отпускания цели = якорям призраков" % list.size(), g.get("ok", false) and same, str(anchors))
	print("приказ не пройдёт")
	m._select_only(0)
	var before: Vector2 = m.squad_target[0]
	mouse(m, MOUSE_BUTTON_RIGHT, m.squad_target[1], true)   # отряд 2 идёт туда: блок пересечётся с его целью
	g = m.ghost_plan()
	check("в цели отряда 2: призрак красный, сообщение «%s»" % g.get("msg", ""), not g.get("ok", true) and g.msg == tr("MSG_BLOCK_OVERLAP") % 2)
	mouse(m, MOUSE_BUTTON_RIGHT, m.squad_target[1], false)
	check("отпустили — цель прежняя (проверка та же, что у приказа)", m.squad_target[0] == before)
	m.queue_free()
	await step(1)
	print("симуляция не меняется")
	var a := await scene(REF)
	var b := await scene()
	var first := -1
	for x in [a, b]:
		x._select_only(0)
		mouse(x, MOUSE_BUTTON_RIGHT, x.squad_pos[0] + Vector2(-200, -120), true)
		motion(x, x.squad_pos[0] + Vector2(-195, -118))
		mouse(x, MOUSE_BUTTON_RIGHT, x.squad_pos[0] + Vector2(-195, -118), false)
		x._select_all()
		mouse(x, MOUSE_BUTTON_RIGHT, x.squad_pos[1] + Vector2(150, -150), true)
		mouse(x, MOUSE_BUTTON_RIGHT, x.squad_pos[1] + Vector2(150, -150), false)
	for t in 300:
		a._physics_process(DT)
		b._physics_process(DT)
		if first < 0:
			var ok: bool = a.count == b.count and a.squad_target == b.squad_target
			for i in a.count:
				ok = ok and a.pos[i] == b.pos[i] and a.hp[i] == b.hp[i]
			if not ok:
				first = t
	check("те же ПКМ-приказы и 300 тиков: как у эталона на каждом тике (цели, pos, hp)", first < 0, "первое расхождение: тик %d" % first)
	a.queue_free()
	b.queue_free()
	await step(1)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
