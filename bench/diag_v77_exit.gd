extends SceneTree
# Задача 27: выход из игры в заданном состоянии (дочерний процесс bench/check_v77_exit.ps1, с окном).
# Аргументы: <состояние menu|pause|battle|hub|hubpause> <способ button|close>.
# button — нажатие настоящей кнопки «Выход» (меню, меню паузы боя или хаба: Game.quit_game — сохранить и выйти);
# close — запрос закрытия окна, как Alt+F4 / крестик: NOTIFICATION_WM_CLOSE_REQUEST по дереву и сигнал close_requested окна.
# Своё сохранение во временной папке user://bench_v77x. Печатает EXITTEST|<состояние>|<способ>|quit; сам quit() не зовёт —
# процесс должен закончиться от действия игры. Предохранителя нет нарочно: зависание ловит родитель по времени.

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var state: String = args[0] if args.size() > 0 else "menu"
	var how: String = args[1] if args.size() > 1 else "close"
	var g: Node = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute("user://bench_v77x")
	g.save_path = "user://bench_v77x/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	var quit_btn: Button = null
	match state:
		"menu":
			g.go_menu()
			await _frames(20)
			quit_btn = current_scene.quit_button
		"hub", "hubpause":
			g.go_hub()
			await _frames(20)
			if state == "hubpause":
				current_scene.esc_menu.open()
				await _frames(4)
			quit_btn = current_scene.esc_menu.quit_button
		"battle", "pause":
			g.start_run(1)
			await _frames(10)
			var m: Node = current_scene
			m.wave_number = 9
			m.wave_plan_for = -1
			m._start_wave()
			await _frames(60)   # бой идёт
			if state == "pause":
				m._open_esc_menu()
				await _frames(4)
			quit_btn = m.esc_menu.quit_button
	print("EXITTEST|%s|%s|scene %s" % [state, how, current_scene.name if current_scene else "-"])
	if how == "button":
		if not quit_btn.is_visible_in_tree():
			print("EXITTEST: кнопка «Выход» не видна — нажатие как у мыши невозможно")
		quit_btn.pressed.emit()
	else:
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		root.close_requested.emit()
	print("EXITTEST|quit")
