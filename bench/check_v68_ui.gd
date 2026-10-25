extends SceneTree
# Тесты задачи 18 (без окна): универсальные рамки кнопки и панели. Тема проекта art/ui/theme.tres совпадает с data/ui_theme.json
# (масштаб, срез, отступы, цвета), увеличенные копии — ближайший сосед исходника; тема задаёт только вариации FrameButton,
# FramePanel и FrameLabel. Рамку получили меню, настройки, хаб, меню паузы, баннер, «Командир пал», итог забега, кнопки действий
# отряда и Клич; кнопки магазина, отрядов и карточек — без вариации и с прежним видом (тема на них не действует).
# Размеры берутся из ui_theme.json и ui_layout.json, не зашиты. Временное сохранение user://bench_v68 (user://save.json не трогается).
const MAIN := "res://scripts/main.gd"
const UI := preload("res://scripts/ui.gd")
const DIR := "user://bench_v68"
var fails := 0
var cfg: Dictionary
var lay: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == MAIN:
		n.process_mode = Node.PROCESS_MODE_DISABLED

func slice_of(d: Dictionary) -> int:
	return int(d.get("slice", d.corner))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_theme.json"))
	lay = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	t_theme()
	await t_screens()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Пиксели совпадают; у полностью прозрачных цвет не важен (импорт перекрашивает их в соседей).
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

func scaled_ok(tex: Texture2D, src_path: String) -> bool:
	var src := Image.load_from_file(ProjectSettings.globalize_path(src_path))
	src.convert(Image.FORMAT_RGBA8)
	var s := int(cfg.scale)
	src.resize(src.get_width() * s, src.get_height() * s, Image.INTERPOLATE_NEAREST)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	return same_visible(img, src)

func t_theme() -> void:
	print("тема")
	var s := int(cfg.scale)
	var b: Dictionary = cfg.button
	var p: Dictionary = cfg.panel
	var t := ThemeDB.get_project_theme()
	check("тема проекта (gui/theme/custom) — %s" % cfg.theme_path, t != null and ProjectSettings.get_setting("gui/theme/custom") == cfg.theme_path
		and t.resource_path == cfg.theme_path)
	if t == null:
		return
	var types := Array(t.get_type_list())
	types.sort()
	check("в теме только вариации %s (базовые Button, PanelContainer, Label не заданы)" % ", ".join(types), types == [String(UI.BUTTON), String(UI.LABEL), String(UI.PANEL)]
		and t.get_type_variation_base(UI.BUTTON) == &"Button" and t.get_type_variation_base(UI.PANEL) == &"PanelContainer" and t.get_type_variation_base(UI.LABEL) == &"Label")
	var bt: Texture2D = (t.get_stylebox("normal", UI.BUTTON) as StyleBoxTexture).texture
	var src := Image.load_from_file(ProjectSettings.globalize_path(b.file))
	var sh := bt.get_height() / int(b.states)
	check("кнопка: %s %dx%d -> %s %dx%d (x%d), состояний %d по %d px" % [b.file, src.get_width(), src.get_height(), bt.resource_path, bt.get_width(), bt.get_height(), s,
		int(b.states), sh], bt.get_width() == src.get_width() * s and bt.get_height() == src.get_height() * s and scaled_ok(bt, b.file)
		and bt.resource_path.begins_with(cfg.out_dir))
	var pad := float(int(b.corner) * s + int(b.text_pad))
	var ok := true
	var info := []
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := t.get_stylebox(st, UI.BUTTON) as StyleBoxTexture
		var good := (sb != null and sb.texture == bt and sb.texture_margin_left == slice_of(b) * s and sb.texture_margin_top == slice_of(b) * s
			and sb.region_rect == Rect2(0, int(b.state_rows[st]) * sh, bt.get_width(), sh) and sb.content_margin_left == pad and sb.content_margin_right == pad
			and sb.content_margin_left >= sb.texture_margin_left and sb.modulate_color == Color(b.state_modulate[st]))
		ok = ok and good
		info.append("%s %s" % [st, "да" if good else "НЕТ"])
	check("состояния кнопки — StyleBoxTexture: срез %d (=%d x %d), строка состояния, отступ текста %d (угол %d x %d + %d) — %s" % [slice_of(b) * s, slice_of(b), s, pad,
		int(b.corner), s, int(b.text_pad), ", ".join(info)], ok and t.get_stylebox("focus", UI.BUTTON) is StyleBoxEmpty)
	var fc: Dictionary = b.font_colors
	check("цвета текста (Endesga 32): обычный %s, наведение %s, нажатая %s, недоступная %s; тёмный контур %s" % [fc.normal, fc.hover, fc.pressed, fc.disabled, b.outline_color],
		t.get_color("font_color", UI.BUTTON) == Color(fc.normal) and t.get_color("font_hover_color", UI.BUTTON) == Color(fc.hover)
		and t.get_color("font_pressed_color", UI.BUTTON) == Color(fc.pressed) and t.get_color("font_disabled_color", UI.BUTTON) == Color(fc.disabled)
		and t.get_color("font_outline_color", UI.BUTTON) == Color(b.outline_color) and t.get_constant("outline_size", UI.BUTTON) == int(b.outline_size))
	check("кнопка меню не меньше %d x %d (рамка арта на экране)" % [int(b.min_size[0]), int(b.min_size[1])], t.get_constant("min_width", UI.BUTTON) == int(b.min_size[0])
		and t.get_constant("min_height", UI.BUTTON) == int(b.min_size[1]))
	var ps := t.get_stylebox("panel", UI.PANEL) as StyleBoxTexture
	var psrc := Image.load_from_file(ProjectSettings.globalize_path(p.file))
	check("панель: %s %dx%d -> x%d, срез %d, отступы содержимого %d (не меньше среза и угла x %d)" % [p.file, psrc.get_width(), psrc.get_height(), s,
		ps.texture_margin_left, ps.content_margin_left, s], ps != null and ps.texture.get_width() == psrc.get_width() * s and scaled_ok(ps.texture, p.file)
		and ps.texture_margin_left == slice_of(p) * s and ps.texture_margin_bottom == slice_of(p) * s
		and ps.content_margin_left >= ps.texture_margin_left and ps.content_margin_top >= int(p.corner) * s and ps.content_margin_bottom == ps.content_margin_left)

