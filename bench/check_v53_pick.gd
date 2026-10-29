extends SceneTree
# Тесты задачи 6, этап D (выбор карточек в забеге). Узел Game с временным сохранением в user://bench_v53; сцена боя в дереве с выключенным
# process_mode, физика вручную. Экран выбора после волн 2, 5, 8 (не после 1, 3, 4); тройка без повторов, выбранных и disabled, основные билды разные;
# продолжение билда; клавиши 1-3 и мышь; без выбора волна не начинается; список в HUD; новый забег очищает; генератор забега детерминирован.
const CARDS := preload("res://scripts/cards.gd")
const GAME := "res://scripts/game.gd"
const MAIN := "res://scripts/main.gd"
const DIR := "user://bench_v53"
const DT := 1.0 / 30.0
var fails := 0
var g: Node

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

func _initialize() -> void:
	_run.call_deferred()

# Сильная армия (как в check_v41): волны проходятся без покупок.
func boost(m: Node2D) -> void:
	for arr in [m.base_type_hp, m.type_hp]:
		arr[m.infantry_type] *= 10.0
		arr[m.archer_type] *= 10.0
	for arr in [m.base_type_damage, m.type_damage]:
		arr[m.infantry_type] *= 10.0
	for arr in [m.base_type_arrow_dmg, m.type_arrow_dmg]:
		arr[m.archer_type] *= 10.0
	for i in m.count:
		if m.team[i] == 0:
			m.hp[i] = m.type_hp[m.unit_type[i]]

func wave(m: Node2D) -> void:
	m._start_wave()
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 900:
		m._physics_process(DT)
		t += 1

func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	TranslationServer.set_locale("ru")
	DirAccess.make_dir_recursive_absolute(DIR)
	node_added.connect(_on_node_added)
	g = load(GAME).new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	t_offer_rules()
	await t_run()
	await t_determinism()
	g.queue_free()
	if current_scene != null:
		current_scene.queue_free()
	await step(2)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func builds_of(ids: Array) -> Array:
	return ids.map(func(id): return g.card_defs[id].builds[0])

func distinct(a: Array) -> int:
	var d := {}
	for x in a:
		d[x] = true
	return d.size()

# Подбор тройки (CARDS.offer) на генераторе забега.
func t_offer_rules() -> void:
	print("подбор тройки")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ok := true
	for k in 300:
		var o := CARDS.offer(g.card_defs, [], g.card_rules, rng)
		ok = ok and o.size() == 3 and distinct(o) == 3 and distinct(builds_of(o)) == 3 and o.all(func(id): return not g.card_defs[id].get("disabled", false))
	check("300 троек без выбранных карточек: по 3 разных, основные билды разные, без disabled", ok)
	var owned := [{"id": "purse"}]   # билд gold
	var cont := 0
	for k in 2000:
		var o := CARDS.offer(g.card_defs, owned, g.card_rules, rng)
		if "purse" in o:
			ok = false
		if "gold" in builds_of(o):
			cont += 1
		var b := builds_of(o)
		if distinct(b) != 3:
			ok = false
	check("при карточке билда gold: «Кошеля» в тройке нет, билды разные; gold в тройке в %.0f%% троек (не меньше 50%% — продолжение билда 0.5 плюс случай)" % (cont / 20.0),
		ok and cont >= 1000)
	var many := []
	for id in CARDS.active_ids(g.card_defs):
		if g.card_defs[id].builds[0] != "risk":
			many.append({"id": id})
	var left := CARDS.offer(g.card_defs, many, g.card_rules, rng)
	check("выбраны все карточки, кроме билда risk: разных билдов не хватает, тройка добрана из оставшихся (все risk, без повторов)",
		left.size() == 3 and distinct(left) == 3 and builds_of(left).all(func(b): return b == "risk"), str(left))

