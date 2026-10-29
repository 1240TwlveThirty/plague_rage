extends "res://bench/shots_v72_ui.gd"
# Снимки задачи 24 (окно 1920x1080) для ru и en: передышка с открытым и закрытым магазином, бой, панель отрядов развёрнутая
# и свёрнутая, хаб («Осада», «Дары») и настройки (вкладки) на тёмной панели. Обход текста и кнопок — как в shots_v72_ui
# (строки «CLIP|...»). Аргумент: папка для PNG (<язык>_<экран>.png). Временное сохранение user://bench_v72s.

func slide(m: Node2D) -> void:
	for i in 60:
		m.shop_slide_step(1.0 / 60.0)

func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a): return not a.begins_with("--font="))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var locale := TranslationServer.get_locale()
	var g: Node = root.get_node_or_null("Game")
	var st: Node = root.get_node("Settings")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	node_added.connect(_on_node_added)
	for l in ["ru", "en"]:
		lang = l
		TranslationServer.set_locale(l)
		DirAccess.remove_absolute(g.save_path)
		g._setup()
		g.run_seed = 3
		g.radiance = 1240
		st.squad_panel_expanded = true
		g.go_menu()
		await step(8)
		var mn := current_scene
		for t in 3:
			mn.settings_menu.open()
			mn.settings_menu.tabs.current_tab = t
			await step(3)
			await shot("settings_dark_%d" % t)
			scan("settings_dark_%d" % t, mn.settings_menu)
		mn.settings_menu.close()
		g.go_hub()
		await step(5)
		var h := current_scene
		await shot("hub_dark_siege")
		scan("hub_dark_siege", h)
		h.tabs.current_tab = 1
		await step(3)
		await shot("hub_dark_gifts")
		scan("hub_dark_gifts", h)
		for id in g.gift_defs:   # причины отказа в строках
			g.gift_levels[id] = 1
		g.radiance = 0
		h._refresh_gifts()
		await step(3)
		await shot("hub_dark_gifts_locked")
		scan("hub_dark_gifts_locked", h)
		g.gift_levels.clear()
		g.radiance = 1240
		g.start_run(1)
		await step(5)
		var m := current_scene as Node2D
		m.war_cry_level = 1   # Клич (дар) — чтобы кнопка была на снимках
		m._setup_war_cry_ui(m.squad_panel.get_parent())
		m._cmd_new_squad()   # третий отряд: в панели больше строк
		m.squad_panel_sig = -1
		m._update_squad_panel()
		refresh(m)
		slide(m)
		m.banner.visible = false
		await shot("respite_shop_open")
		scan("respite_shop_open", m)
		fixed("respite_shop_open", m)
		m.toggle_shop()
		slide(m)
		await shot("respite_shop_closed")
		scan("respite_shop_closed", m)
		m.toggle_shop()
		slide(m)
		m.toggle_squad_panel()
		refresh(m)
		await shot("respite_squads_collapsed")
		scan("respite_squads_collapsed", m)
		m.toggle_squad_panel()
		m._start_wave()
		for t in 90:
			m._physics_process(DT)
		m.banner.visible = false
		m.squad_panel_sig = -1
		m._update_squad_panel()
		refresh(m)
		slide(m)
		await shot("battle_squads_expanded")
		scan("battle_squads_expanded", m)
		fixed("battle_squads_expanded", m)
		m.toggle_squad_panel()
		refresh(m)
		await shot("battle_squads_collapsed")
		scan("battle_squads_collapsed", m)
		m.toggle_squad_panel()
		m.queue_free()
		await step(2)
	st.squad_panel_expanded = true
	TranslationServer.set_locale(locale)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("SHOTS: готово, мест с обрезанным текстом %d" % clips)
	quit(0)
