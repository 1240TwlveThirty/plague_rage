extends SceneTree
# Тесты v42 (каркас забега, часть 2): сохранение на диск (в том числе время игры play_time), story.json новой структуры, дневник по событиям, концовки, рекорды.
# Game создаётся вручную на каждый случай (автозагрузка проекта убирается), сохранение — во временной папке user://bench_v42;
# настоящий user://save.json не трогается. Физика боя вручную. Аргументы: [save | story | diary | endings | records] — по умолчанию все.
# Интерфейс с окном — bench/smoke_v42.gd.
const GAME := "res://scripts/game.gd"
const MAIN := "res://scripts/main.gd"
const STORY := "res://data/story.json"
const STORY_OLD := "res://bench/fixtures_story/story_old.json"   # story.json прошлого коммита (прежняя структура)
const FIX := "res://bench/fixtures_story/"
const DIR := "user://bench_v42"
const SAVE := DIR + "/save.json"
const DT := 1.0 / 30.0
const ENTRY_COUNT := 14   # записей дневника в data/story.json
const VICTORIES := [
	"День десятый. Последний из них упал у ворот, и боль короля стихла. Я записал это, как записываю всё. Это не конец: Благодать умеет возвращаться.",
	"Снова десять дней, и снова ворота стоят. Свет над лесом стал ярче. Он красивый. Я перестал отводить глаза.",
	"Ворота стоят, но я больше не держу их. Благодать вошла не как захватчик, а как та, кого я ждал. Я принимаю."]
