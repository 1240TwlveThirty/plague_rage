extends SceneTree
# Тесты задачи 24 (без окна): интерфейс. Все размеры, клавиши и длительности — из data/ui_layout.json и data/ui_theme.json.
#   Кнопки действий отряда: размер action_button_size, тексты ru и en с клавишами по умолчанию входят целиком (без многоточия
#   и без уменьшения кегля); переназначенная длинная клавиша — многоточие, целиком в подсказке, кнопка не растёт.
#   Строка FPS: флаг debug_fps выключен по умолчанию — строки нет; в релизной сборке нет и с флагом; с флагом — внизу слева,
#   не пересекает окошки верхней панели и панель отрядов.
#   Запасные рамки: файл рамки <prefix><угол>.png (временный, user://) подключается с углом из имени и состояниями столбиком;
#   после переименования — универсальная кнопка, одно предупреждение за запуск, сцена боя строится, кнопки того же размера.
#   Магазин: в передышке открыт (на экране, у правого края), в бою закрыт (за краем, скрыт, кнопки сворачивания нет); клавиша
#   shop_toggle (по умолчанию из ui_layout.json keys) и кнопка сворачивают и разворачивают; выезд за shop_slide_time; два блока
#   («Войска» — наборы отрядов, «Улучшения» — остальное); клик по панели не доходит до поля боя, клик мимо — доходит.
#   Панель отрядов: развёрнутая (строки, действия, Клич) и свёрнутая (квадратики и числа живых); клавиша и кнопка; состояние —
#   в Settings и в новой сцене то же.
#   Тёмные экраны: хаб и настройки — вкладки на тёмной панели (без файла — универсальная с затемнением, с файлом — свой арт),
#   строки даров на рамке ui_slot; контраст текста к фону (WCAG, середина арта рамки) не меньше contrast_min (ui_theme.json).
# Временное сохранение user://bench_v74 (user://save.json не трогается).
const FONTS := preload("res://scripts/fonts.gd")
const DIR := "user://bench_v74"
var fails := 0
var lay: Dictionary
var theme_cfg: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	lay = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	theme_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_theme.json"))
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	node_added.connect(_on_node_added)
	await t_frames(g)
	for l in ["ru", "en"]:
		TranslationServer.set_locale(l)
		g.start_run(1)
		await step(3)
		var m := current_scene as Node2D
		await t_actions(m, l)
		await t_shop(m, l)
		await t_squads(m, l)
		if l == "ru":
			await t_fps(m, g)
		m.queue_free()
		await step(2)
	TranslationServer.set_locale("ru")
	await t_dark(g)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Ширина строки text кнопки b при её кегле и место под текст (размер минус поля рамки).
func text_w(b: Button, text: String) -> float:
	return b.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x

func room_w(b: Button) -> float:
	return b.size.x - b.get_theme_stylebox("normal").get_minimum_size().x

func t_actions(m: Node2D, l: String) -> void:
	print("кнопки действий отряда, %s" % l)
	var want := Vector2(lay.action_button_size[0], lay.action_button_size[1])
	m._update_squad_panel()
	await step(2)
	var base := FONTS.px(FONTS.DEFAULT_SIZE)
	for b: Button in m.action_buttons:
		var w := text_w(b, b.text)
		print("ACTION|%s|%s|%.0f из %.0f px|кегль %d" % [l, b.text, w, room_w(b), b.get_theme_font_size("font_size")])
		check("%s: «%s» — размер %s, текст %.0f <= %.0f px целиком, кегль темы %d" % [l, b.text, str(want), w, room_w(b), base],
			b.size == want and w <= room_w(b) + 0.5 and b.get_theme_font_size("font_size") == base)
	# переназначенная длинная клавиша: кнопка того же размера, многоточие, целиком в подсказке
	var saved: Array = InputMap.action_get_events("squad_split")
	InputMap.action_erase_events("squad_split")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("squad_split", e)
	m._update_squad_panel()
	await step(2)
	var b: Button = m.action_buttons[1]
	check("%s: длинная клавиша «%s» — кнопка %s, многоточие, целиком в подсказке" % [l, b.text, str(b.size)], b.size == want
		and b.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and b.autowrap_mode == TextServer.AUTOWRAP_OFF and b.tooltip_text == b.text)
	InputMap.action_erase_events("squad_split")
	for ev in saved:
		InputMap.action_add_event("squad_split", ev)
	m._update_squad_panel()

