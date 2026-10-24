extends SceneTree
# Уменьшенные копии иллюстраций отрядов для кнопок (задача 15): из data/unit_portraits.json (path, crop) — полосы с пропорциями
# кнопок, уменьшенные до 2x их размера (Lanczos): art/ui/<тип>_640x88.png (магазин 320x44) и <тип>_520x80.png (отряд 260x40),
# и art/ui/unit_portraits_made.json — из чего сделаны. Оригиналы не трогаются. После crop в данных — запустить снова:
#   godot --headless --path . -s res://bench/make_unit_portraits.gd   (новые PNG — затем godot --headless --path . --import)
const PORTRAITS := preload("res://scripts/portraits.gd")
const BUTTONS := [Vector2i(320, 44), Vector2i(260, 40)]   # кнопка магазина, кнопка отряда (main.gd)

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	var p := PORTRAITS.new()
	p.load_defs()
	DirAccess.make_dir_recursive_absolute(PORTRAITS.UI_DIR)
	var made := {}
	var fails := 0
	for t in p.defs:
		var d: Dictionary = p.defs[t]
		var src := PORTRAITS.source_image(d.path)
		for bs in BUTTONS:
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
