extends SceneTree
# Задача 27: нарочно зависающая сцена для проверки предохранителя (bench/check_v77_exit.ps1): ошибка скрипта в корутине,
# как в view_v47 до исправления, — quit() не вызывается. Предохранитель (data/bench.json watchdog_sec.diag_v77_hang) должен
# закрыть процесс с кодом watchdog_exit_code.

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var o: Object = RefCounted.new()
	print("HANG|до ошибки")
	print(o.get("нет_такого_поля").length())   # обрыв корутины: null.length()
	quit(0)