func t_fps(m: Node2D, g: Node) -> void:
	print("строка FPS")
	var script: GDScript = load("res://scripts/main.gd")
	check("debug_fps в ui_layout.json выключен (%s), строки FPS нет" % str(lay.get("debug_fps")), lay.get("debug_fps") == false and m.fps_label == null
		and not m.debug_fps_on())
	check("релизная сборка: строки нет и с флагом, и с --debug-fps", not script.fps_wanted(false, true, PackedStringArray(["--debug-fps"])))
	check("отладочная сборка: флаг или --debug-fps включают строку", script.fps_wanted(true, true, PackedStringArray())
		and script.fps_wanted(true, false, PackedStringArray(["--debug-fps"])) and not script.fps_wanted(true, false, PackedStringArray()))
	# с флагом: новая сцена, строка внизу слева вне окошек и панели отрядов
	var m2: Node2D = load("res://scenes/main.tscn").instantiate()
	m2.debug_fps_force = true
	m2.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m2)
	await step(2)
	var ok: bool = m2.fps_label != null
	if ok:
		m2.fps_label.text = tr("DEBUG_FPS_LINE") % [999, 700, 1.0, 2.0, 0.5, 1, 1000.0, 99, 99]
		await step(2)
		var r: Rect2 = m2.fps_label.get_global_rect()
		var vp := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
		var clear: bool = not r.intersects(m2.top_hud.get_global_rect()) and not r.intersects(m2.squad_panel.get_global_rect())
		check("с флагом: строка %s внизу слева, на экране, не на окошках %s и не на панели отрядов %s" % [str(r), str(m2.top_hud.get_global_rect()),
			str(m2.squad_panel.get_global_rect())], clear and r.position.x < vp.x * 0.5 and r.end.y <= vp.y and r.position.y > vp.y * 0.5)
	else:
		check("с флагом строка FPS создана", false)
	m2.queue_free()
	await step(1)

const UI := preload("res://scripts/ui.gd")

func t_frames(g: Node) -> void:
	print("запасные рамки")
	var dir := DIR + "/frames"
	DirAccess.make_dir_recursive_absolute(dir)
	var tc := theme_cfg
	var s := int(tc.scale)
	for kind in ["shop", "squad"]:
		var fd: Dictionary = tc.frames[kind]
		var aw := int(fd.art_size[0])
		var ah := int(fd.art_size[1])
		var states := int(fd.states)
		var corner := 5   # не как у универсальной кнопки: видно, что угол взят из имени
		var img := Image.create(aw, ah * states, false, Image.FORMAT_RGBA8)
		for k in states:   # каждое состояние своим цветом: видно, какая строка взята
			img.fill_rect(Rect2i(0, k * ah, aw, ah), Color.from_hsv(k / float(states), 0.6, 0.8))
		var path := dir.path_join("%s%d.png" % [fd.prefix, corner])
		img.save_png(ProjectSettings.globalize_path(path))
		UI.reset_frames(dir)
		var f: Dictionary = UI.frame_styles(kind)
		var sb: StyleBoxTexture = f.styles.normal
		var pr: StyleBoxTexture = f.styles.pressed
		var rows: Dictionary = fd.state_rows
		check("%s: файл %s — свой арт, угол %d из имени (9-slice %d на экране), текстура x%d, состояние pressed — строка %d" % [kind, path.get_file(),
			f.corner, int(sb.texture_margin_left), s, int(rows.pressed)], not f.fallback and f.corner == corner and int(sb.texture_margin_left) == corner * s
			and sb.texture.get_size() == Vector2(aw * s, ah * states * s) and pr.region_rect.position.y == int(rows.pressed) * ah * s
			and int(UI.warnings.get(kind, 0)) == 0)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(dir.path_join("%sold.png" % fd.prefix)))
		UI.reset_frames(dir)
		for i in 5:
			f = UI.frame_styles(kind)
		var b := Button.new()
		UI.frame_kind(b, kind)
		UI.frame_kind(b, kind, false)
		var fb: StyleBoxTexture = f.styles.normal
		check("%s: файл переименован — универсальная кнопка (%s, угол %d), предупреждений %d (одно на запуск)" % [kind, tc.button.file.get_file(),
			f.corner, int(UI.warnings.get(kind, 0))], f.fallback and f.corner == int(tc.button.corner) and int(UI.warnings.get(kind, 0)) == 1
			and fb.texture != null and b.get_theme_stylebox("normal") is StyleBoxTexture)
		b.free()
	# сцена боя с переименованными файлами строится, кнопки фиксированного размера
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	m._update_ui()
	m._update_squad_panel()
	await step(2)
	var shop_ok: bool = m.shop_buttons.all(func(b): return not b.visible or b.size == Vector2(lay.shop_button_size[0], lay.shop_button_size[1]))
	var sq_ok: bool = m.squad_buttons.all(func(b): return not b.is_visible_in_tree() or b.size == Vector2(lay.squad_button_size[0], lay.squad_button_size[1]))
	check("без файлов рамок бой строится: магазин %s и строки отрядов %s того же размера, предупреждений по виду не больше одного (%s)" % [
		str(lay.shop_button_size), str(lay.squad_button_size), str(UI.warnings)], shop_ok and sq_ok and UI.warnings.values().all(func(n): return n == 1))
	m.queue_free()
	await step(2)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	UI.reset_frames()

