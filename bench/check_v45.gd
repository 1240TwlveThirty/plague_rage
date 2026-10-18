extends SceneTree
# Тесты v45: меню и хаб по центру экрана, золотые кнопки на чёрном фоне, меню паузы по Esc в хабе и в бою.
# Узел Game с временным сохранением в user://bench_v45 (настоящий user://save.json не трогается). «Выход» не нажимается.
const GAME := "res://scripts/game.gd"
const MAIN := "res://scripts/main.gd"
const UI := preload("res://scripts/ui.gd")
const DIR := "user://bench_v45"
const SCREEN := Vector2(1920.0, 1080.0)
var fails := 0
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	return e

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == MAIN:
		n.process_mode = Node.PROCESS_MODE_DISABLED

func gold(b: Button) -> bool:
	var s := b.get_theme_stylebox("normal")
	return s is StyleBoxFlat and s.bg_color == UI.GOLD

# Прямоугольник узла целиком на экране и по центру по горизонтали.
func centered(c: Control) -> bool:
	var r := c.get_global_rect()
	return Rect2(Vector2.ZERO, SCREEN).encloses(r) and absf(r.get_center().x - SCREEN.x * 0.5) <= 1.0 and r.size.x > 0.0

func bg_of(scene: Control) -> ColorRect:
	return scene.get_child(0) as ColorRect