const START_HINT := "Расставь отряды. Space — начать волну 1"
var fails := 0
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func key(m: Node, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	m._unhandled_input(e)

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == MAIN:
		n.process_mode = Node.PROCESS_MODE_DISABLED

func files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		out.append(f)
	return out

func wipe() -> void:
	for f in files():
		DirAccess.remove_absolute(DIR + "/" + f)

func put(text: String) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func read() -> String:
	return FileAccess.get_file_as_string(SAVE) if FileAccess.file_exists(SAVE) else ""

func on_disk() -> Dictionary:
	var d = JSON.parse_string(read()) if read() != "" else null
	return d if d is Dictionary else {}

# Новый узел Game (как при новом запуске игры): сохранение читается из временной папки.
func new_game() -> void:
	if g != null:
		g.free()
		await step(1)
	g = load(GAME).new()
	g.name = "Game"
	g.save_path = SAVE
	g.card_rules_path = ""   # каркас забега без выбора карточек (он — в check_v53_pick.gd)
	root.add_child(g)

func clean() -> bool:
	return g.unlocked_siege == 1 and g.last_siege == 1 and g.diary_seen.is_empty() and not g.completed and g.runs_total == 0 and g.records.size() == 3 \
		and g.records[1] == {"best_wave": 0, "wins": 0, "runs": 0} and g.records[3] == {"best_wave": 0, "wins": 0, "runs": 0}

func run(siege := 1) -> Node2D:
	g.start_run(siege)
	await step(3)
	return current_scene as Node2D

func hub() -> Node:
	g.go_hub()
	await step(3)
	return current_scene

func boost(m: Node2D) -> void:
	m.type_hp[m.infantry_type] *= 10.0
	m.type_hp[m.archer_type] *= 10.0
	m.type_damage[m.infantry_type] *= 10.0
	m.base_type_hp[m.infantry_type] *= 10.0   # база тоже: данные волны пересчитываются от неё в начале каждой волны
	m.base_type_hp[m.archer_type] *= 10.0
	m.base_type_damage[m.infantry_type] *= 10.0
	for i in m.count:
		if m.team[i] == 0:
			m.hp[i] = m.type_hp[m.unit_type[i]]

func wave(m: Node2D) -> void:
	m._start_wave()
	var t := 0
	while m.wave_state == m.WS_BATTLE and t < 30 * 400:
		m._physics_process(DT)
		t += 1

# Конец забега без боя: волна выставляется вручную (настоящий бой до победы и поражения — в check_v41).
func finish(m: Node2D, w: int, win := false) -> void:
	m.wave_number = w
	m.wave_state = m.WS_BATTLE
	if win:
		m._on_win()
	else:
		m._on_defeat()

func real_stamp() -> String:
	return "%d/%d" % [FileAccess.get_modified_time("user://save.json"), FileAccess.get_file_as_bytes("user://save.json").size()] if FileAccess.file_exists("user://save.json") else "нет"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var real := real_stamp()
	if root.has_node("Game"):
		root.get_node("Game").free()   # автозагрузка проекта: дальше Game создаётся вручную с временным сохранением
		await step(1)
	DirAccess.make_dir_recursive_absolute(DIR)
	wipe()
	node_added.connect(_on_node_added)
	var args := OS.get_cmdline_user_args()
	var mode := "all" if args.is_empty() else args[0]
	if mode in ["all", "story"]:
		await t_story()
	if mode in ["all", "diary"]:
		await t_diary()
	if mode in ["all", "endings"]:
		await t_endings()
	if mode in ["all", "records"]:
		await t_records()
	if mode in ["all", "save"]:
		await t_save()
	wipe()
	DirAccess.remove_absolute(DIR)
	check("настоящий user://save.json не тронут, временная папка убрана", real_stamp() == real and not DirAccess.dir_exists_absolute(DIR), real)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# (б) сохранение.
func t_save() -> void:
	print("(б) сохранение — ниже ожидаются строки WARNING о повреждённом и более новом сохранении")
	wipe()
	await new_game()
	check("файла нет: чистое состояние, предупреждения нет, файл загрузкой не создан", clean() and g.save_warning == "" and not g.save_locked and files().is_empty())
	g.siege = 1
	g.end_run("loss", 3, 10)
	g.end_run("win", 10, 99)
	g.mark_diary("intro")
	g.mark_diary("s1w3")
	g.mark_diary("s1w1")
	g.siege = 3
	g.unlocked_siege = 3
	g.last_siege = 2
	g.end_run("win", 10, 5)
	var d := on_disk()
	check("после записи файл парсится, version 1, все поля на месте", d.get("version") == 1.0 and d.has("unlocked_siege") and d.has("last_siege") and d.has("records")
		and d.has("diary_seen") and d.has("completed") and d.has("runs_total"), str(d.keys()))
	check("рядом нет временного файла: в папке только save.json", files() == PackedStringArray(["save.json"]), str(files()))
	var want := [g.records.duplicate(true), g.unlocked_siege, g.diary_seen.duplicate(), g.completed, g.runs_total, g.last_siege]
	await new_game()
	var got := [g.records, g.unlocked_siege, g.diary_seen, g.completed, g.runs_total, g.last_siege]
	check("новый узел Game загрузил то же: records, unlocked_siege, diary_seen, completed, runs_total, last_siege", got == want and g.save_warning == "", str(got))
	check("значения: осада I {10, 1, 2}, осада III {10, 1, 1}, открыто 3, completed, забегов 3, дневник intro, s1w3, s1w1",
		g.records[1] == {"best_wave": 10, "wins": 1, "runs": 2} and g.records[3] == {"best_wave": 10, "wins": 1, "runs": 1} and g.unlocked_siege == 3
		and g.completed and g.runs_total == 3 and g.diary_seen == ["intro", "s1w3", "s1w1"] and g.last_siege == 2 and g.siege == 2)
	var h := await hub()
	check("хаб из загруженных данных: рекорды, выбрана последняя осада II, предупреждения нет", tr(h.record_labels[0].text) == "Осада I: лучшая волна 10, побед 1, забегов 2"
		and tr(h.record_labels[2].text) == "Осада III: лучшая волна 10, побед 1, забегов 1" and h.chosen == 2 and h.siege_option.item_count == 3 and not h.warning_label.visible)
	# запись при выходе
	g.diary_seen.append("s1w5")   # в памяти, без сохранения
	var before := read()
	g.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check("закрытие окна (WM_CLOSE_REQUEST) записывает сохранение", not "s1w5" in before and on_disk().get("diary_seen", []).has("s1w5") and files().size() == 1)
	# повреждённые файлы
	var good := read()
	var no_field: Dictionary = JSON.parse_string(good)
	no_field.erase("records")
	var v0: Dictionary = JSON.parse_string(good)
	v0.version = 0
	var no_version: Dictionary = JSON.parse_string(good)
	no_version.erase("version")
	var bad_records: Dictionary = JSON.parse_string(good)
	bad_records.records["1"].erase("wins")
	var cases := {"обрезанный JSON": good.substr(0, good.length() / 2), "нет поля records": JSON.stringify(no_field), "пустой": "", "не JSON": "это не JSON",
		"version 0": JSON.stringify(v0), "version отсутствует": JSON.stringify(no_version), "JSON-массив": "[1, 2, 3]", "рекорд без wins": JSON.stringify(bad_records)}
	for name in cases:
		wipe()
		put(cases[name])
		await new_game()
		var fs := files()
		var moved: bool = fs.size() == 1 and fs[0].begins_with("save_corrupt_") and fs[0].ends_with(".json") and fs[0].trim_prefix("save_corrupt_").trim_suffix(".json").is_valid_int()
		var kept: bool = moved and FileAccess.get_file_as_string(DIR + "/" + fs[0]) == cases[name]
		check("повреждённый (%s): переименован в save_corrupt_<unix>.json с тем же содержимым, состояние чистое, предупреждение" % name,
			moved and kept and clean() and tr(g.save_warning) == "Сохранение повреждено, начато заново" and not g.save_locked, str(fs))
	h = await hub()
	check("хаб: строка «Сохранение повреждено, начато заново» видна", h.warning_label.visible and tr(h.warning_label.text) == "Сохранение повреждено, начато заново")
	g.siege = 1
	g.end_run("loss", 2, 1)
	check("после повреждённого игра сохраняется заново: save.json парсится, забегов 1", on_disk().get("runs_total") == 1.0 and files().size() == 2, str(files()))
	await new_game()
	check("следующий запуск: предупреждения уже нет, забегов 1", g.save_warning == "" and g.runs_total == 1 and g.records[1].best_wave == 2)
	# более новая версия
	wipe()
	var newer := JSON.stringify({"version": 2, "unlocked_siege": 3, "extra": "поле из будущего"})
	put(newer)
	await new_game()
	check("version 2: игра в памяти с чистым состоянием, предупреждение, файл не переименован", clean() and g.save_locked and tr(g.save_warning) == "Сохранение от более новой версии"
		and files() == PackedStringArray(["save.json"]))
	g.siege = 1
	g.end_run("win", 10, 7)
	g.mark_diary("intro")
	g.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check("version 2: после end_run, отметки дневника и выхода файл не изменён; в памяти итог есть", read() == newer and files().size() == 1 and g.records[1].wins == 1 and g.unlocked_siege == 2)
	h = await hub()
	check("хаб: строка «Сохранение от более новой версии» видна", h.warning_label.visible and tr(h.warning_label.text) == "Сохранение от более новой версии")
	# время игры: поле play_time, version прежняя
	wipe()
	await new_game()
	var t0: float = g.play_time
	await step(5)
	check("play_time: начинается с нуля и растёт по кадрам", t0 >= 0.0 and t0 < 1.0 and g.play_time > t0, "%.3f -> %.3f" % [t0, g.play_time])
	g.play_time = 1234.56
	g.save()
	d = on_disk()
	check("play_time в файле: 1234.6 с, version 1", absf(d.get("play_time", -1.0) - 1234.6) < 0.01 and d.get("version") == 1.0, str(d.get("play_time")))
	await new_game()
	check("новый узел Game продолжает счёт с сохранённого", g.play_time >= 1234.59 and g.play_time < 1236.0 and g.save_warning == "", "%.3f" % g.play_time)
	var old_save := on_disk()
	old_save.erase("play_time")
	old_save.runs_total = 4
	put(JSON.stringify(old_save))
	await new_game()
	check("старый файл без play_time: читается без предупреждения, время 0, забегов 4", g.save_warning == "" and g.runs_total == 4 and g.play_time < 1.0
		and files() == PackedStringArray(["save.json"]), "%.3f" % g.play_time)
	old_save.play_time = "много"
	put(JSON.stringify(old_save))
	await new_game()
	check("play_time не число: время 0, сохранение не считается повреждённым", g.save_warning == "" and g.runs_total == 4 and g.play_time < 1.0
		and files() == PackedStringArray(["save.json"]))
	# кнопка «Выход»: сохраняет (дерево завершится в конце теста — quit уже запрошен, проверки ниже идут до конца кадра)
	wipe()
	await new_game()
	g.go_menu()
	await step(3)
	g.diary_seen.append("s2w5")
	current_scene.quit_button.pressed.emit()
	check("кнопка «Выход» записывает сохранение", on_disk().get("diary_seen", []).has("s2w5") and files() == PackedStringArray(["save.json"]), str(files()))

# (в) story.json новой структуры и его конвертация.
func t_story() -> void:
	print("(в) story.json — ниже ожидаются строки ERROR от повреждённых файлов")
	var gs: GDScript = load(GAME)
	var s: Dictionary = gs.load_story(STORY, 3)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STORY))   # файл как есть: тексты сверяются с ним байт в байт
	check("story.json грузится; записей %d" % ENTRY_COUNT, not s.is_empty() and s.entries.size() == ENTRY_COUNT and raw.entries.size() == ENTRY_COUNT,
		"" if s.is_empty() else "записей %d" % s.entries.size())
	check("вступление непустое, дословно как в файле", s.intro != "" and s.intro.to_utf8_buffer() == String(raw.intro_key).to_utf8_buffer())
	var by_place := {}
	for e in s.entries:
		by_place[Vector2i(e.siege, e.wave)] = e
	var good := 0
	for e in raw.entries:
		var place := Vector2i(int(e.siege), int(e.wave))
		var n = by_place.get(place)
		if n != null and n.text != "" and n.text.to_utf8_buffer() == String(e.text_key).to_utf8_buffer() and n.id == "s%dw%d" % [place.x, place.y] and e.id == n.id 				and place.x >= 1 and place.x <= 3 and place.y >= 1 and place.y <= 10:
			good += 1
		else:
			print("    запись %s не на месте" % str(e.get("id")))
	check("каждая запись: осада 1-3, волна 1-10, id вида s{осада}w{волна}, текст непустой и байт в байт как в файле", good == ENTRY_COUNT, "%d из %d" % [good, ENTRY_COUNT])
	var sorted := true
	for k in range(1, s.entries.size()):
		var a: Dictionary = s.entries[k - 1]
		var b: Dictionary = s.entries[k]
		sorted = sorted and (a.siege < b.siege or (a.siege == b.siege and a.wave < b.wave))
	check("записи отсортированы по (осада, волна)", sorted)
	var raw_ends: Array = raw.endings.duplicate()
	raw_ends.sort_custom(func(a, b): return a.min_wave < b.min_wave)
	var ends_ok: bool = Array(s.end_wave) == [0, 4, 7, 10] and raw_ends.size() == 4
	for k in 4:
		ends_ok = ends_ok and s.end_text[k] == raw_ends[k].text_key and "{wave}" in tr(s.end_text[k])
	check("4 концовки с порогами 0, 4, 7, 10; тексты дословно как в файле, в каждом есть {wave}", ends_ok, str(s.end_wave))
	check("3 победы (осады 1-3), тексты по осадам как в задании", s.victories.size() == 3 and tr(s.victories[1]) == VICTORIES[0] and tr(s.victories[2]) == VICTORIES[1] and tr(s.victories[3]) == VICTORIES[2])
	for name in ["no_field", "bad_type", "dup_id", "no_victory", "no_siege", "missing_file"]:
		check("повреждённый %s.json не грузится" % name, gs.load_story(FIX + name + ".json", 3).is_empty())
	check("прежняя структура (без id, siege, victories) не грузится", gs.load_story(STORY_OLD, 3).is_empty())
	for name in ["no_field", "bad_type"]:
		var m: Node2D = load(MAIN).new()
		m.story_path = FIX + name + ".json"
		m._setup_data()
		check("сцена боя с %s.json: остановка (типы сброшены, тик выключен)" % name, m.type_id.is_empty() and not m.is_physics_processing() and not m.is_processing())
		m.free()
	var ok: Node2D = load(MAIN).new()
	ok._setup_data()
	check("сцена боя с рабочим story.json грузится; вне дерева (без синглтона) запись волны 1 отдаётся каждый раз, у волны 4 записи нет", not ok.type_id.is_empty()
		and ok._entry_text(1) == by_place[Vector2i(1, 1)].text and ok._entry_text(1) != "" and ok._entry_text(4) == "")
	ok.free()

