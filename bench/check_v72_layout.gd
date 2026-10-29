extends SceneTree
# Тесты задачи 22 (без окна): итоговые размеры кнопок под шрифт из data/ui_theme.json (по умолчанию fusion10). Все размеры —
# из data/ui_layout.json, кегль — FONTS.px от кегля темы, высота строки — из шрифта; ничего не зашито.
#   Магазин: в сценариях (старт, после покупок, самая длинная клавиша, цена 9999, «макс.», «куплено 99», всё сразу) на ru и en —
#   у каждой кнопки не больше двух строк, каждая строка не шире места; высота кнопки в ui_layout — наименьшая чётная, в которую
#   входят две строки с полями; кнопки не растянуты; «куплено N» и клавиша целиком — в подсказке. Печатает «SHOP|...» для отчёта.
#   Отряды: строка одна, фиксированного размера, длинная — многоточием, целиком в подсказке; панель не шире строки и кнопок
#   действий; высота не меньше одной строки с полями. Кнопки действий и Клич: строка помещается в высоту.
#   Верхняя панель: «99 999» в окошке рядом с иконкой, «100 000/100 000» на полосе ворот.
#   Хаб: таблица даров (с причинами отказа) целиком на экране, ru и en.
# Временное сохранение user://bench_v72 (user://save.json не трогается).
const FONTS := preload("res://scripts/fonts.gd")
const HUD_SLOT := preload("res://scripts/hud_slot.gd")
const DIR := "user://bench_v72"
const DT := 1.0 / 30.0
var fails := 0
var lay: Dictionary
var line_h := 0.0
var shop_need := 0.0   # наибольшая натуральная высота кнопки магазина
var shop_lines := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func even_up(x: float) -> int:
	var n := ceili(x - 0.001)
	return n + (n % 2)

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	lay = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_theme.json"))
	FONTS.load_cfg()
	check("шрифт по умолчанию — %s (font_variant), действует: %s, кегль темы %d -> %d" % [cfg.font_variant, FONTS.variant, FONTS.DEFAULT_SIZE,
		FONTS.px(FONTS.DEFAULT_SIZE)], FONTS.variant == cfg.font_variant)
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	node_added.connect(_on_node_added)
	for l in ["ru", "en"]:
		TranslationServer.set_locale(l)
		g.start_run(1)
		await step(3)
		var m := current_scene as Node2D
		await t_shop(m, l)
		await t_squads(m, l)
		if l == "ru":
			t_hud(m)
		m.queue_free()
		await step(2)
	var want := even_up(shop_need)
	check("высота кнопки магазина в ui_layout (%d) — наименьшая чётная для %d строк по %.0f px с полями (натуральная до %.0f): %d" % [int(lay.shop_button_size[1]),
		shop_lines, line_h, shop_need, want], int(lay.shop_button_size[1]) == want and shop_lines <= 2)
	await t_hub(g)
	TranslationServer.set_locale("ru")
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Строки подписи кнопки и их ширины при кегле кнопки.
func lines_of(b: Button) -> Array:
	var font := b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var out := []
	for t in b.text.split("\n"):
		out.append([t, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x])
	return out

func shop_case(m: Node2D, l: String, name: String) -> void:
	m._update_ui()
	await step(1)
	var ok := true
	for k in m.shop_buttons.size():
		var b: Button = m.shop_buttons[k]
		if not b.visible:
			continue
		var sb := b.get_theme_stylebox("normal")
		var room := b.custom_minimum_size.x - sb.get_minimum_size().x
		var ls := lines_of(b)
		line_h = b.get_theme_font("font").get_height(b.get_theme_font_size("font_size"))
		var natural := ls.size() * line_h + sb.get_minimum_size().y
		shop_need = maxf(shop_need, natural)
		shop_lines = maxi(shop_lines, ls.size())
		var wide: bool = ls.any(func(e): return e[1] > room + 0.5)
		var tip_ok: bool = b.tooltip_text.contains(SETTINGS_key(m, k)) and b.tooltip_text.contains(str(m.shop_bought[k]))
		ok = ok and ls.size() <= 2 and not wide and tip_ok and b.size == Vector2(lay.shop_button_size[0], lay.shop_button_size[1])
		print("SHOP|%s|%s|%s|строк %d|натуральная высота %.0f|шире места: %s|%s|подсказка: %s" % [l, name, m.SHOP_ITEMS[k], ls.size(), natural, wide,
			b.text.replace("\n", " / "), b.tooltip_text])
	check("%s, %s: кнопки магазина — не больше двух строк, строки не шире места, размер %s, в подсказке клавиша и «куплено»" % [l, name,
		str(lay.shop_button_size)], ok)

