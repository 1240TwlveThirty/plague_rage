extends Node
# Каркас забега: какая осада идёт, что открыто, рекорды, прочитанный дневник, время игры и итог последнего забега.
# Автозагрузка с именем Game. Состояние между запусками хранится в save_path (user://save.json).
const RUN_PATH := "res://data/run.json"
const STORY_PATH := "res://data/story.json"
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const MAIN_SCENE := "res://scenes/main.tscn"
const HUB_SCENE := "res://scenes/hub.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const INTRO_ID := "intro"      # id вступления в diary_seen
const WARN_CORRUPT := "Сохранение повреждено, начато заново"
const WARN_NEWER := "Сохранение от более новой версии"

var run_path := RUN_PATH       # тесты подменяют и вызывают _setup
var story_path := STORY_PATH   # тесты подменяют
var save_path := SAVE_PATH     # тесты подменяют: настоящее сохранение они не трогают
var cfg_ok := false            # run.json загрузился; иначе забег не начать
var waves_per_run := 0
var siege_count := 0
var siege := 1                 # текущая осада, 1..siege_count
var unlocked_siege := 1        # до какой осады открыто
var last_siege := 1            # осада последнего начатого забега: хаб выбирает её по умолчанию
var records := {}              # осада -> {best_wave, wins, runs}
var diary_seen: Array = []     # id прочитанных записей дневника и INTRO_ID
var completed := false         # последняя осада пройдена хотя бы раз
var runs_total := 0            # законченных забегов за всё время
var play_time := 0.0           # секунд игры за всё время: идёт, пока игра запущена (меню, хаб, бой, пауза)
var last_run := {}             # {siege, result "win" / "loss" / "", wave, kills}; result "" — забега ещё не было
var run_index := 0             # сколько забегов начато за этот запуск
var save_locked := false       # сохранение от более новой версии: файл не перезаписывается, игра идёт в памяти
var save_warning := ""         # строка-предупреждение для хаба или ""
var story := {}                # дневник для хаба (load_story) или {} при ошибке
var active_gifts := {}         # дары следующего забега, id -> уровень: сцена боя читает при старте; в сохранение не пишется


func _ready() -> void:
	_setup()


func _process(delta: float) -> void:
	play_time += delta


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