# (г) дневник по событиям.
func t_diary() -> void:
	print("(г) дневник")
	wipe()
	await new_game()
	var st: Dictionary = g.story
	var texts := {}
	for e in st.entries:
		texts[e.id] = tr(e.text)   # в story — ключи, в баннере и дневнике — перевод
	var h := await hub()
	h.diary_button.pressed.emit()
	check("хаб без прочитанного: «Дневник» открывается, в нём только «Записей пока нет.»", h.diary_panel.visible and h._diary_lines().is_empty()
		and h.diary_box.get_child_count() == 1 and tr(h.diary_box.get_child(0).text) == "Записей пока нет." and h.diary_close.has_focus())
	h.diary_close.pressed.emit()
	check("кнопка «Закрыть» закрывает дневник, фокус на «Начать забег»", not h.diary_panel.visible and h.start_button.has_focus())
	var m := await run(1)
	check("первый забег: стартовый баннер с заголовком и вступлением", m.banner_parts[0] == "Дневник военачальника" and m.banner_parts[2] == tr(st.intro) and m.banner_parts[3] == START_HINT, str(m.banner_parts))
	check("intro отмечено и сохранено", g.diary_seen == ["intro"] and on_disk().get("diary_seen") == ["intro"])
	boost(m)
	await wave(m)
	check("волна 1 пройдена: запись s1w1 в баннере итога, отмечена и сохранена", m.wave_state == m.WS_RESPITE and m.banner_parts[2] == texts["s1w1"] and m.banner_parts[1].begins_with("Волна 1 пройдена")
		and g.diary_seen == ["intro", "s1w1"] and on_disk().get("diary_seen") == ["intro", "s1w1"], m.banner_parts[2])
	await wave(m)
	check("волна 2 пройдена: запись s1w2 в баннере итога, отмечена и сохранена", m.wave_number == 2 and m.banner_parts[1].begins_with("Волна 2 пройдена") and m.banner_parts[2] == texts["s1w2"]
		and g.diary_seen == ["intro", "s1w1", "s1w2"] and on_disk().get("diary_seen") == ["intro", "s1w1", "s1w2"])
	finish(m, 3)
	key(m, KEY_ENTER)
	await step(3)
	current_scene.start_button.pressed.emit()
	await step(3)
	m = current_scene as Node2D
	check("второй забег: стартовый баннер без дневника — только «%s»" % START_HINT, m.banner_parts[0] == "" and m.banner_parts[2] == "" and m.banner_parts[3] == START_HINT and m.banner.visible, str(m.banner_parts))
	boost(m)
	await wave(m)
	check("волна 1 второго забега: запись s1w1 уже не показывается (баннер как без неё)", m.banner_parts[1].begins_with("Волна 1 пройдена") and m.banner_parts[2] == "" and g.diary_seen.size() == 3)
	m.queue_free()
	await step(2)
	await new_game()
	check("новый узел Game с тем же файлом: прочитанное загружено", g.diary_seen == ["intro", "s1w1", "s1w2"])
	m = await run(1)
	boost(m)
	check("после перезапуска вступление не показывается", m.banner_parts[0] == "" and m.banner_parts[2] == "")
	await wave(m)
	check("после перезапуска запись (1, 1) не показывается", m.banner_parts[2] == "" and m.wave_number == 1)
	await wave(m)
	check("после перезапуска запись (1, 2) не показывается", m.banner_parts[2] == "" and m.wave_number == 2)
	await wave(m)
	check("волна 3: запись s1w3 показана в первый раз", m.wave_number == 3 and m.banner_parts[2] == texts["s1w3"] and g.diary_seen == ["intro", "s1w1", "s1w2", "s1w3"])
	await wave(m)
	check("волна 4 (записи нет): баннер итога без дневника, diary_seen не изменился", m.wave_number == 4 and m.banner_parts[1].begins_with("Волна 4 пройдена") and m.banner_parts[2] == ""
		and g.diary_seen.size() == 4)
	finish(m, 5)
	key(m, KEY_ENTER)
	await step(3)
	h = current_scene
	g.mark_diary("s2w5")   # отмечены не по порядку: в дневнике всё равно (осада, волна)
	g.mark_diary("s1w5")
	h.diary_button.pressed.emit()
	var lines: Array = h._diary_lines()
	check("«Дневник»: вступление, затем прочитанные записи в порядке (осада, волна)", h.diary_panel.visible and lines == [["", tr(st.intro)], ["Осада I, волна 1", texts["s1w1"]],
		["Осада I, волна 2", texts["s1w2"]], ["Осада I, волна 3", texts["s1w3"]], ["Осада I, волна 5", texts["s1w5"]], ["Осада II, волна 5", texts["s2w5"]]], str(lines.map(func(l): return l[0])))
	var shown := PackedStringArray()
	for c in h.diary_box.get_children():
		shown.append(c.text)
	var leaked := 0
	for e in st.entries:
		if not g.diary_seen.has(e.id) and (tr(e.text) in shown or ("%s, волна %d" % [g.siege_name(e.siege), e.wave]) in shown):
			leaked += 1
	check("непрочитанных записей в панели нет (ни текста, ни заголовка); строк 11 = вступление + 5 заголовков + 5 текстов", leaked == 0 and shown.size() == 11
		and st.entries.size() > 5, "строк %d" % shown.size())
	key(h, KEY_ESCAPE)
	check("Esc закрывает дневник", not h.diary_panel.visible and h.start_button.has_focus())

