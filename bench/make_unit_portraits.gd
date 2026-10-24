extends SceneTree
# Уменьшенные копии иллюстраций отрядов для кнопок (задача 15): из data/unit_portraits.json (path, crop) — полосы с пропорциями
# кнопок, уменьшенные до 2x их размера (Lanczos): art/ui/<тип>_<2w>x<2h>.png для кнопки магазина и кнопки отряда
# (размеры — data/ui_layout.json: shop_button_size, squad_button_size), и art/ui/unit_portraits_made.json — из чего сделаны.
# Оригиналы не трогаются. После crop или размеров кнопок в данных — запустить снова:
#   godot --headless --path . -s res://bench/make_unit_portraits.gd   (новые PNG — затем godot --headless --path . --import)
const PORTRAITS := preload("res://scripts/portraits.gd")
const LAYOUT := "res://data/ui_layout.json"

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var p := PORTRAITS.new()
	p.load_defs()
	DirAccess.make_dir_recursive_absolute(PORTRAITS.UI_DIR)
	var lay = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var buttons := []   # кнопка магазина, кнопка отряда
	for key in ["shop_button_size", "squad_button_size"]:
		buttons.append(Vector2i(int(lay[key][0]), int(lay[key][1])))
	var made := {}
	var fails := 0
	for t in p.defs:
		var d: Dictionary = p.defs[t]
		var src := PORTRAITS.source_image(d.path)
		for bs in buttons:
			var size: Vector2i = bs * 2
			var img := PORTRAITS.strip(src, d.crop, size)
			if img == null:
				print("  %s: нет картинки %s или crop вне её" % [t, d.path])
				fails += 1
				continue
			var out := PORTRAITS.copy_path(t, size)
			img.save_png(out)
			var r := PORTRAITS.fit(d.crop, size, src.get_width(), src.get_height())
			print("  %s: %s, исходник %dx%d, crop %s -> полоса %s -> %dx%d" % [t, out, src.get_width(), src.get_height(), str(d.crop), str(r), size.x, size.y])
		made[t] = {"path": d.path, "crop": [d.crop.position.x, d.crop.position.y, d.crop.size.x, d.crop.size.y]}
	var f := FileAccess.open(PORTRAITS.MADE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(made, "\t") + "\n")
	f.close()
	print("PORTRAITS: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
