extends SceneTree
# Задача 26, этап 4 (без окна): первая минута и подсказки.
#   data/hints.json: у каждой подсказки id, известное условие when, ключ текста с переводом ru и en, известное done_on, seconds > 0;
#   текст в одну строку не шире max_width при кегле подсказки (ru, en).
#   Hints: одновременно не больше одной (ждущая показывается после), каждая один раз, исчезает через seconds или по done_on,
#   выключены — не показываются, «Сбросить» — покажутся снова; флаги в Settings и в файле настроек.
#   Бой: вступление дневника не показывается само (баннер — только «начать волну»), но отмечено прочитанным (дневник хаба);
#   при начале первой битвы — «выбор и приказ», при выборе отряда — «ПКМ — идти…», приказ убирает, при первой передышке — магазин.
#   Настройки: вкладка «Игра» — «Подсказки» и «Сбросить подсказки».
# Временное сохранение и настройки — user://bench_v76_hints.
const HINTS := preload("res://scripts/hints.gd")
const DIR := "user://bench_v76_hints"
const DONE_ON := ["", "order", "hero_attack", "buy", "camera"]
var fails := 0
var clock := 0

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
	DirAccess.make_dir_recursive_absolute(DIR)
	var st: Node = root.get_node("Settings")
	st.hints_seen = []
	st.hints_enabled = true
	await t_data()
	await t_logic(st)
	await t_settings_file()
	await t_battle(st)
	await t_menu(st)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("data/hints.json")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hints.json"))
	var m: Node2D = load("res://scripts/main.gd").new()
	var conds: Array = m.hint_conditions().keys()
	m.free()
	var h: PanelContainer = HINTS.new()
	h.load_defs()
	root.add_child(h)
	await step(1)
	var bad := []
	var ids := {}
	for e in d.hints:
		if ids.has(e.id) or not e.when in conds or not str(e.get("done_on", "")) in DONE_ON or float(e.seconds) <= 0.0:
			bad.append(e.id)
		ids[e.id] = true
	check("подсказок %d, у всех id (без повторов), условие из %s, done_on из %s, seconds > 0" % [d.hints.size(), str(conds), str(DONE_ON)],
		bad.is_empty() and h.defs.size() == d.hints.size(), str(bad))
	var want := ["select_order", "mouse_orders", "hero_attack", "shop", "camera"]
	check("начальные подсказки: выбор и приказ, ПКМ, удар героя, магазин, камера (задача 28)", want.all(func(id): return ids.has(id)))
	var font: Font = h.label.get_theme_font("font")
	var fs: int = h.label.get_theme_font_size("font_size")
	var wide := []
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		for e in d.hints:
			var t := HINTS.text_of(e.text)
			var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if t == e.text or "{" in t or "\n" in t or w > float(d.max_width):
				wide.append("%s %s: %d px «%s»" % [loc, e.id, int(w), t])
	TranslationServer.set_locale("ru")
	check("тексты ru и en переведены, клавиши подставлены, одна строка не шире max_width %d" % int(d.max_width), wide.is_empty(), "; ".join(wide))
	h.queue_free()
	await step(1)

func t_logic(st: Node) -> void:
	print("показ: одна за раз, один раз, время, действие")
	var h: PanelContainer = HINTS.new()
	h.load_defs()
	h.now_ms = func() -> int: return clock
	root.add_child(h)
	await step(1)
	var d0: Dictionary = h.defs[0]
	var d1: Dictionary = h.defs[1]
	clock = 1000
	var both := {d0.when: true, d1.when: true}
	h.poll(both)
	check("выполнены два условия — показана первая по списку", h.visible and h.current.id == d0.id and h.label.text == HINTS.text_of(d0.text))
	clock += 500
	h.poll(both)
	check("пока она видна, вторая ждёт", h.current.id == d0.id and h.shown_log == [d0.id])
	clock = 1000 + int(d0.seconds * 1000.0)
	h.poll(both)
	check("через seconds (%s с) исчезла сама" % d0.seconds, not h.visible and h.current.is_empty())
	h.poll(both)
	check("затем показана вторая; первая — больше никогда", h.current.id == d1.id and h.shown_log == [d0.id, d1.id])
	h.event("nothing")
	check("чужое действие не убирает", h.visible)
	h.event(d1.done_on)
	check("действие done_on «%s» убирает сразу" % d1.done_on, not h.visible)
	h.poll(both)
	var rest: Array = h.defs.slice(2).filter(func(e): return both.has(e.when))   # задача 28: camera — тоже при battle_start
	check("обе показаны — больше ни одна из них; дальше — следующая с тем же условием (%s) или ничего (флаги в Settings: %s)" % [
		str(rest.map(func(e): return e.id)), str(st.hints_seen)], st.hints_seen.slice(0, 2) == [d0.id, d1.id]
		and (h.current.get("id", "") == rest[0].id if not rest.is_empty() else not h.visible))
	st.reset_hints()
	st.set_hints_enabled(false)
	h.poll(both)
	check("подсказки выключены — не показываются", not h.visible)
	st.set_hints_enabled(true)
	h.poll(both)
	check("сброс и включение — первая снова показана", h.visible and h.current.id == d0.id)
	st.set_hints_enabled(false)
	h.poll(both)
	check("выключение прячет показанную", not h.visible)
	st.set_hints_enabled(true)
	st.reset_hints()
	h.queue_free()
	await step(1)

