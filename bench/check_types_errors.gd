extends SceneTree
func _initialize() -> void:
	for name in ["missing", "broken", "nopeasant"]:
		var m: Node2D = load("res://bench/main_err_%s.gd" % name).new()
		m._setup_data()
		print("%s: type_id пуст=%s, юнитов создано=%d, physics_process=%s" % [name, m.type_id.is_empty(), m.pos.size(), m.is_physics_processing()])
		m.free()
	quit()