# Кнопка с универсальной рамкой.
func framed(b: Control) -> bool:
	var sb := b.get_theme_stylebox("normal")
	return b.theme_type_variation == UI.BUTTON and sb is StyleBoxTexture and (sb as StyleBoxTexture).texture.resource_path.contains("ui_button")

# Все кнопки списка с рамкой и не меньше min_size.
func all_framed(list: Array, min_size := Vector2.ZERO) -> bool:
	for b in list:
		if not framed(b) or b.size.x < min_size.x or b.size.y < min_size.y:
			return false
	return not list.is_empty()

func panel_framed(p: Control) -> bool:
	var sb := p.get_theme_stylebox("panel")
	return p.theme_type_variation == UI.PANEL and sb is StyleBoxTexture and (sb as StyleBoxTexture).texture.resource_path.contains("ui_panel")

# Кнопка без рамки темы: вариации нет, StyleBox не рамка; цвет текста — свой (переопределение) или встроенной темы Godot, как до задачи.
func untouched(b: Button) -> bool:
	var sb := b.get_theme_stylebox("normal")
	var color_ok := b.has_theme_color_override("font_color") or b.get_theme_color("font_color") == ThemeDB.get_default_theme().get_color("font_color", "Button")
	return (b.theme_type_variation == &"" and color_ok and not (sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null
		and (sb as StyleBoxTexture).texture.resource_path.contains("ui_button")))

# Низкая кнопка с рамкой: углы не налезают (2 x срез <= высоты), строка текста помещается между отступами.
func fits(b: Button) -> bool:
	var sb := b.get_theme_stylebox("normal") as StyleBoxTexture
	var font := b.get_theme_font("font")
	var line := font.get_height(b.get_theme_font_size("font_size"))
	return sb.texture_margin_top + sb.texture_margin_bottom <= b.size.y and line + sb.content_margin_top + sb.content_margin_bottom <= b.size.y + 0.5

