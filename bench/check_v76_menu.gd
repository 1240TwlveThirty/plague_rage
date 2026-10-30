extends SceneTree
# Задача 26, этап 3 (без окна): меню.
#   Подсветка фокуса: при открытии главного меню, меню паузы и настроек ни одна кнопка не подсвечена (фокус у кнопки есть —
#   Enter работает, — но стиль focus пустой); после клавиши подсветка видна, после движения мыши снова скрыта.
#   Окно настроек одного размера на всех вкладках, равного data/ui_layout.json settings_size; лишнее прокручивается внутри.
#   «Управление»: группы controls_groups с заголовками (пустые не показаны), каждое показанное действие — ровно в одной группе,
#   высота строки — settings_key_row_height.
const ST := preload("res://scripts/settings.gd")
const FOCUS := preload("res://scripts/focus_ui.gd")
var fails := 0
var lay: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

# Все контролы под node, у которых сейчас видна подсветка фокуса.
func lit(node: Node) -> Array:
	var out := []
	if node is Control and FOCUS.focus_drawn(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(lit(c))
	return out

func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e

func motion() -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = Vector2(300, 300)
	e.relative = Vector2(5, 3)
	return e

func names(a: Array) -> String:
	return ", ".join(a.map(func(c): return "%s «%s»" % [c.get_class(), c.text if "text" in c else ""]))

func _run() -> void:
	lay = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	var focus: Node = root.get_node_or_null("Focus")
	check("автозагрузка Focus есть", focus != null)
	if root.has_node("Game"):
		root.get_node("Game").free()   # меню без забега
	await step(1)
	print("подсветка фокуса")
	var menu: Control = load("res://scripts/menu.gd").new()
	root.add_child(menu)
	await step(2)
	check("главное меню открыто: фокус у «Играть» (Enter), подсвеченных кнопок нет", menu.play_button.has_focus() and lit(menu).is_empty(), names(lit(menu)))
	root.push_input(key(KEY_DOWN))
	await step(2)
	var l := lit(menu)
	var fo: Control = menu.get_viewport().gui_get_focus_owner()
	check("после клавиши подсветка видна у одной кнопки", focus.keyboard and l.size() == 1, "%s; фокус: %s, стиль %s" % [names(l), fo, fo.get_theme_stylebox("focus") if fo != null else null])
	root.push_input(motion())
	await step(2)
	check("движение мыши прячет подсветку", not focus.keyboard and lit(menu).is_empty(), names(lit(menu)))
	root.push_input(key(KEY_DOWN))
	await step(1)
	menu.settings_menu.open()
	await step(2)
	var sm: CanvasLayer = menu.settings_menu
	check("настройки открыты после клавиши: всё равно ни одна кнопка не подсвечена", sm.back_button.has_focus() and lit(sm).is_empty() and lit(menu).is_empty(), names(lit(sm)))
	print("размер окна настроек")
	var want := Vector2(lay.settings_size[0], lay.settings_size[1])
	var sizes := []
	var titles := []
	for t in sm.tabs.get_tab_count():
		sm.tabs.current_tab = t
		await step(2)
		sizes.append(sm.tabs.size)
		titles.append(tr(sm.tabs.get_tab_title(t)))
	check("вкладки %s: окно одного размера %s на всех (settings_size)" % [", ".join(titles), str(want)], sizes.all(func(z): return z == want), str(sizes))
	for loc in ["en", "ru"]:
		TranslationServer.set_locale(loc)
		var sz := []
		for t in sm.tabs.get_tab_count():
			sm.tabs.current_tab = t
			await step(2)
			sz.append(sm.tabs.size)
		check("%s: размер тот же на всех вкладках" % loc, sz.all(func(z): return z == want), str(sz))
	print("вкладка «Управление»")
	var groups: Array = lay.controls_groups
	var hidden: Array = ST.hidden_actions()
	var shown_groups := groups.filter(func(g): return g.actions.any(func(a): return not a in hidden))
	check("заголовков групп %d (пустые не показаны: %s)" % [shown_groups.size(), ", ".join(groups.filter(func(g): return not g in shown_groups).map(func(g): return tr(g.title)))],
		sm.group_heads.size() == shown_groups.size() and range(shown_groups.size()).all(func(i): return sm.group_heads[i].text == shown_groups[i].title),
		", ".join(sm.group_heads.map(func(h): return tr(h.text))))
	var count := {}
	for g in sm.key_groups:
		for a in g[1]:
			count[a] = count.get(a, 0) + 1
	var bad := []
	for a in ST.REBINDABLE:
		if not a in hidden and count.get(a, 0) != 1:
			bad.append(a)
	check("каждое показанное действие (%d) ровно в одной группе" % count.size(), bad.is_empty() and count.size() == sm.key_buttons.size(), str(bad))
	var row_h := float(lay.settings_key_row_height)
	sm.tabs.current_tab = 2
	await step(2)
	var low: Array = sm.key_buttons.values().filter(func(b): return b.size.y < row_h)
	check("строки клавиш высотой settings_key_row_height %d" % int(row_h), low.is_empty() and sm.key_titles.values().all(func(x): return x.size.y >= row_h), str(low.size()))
	sm.close()
	menu.queue_free()
	await step(2)
	print("меню паузы")
	var esc: CanvasLayer = load("res://scripts/esc_menu.gd").new()
	root.add_child(esc)
	await step(1)
	root.push_input(key(KEY_ESCAPE))   # клавиатура, как при открытии по Esc
	await step(1)
	esc.open()
	await step(2)
	check("меню паузы открыто по Esc: фокус у «Продолжить», подсвеченных кнопок нет", esc.continue_button.has_focus() and lit(esc).is_empty(), names(lit(esc)))
	esc.close()
	esc.queue_free()
	await step(2)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
