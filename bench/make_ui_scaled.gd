extends SceneTree
# Универсальные рамки (задача 18): проверка арта, увеличение ×scale ближайшим соседом и сборка темы. Всё — из data/ui_theme.json
# (масштаб, файлы, угол, число состояний кнопки), код при смене масштаба или угла не правится.
# Арт нарисован в пикселях арта (1 пиксель арта = scale x scale на экране 1920x1080); StyleBoxTexture рисует текстуру 1:1 к холсту,
# поэтому в игру идут заранее увеличенные копии в out_dir, а углы 9-slice в теме — угол x scale.
# Порядок (новые PNG надо импортировать, прежде чем тема на них сошлётся):
#   godot --headless --path . -s res://bench/make_ui_scaled.gd          — проверка, PNG в out_dir; тема — если PNG уже импортированы
#   godot --headless --path . --import                                  — импорт новых или изменённых PNG
#   godot --headless --path . -s res://bench/make_ui_scaled.gd          — ещё раз: тема (theme_path)
# Аргумент -- check: только проверка арта (печатает размеры, ничего не пишет). Итог: строка «UI_ART: ...» или FAIL.
const CFG := "res://data/ui_theme.json"
# Палитра Endesga 32
const PALETTE := ["be4a2f", "d77643", "ead4aa", "e4a672", "b86f50", "733e39", "3e2731", "a22633", "e43b44", "f77622", "feae34",
	"fee761", "63c74d", "3e8948", "265c42", "193c3e", "124e89", "0099db", "2ce8f5", "ffffff", "c0cbdc", "8b9bb4", "5a6988", "3a4466",
	"262b44", "181425", "ff0044", "68386c", "b55088", "f6757a", "e8b796", "c28569"]
const STATES := ["normal", "hover", "pressed", "disabled"]
const BUTTON := "FrameButton"
const PANEL := "FramePanel"
const LABEL := "FrameLabel"
const SLOT := "FrameSlot"   # окошко верхней панели боя и Сияния (задача 19): PanelContainer
const BAR := "FrameBar"     # полоса HP: рамка и заливка ×scale — иконки темы frame и fill, окно заливки — константы fill_left, fill_right

var fails := 0


func fail(msg: String) -> void:
	fails += 1
	print("FAIL  " + msg)


func _initialize() -> void:
	var check_only := "check" in OS.get_cmdline_user_args()
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG))
	var s: int = int(cfg.scale)
	var b: Dictionary = cfg.button
	var p: Dictionary = cfg.panel
	var b_img := check_art(b.file, int(b.corner), int(b.states), slice_of(b))
	var p_img := check_art(p.file, int(p.corner), 1, slice_of(p))
	var sl: Dictionary = cfg.slot
	var bar: Dictionary = cfg.bar
	var sl_img := check_art(sl.file, int(sl.corner), 1, slice_of(sl))
	var bf_img := check_art(bar.frame, 0, 1, 0)
	var bl_img := check_art(bar.fill, 0, 1, 0)
	if bf_img != null and bl_img != null:
		check_bar(bar, bf_img, bl_img)
	for st in STATES:
		if int(b.state_rows[st]) < 0 or int(b.state_rows[st]) >= int(b.states):
			fail("button.state_rows.%s = %d вне 0..%d" % [st, int(b.state_rows[st]), int(b.states) - 1])
	if fails > 0 or check_only:
		print("UI_ART: %s" % ("провалов %d" % fails if fails > 0 else "проверка пройдена"))
		quit(1 if fails > 0 else 0)
		return
	var b_out := scaled(b_img, b.file, cfg.out_dir, s)
	var p_out := scaled(p_img, p.file, cfg.out_dir, s)
	var sl_out := scaled(sl_img, sl.file, cfg.out_dir, s)
	var bf_out := scaled(bf_img, bar.frame, cfg.out_dir, s)
	var bl_out := scaled(bl_img, bar.fill, cfg.out_dir, s)
	var b_tex := imported(b_out, b_img, s)
	var p_tex := imported(p_out, p_img, s)
	var tex := {"slot": imported(sl_out, sl_img, s), "frame": imported(bf_out, bf_img, s), "fill": imported(bl_out, bl_img, s)}
	if b_tex == null or p_tex == null or tex.values().has(null):
		print("UI_ART: PNG записаны; импортируйте (godot --headless --path . --import) и запустите скрипт ещё раз — тогда соберётся тема")
		quit(0)
		return
	var theme := build_theme(cfg, b_tex, p_tex, tex)
	var err := ResourceSaver.save(theme, cfg.theme_path)
	if err != OK:
		fail("не сохранить %s: %d" % [cfg.theme_path, err])
	print("UI_ART: тема %s, масштаб %d, кнопка %s (срез %d), панель %s (срез %d), окошко %s (срез %d), полоса %s + %s" % [cfg.theme_path, s,
		b_out, slice_of(b) * s, p_out, slice_of(p) * s, sl_out, slice_of(sl) * s, bf_out, bl_out])
	quit(1 if fails > 0 else 0)


