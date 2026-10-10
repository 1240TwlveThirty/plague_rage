extends SceneTree
# Этап 1 (в): поражение -> R -> полный сброс, второй прогон совпадает с первым.
# Запуск с --fixed-fps 30: один кадр = один физический тик.
var phase := 0
var frames := 0
var runs := []          # [тик поражения, контрольная сумма позиций, gate_hits]
var saved_record = null
var started := false

func _initialize() -> void:
	if FileAccess.file_exists("user://record.json"):
		saved_record = FileAccess.get_file_as_string("user://record.json")
	change_scene_to_file("res://scenes/main.tscn")

func checksum(m: Node) -> float:
	var s := 0.0
	for i in m.count:
		s += m.pos[i].x * 1.37 + m.pos[i].y * 0.73 + i
	return s

func _process(_delta: float) -> bool:
	var m := current_scene
	if m == null or not "gate_hp" in m:
		return false
	frames += 1
	if not started:
		# свежая сцена: проверяем сброс и убираем игрока, чтобы ворота пали
		var fresh: bool = m.tick_counter <= 1 and m.gate_hp == m.gate_hp_max and m.wave_state == m.WS_BATTLE and m.gate_hits == 0
		print("  прогон %d: сцена свежая: %s (tick %d, ворота %.0f/%.0f, юнитов %d, состояние %d)" % [runs.size() + 1, fresh, m.tick_counter, m.gate_hp, m.gate_hp_max, m.count, m.wave_state])
		for i in m.count:
			if m.team[i] == 0:
				m.hp[i] = 0.0
		started = true
		return false
	if m.wave_state == m.WS_DEFEAT:
		runs.append([m.tick_counter, checksum(m), m.gate_hits])
		print("  прогон %d: ворота пали на тике %d, ударов %d, баннер: «%s»" % [runs.size(), m.tick_counter, m.gate_hits, m.banner.text])
		if runs.size() == 2:
			print("(в) второй прогон совпадает с первым: %s" % (runs[0] == runs[1]))
			if saved_record != null:
				var f := FileAccess.open("user://record.json", FileAccess.WRITE)
				f.store_string(saved_record)
				f.close()
			elif FileAccess.file_exists("user://record.json"):
				DirAccess.remove_absolute(OS.get_user_data_dir() + "/record.json")
			return true
		var ev := InputEventKey.new()
		ev.keycode = KEY_R
		ev.pressed = true
		m._unhandled_input(ev)   # то же, что нажать R
		started = false
		return false
	if frames > 30 * 120:
		print("FAIL: ворота не пали за 120 с")
		return true
	return false