const SETTINGS_SCRIPT := preload("res://scripts/settings.gd")

func key_ev(action: String) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = (InputMap.action_get_events(action)[0] as InputEventKey).keycode
	e.pressed = true
	return e

func key_name(action: String) -> String:
	return OS.get_keycode_string((InputMap.action_get_events(action)[0] as InputEventKey).keycode)

func slide_done(m: Node2D) -> void:
	for i in 100:
		m.shop_slide_step(1.0 / 60.0)

func on_screen(c: Control) -> bool:
	return c.is_visible_in_tree() and c.get_viewport_rect().encloses(c.get_global_rect())

# ЛКМ в точке холста 1920x1080 через окно: true — дошёл до поля боя (main начал рамку выбора).
func click(m: Node2D, at: Vector2) -> bool:
	m.box_active = false
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = root.get_final_transform() * at   # окно (без окна — 64 x 64) -> координаты окна
	e.global_position = e.position
	e.pressed = true
	root.push_input(e)
	var got: bool = m.box_active
	var r := e.duplicate() as InputEventMouseButton
	r.pressed = false
	root.push_input(r)
	m.box_active = false
	return got

func t_shop(m: Node2D, l: String) -> void:
	print("выдвижной магазин, %s" % l)
	var keys: Dictionary = lay["keys"]
	check("%s: клавиша сворачивания магазина по умолчанию — из ui_layout.json keys (%s)" % [l, keys.shop_toggle], key_name("shop_toggle") == keys.shop_toggle)
	m._update_ui()
	slide_done(m)
	await step(1)
	var p: Control = m.shop_panel
	var vp := p.get_viewport_rect()
	check("%s: передышка — магазин открыт: %s целиком на экране у правого края, кнопка «%s» видна" % [l, str(p.get_global_rect()), m.shop_tab.text],
		m.wave_state == m.WS_RESPITE and m.shop_open and on_screen(p) and absf(p.get_global_rect().end.x - (vp.size.x - m.SHOP_EDGE)) < 1.0
		and on_screen(m.shop_tab) and m.shop_tab.text.contains(SETTINGS_SCRIPT.key_label("shop_toggle")))
	# два блока: заголовки и какие кнопки под каким
	var box: VBoxContainer = p.get_child(0)
	var block := -1
	var ok: bool = m.shop_blocks.size() == 2
	for c in box.get_children():
		if c is Label:
			block = m.shop_blocks.find(c)
		elif c is Button:
			var k: int = c.get_meta("shop_k")
			ok = ok and (block == 0) == m.SHOP_PORTRAIT.has(m.SHOP_ITEMS[k]) and m.shop_buttons[k] == c
	check("%s: два блока — «%s» (наборы отрядов) и «%s» (оружие, ворота); shop_buttons по порядку SHOP_ITEMS" % [l, tr("HUD_SHOP_TROOPS"),
		tr("HUD_SHOP_UPGRADES")], ok)
	# клик по панели не доходит до поля боя, мимо панели — доходит (выбор рамкой начинается)
	m.process_mode = Node.PROCESS_MODE_INHERIT
	var r := p.get_global_rect()
	var hit_button := click(m, (m.shop_buttons[0] as Button).get_global_rect().get_center())
	var hit_edge := click(m, Vector2(r.position.x + 4, r.get_center().y))   # поле панели, не кнопка
	var hit_field := click(m, Vector2(vp.size.x * 0.5, vp.size.y * 0.45))
	m.process_mode = Node.PROCESS_MODE_DISABLED
	check("%s: клик по кнопке и по краю панели не доходит до поля (%s, %s), мимо — доходит (%s)" % [l, hit_button, hit_edge, hit_field],
		not hit_button and not hit_edge and hit_field)
	# клавиша: закрыть; анимация — shop_slide_time
	var dur: float = lay.shop_slide_time
	m._unhandled_input(key_ev("shop_toggle"))
	m.shop_slide_step(dur * 0.5)
	var half: float = m.shop_slide
	slide_done(m)
	await step(1)
	check("%s: клавиша закрывает: через половину shop_slide_time (%.2f с) выехал наполовину (%.2f), потом за краем и скрыт; кнопка на месте" % [l, dur, half],
		not m.shop_open and absf(half - 0.5) < 0.01 and not p.visible and p.position.x >= vp.size.x and on_screen(m.shop_tab))
	m.shop_tab.pressed.emit()
	slide_done(m)
	await step(1)
	check("%s: кнопка открывает снова" % l, m.shop_open and on_screen(p))
	# бой: закрыт, кнопки нет, клавиша не открывает
	m._start_wave()
	m._update_ui()
	slide_done(m)
	await step(1)
	m._unhandled_input(key_ev("shop_toggle"))
	slide_done(m)
	check("%s: бой — магазин закрыт и скрыт, кнопки сворачивания нет, клавиша не открывает" % l, m.wave_state == m.WS_BATTLE and not m.shop_open
		and not p.visible and not m.shop_tab.visible)
	# снова передышка — открыт
	m.wave_state = m.WS_RESPITE
	m._update_ui()
	slide_done(m)
	await step(1)
	check("%s: передышка снова — открыт" % l, m.shop_open and on_screen(p))

