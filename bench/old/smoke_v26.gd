extends SceneTree
# Smoke UI v26: старт, волна 1, передышка, поражение, R, снова старт. Настоящая сцена, клавиши через Input.
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await step(3)

# Баннер: не шире 700 px, шрифт не меньше 36, не пересекает панели магазина и отрядов.
func layout(m: Node2D, label: String) -> void:
	var r: Rect2 = m.banner.get_global_rect()
	var min_font := 1000
	var lines := 0
	for l in m.banner_labels:
		if l.visible:
			min_font = mini(min_font, l.get_theme_font_size("font_size"))
			lines += l.get_line_count()
	var shop_hit: bool = m.shop_panel.visible and r.intersects(m.shop_panel.get_global_rect())
	var centered: bool = r.get_center().distance_to(Vector2(960, 540)) <= 1.0 and absf(r.size.y - m.banner.get_combined_minimum_size().y) <= 1.0
	check(label + ": ширина ≤ 700, шрифт ≥ 36, по центру, панели не перекрыты", r.size.x <= 700.0 and min_font >= 36 and centered and not shop_hit and not r.intersects(m.squad_panel.get_global_rect()),
		"баннер %s, строк %d, шрифт от %d, магазин %s, отряды %s" % [r, lines, min_font, m.shop_panel.get_global_rect(), m.squad_panel.get_global_rect()])

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var m: Node2D = load("res://scenes/main.tscn").instantiate()
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(5)
	print("окно %s" % root.size)
	check("старт: передышка, волна 0", m.wave_state == m.WS_RESPITE and m.wave_number == 0)
	check("старт: заголовок, intro, подсказка", m.banner.visible and m.banner_labels[0].text == "Дневник военачальника" and m.banner_labels[2].text == m.story_intro
		and m.story_intro != "" and m.banner_labels[3].text == "Расставь отряды. Space — начать волну 1" and not m.banner_labels[1].visible)
	layout(m, "старт")
	await key(KEY_SPACE)
	check("Space: волна 1 идёт, баннер скрыт", m.wave_state == m.WS_BATTLE and m.wave_number == 1 and not m.banner.visible)
	var frames := 0
	while m.wave_state == m.WS_BATTLE and frames < 20000:
		await process_frame
		frames += 1
	await step(3)
	check("волна 1 пройдена: строка итога и запись дневника", m.wave_state == m.WS_RESPITE and m.banner.visible and m.banner_labels[1].text.begins_with("Волна 1 пройдена")
		and m.banner_labels[2].text == m._entry_text(1) and m.banner_labels[2].visible == (m._entry_text(1) != ""), "тиков %d" % m.tick_counter)
	layout(m, "передышка")
	await key(KEY_SPACE)
	check("Space: волна 2 идёт", m.wave_state == m.WS_BATTLE and m.wave_number == 2)
	m.gate_hp = 0.0   # ворота пали
	await step(5)
	check("поражение: концовка и рекорд", m.wave_state == m.WS_DEFEAT and m.banner.visible and m.banner_labels[2].text == m._ending_text(2)
		and m.banner_labels[3].text == "Рекорд: день %d. R — заново" % m.best_wave and not m.banner_labels[2].text.contains("{wave}"), m.banner_labels[2].text)
	layout(m, "поражение")
	await key(KEY_R)
	await step(5)
	var m2: Node2D = current_scene
	check("R: новая сцена, передышка, волна 0, баннер старта", m2 != null and m2 != m and m2.wave_state == m2.WS_RESPITE and m2.wave_number == 0
		and m2.is_physics_processing() and m2.banner.visible and m2.banner_labels[0].text == "Дневник военачальника")
	layout(m2, "после R")
	await key(KEY_SPACE)
	await step(30)
	check("после R: волна 1 идёт", m2.wave_state == m2.WS_BATTLE and m2.wave_number == 1 and m2.tick_counter > 0)
	print("SMOKE: провалов %d" % fails)
	quit()