func t_run() -> void:
	print("выбор в забеге")
	g.run_seed = 42
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	check("забег начат: экран выбора есть и скрыт, выбранных карточек нет, в HUD списка нет", m != null and m.card_screen != null and not m.card_screen.visible and g.run_cards.is_empty()
		and m.cards_rows.is_empty() and not m.cards_label.visible)
	boost(m)
	wave(m)
	check("после волны 1 выбора нет", m.wave_state == m.WS_RESPITE and m.pending_offer.is_empty() and not m.card_screen.visible)
	wave(m)
	var offer: Array = m.pending_offer.duplicate()
	check("после волны 2 — экран выбора: тройка из разных основных билдов, на экране 3 карточки", m.wave_number == 2 and offer.size() == 3 and m.card_screen.visible
		and m.card_screen.buttons.size() == 3 and distinct(builds_of(offer)) == 3, str(offer))
	var b0: Button = m.card_screen.buttons[0]
	check("на карточке: клавиша [1], название, метка билда, описание", tr(b0.find_child("Name", true, false).text) == tr(g.card_defs[offer[0]].name_key)
		and b0.find_child("Key", true, false).text == "[1]" and tr(b0.find_child("Build", true, false).text) != "" and b0.find_child("Desc", true, false).text != "")
	m._start_wave()
	check("пока не выбрано, волна 3 не начинается (Space)", m.wave_state == m.WS_RESPITE and m.wave_number == 2)
	m.card_screen._input(key(KEY_2))
	await step(1)
	# задача 25: карточка применяется сразу, экран доигрывает анимацию; любая клавиша — пропуск и закрытие
	var applied: bool = g.run_cards.size() == 1 and g.run_cards[0].id == offer[1] and m.pending_offer.is_empty()
	m.card_screen._input(key(KEY_SPACE))
	check("клавиша 2: выбрана вторая карточка, тройка снята; пропуск анимации закрывает экран", applied and not m.card_screen.visible
		and g.run_cards.size() == 1)
	m._update_ui()
	check("HUD: «Карточки:» и строка с названием выбранной", m.cards_label.visible and tr(m.cards_label.text) == tr("HUD_CARDS") and m.cards_rows.size() == 1
		and m.cards_rows[0].text.contains(tr(g.card_defs[offer[1]].name_key)), "" if m.cards_rows.is_empty() else m.cards_rows[0].text)
	for w in [3, 4]:
		wave(m)
		check("после волны %d выбора нет" % w, m.wave_number == w and m.pending_offer.is_empty())
	wave(m)
	offer = m.pending_offer.duplicate()
	check("после волны 5 — снова тройка, без уже выбранной; на экране в списке «Уже выбрано» — она", offer.size() == 3 and not g.run_cards[0].id in offer and m.card_screen.visible
		and m.card_screen.owned_label.text.contains(tr(g.card_defs[g.run_cards[0].id].name_key)))
	m.card_screen.buttons[0].pressed.emit()
	await step(1)
	m.card_screen.finish_now()
	check("мышь (нажатие первой карточки): выбрана, всего 2", g.run_cards.size() == 2 and g.run_cards[1].id == offer[0] and not m.card_screen.visible)
	for w in [6, 7, 8]:
		wave(m)
	check("после волны 8 — третья тройка", m.wave_number == 8 and m.pending_offer.size() == 3)
	m.card_screen._input(key(KEY_3))
	check("клавиша 3: третья карточка, всего 3", g.run_cards.size() == 3)
	m.card_screen.finish_now()
	var cards_before: Array = g.run_cards.duplicate()
	g.start_run(1)
	await step(3)
	m = current_scene as Node2D
	check("новый забег: выбранные карточки очищены, HUD пуст", g.run_cards.is_empty() and m.cards_rows.is_empty() and not m.cards_label.visible and cards_before.size() == 3)

# Один seed забега — одни и те же тройки (без выбора: генератор забега не зависит от симуляции).
func offers_of(seed: int) -> Array:
	g.run_seed = seed
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	boost(m)
	var out := []
	for w in 8:
		wave(m)
		if not m.pending_offer.is_empty():
			out.append(m.pending_offer.duplicate())
			m.choose_card(m.pending_offer[0])
	return out

func t_determinism() -> void:
	print("генератор забега")
	var a: Array = await offers_of(7)
	var b: Array = await offers_of(7)
	var c: Array = await offers_of(8)
	check("seed 7 дважды — те же три тройки; seed 8 — другие", a.size() == 3 and a == b and c != a, "%s / %s" % [str(a), str(c)])
