extends SceneTree
# Тесты v41 (каркас забега, часть 1): Game, run.json, победа, поражение, повторный забег, хаб. Сцены в дереве,
# физика боя вручную (process_mode сцены боя выключен, тики идут вызовом _physics_process).
# Аргументы: [cfg | win | loss | rerun | hub] — по умолчанию все. Интерфейс с окном — bench/smoke_v41.gd.
const GAME := "res://scripts/game.gd"
const MAIN := "res://scripts/main.gd"
const FIX := "res://bench/fixtures_run/"
const DT := 1.0 / 30.0
const SAVE_DIR := "user://bench_v41"
const SAVE := SAVE_DIR + "/save.json"
var fails := 0
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

# Game с нуля: временное сохранение удаляется (настоящее user://save.json тест не трогает).
func reset() -> void:
	DirAccess.remove_absolute(SAVE)
	g._setup()

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(m: Node, code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	m._unhandled_input(e)

# Сцена боя не тикает сама с момента входа в дерево: tick_counter остаётся 0 до ручных тиков.
func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == MAIN:
		n.process_mode = Node.PROCESS_MODE_DISABLED

# Game.start_run(siege) и ожидание новой сцены боя.
func run(siege := 1) -> Node2D:
	g.start_run(siege)
	await step(3)
	return current_scene as Node2D

func from_hub() -> Node2D:
	current_scene.start_button.pressed.emit()
	await step(3)
	return current_scene as Node2D

func ticks(m: Node2D, n: int) -> void:
	for i in n:
		m._physics_process(DT)

# Армия игрока x10 по HP, урон пехоты и стрел x10 (только в тесте): 10 волн слоя 1 проходятся без покупок.
func boost(m: Node2D) -> void:
	m.type_hp[m.infantry_type] *= 10.0
	m.type_hp[m.archer_type] *= 10.0
	m.type_damage[m.infantry_type] *= 10.0
	m.base_type_hp[m.infantry_type] *= 10.0   # база тоже: данные волны пересчитываются от неё в начале каждой волны
	m.base_type_hp[m.archer_type] *= 10.0
	m.base_type_damage[m.infantry_type] *= 10.0
	m.base_type_arrow_dmg[m.archer_type] *= 10.0
	m.type_arrow_dmg[m.archer_type] *= 10.0   # без этого при численности волн x2.7 (калибровка, этап 2) ворота падают на волне 9
	for i in m.count:
		if m.team[i] == 0:
			m.hp[i] = m.type_hp[m.unit_type[i]]

# Волна до конца боя; возвращает число зомби в плане волны.
func wave(m: Node2D, limit := 30 * 400) -> int:
	m._start_wave()
	var planned: int = m.wave_remaining
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < limit:
		m._physics_process(DT)
		t += 1
	return planned

# Поражение на текущей волне: армия игрока снята, у ворот 1 HP — зомби доходят и ломают их.
func lose(m: Node2D, limit := 30 * 300) -> void:
	m._start_wave()
	for i in m.count:
		if m.team[i] == 0:
			m.hp[i] = 0.0
	m.gate_hp = 1.0
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < limit:
		m._physics_process(DT)
		t += 1

func record_stamp() -> int:
	return FileAccess.get_modified_time("user://record.json") if FileAccess.file_exists("user://record.json") else -1

func snap(m: Node2D) -> Dictionary:
	var prices := []
	for k in m.SHOP_ITEMS.size():
		prices.append(m._price(k))
	return {"tick": m.tick_counter, "count": m.count, "gold": m.gold, "pos": m.pos.slice(0, m.count), "hp": m.hp.slice(0, m.count),
		"prices": prices, "bought": m.shop_bought.duplicate(), "dmg": m.type_damage[m.infantry_type], "arrow": m.type_arrow_dmg[m.archer_type],
		"wave": m.wave_number, "gate": m.gate_hp, "gate_max": m.gate_hp_max, "kills": m.run_kills}

func same(a: Dictionary, b: Dictionary) -> String:
	for k in a:
		if a[k] != b[k]:
			return k
	return ""

func plan_str(m: Node2D, w: int) -> String:
	var out := []
	for b in m._plan_bursts(w, m._plan_wave(w)):
		out.append([snappedf(b.t_start, 0.001), b.side, b.records])
	return JSON.stringify(out)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	g = root.get_node_or_null("Game")
	var manual := g == null
	if manual:   # автозагрузки в этом режиме нет: Game создаётся вручную
		g = load(GAME).new()
		g.name = "Game"
		root.add_child(g)
	print("Game: %s" % ("создан вручную" if manual else "автозагрузка проекта"))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	g.save_path = SAVE
	g.card_rules_path = ""   # каркас забега без выбора карточек (он — в check_v53_pick.gd)
	g.card_rules = {}
	node_added.connect(_on_node_added)
	var args := OS.get_cmdline_user_args()
	var mode := "all" if args.is_empty() else args[0]
	if mode in ["all", "cfg"]:
		await t_cfg()
	if mode in ["all", "win"]:
		await t_win()
	if mode in ["all", "loss"]:
		await t_loss()
	if mode in ["all", "rerun"]:
		await t_rerun()
	if mode in ["all", "hub"]:
		await t_hub()
	DirAccess.remove_absolute(SAVE)
	DirAccess.remove_absolute(SAVE_DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# (б) run.json: корректный грузится; без поля, с неверным типом, пустой — push_error и остановка.
func t_cfg() -> void:
	print("(б) конфиг run.json — ниже ожидаются строки ERROR от повреждённых файлов")
	var gs: GDScript = load(GAME)
	var ok: Dictionary = gs.load_run_cfg("res://data/run.json")
	check("data/run.json грузится: waves_per_run 10, siege_count 3", ok.get("waves_per_run") == 10 and ok.get("siege_count") == 3, str(ok))
	check("корректная копия грузится", gs.load_run_cfg(FIX + "ok.json") == {"waves_per_run": 7, "siege_count": 2})
	for name in ["no_field", "bad_type", "empty", "not_object", "fraction", "missing_file"]:
		check("повреждённый %s.json не грузится" % name, gs.load_run_cfg(FIX + name + ".json").is_empty())
	for name in ["no_field", "bad_type", "empty"]:
		g.run_path = FIX + name + ".json"
		reset()
		g.start_run(1)
		await step(3)
		check("Game с %s.json: cfg_ok false, забег не начинается" % name, not g.cfg_ok and g.run_index == 0 and current_scene == null)
		var m: Node2D = load(MAIN).new()
		m.run_path = FIX + name + ".json"
		m._setup_data()
		check("сцена боя с %s.json: остановка (типы сброшены, тик выключен)" % name, m.type_id.is_empty() and not m.is_physics_processing() and not m.is_processing())
		m.free()
	g.run_path = FIX + "ok.json"
	reset()
	check("Game с ok.json: 7 волн, 2 осады, рекорды нулевые", g.cfg_ok and g.waves_per_run == 7 and g.siege_count == 2 and g.records.size() == 2
		and g.records[2] == {"best_wave": 0, "wins": 0, "runs": 0})
	g.run_path = g.RUN_PATH
	reset()
	check("начальное состояние Game: siege 1, unlocked 1, run_index 0, last_run без результата, 3 записи рекордов",
		g.cfg_ok and g.siege == 1 and g.unlocked_siege == 1 and g.run_index == 0 and g.last_run.result == "" and g.records.size() == 3)

# (в) победа: 10 волн слоя 1 усиленной армией.
func t_win() -> void:
	print("(в) победа")
	reset()
	var stamp := record_stamp()
	var m := await run(1)
	check("забег начат: сцена боя, tick 0, передышка, волна 0, run_index 1", m != null and m.tick_counter == 0 and m.wave_state == m.WS_RESPITE
		and m.wave_number == 0 and g.run_index == 1 and m.run_limit and m.waves_per_run == 10)
	boost(m)
	var planned := 0
	for w in 9:
		planned += await wave(m)
	m._update_ui()
	check("после 9 волн передышка, HUD «Волна 9/10»", m.wave_state == m.WS_RESPITE and m.wave_number == 9 and m.hud_label.text.begins_with("Волна 9/10 · "), m.hud_label.text.get_slice("\n", 0))
	check("до конца забега Game не тронут: runs 0, last_run пуст", g.records[1].runs == 0 and g.last_run.result == "")
	var gold_before: float = m.gold
	planned += await wave(m)
	m._update_ui()
	check("после 10-й волны wave_state 3 (победа), ворота целы", m.wave_state == m.WS_WIN and m.wave_state == 3 and m.gate_hp > 0.0, "state %d, волна %d" % [m.wave_state, m.wave_number])
	check("физический тик остановлен, паузы нет", not m.is_physics_processing() and not m.paused)
	check("Game: records[1] wins 1, best_wave 10, runs 1", g.records[1] == {"best_wave": 10, "wins": 1, "runs": 1}, str(g.records[1]))
	check("Game: unlocked_siege 2, осады II и III без забегов", g.unlocked_siege == 2 and g.records[2].runs == 0 and g.records[3].runs == 0)
	check("last_run: win, осада 1, волна 10, kills = все зомби 10 волн (%d)" % planned,
		g.last_run == {"siege": 1, "result": "win", "wave": 10, "kills": planned, "radiance": g.run_reward("win", 10)}, str(g.last_run))
	check("баннер: «Осада пережита. Волн: 10 из 10.» и «Enter — в хаб», кнопка «В хаб» видна", m.banner.visible and m.banner_parts[1] == "Осада пережита. Волн: 10 из 10."
		and m.banner_parts[3] == "Enter — в хаб" and m.hub_button.visible and tr(m.hub_button.text) == "В хаб", str(m.banner_parts))
	check("HUD «Волна 10/10», магазин скрыт", m.hud_label.text.begins_with("Волна 10/10 · ") and not m.shop_panel.visible)
	m._start_wave()
	key(m, KEY_P)
	check("волна 11 не стартует, пауза при wave_state 3 недоступна", m.wave_number == 10 and m.wave_state == m.WS_WIN and not m.paused)
	ticks(m, 30)
	check("повторной записи итога нет (runs 1)", g.records[1].runs == 1 and g.records[1].wins == 1)
	check("user://record.json не тронут", record_stamp() == stamp)
	check("бонус за волну на победной волне не начисляется дважды (золото не меньше, чем до волны)", m.gold >= gold_before)
	key(m, KEY_ENTER)
	await step(3)
	check("Enter на экране победы ведёт в хаб: строка итога и выбор осады (две)", current_scene != null and current_scene.name == "Hub"
		and tr(current_scene.last_label.text) == "Последний забег: победа на 10-й волне" and current_scene.siege_option.visible and current_scene.siege_option.item_count == 2,
		"" if current_scene == null else current_scene.last_label.text)

# (г) поражение: ворота 1 HP на волне 3; второй забег — поражение на волне 2.
func t_loss() -> void:
	print("(г) поражение")
	reset()
	var stamp := record_stamp()
	var m := await run(1)
	boost(m)
	await wave(m)
	await wave(m)
	check("две волны пройдены, передышка", m.wave_state == m.WS_RESPITE and m.wave_number == 2)
	await lose(m)
	check("волна 3: wave_state 1 (поражение), тик остановлен", m.wave_state == m.WS_DEFEAT and m.wave_state == 1 and m.wave_number == 3 and not m.is_physics_processing())
	check("Game: runs 1, best_wave 3, wins 0, unlocked_siege 1", g.records[1] == {"best_wave": 3, "wins": 0, "runs": 1} and g.unlocked_siege == 1, str(g.records[1]))
	check("last_run: loss, волна 3, kills = счётчик сцены", g.last_run.result == "loss" and g.last_run.wave == 3 and g.last_run.siege == 1 and g.last_run.kills == m.run_kills and m.run_kills > 0, str(g.last_run))
	check("баннер: концовка дневника, «Лучшая волна осады I: 3. Enter — в хаб», без строки про рекорд-день", m.banner.visible and m.banner_parts[2] == m._ending_text(3) and m.banner_parts[2] != ""
		and m.banner_parts[3] == "Лучшая волна осады I: 3. Enter — в хаб" and not "Рекорд" in m.banner_parts[3] and m.hub_button.visible, str(m.banner_parts[3]))
	key(m, KEY_P)
	key(m, KEY_G)
	check("пауза при wave_state 1 недоступна", not m.paused)
	key(m, KEY_ENTER)
	await step(3)
	check("Enter ведёт в хаб: «Последний забег: поражение на волне 3», выбор осады скрыт", current_scene != null and current_scene.name == "Hub"
		and tr(current_scene.last_label.text) == "Последний забег: поражение на волне 3" and not current_scene.siege_option.visible)
	check("хаб: строка рекордов «Осада I: лучшая волна 3, побед 0, забегов 1»", tr(current_scene.record_labels[0].text) == "Осада I: лучшая волна 3, побед 0, забегов 1", current_scene.record_labels[0].text)
	m = await from_hub()
	check("второй забег с нуля: волна 0, run_index 2, last_run очищен", m.wave_number == 0 and m.tick_counter == 0 and g.run_index == 2 and g.last_run.result == "")
	boost(m)
	await wave(m)
	await lose(m)
	check("второй забег: поражение на волне 2", m.wave_state == m.WS_DEFEAT and m.wave_number == 2)
	check("Game: best_wave остаётся 3, runs 2, wins 0, unlocked_siege 1", g.records[1] == {"best_wave": 3, "wins": 0, "runs": 2} and g.unlocked_siege == 1, str(g.records[1]))
	check("баннер второго забега: «Лучшая волна осады I: 3. Enter — в хаб»", m.banner_parts[3] == "Лучшая волна осады I: 3. Enter — в хаб", m.banner_parts[3])
	check("user://record.json не тронут", record_stamp() == stamp)
	m.hub_button.pressed.emit()
	await step(3)
	check("кнопка «В хаб» ведёт в хаб: «поражение на волне 2»", current_scene != null and current_scene.name == "Hub" and tr(current_scene.last_label.text) == "Последний забег: поражение на волне 2")

# Один забег теста (д): снимок на тике 0, покупки, волна 1, 600 тиков, снимок, поражение, хаб.
func one_run(first: bool) -> Array:
	var m: Node2D = await run(1) if first else await from_hub()
	var s0 := snap(m)
	m.gold += 500.0   # только в тесте: хватает на оружие и отряд; следующий забег должен начаться без них
	m._buy(2)   # оружие
	m._buy(0)   # +50 пехоты
	m._start_wave()
	ticks(m, 600)
	var s600 := snap(m)
	m.gate_hp = 0.0
	ticks(m, 1)
	var lost: bool = m.wave_state == m.WS_DEFEAT
	key(m, KEY_ENTER)
	await step(3)
	return [s0, s600, lost and current_scene != null and current_scene.name == "Hub"]

# (д) повторный забег: то же состояние на тиках 0 и 600, узлы и память не копятся.
func t_rerun() -> void:
	print("(д) повторный забег")
	reset()
	var a := await one_run(true)
	var b := await one_run(false)
	check("оба забега кончились поражением и хабом", a[2] and b[2])
	check("тик 0: tick_counter 0, покупок нет, золото стартовое", a[0].tick == 0 and b[0].tick == 0 and a[0].wave == 0 and Array(a[0].bought) == [0, 0, 0, 0] and a[0].kills == 0)
	check("тик 0 второго забега как у первого (pos, hp, count, gold, цены, множитель оружия)", same(a[0], b[0]) == "", "расходится: " + same(a[0], b[0]))
	check("тик 600: покупки сделаны, бой шёл (есть убитые)", a[1].tick == 600 and a[1].bought[2] == 1 and a[1].bought[0] == 1 and a[1].dmg > a[0].dmg and a[1].prices[2] > a[0].prices[2] and a[1].kills > 0,
		"убито %d, куплено %s" % [a[1].kills, str(a[1].bought)])
	check("тик 600 второго забега как у первого", same(a[1], b[1]) == "", "расходится: " + same(a[1], b[1]))
	check("Game: runs 2, run_index 2", g.records[1].runs == 2 and g.run_index == 2)
	await step(5)
	var orphans0 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var mem0 := OS.get_static_memory_usage()
	for i in 5:
		var r := await one_run(false)
		if not r[2]:
			fails += 1
			print("  забег %d серии не дошёл до хаба: НЕТ" % (i + 1))
	await step(5)
	var orphans1 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var mem1 := OS.get_static_memory_usage()
	check("5 забегов подряд: орфанных узлов не больше, чем до серии", orphans1 <= orphans0, "%d -> %d" % [orphans0, orphans1])
	check("5 забегов подряд: всего узлов не больше, чем до серии", nodes1 <= nodes0, "%d -> %d" % [nodes0, nodes1])
	check("5 забегов подряд: память выросла не больше чем на 10 МБ", mem0 > 0 and mem1 - mem0 <= 10 * 1024 * 1024, "%.2f -> %.2f МБ" % [mem0 / 1048576.0, mem1 / 1048576.0])
	check("Game после серии: runs 7, run_index 7", g.records[1].runs == 7 and g.run_index == 7)

# (е) хаб: выбор осады, осада II берёт слой 2.
func t_hub() -> void:
	print("(е) хаб")
	reset()
	g.go_hub()
	await step(3)
	var h := current_scene
	check("хаб без забегов: выбор осады скрыт, итог пуст, «Осада I», три строки рекордов", h != null and h.name == "Hub" and not h.siege_option.visible and tr(h.last_label.text) == ""
		and tr(h.siege_label.text) == "Осада I" and h.record_labels.size() == 3 and tr(h.record_labels[2].text) == "Осада III: лучшая волна 0, побед 0, забегов 0")
	check("главная кнопка «Начать забег» в фокусе, фокус у кнопок по умолчанию", h.start_button.has_focus() and tr(h.start_button.text) == "Начать забег"
		and h.menu_button.focus_mode == Control.FOCUS_ALL and tr(h.menu_button.text) == "В меню")
	g.unlocked_siege = 2
	g.go_hub()
	await step(3)
	h = current_scene
	check("unlocked_siege 2: выбор виден, в нём «Осада I» и «Осада II»", h.siege_option.visible and h.siege_option.item_count == 2
		and h.siege_option.get_item_text(0) == "Осада I" and h.siege_option.get_item_text(1) == "Осада II")
	check("по умолчанию выбрана первая (забегов не было)", h.chosen == 1 and h.siege_option.get_selected_id() == 1)
	h.siege_option.select(1)
	h.siege_option.item_selected.emit(1)
	check("выбрана осада II: строка «Осада II»", h.chosen == 2 and tr(h.siege_label.text) == "Осада II")
	var m := await from_hub()
	check("Game.start_run взял выбранную: siege 2, сцена боя на слое 2", g.siege == 2 and m != null and m.debug_layer == 2 and m._layer() == m.wave_cfg.layers[1])
	var ref2: Node2D = load(MAIN).new()   # вне дерева: синглтона нет, слой задаётся вручную
	ref2.debug_layer = 2
	ref2._setup_data()
	var ref1: Node2D = load(MAIN).new()
	ref1._setup_data()
	var p := plan_str(m, 3)
	check("план всплесков волны 3 в осаде II — как у слоя 2 и не как у слоя 1", p == plan_str(ref2, 3) and p != plan_str(ref1, 3) and p != "[]")
	check("вне дерева синглтона нет: слой DEBUG_LAYER, предела волн нет", ref1.game == null and not ref1.run_limit and ref1.debug_layer == ref1.DEBUG_LAYER)
	ref1.free()
	ref2.free()
	await lose(m)
	check("поражение в осаде II пишется в records[2]", g.records[2].runs == 1 and g.records[2].best_wave == 1 and g.records[1].runs == 0 and g.last_run.siege == 2)
	check("баннер: «Лучшая волна осады II: 1. Enter — в хаб»", m.banner_parts[3] == "Лучшая волна осады II: 1. Enter — в хаб", m.banner_parts[3])
	key(m, KEY_ENTER)
	await step(3)
	h = current_scene
	check("хаб после забега: выбрана последняя сыгранная осада II", h.chosen == 2 and h.siege_option.get_selected_id() == 2 and tr(h.siege_label.text) == "Осада II")
	check("строка рекордов осады II: «Осада II: лучшая волна 1, побед 0, забегов 1»", tr(h.record_labels[1].text) == "Осада II: лучшая волна 1, побед 0, забегов 1", h.record_labels[1].text)
	h.menu_button.pressed.emit()
	await step(3)
	check("«В меню» ведёт в меню: заголовок, «Играть» в фокусе, «Выход»", current_scene != null and current_scene.name == "Menu" and current_scene.play_button.has_focus()
		and tr(current_scene.play_button.text) == "Играть" and tr(current_scene.quit_button.text) == "Выход")
	check("Game после меню не сброшен: unlocked_siege 2, records[2].runs 1", g.unlocked_siege == 2 and g.records[2].runs == 1)