func t_squads(m: Node2D, l: String) -> void:
	print("панель отрядов, %s" % l)
	var st := root.get_node("Settings")
	var keys: Dictionary = lay["keys"]
	m.wave_state = m.WS_RESPITE
	m.squad_expanded = true
	m.squad_panel_sig = -1
	m._update_squad_panel()
	await step(2)
	var used := range(m.SQUAD_MAX).filter(func(q): return m.squad_used[q] == 1)
	var rows_ok: bool = used.all(func(q): return m.squad_buttons[q].is_visible_in_tree() and not m.squad_compact[q].visible)
	check("%s: развёрнутая — строки отрядов (%d), кнопки действий, деление, подсказка; кнопка «%s»" % [l, used.size(), m.squad_toggle.text],
		rows_ok and m.squad_actions.is_visible_in_tree() and m.split_box.visible and m.hint_label.visible and on_screen(m.squad_panel)
		and m.squad_toggle.text.contains(SETTINGS_SCRIPT.key_label("squad_panel_toggle")))
	var was: bool = st.squad_panel_expanded
	check("%s: клавиша по умолчанию — из ui_layout.json keys (%s)" % [l, keys.squad_panel_toggle], key_name("squad_panel_toggle") == keys.squad_panel_toggle)
	m._unhandled_input(key_ev("squad_panel_toggle"))
	await step(2)
	var csz := Vector2(lay.squad_compact_size[0], lay.squad_compact_size[1])
	var comp_ok := true
	for q in used:
		comp_ok = comp_ok and m.squad_compact[q].is_visible_in_tree() and not m.squad_buttons[q].visible and m.squad_compact[q].size == csz 			and m.squad_compact[q].text.ends_with(str(m.squad_n[q])) and m.squad_swatches[q].is_visible_in_tree()
	check("%s: клавиша сворачивает — квадратики и числа живых (%s), действий, деления и подсказки нет; в настройках развёрнута: %s" % [l,
		", ".join(used.map(func(q): return m.squad_compact[q].text)), str(st.squad_panel_expanded)], comp_ok and not m.squad_actions.is_visible_in_tree()
		and not m.split_box.visible and not m.hint_label.visible and st.squad_panel_expanded == false and was == true and on_screen(m.squad_panel)
		and m.squad_panel.size.x < m.ui_layout.squad_button_size.x)
	# клик по свёрнутой строке выбирает отряд
	var q: int = used[used.size() - 1]
	m.squad_compact[q].pressed.emit()
	check("%s: клик по свёрнутой строке выбирает отряд %d" % [l, q + 1], m._is_sel(q) and m.squad_compact[q].button_pressed)
	# новая сцена — то же состояние (из настроек)
	var m2: Node2D = load("res://scenes/main.tscn").instantiate()
	m2.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(m2)
	await step(2)
	check("%s: новая сцена — панель свёрнута (из настроек)" % l, m2.squad_expanded == false and not m2.squad_actions.is_visible_in_tree())
	m2.queue_free()
	await step(1)
	m.squad_toggle.pressed.emit()
	await step(2)
	check("%s: кнопка разворачивает, в настройках снова развёрнута" % l, m.squad_expanded and st.squad_panel_expanded and m.squad_actions.is_visible_in_tree())