func real_stamp() -> String:
	return "%d/%d" % [FileAccess.get_modified_time("user://save.json"), FileAccess.get_file_as_bytes("user://save.json").size()] if FileAccess.file_exists("user://save.json") else "нет"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	var real := real_stamp()
	DirAccess.make_dir_recursive_absolute(DIR)
	node_added.connect(_on_node_added)
	g = load(GAME).new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	g.radiance = 100
	check("окно теста 1920x1080", root.get_visible_rect().size == SCREEN, str(root.get_visible_rect().size))

	print("меню")
	g.go_menu()
	await step(3)
	var mn := current_scene as Control
	check("меню занимает весь экран, фон чёрный на весь экран", mn != null and mn.name == "Menu" and mn.size == SCREEN and bg_of(mn).color == Color.BLACK and bg_of(mn).size == SCREEN, str(mn.size))
	check("«Играть» и «Выход» по центру, золотые, фокус на «Играть»", centered(mn.play_button) and centered(mn.quit_button) and gold(mn.play_button) and gold(mn.quit_button)
		and mn.play_button.has_focus() and mn.play_button.get_global_rect().get_center().y > 300.0, str(mn.play_button.get_global_rect()))
	mn.play_button.pressed.emit()
	await step(3)

	print("хаб")
	var h := current_scene as Control
	check("хаб занимает весь экран, фон чёрный на весь экран", h != null and h.name == "Hub" and h.size == SCREEN and bg_of(h).color == Color.BLACK and bg_of(h).size == SCREEN, str(h.size))
	check("вкладка «Осада»: вкладки и кнопки по центру и целиком на экране, кнопки золотые", centered(h.tabs) and centered(h.start_button) and centered(h.diary_button) and centered(h.menu_button)
		and gold(h.start_button) and gold(h.diary_button) and gold(h.menu_button), str(h.tabs.get_global_rect()))
	h.tabs.current_tab = 1
	await step(2)
	var row: Dictionary = h.gift_rows["reserve"]
	check("вкладка «Дары»: по центру, целиком на экране (ширина %d), баланс виден, «Купить» золотая" % int(h.tabs.get_global_rect().size.x), centered(h.tabs) and centered(h.radiance_label.get_parent())
		and gold(row.button) and Rect2(Vector2.ZERO, SCREEN).encloses(row.reason.get_global_rect()), str(h.tabs.get_global_rect()))
	h.tabs.current_tab = 0
	await step(1)

	print("Esc в хабе")
	var em: CanvasLayer = h.esc_menu
	check("меню паузы скрыто, дерево не на паузе", em != null and not em.visible and not paused)
	h._unhandled_input(esc())
	await step(2)
	check("Esc: меню паузы открыто, дерево на паузе, фокус на «Продолжить»; кнопки «Продолжить», «Выйти в меню», «Выход из игры» золотые и по центру, предупреждения нет", em.visible and paused and em.continue_button.has_focus()
		and tr(em.continue_button.text) == "Продолжить" and tr(em.menu_button.text) == "Выйти в меню" and tr(em.quit_button.text) == "Выход из игры" and not em.note_label.visible and gold(em.continue_button) and gold(em.quit_button)
		and centered(em.continue_button) and centered(em.menu_button) and centered(em.quit_button))
	check("«Выход из игры» ведёт в Game.quit_game (сохранить и закрыть игру); не нажимается", em.quit_button.pressed.is_connected(em._on_quit) and g.has_method("quit_game"))
	var play_hub: float = g.play_time
	await step(30)
	check("30 кадров паузы в хабе: play_time стоит", g.play_time == play_hub, "%.3f -> %.3f" % [play_hub, g.play_time])
	em._input(esc())
	await step(5)
	check("Esc ещё раз: меню закрыто, пауза снята, хаб на месте, play_time снова идёт", not em.visible and not paused and current_scene == h and g.play_time > play_hub)
	h._unhandled_input(esc())
	em.continue_button.pressed.emit()
	check("«Продолжить»: меню закрыто, пауза снята", not em.visible and not paused and current_scene == h)
	h.diary_button.pressed.emit()
	h._unhandled_input(esc())
	check("при открытом дневнике Esc закрывает дневник, меню паузы не открывается", not h.diary_panel.visible and not em.visible and not paused)
	h._unhandled_input(esc())
	em.menu_button.pressed.emit()
	await step(3)
	check("«Выйти в меню» из хаба: сцена меню, пауза снята, забегов и Сияния не прибавилось", current_scene != null and current_scene.name == "Menu" and not paused and g.runs_total == 0 and g.radiance == 100)

	print("Esc в бою")
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	em = m.esc_menu
	check("бой начат, меню паузы скрыто", m != null and em != null and not em.visible and not paused and g.run_index == 1)
	m.drag_active = true
	m._unhandled_input(esc())
	check("Esc во время протяжки отменяет её, меню паузы не открывается", not m.drag_active and not em.visible and not paused)
	m.box_active = true
	m._unhandled_input(esc())
	check("Esc во время рамки отменяет её, меню паузы не открывается", not m.box_active and not em.visible and not paused)
	m._start_wave()
	m.process_mode = Node.PROCESS_MODE_INHERIT   # бой идёт сам, как в игре
	await step(20)
	check("бой идёт сам: тики и время волны растут", m.tick_counter > 0 and m.wave_t > 0.0 and m.wave_state == m.WS_BATTLE, "тик %d" % m.tick_counter)
	m._unhandled_input(esc())
	var tick0: int = m.tick_counter
	var wave_t0: float = m.wave_t
	var signals0: int = m.burst_signal_n
	var play0: float = g.play_time
	await step(30)
	check("Esc в бою: меню паузы открыто, дерево на паузе, предупреждение «%s»; пауза боя (P) не включена" % m.ESC_NOTE, em.visible and paused and not m.paused and m.wave_state == m.WS_BATTLE
		and em.continue_button.has_focus() and em.note_label.visible and tr(em.note_label.text) == "Выход в меню засчитает поражение")
	check("30 кадров паузы: симуляция стоит (тик %d), окно сигнала стоит (время волны и число сигналов прежние), play_time стоит" % tick0,
		m.tick_counter == tick0 and m.wave_t == wave_t0 and m.burst_signal_n == signals0 and g.play_time == play0, "тик %d, play_time %.3f -> %.3f" % [m.tick_counter, play0, g.play_time])
	em._input(esc())
	await step(20)
	check("Esc ещё раз: бой продолжается с той же волны, тики, время волны и play_time снова идут", not em.visible and not paused and current_scene == m and m.wave_number == 1
		and m.wave_state == m.WS_BATTLE and m.tick_counter > tick0 and m.wave_t > wave_t0 and g.play_time > play0)
	m._unhandled_input(esc())
	em.continue_button.pressed.emit()
	check("«Продолжить»: меню закрыто, пауза снята", not em.visible and not paused and current_scene == m)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	var kills: int = m.run_kills
	m._unhandled_input(esc())
	em.menu_button.pressed.emit()
	await step(3)
	check("«Выйти в меню» в бою на волне 1: сцена меню, пауза снята; забег засчитан поражением на волне 1, Сияния +0",
		current_scene != null and current_scene.name == "Menu" and not paused and g.runs_total == 1 and g.records[1] == {"best_wave": 1, "wins": 0, "runs": 1} and g.radiance == 100
		and g.last_run == {"siege": 1, "result": "loss", "wave": 1, "kills": kills, "radiance": 0}, str(g.last_run))
	g.start_run(1)
	await step(3)
	m = current_scene as Node2D
	m.wave_number = 3   # три волны пройдены, передышка
	m._unhandled_input(esc())
	m.esc_menu.menu_button.pressed.emit()
	await step(3)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(g.save_path))
	check("«Выйти в меню» в передышке после волны 3: поражение на волне 4, Сияния +15 (волны 1-3), записано в сохранение",
		current_scene.name == "Menu" and g.last_run.result == "loss" and g.last_run.wave == 4 and g.last_run.radiance == 15 and g.radiance == 115 and g.runs_total == 2
		and g.records[1].best_wave == 4 and saved is Dictionary and saved.get("radiance") == 115, str(g.last_run))
	current_scene.play_button.pressed.emit()
	await step(3)
	check("хаб после брошенного забега: «Последний забег: поражение на волне 4»", current_scene.name == "Hub" and tr(current_scene.last_label.text) == "Последний забег: поражение на волне 4", current_scene.last_label.text)
	g.start_run(1)
	await step(3)
	m = current_scene as Node2D
	m.wave_number = 2
	m.wave_state = m.WS_BATTLE
	m._on_defeat()
	var rad: int = g.radiance
	m._unhandled_input(esc())
	check("на экране итога Esc тоже открывает меню паузы, без предупреждения", m.esc_menu.visible and paused and not m.esc_menu.note_label.visible and g.runs_total == 3)
	m.esc_menu.menu_button.pressed.emit()
	await step(3)
	check("«Выйти в меню» с экрана итога: повторно забег не засчитан", current_scene.name == "Menu" and g.runs_total == 3 and g.radiance == rad and g.last_run.wave == 2)

	current_scene.queue_free()
	g.queue_free()
	await step(2)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)
	check("настоящий user://save.json не тронут, временная папка убрана", real_stamp() == real and not DirAccess.dir_exists_absolute(DIR))
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
