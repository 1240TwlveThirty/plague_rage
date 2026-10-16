extends SceneTree
# Тесты v48: подгонка слоя замка (F3 в debug-сборке) и data/layer_tuning.json.
# Сохранение (F4) пишет во временный user://bench_v48/layer_tuning.json, настоящий data/layer_tuning.json не трогается.
const DIR := "user://bench_v48"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func key(m: Node, k: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.shift_pressed = shift
	m._unhandled_input(e)

func near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 1e-4

func make(path: String) -> Node2D:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	m.layer_tuning_path = path
	root.add_child(m)
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "/layer_tuning.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	print("CHECK v48: подгонка слоя замка")
	# файл проекта читается при старте: замок стоит по data/layer_tuning.json, а не по значениям по умолчанию
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/layer_tuning.json"))
	var m0: Node2D = load("res://scenes/main.tscn").instantiate()
	m0.record_path = "user://record_bench.json"
	root.add_child(m0)
	await process_frame
	check("data/layer_tuning.json загружается при старте", d is Dictionary
		and near(Vector2(d["castle_offset"][0], d["castle_offset"][1]), m0.castle_offset)
		and is_equal_approx(d["castle_scale_x"], m0.castle_scale.x) and is_equal_approx(d["castle_scale_y"], m0.castle_scale.y)
		and near(m0.castle_sprite.scale, m0.castle_scale * m0.BG_SCALE), "%s %s" % [m0.castle_offset, m0.castle_scale])
	# камера: поле закрывает экран (нет полос очистки), края вида не выходят за поле
	var vr: Rect2 = m0.view_rect()
	check("камера: зум = camera_min_zoom() >= 1080/1056", is_equal_approx(m0.camera.zoom.x, m0.camera_min_zoom())
		and m0.camera_min_zoom() >= 1080.0 / 1056.0 - 1e-6, str(m0.camera.zoom))
	check("камера: вид внутри поля", vr.position.x >= -1e-3 and vr.position.y >= -1e-3 and vr.end.x <= m0.FIELD.x + 1e-3
		and vr.end.y <= m0.FIELD.y + 1e-3, str(vr))
	check("камера: вид по высоте = поле", absf(vr.size.y - m0.FIELD.y) < 0.01, str(vr.size))
	# экран -> мир: клик в пикселе (960, 540) — центр поля, в (0, 0) — левый верх вида
	var ct: Transform2D = m0.get_viewport().get_canvas_transform()
	check("экран -> мир через холст", near(ct.affine_inverse() * Vector2(960, 540), m0.FIELD * 0.5)
		and near(ct.affine_inverse() * Vector2.ZERO, vr.position), str(ct.affine_inverse() * Vector2.ZERO))
	m0.queue_free()
	await process_frame
	# нет файла — значения по умолчанию
	var m := make(path)
	await process_frame
	var sp: Sprite2D = m.castle_sprite
	var pos0: Vector2 = sp.position
	check("без файла: значения по умолчанию", near(m.castle_offset, m.CASTLE_TX_OFFSET) and near(m.castle_scale, Vector2.ONE * m.CASTLE_TX_SCALE))
	check("режим выключен при старте", not m.tune_on)
	# выключенный режим: стрелка — команда игры, замок на месте
	key(m, KEY_LEFT)
	check("выключен: стрелка не двигает замок", near(sp.position, pos0) and near(m.castle_offset, m.CASTLE_TX_OFFSET))
	key(m, KEY_F3)
	check("F3 включает", m.tune_on and m.tune_label != null and m.tune_label.visible)
	var tick0: int = m.tick_counter
	key(m, KEY_RIGHT)
	key(m, KEY_DOWN, true)
	check("стрелки: +1 по x, Shift +0.25 по y", near(m.castle_offset, m.CASTLE_TX_OFFSET + Vector2(1.0, 0.25)), str(m.castle_offset))
	check("спрайт сдвинут на смещение x BG_SCALE", near(sp.position, pos0 + Vector2(1.0, 0.25) * m.BG_SCALE))
	var s0: float = m.CASTLE_TX_SCALE
	key(m, KEY_E)
	check("E: обе оси x 1.005", near(m.castle_scale, Vector2.ONE * s0 * 1.005))
	key(m, KEY_Z, true)
	check("Shift+Z: только x x 0.999", near(m.castle_scale, Vector2(s0 * 1.005 * 0.999, s0 * 1.005)))
	key(m, KEY_V)
	check("V: только y x 1.005", near(m.castle_scale, Vector2(s0 * 1.005 * 0.999, s0 * 1.005 * 1.005)))
	check("спрайт масштабирован", near(sp.scale, m.castle_scale * m.BG_SCALE))
	check("текст показывает значения", ("%.2f" % m.castle_offset.x) in m.tune_label.text and ("%.4f" % m.castle_scale.y) in m.tune_label.text)
	check("включён: клавиши не трогают отряды и тики", m.tick_counter == tick0)
	key(m, KEY_F4)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	check("F4 сохраняет", saved is Dictionary and near(Vector2(saved["castle_offset"][0], saved["castle_offset"][1]), m.castle_offset)
		and is_equal_approx(saved["castle_scale_x"], m.castle_scale.x) and is_equal_approx(saved["castle_scale_y"], m.castle_scale.y))
	var off1: Vector2 = m.castle_offset
	var sc1: Vector2 = m.castle_scale
	key(m, KEY_F3)
	check("F3 выключает", not m.tune_on and not m.tune_label.visible)
	key(m, KEY_Q)
	check("выключен: Q не меняет масштаб", near(m.castle_scale, sc1))
	m.queue_free()
	await process_frame
	# сохранённый файл загружается при старте
	var m2 := make(path)
	await process_frame
	check("при старте значения из файла", near(m2.castle_offset, off1) and near(m2.castle_scale, sc1)
		and near(m2.castle_sprite.scale, sc1 * m2.BG_SCALE))
	m2.queue_free()
	await process_frame
	# битый файл — значения по умолчанию
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"castle_offset": [1]}')
	f.close()
	var m3 := make(path)
	await process_frame
	check("битый файл: значения по умолчанию", near(m3.castle_offset, m3.CASTLE_TX_OFFSET) and near(m3.castle_scale, Vector2.ONE * m3.CASTLE_TX_SCALE))
	m3.queue_free()
	DirAccess.remove_absolute(path)
	await process_frame
	print("CHECK: провалов %d" % fails)
	quit()