# (д) концовки и тексты победы.
func t_endings() -> void:
	print("(д) концовки")
	wipe()
	await new_game()
	var st: Dictionary = g.story
	var want := {1: 0, 3: 0, 4: 4, 6: 4, 7: 7, 9: 7, 10: 10}
	for w in want:
		var m := await run(1)
		finish(m, w)
		var text: String = tr(st.end_text[Array(st.end_wave).find(want[w])]).replace("{wave}", str(w))
		check("поражение на волне %d: концовка порога %d, {wave} подставлен" % [w, want[w]], m.banner_parts[2] == text and ("День %d." % w) in text and not "{wave}" in text
			and m.banner_parts[2] == m._ending_text(w), m.banner_parts[2].left(40))
	check("после поражений completed false", not g.completed and g.unlocked_siege == 1)
	g.unlocked_siege = 3
	for s in [1, 2, 3]:
		var before: bool = g.completed
		var m := await run(s)
		finish(m, 10, true)
		check("победа на осаде %s: свой текст из victories, «Осада пережита. Волн: 10 из 10.», «Enter — в хаб»" % g.roman(s),
			m.wave_state == m.WS_WIN and m.banner_parts[2] == VICTORIES[s - 1] and m.banner_parts[1] == "Осада пережита. Волн: 10 из 10." and m.banner_parts[3] == "Enter — в хаб")
		check("  completed до победы %s, после %s; в файле то же" % [before, g.completed], not before and g.completed == (s == 3) and on_disk().get("completed") == (s == 3))
	var m2 := await run(3)
	finish(m2, 2)
	check("поражение после прохождения: completed остаётся true", g.completed and on_disk().get("completed") == true)