func t_screens() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	g.radiance = 100
	var min_size := Vector2(int(cfg.button.min_size[0]), int(cfg.button.min_size[1]))
	print("меню и настройки")
	g.go_menu()
	await step(3)
	var mn := current_scene
	var menu_btns: Array = [mn.play_button, mn.settings_button, mn.quit_button]
	check("главное меню: «Играть», «Настройки», «Выход» с рамкой, не меньше %s" % str(min_size), all_framed(menu_btns, min_size), str(mn.play_button.size))
	var st = mn.settings_menu
	check("настройки: «Назад», «Сбросить», кнопки клавиш с рамкой; вкладки, флажки — стандартные", framed(st.back_button) and framed(st.reset_keys_button)
		and all_framed(st.key_buttons.values()) and st.tabs.theme_type_variation == &"" and st.fullscreen_check.theme_type_variation == &"")
	print("хаб")
	mn.play_button.pressed.emit()
	await step(3)
	var h := current_scene
	check("хаб: «Начать забег», «Дневник», «В меню», «Закрыть» с рамкой; вкладки стандартные", all_framed([h.start_button, h.diary_button, h.menu_button],
		min_size) and framed(h.diary_close) and h.tabs.theme_type_variation == &"")
	check("хаб: дневник и дары на универсальной панели, «Купить» с рамкой", panel_framed(h.diary_panel) and panel_framed(h.gifts_panel)
		and all_framed(h.gift_rows.values().map(func(r): return r.button)))
	h.tabs.current_tab = 1
	await step(2)
	var scr := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	check("вкладка «Дары» с панелью целиком на экране (%s)" % str(h.gifts_panel.get_global_rect()), scr.encloses(h.gifts_panel.get_global_rect()))
	h.esc_menu.open()
	await step(2)
	var em = h.esc_menu
	check("меню паузы: панель темы, кнопки с рамкой и не меньше %s" % str(min_size), panel_framed(em.panel) and all_framed([em.continue_button, em.settings_button,
		em.menu_button, em.quit_button], min_size) and scr.encloses(em.panel.get_global_rect()))
	em.close()
	print("бой")
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	m.war_cry_level = 1
	m._setup_war_cry_ui(m.squad_panel.get_parent())
	m._update_squad_panel()
	m._update_ui()
	await step(2)
	var ah := float(lay.action_button_height)
	var wc := Vector2(lay.war_cry_size[0], lay.war_cry_size[1])
	var act_ok := all_framed(m.action_buttons)
	for b in m.action_buttons:
		act_ok = act_ok and is_equal_approx(b.size.y, ah) and fits(b)
	check("кнопки действий отряда с рамкой, высота %s из ui_layout; углы не налезают, строка текста помещается" % ah, act_ok,
		str(m.action_buttons.map(func(b): return b.size)))
	check("Клич с рамкой, %s из ui_layout; углы не налезают, текст помещается" % str(wc), framed(m.war_cry_button) and m.war_cry_button.size == wc and fits(m.war_cry_button),
		str(m.war_cry_button.size))
	var shop_ok: bool = m.shop_buttons.all(untouched)
	var squad_ok: bool = m.squad_buttons.all(untouched)
	check("магазин (%d) и отряды (%d) без рамки темы (свои StyleBox, цвет текста свой или встроенной темы); деление — стандартная кнопка" % [m.shop_buttons.size(),
		m.squad_buttons.size()], shop_ok and squad_ok and m.split_mode_button.theme_type_variation == &"", "магазин %s, отряды %s" % [shop_ok, squad_ok])
	check("баннер на панели темы, ширина %d как была (BANNER_WIDTH), рамка полупрозрачная (%.2f) — строй под баннером виден" % [int(m.banner.size.x),
		m.banner.self_modulate.a], panel_framed(m.banner) and m.banner.visible and is_equal_approx(m.banner.size.x, m.BANNER_WIDTH)
		and m.banner.self_modulate.a < 1.0 and m.banner.modulate.a == 1.0)
	check("«Командир пал» на панели темы, панель видна вместе с меткой", panel_framed(m.hero_fallen_panel) and m.hero_fallen_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and m.hero_fallen_panel.visible == m.hero_fallen_label.visible)
	var ids: Array = m.card_defs.keys().slice(0, 3)
	m.card_screen.open(ids, m.card_defs, [])
	await step(2)
	var cards_ok: bool = m.card_screen.buttons.size() == ids.size()
	for b in m.card_screen.buttons:
		cards_ok = cards_ok and b.theme_type_variation == &"" and b.get_theme_stylebox("normal") is StyleBoxEmpty
	check("карточки выбора (%d) без рамки темы" % m.card_screen.buttons.size(), cards_ok)
	m.card_screen.visible = false
	m._on_defeat()
	m._update_ui()
	await step(2)
	check("итог забега: баннер на панели, «В хаб» с рамкой и не меньше %s, всё на экране" % str(min_size), panel_framed(m.banner) and framed(m.hub_button) and m.hub_button.visible
		and m.hub_button.size.y >= min_size.y and scr.encloses(m.banner.get_global_rect()), str(m.banner.get_global_rect()))
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