func SETTINGS_key(m: Node2D, k: int) -> String:
	return m.SETTINGS.key_label(m.SHOP_ACTIONS[k])

func t_shop(m: Node2D, l: String) -> void:
	print("магазин, %s" % l)
	m.gold = 1e6
	await shop_case(m, l, "старт")
	for k in m.shop_bought.size():
		m.shop_bought[k] = 3
	await shop_case(m, l, "после покупок")
	var saved := {}
	for a in m.SHOP_ACTIONS:   # самая длинная подпись клавиши — средняя кнопка мыши
		saved[a] = InputMap.action_get_events(a)
		InputMap.action_erase_events(a)
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_MIDDLE
		InputMap.action_add_event(a, e)
	await shop_case(m, l, "клавиша «%s»" % SETTINGS_key(m, 0))
	var base: PackedFloat64Array = m.shop_base.duplicate()
	var growth: PackedFloat64Array = m.shop_growth.duplicate()
	for k in m.shop_base.size():
		m.shop_base[k] = 9999.0
		m.shop_growth[k] = 0.0
		m.shop_bought[k] = 99
	await shop_case(m, l, "длинная клавиша, цена 9999, куплено 99")
	var cap: PackedInt32Array = m.shop_cap.duplicate()
	for k in m.shop_cap.size():
		m.shop_cap[k] = 1
	await shop_case(m, l, "длинная клавиша, «макс.», куплено 99")
	m.shop_cap = cap
	m.shop_base = base
	m.shop_growth = growth
	for a in saved:
		InputMap.action_erase_events(a)
		for e in saved[a]:
			InputMap.action_add_event(a, e)
	for k in m.shop_bought.size():
		m.shop_bought[k] = 0

func t_squads(m: Node2D, l: String) -> void:
	print("отряды, %s" % l)
	var want := Vector2(lay.squad_button_size[0], lay.squad_button_size[1])
	var b: Button = m.squad_buttons[0]
	var sb := b.get_theme_stylebox("normal")
	var one := b.get_theme_font("font").get_height(b.get_theme_font_size("font_size")) + sb.get_minimum_size().y
	var saved: Array = InputMap.action_get_events("squad_select_1")
	InputMap.action_erase_events("squad_select_1")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("squad_select_1", e)
	m.squad_skill_on[0] = 1   # «● Стена щитов» — длиннее всего
	m.squad_panel_sig = -1
	m.squad_text_sig.fill(-1)
	m._update_squad_panel()
	await step(2)
	var full: String = b.text
	var w := b.get_theme_font("font").get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
	var widest := 0.0
	for c in m.squad_actions.get_children():
		widest += (c as Control).size.x
	widest += m.squad_actions.get_theme_constant("separation") * (m.squad_actions.get_child_count() - 1)
	check("%s: строка отряда «%s» (%.0f px текста) — размер %s без переноса, многоточие, целиком в подсказке; одна строка с полями %.0f px <= %d" % [l,
		full, w, str(want), one, int(want.y)], b.size == want and b.autowrap_mode == TextServer.AUTOWRAP_OFF
		and b.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and b.tooltip_text == full and one <= want.y)
	check("%s: панель отрядов не растёт от длинной строки: ширина %.0f = max(строка с квадратом %.0f, кнопки действий %.0f)" % [l, m.squad_panel.size.x,
		m.squad_rows_ui[0].size.x, widest], absf(m.squad_panel.size.x - maxf(m.squad_rows_ui[0].size.x, widest)) < 1.0)
	InputMap.action_erase_events("squad_select_1")
	for ev in saved:
		InputMap.action_add_event("squad_select_1", ev)
	m.squad_skill_on[0] = 0
	m.squad_text_sig.fill(-1)
	m._update_squad_panel()
	var ah := float(lay.action_button_size[1])
	var ok := true
	var need := 0.0
	for c: Button in m.action_buttons:
		var s2: StyleBox = c.get_theme_stylebox("normal")
		need = maxf(need, c.get_theme_font("font").get_height(c.get_theme_font_size("font_size")) + s2.get_minimum_size().y)
		ok = ok and is_equal_approx(c.size.y, ah)
	check("%s: кнопки действий — высота %d, строка с полями рамки %.0f помещается" % [l, int(ah), need], ok and need <= ah)
	m.war_cry_level = 1
	m._setup_war_cry_ui(m.squad_panel.get_parent())
	m._update_ui()
	await step(2)
	var wc: Button = m.war_cry_button
	var wsz := Vector2(lay.war_cry_size[0], lay.war_cry_size[1])
	var ls := lines_of(wc)
	var wneed: float = wc.get_theme_font("font").get_height(wc.get_theme_font_size("font_size")) + wc.get_theme_stylebox("normal").get_minimum_size().y
	var wroom: float = wsz.x - wc.get_theme_stylebox("normal").get_minimum_size().x
	check("%s: Клич %s, «%s» — одна строка %.0f px <= %d, ширина текста %.0f <= %.0f" % [l, str(wsz), wc.text, wneed, int(wsz.y), ls[0][1], wroom],
		wc.size == wsz and ls.size() == 1 and wneed <= wsz.y and ls[0][1] <= wroom + 0.5)