# Срез 9-slice в пикселях арта: slice из ui_theme.json, если задан (рисунок угла шире угла из имени), иначе угол.
func slice_of(d: Dictionary) -> int:
	return int(d.get("slice", d.corner))


# Полоса: рамка и заливка одного размера и совпадают вне окна заливки fill_left..ширина-fill_right (пиксели арта): заливка,
# обрезанная по доле поверх рамки, не даёт ступеньки на краях; внутри окна заливка отличается от рамки (иначе полосы не видно).
func check_bar(bar: Dictionary, frame: Image, fill: Image) -> void:
	var w := frame.get_width()
	var h := frame.get_height()
	if fill.get_size() != frame.get_size():
		fail("полоса: заливка %s и рамка %s разного размера" % [fill.get_size(), frame.get_size()])
		return
	var l := int(bar.fill_left)
	var r := int(bar.fill_right)
	if l < 0 or r < 0 or l + r >= w:
		fail("полоса: окно заливки fill_left %d, fill_right %d вне ширины %d" % [l, r, w])
		return
	var outside := 0
	var inside := 0
	for y in h:
		for x in w:
			if same(frame.get_pixel(x, y), fill.get_pixel(x, y)):
				continue
			if x < l or x >= w - r:
				outside += 1
			else:
				inside += 1
	print("    полоса: окно заливки x %d..%d из %d; вне окна заливка отличается от рамки в %d пикс., внутри — в %d" % [l, w - r, w, outside, inside])
	if outside > 0:
		fail("полоса: вне окна заливка отличается от рамки в %d пикселях — на краях будет ступенька" % outside)
	if inside == 0:
		fail("полоса: заливка внутри окна не отличается от рамки — полосу не видно")


# Размеры, угол в имени, состояния, углы не пустые, только альфа 0 и 255, цвета из палитры, края 9-slice однородны при срезе.
# Печатает реальные размеры и наименьший срез с однородными краями. corner 0 — не 9-slice (полоса): размер, альфа, палитра.
func check_art(path: String, corner: int, states: int, slice: int) -> Image:
	if not FileAccess.file_exists(path):
		fail("нет файла %s" % path)
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var sh := h / states
	print("  %s: %d x %d, состояний %d по %d x %d, угол %d" % [path, w, h, states, w, sh, corner])
	if corner == 0:
		if w % 2 != 0:
			fail("%s: нечётная ширина %d" % [path, w])
		check_pixels(img, path)
		return img
	var m := RegEx.create_from_string("_c(\\d+)\\.png$").search(path)
	if m == null or int(m.get_string(1)) != corner:
		fail("%s: угол в имени (%s) не совпадает с углом в ui_theme.json (%d)" % [path, "нет" if m == null else m.get_string(1), corner])
	if w % 2 != 0:
		fail("%s: нечётная ширина %d" % [path, w])
	if h % states != 0:
		fail("%s: высота %d не делится на %d состояния" % [path, h, states])
	if w < corner * 2 + 1 or sh < corner * 2 + 1:
		fail("%s: кадр %d x %d меньше двух углов %d + 1" % [path, w, sh, corner])
		return img
	check_pixels(img, path)
	for k in states:
		for corner_at in [Vector2i(0, 0), Vector2i(w - corner, 0), Vector2i(0, sh - corner), Vector2i(w - corner, sh - corner)]:
			var o: Vector2i = corner_at + Vector2i(0, k * sh)
			var opaque := 0
			for y in corner:
				for x in corner:
					opaque += 1 if img.get_pixel(o.x + x, o.y + y).a > 0.0 else 0
			if opaque == 0:
				fail("%s: состояние %d, угол %s пустой целиком" % [path, k, str(corner_at)])
	var clean := -1
	for c in range(1, mini(w, sh) / 2):
		if clean_at(img, states, c):
			clean = c
			break
	print("    срез: %d (угол %d), наименьший с однородными краями: %s" % [slice, corner, "нет" if clean < 0 else str(clean)])
	if slice < corner:
		fail("%s: срез %d меньше угла %d" % [path, slice, corner])
	elif not clean_at(img, states, slice):
		fail("%s: при срезе %d края и середина неоднородны — при растяжении появятся полосы (наименьший однородный срез %s)" % [path, slice,
			"нет" if clean < 0 else str(clean)])
	return img


