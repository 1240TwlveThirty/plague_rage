extends RefCounted
# Предохранитель по времени для скриптов-сцен (view_*, shots_*; задача 27): если сцена не дошла до quit() за
# data/bench.json watchdog_sec (по имени скрипта или default) секунд реального времени — FAIL и выход.
# Ловит и ошибку скрипта в корутине (после SCRIPT ERROR функция обрывается, quit() не вызывается, окно висит).
# Вызов: preload("res://bench/watchdog.gd").arm(self) в _initialize.

static func limit_sec(script_path: String) -> float:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bench.json"))
	var w: Dictionary = cfg["watchdog_sec"]
	return float(w.get(script_path.get_file().get_basename(), w["default"]))

static func arm(tree: SceneTree) -> void:
	var path: String = tree.get_script().resource_path
	var sec := limit_sec(path)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bench.json"))
	var code := int(cfg["watchdog_exit_code"])
	# process_always — идёт и на паузе дерева; ignore_time_scale — секунды реальные при Engine.time_scale 4 или 8
	tree.create_timer(sec, true, false, true).timeout.connect(func():
		printerr("FAIL: предохранитель — %s не закончился за %.0f с (data/bench.json watchdog_sec); выход с кодом %d" % [path.get_file(), sec, code])
		print("FAIL: watchdog %s %.0f с" % [path.get_file(), sec])
		Engine.time_scale = 1.0
		tree.quit(code))
