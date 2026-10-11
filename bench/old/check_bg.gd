extends SceneTree
func _initialize() -> void:
	var path := "res://art/castle_bg.jpg"
	var ok := ResourceLoader.exists(path)
	var tex: Texture2D = load(path) if ok else null
	print("exists=%s, размер=%s" % [ok, tex.get_size() if tex else "—"])
	quit()