# run.json: waves_per_run и siege_count — целые числа не меньше 1. Значений по умолчанию нет: чего нет — ошибка.
# При ошибке push_error и пустой словарь.
static func load_run_cfg(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: %s" % path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d == null:
		push_error("%s: битый JSON" % path)
		return {}
	if not d is Dictionary:
		push_error("%s: ожидается JSON-объект" % path)
		return {}
	for key in ["waves_per_run", "siege_count"]:
		var v = d.get(key)
		if not (v is float or v is int) or v != floorf(v) or v < 1:
			push_error("%s: нет целого поля %s (не меньше 1)" % [path, key])
			return {}
	return {"waves_per_run": int(d.waves_per_run), "siege_count": int(d.siege_count)}


static func _whole(v: Variant) -> bool:
	return (v is float or v is int) and v == floorf(v)


# story.json: intro (строка), entries [{id, siege, wave, text}], endings [{min_wave, text}], victories [{siege, text}].
# Значений по умолчанию нет. sieges > 0 — текст победы нужен для каждой осады 1..sieges.
# Результат: {intro, entries [{id, siege, wave, text}] в порядке (осада, волна), end_wave, end_text, victories {осада: текст}};
# при ошибке push_error и пустой словарь.
static func load_story(path: String, sieges := 0) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: %s" % path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d == null:
		push_error("%s: битый JSON" % path)
		return {}
	if not d is Dictionary:
		push_error("%s: ожидается JSON-объект" % path)
		return {}
	if not d.get("intro") is String:
		push_error("%s: нет строкового поля intro" % path)
		return {}
	for key in ["entries", "endings", "victories"]:
		if not d.get(key) is Array:
			push_error("%s: нет массива %s" % [path, key])
			return {}
	var entries := []
	var ids := {}
	var places := {}
	for e in d.entries:
		if not e is Dictionary or not e.get("id") is String or e.id == "" or not _whole(e.get("siege")) or not _whole(e.get("wave")) \
				or e.siege < 1 or e.wave < 1 or not e.get("text") is String:
			push_error("%s: запись entries без строки id, целых siege и wave (не меньше 1) или строки text" % path)
			return {}
		var place := Vector2i(int(e.siege), int(e.wave))
		if ids.has(e.id) or e.id == INTRO_ID or places.has(place):
			push_error("%s: в entries повторяется id \"%s\" или пара (осада %d, волна %d)" % [path, e.id, place.x, place.y])
			return {}
		ids[e.id] = true
		places[place] = true
		entries.append({"id": e.id, "siege": place.x, "wave": place.y, "text": e.text})
	entries.sort_custom(func(a, b): return a.siege < b.siege or (a.siege == b.siege and a.wave < b.wave))
	var end_wave := PackedInt32Array()
	var end_text := PackedStringArray()
	for e in d.endings:
		if not e is Dictionary or not _whole(e.get("min_wave")) or not e.get("text") is String:
			push_error("%s: запись endings без целого min_wave или строки text" % path)
			return {}
		if end_wave.has(int(e.min_wave)):
			push_error("%s: в endings min_wave %d повторяется" % [path, int(e.min_wave)])
			return {}
		end_wave.append(int(e.min_wave))
		end_text.append(e.text)
	var has_zero := false
	for w in end_wave:
		has_zero = has_zero or w <= 0
	if not has_zero:
		push_error("%s: в endings нет концовки с min_wave 0" % path)
		return {}
	var victories := {}
	for e in d.victories:
		if not e is Dictionary or not _whole(e.get("siege")) or e.siege < 1 or not e.get("text") is String:
			push_error("%s: запись victories без целого siege (не меньше 1) или строки text" % path)
			return {}
		if victories.has(int(e.siege)):
			push_error("%s: в victories осада %d повторяется" % [path, int(e.siege)])
			return {}
		victories[int(e.siege)] = e.text
	for s in range(1, sieges + 1):
		if not victories.has(s):
			push_error("%s: в victories нет текста победы для осады %d" % [path, s])
			return {}
	return {"intro": d.intro, "entries": entries, "end_wave": end_wave, "end_text": end_text, "victories": victories}


# Состояние с нуля, затем конфиг, дневник и сохранение. Конфиг не загрузился — cfg_ok false, забег не начинается.
func _setup() -> void:
	run_index = 0
	save_locked = false
	save_warning = ""
	story = {}
	active_gifts = {}
	_clear_last_run()
	var cfg := load_run_cfg(run_path)
	cfg_ok = not cfg.is_empty()
	waves_per_run = cfg.waves_per_run if cfg_ok else 0
	siege_count = cfg.siege_count if cfg_ok else 0
	_clean_state()
	if not cfg_ok:
		return
	story = load_story(story_path, siege_count)
	_load_save()


# Чистое состояние: всё, что хранит сохранение.
func _clean_state() -> void:
	siege = 1
	unlocked_siege = 1
	last_siege = 1
	diary_seen = []
	completed = false
	runs_total = 0
	play_time = 0.0
	records = {}
	for s in range(1, siege_count + 1):
		records[s] = {"best_wave": 0, "wins": 0, "runs": 0}


func _clear_last_run() -> void:
	last_run = {"siege": 0, "result": "", "wave": 0, "kills": 0}


# Разбор сохранения: {} — не парсится, нет обязательных полей или версия меньше 1; {"newer": true} — версия больше нашей.
func _parse_save(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	var d: Dictionary = json.data
	if not _whole(d.get("version")) or d.version < 1:
		return {}
	if d.version > SAVE_VERSION:
		return {"newer": true}
	for key in ["unlocked_siege", "last_siege", "runs_total"]:
		if not _whole(d.get(key)) or d[key] < 0:
			return {}
	if not d.get("records") is Dictionary or not d.get("diary_seen") is Array or not d.get("completed") is bool:
		return {}
	var recs := {}
	for key in d.records:
		var r = d.records[key]
		if not str(key).is_valid_int() or not r is Dictionary:
			return {}
		for f in ["best_wave", "wins", "runs"]:
			if not _whole(r.get(f)) or r[f] < 0:
				return {}
		recs[int(str(key))] = {"best_wave": int(r.best_wave), "wins": int(r.wins), "runs": int(r.runs)}
	var seen := []
	for id in d.diary_seen:
		if not id is String:
			return {}
		if not seen.has(id):
			seen.append(id)
	# play_time появилось позже без смены version: в старых файлах поля нет — 0; не число или меньше 0 — тоже 0
	var pt = d.get("play_time")
	var secs: float = pt if (pt is float or pt is int) and pt >= 0 else 0.0
	return {"unlocked_siege": int(d.unlocked_siege), "last_siege": int(d.last_siege), "runs_total": int(d.runs_total),
		"records": recs, "diary_seen": seen, "completed": d.completed, "play_time": secs}


# Файла нет — чистое состояние. Повреждён — переименовать в save_corrupt_<unix>.json, чистое состояние, предупреждение.
# От более новой версии — файл не трогать и не перезаписывать, игра идёт в памяти.
func _load_save() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var d := _parse_save(FileAccess.get_file_as_string(save_path))
	if d.has("newer"):
		save_locked = true
		save_warning = WARN_NEWER
		push_warning("%s: %s, файл не перезаписывается" % [save_path, WARN_NEWER.to_lower()])
		return
	if d.is_empty():
		var moved := save_path.get_base_dir().path_join("save_corrupt_%d.json" % int(Time.get_unix_time_from_system()))
		var err := DirAccess.rename_absolute(save_path, moved)
		save_warning = WARN_CORRUPT
		push_warning("%s повреждён: %s, начато заново" % [save_path, "переименован в " + moved if err == OK else "переименовать не удалось"])
		return
	unlocked_siege = clampi(d.unlocked_siege, 1, siege_count)
	last_siege = clampi(d.last_siege, 1, unlocked_siege)
	siege = last_siege
	runs_total = d.runs_total
	diary_seen = d.diary_seen
	completed = d.completed
	play_time = d.play_time
	for s in d.records:
		if records.has(s):   # осады сверх siege_count в памяти не держатся
			records[s] = d.records[s]


# Запись атомарная: во временный файл рядом, затем переименование поверх. Возвращает, записано ли.
func save() -> bool:
	if save_locked or not cfg_ok:
		return false
	var recs := {}
	for s in records:
		recs[str(s)] = records[s]
	var text := JSON.stringify({"version": SAVE_VERSION, "unlocked_siege": unlocked_siege, "last_siege": last_siege, "records": recs,
		"diary_seen": diary_seen, "completed": completed, "runs_total": runs_total, "play_time": snappedf(play_time, 0.1)}, "\t")
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Не удалось записать сохранение в %s" % tmp)
		return false
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(tmp, save_path) != OK:
		push_warning("Не удалось переименовать %s в %s" % [tmp, save_path])
		DirAccess.remove_absolute(tmp)
		return false
	return true


# Номер осады римскими цифрами: «Осада II».
static func roman(n: int) -> String:
	var out := ""
	var vals := [10, 9, 5, 4, 1]
	var syms := ["X", "IX", "V", "IV", "I"]
	for k in vals.size():
		while n >= vals[k]:
			out += syms[k]
			n -= vals[k]
	return out


func siege_name(s: int) -> String:
	return "Осада %s" % roman(s)


func diary_read(id: String) -> bool:
	return diary_seen.has(id)


# Запись дневника (или INTRO_ID) показана: отметить прочитанной и сохранить.
func mark_diary(id: String) -> void:
	if diary_seen.has(id):
		return
	diary_seen.append(id)
	save()


# Новый забег с первой волны: сцена боя создаётся заново.
func start_run(s: int) -> void:
	if not cfg_ok:
		push_error("Забег не начат: %s не загружен" % run_path)
		return
	siege = clampi(s, 1, siege_count)
	last_siege = siege
	run_index += 1
	_clear_last_run()
	get_tree().change_scene_to_file(MAIN_SCENE)


# Итог забега: result "win" или "loss", wave — волна, на которой он кончился, kills — убито зомби за забег.
# Победа на последней осаде в первый раз ставит completed. Итог сразу сохраняется.
func end_run(result: String, wave: int, kills: int) -> void:
	if not records.has(siege):
		push_error("Нет рекордов осады %d" % siege)
		return
	var r: Dictionary = records[siege]
	r.runs += 1
	r.best_wave = maxi(r.best_wave, wave)
	runs_total += 1
	if result == "win":
		r.wins += 1
		unlocked_siege = mini(siege_count, maxi(unlocked_siege, siege + 1))
		if siege == siege_count:
			completed = true
	last_run = {"siege": siege, "result": result, "wave": wave, "kills": kills}
	save()


func go_hub() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)


func go_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# Кнопка «Выход»: сохранить и закрыть игру.
func quit_game() -> void:
	save()
	get_tree().quit()