func t_hud(m: Node2D) -> void:
	print("верхняя панель")
	var th = m.top_hud
	var s = th.slots.values().filter(func(x): return x.bar == null)[0]
	s.set_value(99999)
	check("окошко %d px: «%s» кеглем %d — %.0f px из %.0f рядом с иконкой" % [int(s.size.x), s.label.text, s.label.get_theme_font_size("font_size"), s.text_px(),
		s.text_width], s.label.text == HUD_SLOT.group(99999) and s.text_px() <= s.text_width)
	var gs = th.slots.values().filter(func(x): return x.bar != null)[0]
	gs.set_value(100000, 100000)
	check("ворота %d px: «%s» кеглем %d — %.0f px на полосе %.0f" % [int(gs.size.x), gs.label.text, gs.label.get_theme_font_size("font_size"), gs.text_px(),
		gs.text_width], gs.label.text == HUD_SLOT.group(100000) + "/" + HUD_SLOT.group(100000) and gs.text_px() <= gs.text_width)
	var total := 0.0
	for d in lay.top_hud.slots:
		total += float(d.width)
	check("окошки не растянуты подписями: ширина ряда %.0f = сумма ширин и зазоров из ui_layout" % th.size.x,
		is_equal_approx(th.size.x, total + float(lay.top_hud.gap) * (lay.top_hud.slots.size() - 1)))

func t_hub(g: Node) -> void:
	g.radiance = 0
	for id in g.gift_defs:
		g.gift_levels[id] = 1   # у каждой строки причина «Откроется после осады I»
	var scr := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	for l in ["ru", "en"]:
		TranslationServer.set_locale(l)
		g.go_hub()
		await step(3)
		var h := current_scene
		h.tabs.current_tab = 1
		await step(3)
		var out := []
		for id in h.gift_rows:
			var row: Dictionary = h.gift_rows[id]
			for c in [row.level, row.effect, row.price, row.button, row.reason]:
				if not scr.encloses((c as Control).get_global_rect()):
					out.append("%s.%s" % [id, (c as Control).name])
		check("%s: «Дары» (кегль %d) с причинами отказа: панель %s целиком на экране, цена, «Купить» и причина не за краем" % [l,
			FONTS.px(h.GIFT_FONT), str(h.gifts_panel.get_global_rect())], scr.encloses(h.gifts_panel.get_global_rect()) and out.is_empty(), ", ".join(out))
		g.go_menu()
		await step(2)
	g.gift_levels.clear()
