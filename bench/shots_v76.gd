extends "res://bench/shots_v72_ui.gd"
# Снимки задачи 26 (окно 1920x1080) для ru и en в папку-аргумент (<язык>_<экран>.png). Обход текста — как в shots_v72_ui
# (строки «CLIP|...»). Временное сохранение user://bench_v72s; подсказки — в памяти (тестовый запуск не пишет настройки).
#   Первая минута новым игроком: главное меню, хаб, начало боя (баннер без вступления), бой в реальном времени — кадр каждые
#   10 с до 60 с (подсказки: выбор и приказ, «ПКМ — идти…», удар Командира), передышка после волны (подсказка магазина).
#   Панель отряда, кнопка и всплывающая подсказка «Оружия» («до → после»), подсветка после покупки, настройки — все вкладки,
#   призрак блока при зажатой ПКМ (можно и нельзя).

func hover(c: Control) -> void:
	var e := InputEventMouseMotion.new()
	e.position = c.get_global_rect().get_center()
	e.global_position = e.position
	e.relative = Vector2(1, 1)
	Input.warp_mouse(e.position)
	root.push_input(e)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:   # задержка всплывающей подсказки
		await process_frame

func rmb(m: Node2D, w: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = pressed
	e.position = m.get_global_transform_with_canvas() * w
	m._unhandled_input(e)

func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a): return not a.begins_with("--font="))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var g: Node = root.get_node_or_null("Game")
	var st: Node = root.get_node("Settings")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	for l in ["ru", "en"]:
		lang = l
		TranslationServer.set_locale(l)
		DirAccess.remove_absolute(g.save_path)
		g._setup()   # новый игрок: сохранения нет
		g.run_seed = 3
		st.reset_hints()
		st.squad_panel_expanded = true
		print("первая минута, %s" % l)
		g.go_menu()
		await step(8)
		var mn := current_scene
		await shot("a0_menu")
		scan("a0_menu", mn)
		for t in mn.settings_menu.tabs.get_tab_count():
			mn.settings_menu.open()
			mn.settings_menu.tabs.current_tab = t
			await step(3)
			await shot("settings_%d" % t)
			scan("settings_%d" % t, mn.settings_menu)
		mn.settings_menu.close()
		g.go_hub()
		await step(5)
		await shot("a1_hub")
		scan("a1_hub", current_scene)
		g.start_run(1)
		await step(5)
		var m := current_scene as Node2D
		refresh(m)
		await shot("a2_start")
		scan("a2_start", m)
		# бой в реальном времени: Space, кадр каждые 10 с; на 12-й с игрок выбирает отряд, на 20-й — приказ ПКМ
		m._start_wave()
		var t0 := Time.get_ticks_msec()
		var next := 0
		var picked := false
		var ordered := false
		while next <= 60:
			var sec := (Time.get_ticks_msec() - t0) / 1000.0
			if not picked and sec >= 12.0:
				picked = true
				m._select_only(0)
			if not ordered and sec >= 20.0:
				ordered = true
				rmb(m, m.squad_pos[0] + Vector2(0, -60), true)
				rmb(m, m.squad_pos[0] + Vector2(0, -60), false)
			if sec >= next:
				await shot("b%02d_battle" % next)
				print("    %d с: подсказка «%s»" % [next, m.hints.label.text if m.hints.visible else "—"])
				next += 10
			await process_frame
		# до конца волны быстро (зомби снимаются по мере появления), передышка с подсказкой магазина
		Engine.time_scale = 8.0
		var guard := 0
		while m.wave_state == m.WS_BATTLE and guard < 4000:
			for i in m.count:
				if m.team[i] == 1:
					m.hp[i] = 0.0
			await process_frame
			guard += 1
		Engine.time_scale = 1.0
		await step(10)
		refresh(m)
		await shot("c0_respite")
		scan("c0_respite", m)
		print("    передышка: подсказка «%s»" % (m.hints.label.text if m.hints.visible else "—"))
		m.process_mode = Node.PROCESS_MODE_DISABLED   # дальше — неподвижные снимки интерфейса
		m.hints.dismiss()
		m.banner.visible = false   # баннер итога волны закрыл бы поле (H прячет его так же)
		# панель отряда, «до → после», подсветка после покупки
		m.gold = 1000.0
		m._select_only(0)
		refresh(m)
		await shot("d0_squad_info")
		var wk: int = m.SHOP_ITEMS.find("weapons")
		await hover(m.shop_buttons[wk])
		await shot("d1_upgrade_tooltip")
		m._buy(wk)
		refresh(m)
		m._update_squad_panel()
		await shot("d2_after_buy")
		# призрак блока: ПКМ зажата (можно, затем нельзя — на цели другого отряда)
		var w: Vector2 = m.squad_pos[0] + Vector2(-240, -140)
		rmb(m, w, true)
		m.queue_redraw()
		await shot("e0_ghost")
		rmb(m, w, false)
		m._select_only(0)
		rmb(m, m.squad_target[1], true)
		m.queue_redraw()
		await shot("e1_ghost_bad")
		rmb(m, m.squad_target[1], false)
		m.queue_free()
		await step(3)
	TranslationServer.set_locale("ru")
	print("CLIPS: %d" % clips)
	quit(0)
