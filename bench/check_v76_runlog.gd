extends SceneTree
# Задача 26, этап 5 (без окна): журнал забегов.
#   Файла нет — создаётся с заголовком; за забег ровно одна строка (повторный итог её не дублирует), следующий забег — следующая
#   строка. Поля: дата, версия игры, номер забега, осада, итог, волна, длительность, карточки (id), смерти героя, потрачено золота.
#   Тестовый SceneTree без своего пути журнал не пишет. «Открыть папку данных» открывает user://.
# Временные файлы — user://bench_v76_runlog.
const RUN_LOG := preload("res://scripts/run_log.gd")
const DIR := "user://bench_v76_runlog"
var fails := 0

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

func rows(path: String) -> Array:
	var out := []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var r := f.get_csv_line()
		if r.size() > 1:
			out.append(r)
	return out

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var log_path := DIR + "/runs.csv"
	DirAccess.remove_absolute(log_path)
	if root.has_node("Game"):
		check("тестовый SceneTree: автозагрузка Game журнал не пишет", root.get_node("Game").runs_log_path == "")
		root.get_node("Game").free()
		await step(1)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	node_added.connect(_on_node_added)
	await step(1)
	g.runs_log_path = log_path
	check("файла журнала нет", not FileAccess.file_exists(log_path))
	print("забег 1: поражение")
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	m.gold = 1e6
	var gk: int = m.SHOP_ITEMS.find("gate")
	var spent: float = m._price(gk)
	m._buy(gk)
	spent += m._price(gk)
	m._buy(gk)
	g.run_cards.append({"id": "last_bastion"})
	g.run_cards.append({"id": "commander_banner"})
	m.hero_deaths = 2
	m.wave_number = 3
	g.play_time = g.run_started + 75.25
	m._on_defeat()
	var r := rows(log_path)
	check("файл создан: заголовок и одна строка", r.size() == 2 and Array(r[0]) == RUN_LOG.COLUMNS, str(r))
	if r.size() == 2:
		var row := {}
		for i in RUN_LOG.COLUMNS.size():
			row[RUN_LOG.COLUMNS[i]] = r[1][i]
		var date_ok := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$").search(row.date) != null
		check("поля: дата, версия %s, номер забега %d, осада 1, поражение, волна 3, 75.3 с, карточки, смерти героя 2, золото %d" % [RUN_LOG.version(), g.runs_total, roundi(spent)],
			date_ok and row.version == RUN_LOG.version() and row.version != "dev" and int(row.run) == g.runs_total and row.siege == "1" and row.result == "loss"
			and row.wave == "3" and row.duration_s == "75.3" and row.cards == "last_bastion;commander_banner" and row.hero_deaths == "2"
			and int(row.gold_spent) == roundi(spent), str(row))
	g.end_run("loss", 3, 0)   # повторный итог того же забега
	check("повторный итог того же забега строку не добавляет", rows(log_path).size() == 2)
	m.queue_free()
	await step(2)
	print("забег 2: победа")
	g.start_run(1)
	await step(3)
	m = current_scene as Node2D
	m.wave_number = m.waves_per_run
	m._on_win()
	r = rows(log_path)
	check("второй забег — вторая строка: победа, номер — законченных забегов за всё время, без карточек, золото 0", r.size() == 3 and r[2][4] == "win" and r[2][7] == "" and r[2][9] == "0"
		and int(r[2][2]) == g.runs_total, str(r[2] if r.size() > 2 else r))
	m.queue_free()
	await step(2)
	print("«Открыть папку данных»")
	var sm: CanvasLayer = load("res://scripts/settings_menu.gd").new()
	root.add_child(sm)
	await step(1)
	var opened := []
	sm.shell_open = func(p: String) -> Error:
		opened.append(p)
		return OK
	sm.data_folder_button.pressed.emit()
	check("кнопка на вкладке «Игра» открывает папку user:// (%s)" % ProjectSettings.globalize_path("user://"),
		opened == [ProjectSettings.globalize_path("user://")] and sm.data_folder_button.get_parent() == sm.hints_check.get_parent())
	sm.queue_free()
	await step(1)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