# --- Тёмные экраны и контраст (этап 5) ---

# Относительная яркость и контраст по WCAG 2.x.
static func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

static func contrast(a: Color, b: Color) -> float:
	var la := lum(a)
	var lb := lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

# Цвет середины рамки: пиксель в центре исходного арта, с оттенком modulate.
func center_of(path: String, modulate := Color.WHITE) -> Color:
	var img: Image = UI._image(path)
	var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	return Color(c.r * modulate.r, c.g * modulate.g, c.b * modulate.b)

# Цвет текста поверх фона (полупрозрачный текст смешивается с фоном).
static func over(text: Color, bg: Color) -> Color:
	return Color(lerpf(bg.r, text.r, text.a), lerpf(bg.g, text.g, text.a), lerpf(bg.b, text.b, text.a))

func t_dark(g: Node) -> void:
	print("тёмные экраны, контраст")
	var minc: float = theme_cfg.contrast_min
	var pd: Dictionary = theme_cfg.panel_dark
	# без файла тёмной панели — универсальная с затемнением; с файлом (временный, user://) — свой арт, угол из имени
	UI.reset_frames()
	var sb := UI.dark_panel_style()
	var fb: bool = UI._frames.panel_dark.fallback
	var has_file := ResourceLoader.exists(pd.file) or FileAccess.file_exists(pd.file)
	check("тёмная панель: файла %s %s — %s" % [pd.file.get_file(), "есть" if has_file else "нет", "свой арт" if not fb else "универсальная с затемнением " + pd.fallback_modulate],
		fb != has_file and (not fb or sb.modulate_color == Color(pd.fallback_modulate)) and sb.texture != null)
	var dir := DIR + "/dark"
	DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color("#262b44"))
	var tmp := dir.path_join(pd.file.get_file().replace("_c8", "_c7"))
	img.save_png(ProjectSettings.globalize_path(tmp))
	UI.reset_frames(dir)
	var sb2 := UI.dark_panel_style()
	check("тёмная панель из файла: угол из имени (7), без затемнения", not UI._frames.panel_dark.fallback and UI._frames.panel_dark.corner == 7
		and int(sb2.texture_margin_left) == 7 * int(theme_cfg.scale) and sb2.modulate_color == Color.WHITE)
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(dir)
	UI.reset_frames()
	sb = UI.dark_panel_style()
	var dark := center_of(theme_cfg.panel.file, sb.modulate_color) if UI._frames.panel_dark.fallback else center_of(UI._frames.panel_dark.path)
	var slot := center_of(theme_cfg.slot.file)
	var light := center_of(theme_cfg.panel.file)
	print("CONTRAST|фон|тёмная панель %s|слот %s|светлая панель %s|порог %.1f" % [dark.to_html(false), slot.to_html(false), light.to_html(false), minc])
	# хаб: вкладки на тёмной панели, строки даров на рамке слота, текст строк — тёмный
	g.go_hub()
	await step(3)
	var h := current_scene
	h.tabs.current_tab = 1
	await step(3)
	check("хаб: подложка вкладок — тёмная панель, у «Даров» своей рамки нет", h.tabs.get_theme_stylebox("panel") == sb
		and h.gifts_panel.get_theme_stylebox("panel") is StyleBoxEmpty)
	var frames: Array = h.row_frames_box.get_children()
	var rows_ok: bool = frames.size() == h.gift_rows.size()
	for id in h.gift_rows:
		var b: Control = h.gift_rows[id].button
		var r := b.get_global_rect()
		rows_ok = rows_ok and frames.any(func(f): return f.theme_type_variation == UI.SLOT and f.get_global_rect().encloses(r.grow(-1.0)))
	check("хаб: строк даров %d, у каждой рамка ui_slot (%d), «Купить» внутри неё" % [h.gift_rows.size(), frames.size()], rows_ok)
	var worst := 99.0
	var seen := {}
	for id in h.gift_rows:
		for k in ["level", "effect", "price", "reason"]:
			var l: Label = h.gift_rows[id][k]
			var c := contrast(l.get_theme_color("font_color"), slot)
			worst = minf(worst, c)
			seen[k] = c
	print("CONTRAST|строки даров на слоте|%s|%.2f" % [UI.slot_text_color().to_html(false), worst])
	check("хаб: текст строк даров (уровень, эффект, цена, причина) на слоте — контраст %.2f >= %.1f" % [worst, minc], worst >= minc)
	var head: Label = null
	for c in h.gift_grid.get_children():
		if c is Label:
			head = c
			break
	var hc := contrast(over(head.get_theme_color("font_color"), dark), dark)
	var rc := contrast(h.radiance_label.get_theme_color("font_color"), dark)
	print("CONTRAST|заголовки таблицы на тёмной панели|%.2f|Сияние|%.2f" % [hc, rc])
	check("хаб: заголовки таблицы (%.2f) и «Сияние» (%.2f) на тёмной панели — не меньше %.1f" % [hc, rc, minc], hc >= minc and rc >= minc)
	h.tabs.current_tab = 0
	await step(2)
	var lc := contrast(h.siege_label.get_theme_color("font_color"), dark)
	check("хаб, «Осада»: текст на тёмной панели — %.2f" % lc, lc >= minc and h.tabs.get_theme_stylebox("panel") == sb)
	g.go_menu()
	await step(3)
	var st = current_scene.settings_menu
	st.open()
	await step(3)
	var sl: Label = null
	for c in st.tabs.get_child(0).find_children("*", "HBoxContainer", true, false):   # вкладка: поля, прокрутка (задача 26), колонка
		sl = c.get_child(0)
		break
	var scn := contrast(sl.get_theme_color("font_color"), dark)
	print("CONTRAST|настройки на тёмной панели|%.2f" % scn)
	check("настройки: вкладки на тёмной панели, подписи — контраст %.2f" % scn, st.tabs.get_theme_stylebox("panel") == sb and scn >= minc)
	st.close()
	await step(2)
	# магазин: заголовки блоков на светлой панели
	var m_head := contrast(load("res://scripts/main.gd").SHOP_HEAD_COLOR, light)
	print("CONTRAST|заголовки магазина на светлой панели|%.2f" % m_head)
	check("магазин: заголовки блоков на светлой панели — %.2f" % m_head, m_head >= minc)
