extends SceneTree
# Кадры задачи 28б (с окном): главное меню, пауза в бою (Esc), хаб — так же, как F12 (Shots.capture). На каждом кадре — заголовок
# окна и тексты всех видимых Label/Button (после перевода): нигде нет старого названия (OLD), название — из ключа GAME_TITLE.
# Аргумент — папка для кадров. Печатает SHOT80|файл|заголовок окна|старых названий на экране N и SHOTS80: провалов N.
const OLD := ["Plague", "Чума гнева"]
var fails := 0

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)   # задача 27: предохранитель по времени (data/bench.json)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

# Тексты видимых Label и Button под узлом n (переведённые).
func texts(n: Node, out: Array) -> void:
	if n is CanvasItem and not n.is_visible_in_tree():
		return
	if n is Label or n is Button:
		out.append(tr(n.text))
	for c in n.get_children():
		texts(c, out)

func shot(out: String, name: String) -> void:
	await _frames(12)
	var p: String = await root.get_node("Shots").capture()
	var dst := out.path_join(name + ".png")
	DirAccess.copy_absolute(p, dst)
	DirAccess.remove_absolute(p)
	var all: Array = []
	texts(root, all)
	var bad := 0
	for t in all + [root.title]:
		for o in OLD:
			if String(t).contains(o):
				bad += 1
	if bad > 0 or root.title != tr("GAME_TITLE"):
		fails += 1
	print("SHOT80|%s|заголовок окна «%s»|текстов на экране %d, старых названий %d" % [dst.get_file(), root.title, all.size(), bad])

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v80shots/save.json"   # временное сохранение: настоящее не трогается
	DirAccess.make_dir_recursive_absolute("user://bench_v80shots")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.go_menu()
	await _frames(4)
	await shot(out, "menu")
	g.run_seed = 3
	g.start_run(1)
	await _frames(20)
	current_scene._open_esc_menu()
	await shot(out, "pause")
	current_scene.esc_menu.close()
	g.go_hub()
	await _frames(4)
	await shot(out, "hub")
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v80shots")
	print("SHOTS80: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