# Только альфа 0 и 255, непрозрачные пиксели — из палитры.
func check_pixels(img: Image, path: String) -> void:
	var bad_alpha := 0
	var off_palette := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var a := roundi(c.a * 255.0)
			if a != 0 and a != 255:
				bad_alpha += 1
			elif a == 255 and not PALETTE.has(c.to_html(false)):
				off_palette[c.to_html(false)] = true
	if bad_alpha > 0:
		fail("%s: полупрозрачных пикселей %d" % [path, bad_alpha])
	if not off_palette.is_empty():
		fail("%s: цвета не из Endesga 32: %s" % [path, ", ".join(off_palette.keys())])


# Края (вдоль растяжения) и середина каждого состояния однородны при срезе m: растянутая полоса не даёт пятен и разрывов.
func clean_at(img: Image, states: int, m: int) -> bool:
	var w := img.get_width()
	var sh := img.get_height() / states
	if w < m * 2 + 1 or sh < m * 2 + 1:
		return false
	for k in states:
		var oy := k * sh
		for y in sh:
			var mid_row := y >= m and y < sh - m
			for x in range(m, w - m):
				if not same(img.get_pixel(x, oy + y), img.get_pixel(m, oy + y)):
					return false
			if mid_row:
				for x in w:
					var ref := img.get_pixel(x, oy + m)
					if (x < m or x >= w - m) and not same(img.get_pixel(x, oy + y), ref):
						return false
		for y in range(m, sh - m):
			for x in range(m, w - m):
				if not same(img.get_pixel(x, oy + y), img.get_pixel(m, oy + m)):
					return false
	return true


func same(a: Color, b: Color) -> bool:
	return a == b or (a.a == 0.0 and b.a == 0.0)