func t_settings_file() -> void:
	print("флаги в файле настроек")
	var a: Node = load("res://scripts/settings.gd").new()
	root.add_child(a)
	await step(1)
	a.path = DIR + "/settings.cfg"
	a.persist = true
	a.hints_enabled = false
	a.mark_hint_seen("shop")
	var b: Node = load("res://scripts/settings.gd").new()
	root.add_child(b)
	await step(1)
	b.path = a.path
	b.load_settings()
	check("hints/enabled и hints/seen сохраняются и читаются", b.hints_enabled == false and b.hints_seen == ["shop"], "%s %s" % [b.hints_enabled, b.hints_seen])
	a.queue_free()
	b.queue_free()
	await step(1)
	TranslationServer.set_locale("ru")

func t_battle(st: Node) -> void:
	print("первая минута в бою")
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	node_added.connect(_on_node_added)
	await step(1)
	check("новый игрок: вступление ещё не прочитано", not g.diary_read(g.INTRO_ID))
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	check("стартовый баннер без вступления и заголовка дневника — только «начать волну»", m.banner_parts[0] == "" and m.banner_parts[2] == ""
		and m.banner_parts[3] == tr("MSG_WAVE_START") % m.SETTINGS.key_label("wave_start"), str(m.banner_parts))
	check("вступление отмечено прочитанным и сохранено — оно в дневнике хаба", g.diary_read(g.INTRO_ID))
	m._clear_sel()
	m._update_ui()
	check("до волны, без выбора — подсказок нет", not m.hints.visible)
	m._start_wave()
	m._update_ui()
	check("начало первой битвы — «выбор и приказ»", m.hints.visible and m.hints.current.id == "select_order", m.hints.label.text)
	m._select_only(0)
	m._update_ui()
	check("отряд выбран — «ПКМ» ждёт, пока видна первая", m.hints.current.id == "select_order")
	m._hint_event("order")
	m._update_ui()
	check("приказ убирает первую, затем показана «ПКМ — идти…»", m.hints.current.get("id", "") == "mouse_orders", m.hints.label.text)
	m._hint_event("order")
	m._update_ui()
	check("приказ убирает и её, затем — «колесо: зум, зажатое колесо: перемещение» (задача 28)", m.hints.current.get("id", "") == "camera", m.hints.label.text)
	m.zoom_by(1.0, Vector2(960, 540))   # зум колесом — действие camera
	m._update_ui()
	check("зум колесом убирает её", not m.hints.visible)
	# первая передышка: волна кончилась
	m.wave_state = m.WS_RESPITE
	m.wave_number = 1
	m._update_ui()
	check("первая передышка — подсказка магазина", m.hints.current.get("id", "") == "shop", m.hints.label.text)
	var gk: int = m.SHOP_ITEMS.find("gate")
	m.gold = 1e6
	m._buy(gk)
	m._update_ui()
	check("покупка убирает её", not m.hints.visible)
	m.queue_free()
	await step(2)
	st.reset_hints()

func t_menu(st: Node) -> void:
	print("настройки: вкладка «Игра»")
	var sm: CanvasLayer = load("res://scripts/settings_menu.gd").new()
	root.add_child(sm)
	await step(1)
	sm.open()
	var titles := []
	for t in sm.tabs.get_tab_count():
		titles.append(tr(sm.tabs.get_tab_title(t)))
	check("вкладка «Игра» есть", "Игра" in titles, str(titles))
	sm.hints_check.button_pressed = false
	check("«Подсказки» выкл — Settings.hints_enabled false", st.hints_enabled == false)
	sm.hints_check.button_pressed = true
	st.mark_hint_seen("shop")
	sm.hints_reset_button.pressed.emit()
	check("«Сбросить подсказки» — показанных нет, сообщение", st.hints_seen.is_empty() and st.hints_enabled and tr(sm.game_msg.text) == tr("MSG_HINTS_RESET_DONE"))
	sm.close()
	sm.queue_free()
	await step(1)
