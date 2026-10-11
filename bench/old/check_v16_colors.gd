extends SceneTree
# Часть 1: регрессия (раскраска не меняет бой) + прогон _process во всех режимах F1–F4.
func _initialize() -> void:
	var a: Node2D = load("res://bench/old/main_bak16.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a._setup_data()
	b._setup_data()
	var first := -1
	var white := 0
	var states := [0, 0, 0, 0]
	for t in range(1, 30 * 30 + 1):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp):
			first = t
		var now: float = b.tick_counter / 30.0
		for i in b.count:
			if b.unit_squad[i] == 0:
				states[b.unit_state[i]] += 1
				if now - b.unit_slot_changed_t[i] < 0.5:
					white += 1
	print("регрессия против bak16 (обе без привязи): " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first))
	print("пехота, юнито-тики по состояниям: стоит %d, на врага %d, к слоту %d, бьёт %d; «белых» (F4) юнито-тиков %d" % [states[0], states[1], states[2], states[3], white])
	b._setup_rendering()
	b._setup_fps_label()
	for mode in 4:
		b.color_mode = mode
		b._process(0.016)
		var o := 0
		print("режим F%d: юнит 0 цвет (%.2f, %.2f, %.2f), подпись: %s" % [mode + 1, b.buf[o + 8], b.buf[o + 9], b.buf[o + 10], b.fps_label.text.get_slice("|", 5)])
	a.free()
	b.free()
	quit()