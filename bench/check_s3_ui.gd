extends SceneTree
# (б) выбор и клик через настоящий ввод окна; (е) смоук интерфейса: клавиши, режимы, покупки, волна.
var frames := 0
var step := 0
var m: Node
var t_inf: Vector2
var t_arc: Vector2
var ang_arc := 0.0
var saved_record = null

func _initialize() -> void:
	if FileAccess.file_exists("user://record.json"):
		saved_record = FileAccess.get_file_as_string("user://record.json")
	change_scene_to_file("res://scenes/main.tscn")

func click(p: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		root.push_input(ev, true)   # координаты вьюпорта, без пересчёта из окна

func key(k: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		root.push_input(ev)

func _process(_delta: float) -> bool:
	m = current_scene
	if m == null or not "squad_buttons" in m or m.squad_buttons.is_empty():
		return false
	frames += 1
	match step:
		0:
			if frames < 10:   # ждём раскладку интерфейса
				return false
			print("    строка лучников на экране: %s" % m.squad_buttons[1].get_global_rect())
			t_inf = m.squad_target[0]
			t_arc = m.squad_target[1]
			var r: Rect2 = m.squad_buttons[1].get_global_rect()
			click(r.get_center())   # клик по строке «2 Лучники» на панели
			step = 1
		1:
			print("(б) клик по строке лучников: выбран отряд %d; цели не сдвинулись: пехота %s, лучники %s" % [
				m.selected_squad, m.squad_target[0] == t_inf, m.squad_target[1] == t_arc])
			ang_arc = m.squad_angle[1]
			click(Vector2(1300, 300))   # клик по карте: цель выбранного отряда
			step = 2
		2:
			print("    клик по карте: цель лучников %s -> %s, цель пехоты не изменилась: %s" % [t_arc.round(), m.squad_target[1].round(), m.squad_target[0] == t_inf])
			step = 3
			frames = 0
		3:
			if frames >= 120:
				print("    через 4 с: лучники сдвинулись на %.0f px к цели, угол %.2f -> %.2f (к цели %.2f); пехота на месте: %s" % [
					m.squad_pos[1].distance_to(m.squad_target[1]), ang_arc, m.squad_angle[1],
					(m.squad_target[1] - m.squad_pos[1]).angle(), m.squad_pos[0].distance_to(m.squad_target[0]) < 2.0])
				# (е) смоук: клавиши
				for k in [KEY_1, KEY_W, KEY_E, KEY_Q, KEY_2, KEY_3, KEY_F2, KEY_F3, KEY_F4, KEY_F1, KEY_Z, KEY_X, KEY_C, KEY_V]:
					key(k)
				var r: Rect2 = m.shop_buttons[0].get_global_rect()
				click(r.get_center())   # кнопка магазина мышью
				step = 4
				frames = 0
		4:
			if frames == 2:
				print("(е) после клавиш: выбран %d, приказы %s, режим цвета F%d, куплено %s, золото %d, юнитов %d" % [
					m.selected_squad, m.squad_order, m.color_mode + 1, m.shop_bought, floori(m.gold), m.count])
				key(KEY_SPACE)
			if frames == 3:
				print("    Space: волна %d, состояние %d, магазин виден: %s" % [m.wave_number, m.wave_state, m.shop_panel.visible])
			if frames >= 600:
				print("    20 с волны 1: зомби живых %d, убито %d, ворота %.0f, HUD: «%s»" % [m.zombie_alive, m.wave_kills, m.gate_hp, m.hud_label.text])
				if saved_record != null:
					var f := FileAccess.open("user://record.json", FileAccess.WRITE)
					f.store_string(saved_record)
					f.close()
				return true
	return false