# Копия ×s ближайшим соседом в out_dir (то же имя); перезаписывается, только если изменилась.
func scaled(img: Image, src: String, out_dir: String, s: int) -> String:
	var big := img.duplicate() as Image
	big.resize(img.get_width() * s, img.get_height() * s, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var out := out_dir.path_join(src.get_file())
	var old := Image.load_from_file(ProjectSettings.globalize_path(out)) if FileAccess.file_exists(out) else null
	if old != null:
		old.convert(Image.FORMAT_RGBA8)
	if old == null or old.get_data() != big.get_data():
		big.save_png(ProjectSettings.globalize_path(out))
		print("  записан %s (%d x %d)" % [out, big.get_width(), big.get_height()])
	else:
		print("  %s без изменений" % out)
	return out


# Импортированная текстура, совпадающая пиксель в пиксель с исходником ×s; иначе null (импорт устарел или его нет).
func imported(path: String, src: Image, s: int) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var big := src.duplicate() as Image
	big.resize(src.get_width() * s, src.get_height() * s, Image.INTERPOLATE_NEAREST)
	if not same_visible(img, big):
		print("  %s: импорт устарел" % path)
		return null
	return tex


# Совпадение пикселей; у полностью прозрачных цвет не важен (импорт с fix_alpha_border перекрашивает их в соседей).
func same_visible(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca != cb and not (ca.a == 0.0 and cb.a == 0.0):
				return false
	return true


func box(id: String, tex: Texture2D, corner: int, region: Rect2, margins: Vector4, modulate := Color.WHITE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.resource_scene_unique_id = id   # постоянные id в theme.tres: перегенерация без лишнего диффа
	sb.texture = tex
	sb.region_rect = region
	sb.set_texture_margin_all(corner)
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w
	sb.modulate_color = modulate
	return sb


# Тема только из вариаций типов: FrameButton (Button), FramePanel и FrameSlot (PanelContainer), FrameLabel (Label), FrameBar
# (иконки полосы). Базовые типы не задаются, поэтому подключённая к проекту тема не меняет ни одного контрола, которому вариацию
# не назначили явно.
func build_theme(cfg: Dictionary, b_tex: Texture2D, p_tex: Texture2D, tex: Dictionary) -> Theme:
	var s: int = int(cfg.scale)
	var b: Dictionary = cfg.button
	var p: Dictionary = cfg.panel
	var t := Theme.new()
	t.set_type_variation(BUTTON, "Button")
	t.set_type_variation(PANEL, "PanelContainer")
	t.set_type_variation(LABEL, "Label")
	var bc := slice_of(b) * s
	var sw := b_tex.get_width()
	var sh := b_tex.get_height() / int(b.states)
	var pad := float(int(b.corner) * s + int(b.text_pad))   # отступ текста от угла из имени (не от среза)
	var pad_v := float(b.text_pad_v)
	var shift := float(b.pressed_shift)
	for st in STATES:
		var region := Rect2(0, int(b.state_rows[st]) * sh, sw, sh)
		var m := Vector4(pad, pad_v + shift, pad, pad_v - shift) if st == "pressed" else Vector4(pad, pad_v, pad, pad_v)
		t.set_stylebox(st, BUTTON, box("button_" + st, b_tex, bc, region, m, Color(b.state_modulate[st])))
	t.set_stylebox("hover_pressed", BUTTON, t.get_stylebox("pressed", BUTTON))
	var focus := StyleBoxEmpty.new()
	focus.resource_scene_unique_id = "button_focus"
	t.set_stylebox("focus", BUTTON, focus)   # фокус с клавиатуры виден цветом текста (как наведение)
	var fc: Dictionary = b.font_colors
	t.set_color("font_color", BUTTON, Color(fc.normal))
	t.set_color("font_hover_color", BUTTON, Color(fc.hover))
	t.set_color("font_focus_color", BUTTON, Color(fc.hover))
	t.set_color("font_pressed_color", BUTTON, Color(fc.pressed))
	t.set_color("font_hover_pressed_color", BUTTON, Color(fc.pressed))
	t.set_color("font_disabled_color", BUTTON, Color(fc.disabled))
	t.set_color("font_outline_color", BUTTON, Color(b.outline_color))
	t.set_constant("outline_size", BUTTON, int(b.outline_size))
	t.set_constant("min_width", BUTTON, int(b.min_size[0]))   # не свойство Button: читает UI.frame_button для кнопок меню
	t.set_constant("min_height", BUTTON, int(b.min_size[1]))
	var pc := slice_of(p) * s
	var ppad := float(int(p.corner) * s + int(p.content_pad))
	t.set_stylebox("panel", PANEL, box("panel", p_tex, pc, Rect2(0, 0, p_tex.get_width(), p_tex.get_height()), Vector4(ppad, ppad, ppad, ppad)))
	t.set_color("font_outline_color", LABEL, Color(p.label_outline_color))
	t.set_constant("outline_size", LABEL, int(p.label_outline_size))
	var sl: Dictionary = cfg.slot
	var st: Texture2D = tex.slot
	t.set_type_variation(SLOT, "PanelContainer")
	var sh_pad := float(int(sl.corner) * s + int(sl.content_pad))
	var sv_pad := float(int(sl.corner) * s + int(sl.content_pad_v))
	t.set_stylebox("panel", SLOT, box("slot", st, slice_of(sl) * s, Rect2(0, 0, st.get_width(), st.get_height()), Vector4(sh_pad, sv_pad, sh_pad, sv_pad)))
	var bar: Dictionary = cfg.bar
	t.set_icon("frame", BAR, tex.frame)
	t.set_icon("fill", BAR, tex.fill)
	t.set_constant("fill_left", BAR, int(bar.fill_left) * s)    # окно заливки на экране от левого края картинки
	t.set_constant("fill_right", BAR, int(bar.fill_right) * s)  # и от правого
	t.set_constant("step", BAR, s)                              # заливка режется по пикселям арта (кратно масштабу)
	return t