# (е) рекорды: хаб и файл.
func t_records() -> void:
	print("(е) рекорды")
	wipe()
	await new_game()
	var m := await run(1)
	finish(m, 3)
	m = await run(1)
	finish(m, 5)
	check("два поражения (волны 3 и 5): лучшая волна 5, забегов 2", g.records[1] == {"best_wave": 5, "wins": 0, "runs": 2})
	m = await run(1)
	finish(m, 10, true)
	key(m, KEY_ENTER)
	await step(3)
	var h := current_scene
	var d := on_disk()
	var r: Dictionary = d.get("records", {}).get("1", {})
	check("после победы файл: осада 1 {10, 1, 3}, открыто 2, забегов всего 3, last_siege 1", r == {"best_wave": 10.0, "wins": 1.0, "runs": 3.0} and d.get("unlocked_siege") == 2.0
		and d.get("runs_total") == 3.0 and d.get("last_siege") == 1.0, str(r))
	check("хаб показывает те же числа, что в файле", tr(h.record_labels[0].text) == "Осада I: лучшая волна %d, побед %d, забегов %d" % [int(r.best_wave), int(r.wins), int(r.runs)]
		and tr(h.record_labels[0].text) == "Осада I: лучшая волна 10, побед 1, забегов 3" and tr(h.record_labels[1].text) == "Осада II: лучшая волна 0, побед 0, забегов 0", h.record_labels[0].text)
	m = await run(1)
	finish(m, 2)
	check("поражение на волне 2 после победы: best_wave не уменьшается (10), забегов 4", g.records[1] == {"best_wave": 10, "wins": 1, "runs": 4} and on_disk().records["1"].best_wave == 10.0)
	await new_game()
	h = await hub()
	check("новый узел Game: хаб из файла — «Осада I: лучшая волна 10, побед 1, забегов 4», выбор осады виден", tr(h.record_labels[0].text) == "Осада I: лучшая волна 10, побед 1, забегов 4"
		and h.siege_option.visible and h.siege_option.item_count == 2 and h.chosen == 1 and tr(h.last_label.text) == "")
