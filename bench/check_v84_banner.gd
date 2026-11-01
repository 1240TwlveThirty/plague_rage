extends SceneTree
# Задача 30 (без окна): кнопка закрытия баннера в бою. Размеры и отступы — data/ui_layout.json (banner_close_*, banner_log_*), тест
# читает их оттуда. Своё временное сохранение (user://bench_v84), сохранение игрока не трогается. События мыши и клавиш — через
# root.push_input (координаты окна), как от игрока.
#   Передышка: «×» в правом верхнем углу баннера (отступ banner_close_margin, размер banner_close_size), не внутри баннера (текст
#   не сдвигается); баннер, его колонка и подписи пропускают мышь, кнопка — нет. Клик по баннеру вне кнопки доходит до карты
#   (клик по пустой земле снимает выбор отряда), клик по «×» — нет: баннер скрыт, выбор на месте.
#   Скрыт: «Журнал (H)» по центру на BANNER_TOP (текст — перевод с клавишей banner_toggle, ru и en), в группе shot_hidden;
#   H показывает баннер снова, клик по «Журналу» — тоже; на экране выбора карточек «Журнала» нет; новый баннер (итог волны)
#   сбрасывает скрытие. Конец забега (поражение, «В хаб»): «×» и «Журнала» нет, H баннер не скрывает.
const DIR := "user://bench_v84"
var fails := 0
var m: Node2D

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

func click(at: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	root.push_input(mv, true)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		root.push_input(e, true)
		await step(1)
	await step(1)

func key_h() -> void:
	var ev: InputEvent = InputMap.action_get_events("banner_toggle")[0]
	for pressed in [true, false]:
		var e := ev.duplicate() as InputEventKey
		e.pressed = pressed
		root.push_input(e, true)
		await step(1)
	await step(1)

func shown() -> bool:
	return m.banner.visible and not m.banner_hidden

func _run() -> void:
	var lay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	var g: Node = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(8)
	m = current_scene
	var b: Button = m.banner_close
	var lg: Button = m.banner_log
	var br: Rect2 = m.banner.get_global_rect()
	var cr := b.get_global_rect()
	var mg := float(lay.banner_close_margin)
	var sz := Vector2(lay.banner_close_size[0], lay.banner_close_size[1])
	check("передышка: баннер виден, «×» видна, размер %s (banner_close_size %s)" % [str(cr.size), str(sz)], shown() and b.visible and cr.size == sz)
	check("«×» — в правом верхнем углу баннера, отступ %.0f (banner_close_margin): справа %.1f, сверху %.1f" % [mg, br.end.x - cr.end.x, cr.position.y - br.position.y],
		is_equal_approx(br.end.x - cr.end.x, mg) and is_equal_approx(cr.position.y - br.position.y, mg))
	var through: bool = m.banner.mouse_filter == Control.MOUSE_FILTER_IGNORE
	for c in m.banner.find_children("*", "Control", true, false):
		if c != m.hub_button:
			through = through and c.mouse_filter == Control.MOUSE_FILTER_IGNORE
	check("«×» не в раскладке баннера; баннер и его содержимое пропускают мышь, «×» — нет", not m.banner.is_ancestor_of(b) and through
		and b.mouse_filter == Control.MOUSE_FILTER_STOP)
	# клик по баннеру вне кнопки — на карту
	m._select_only(0)
	var spot := Vector2(br.position.x + br.size.x * 0.2, br.get_center().y)
	await click(spot)
	check("клик по баннеру вне «×» (%s) доходит до карты: выбор снят, баннер на месте" % str(spot), m.sel_mask == 0 and shown())
	m._select_only(0)
	await click(cr.get_center())
	check("клик по «×»: баннер скрыт (banner_hidden), до карты клик не дошёл (выбор на месте)", m.banner_hidden and not m.banner.visible and m.sel_mask == 1)
	var lr := lg.get_global_rect()
	var vw: float = root.get_visible_rect().size.x
	check("скрыт: «Журнал» «%s» по центру (%.1f) на BANNER_TOP (%.0f), не меньше banner_log_size, в shot_hidden, «×» нет" % [lg.text, lr.get_center().x, lr.position.y],
		lg.visible and not b.visible and lg.text == tr("HUD_BANNER_SHOW").replace("{banner_toggle}", m.SETTINGS.key_label("banner_toggle"))
		and absf(lr.get_center().x - vw * 0.5) <= 0.5 and is_equal_approx(lr.position.y, m.BANNER_TOP) and lr.size.x >= float(lay.banner_log_size[0])
		and lr.size.y >= float(lay.banner_log_size[1]) and lg.is_in_group(&"shot_hidden") and lg.text.contains(m.SETTINGS.key_label("banner_toggle")))
	TranslationServer.set_locale("en")
	await step(2)
	check("en: «Журнал» — «%s»" % lg.text, lg.visible and lg.text == TranslationServer.translate("HUD_BANNER_SHOW").replace("{banner_toggle}", m.SETTINGS.key_label("banner_toggle")) and m.banner_hidden)
	TranslationServer.set_locale("ru")
	await step(2)
	await key_h()
	check("H показывает баннер снова, «Журнала» нет, «×» на месте", shown() and not lg.visible and b.visible)
	await key_h()
	check("H скрывает снова", m.banner_hidden and lg.visible)
	await click(lg.get_global_rect().get_center())
	check("клик по «Журналу» показывает баннер", shown() and not lg.visible)
	# экран выбора карточек: «Журнала» нет
	await click(m.banner_close.get_global_rect().get_center())
	m.wave_number = int(m.card_rules.pick_after_waves[0])
	m._offer_cards()
	await step(2)
	var picking: bool = m._picking()
	check("экран выбора карточек (%s): баннер скрыт — «Журнала» нет" % picking, picking and m.banner_hidden and not lg.visible and not b.visible)
	m.card_screen.visible = false
	await step(2)
	# новый баннер сбрасывает скрытие
	check("скрыт перед новым баннером", m.banner_hidden and lg.visible)
	m._set_banner(m._banner_wave_cleared.bind("", 1, 0, 0))
	await step(2)
	check("новый баннер (итог волны): виден, «×» видна, «Журнала» нет", shown() and b.visible and not lg.visible)
	# конец забега
	m._on_defeat()
	await step(2)
	check("конец забега: баннер с «В хаб», «×» нет", shown() and m.hub_button.visible and not b.visible and not lg.visible)
	await key_h()
	check("конец забега: H баннер не скрывает", shown() and not lg.visible)
	g.go_menu()
	await step(3)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
