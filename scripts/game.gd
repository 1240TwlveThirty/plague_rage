extends Node
# Каркас забега: какая осада идёт, что открыто, рекорды, прочитанный дневник, время игры и итог последнего забега.
# Автозагрузка с именем Game. Состояние между запусками хранится в save_path (user://save.json).
const RUN_PATH := "res://data/run.json"
const STORY_PATH := "res://data/story.json"
const RADIANCE_PATH := "res://data/radiance.json"
const GIFTS_PATH := "res://data/gifts.json"
const MODS := preload("res://scripts/mods.gd")   # общий загрузчик gifts.json
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const MAIN_SCENE := "res://scenes/main.tscn"
const HUB_SCENE := "res://scenes/hub.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const INTRO_ID := "intro"      # id вступления в diary_seen
const WARN_CORRUPT := "Сохранение повреждено, начато заново"
const WARN_NEWER := "Сохранение от более новой версии"
const BLOCK_MAX := "Максимальный уровень"
const BLOCK_SIEGE := "Откроется после осады %s"
const BLOCK_RADIANCE := "Не хватает Сияния"
const BLOCK_DATA := "Нет данных о цене"

var run_path := RUN_PATH       # тесты подменяют и вызывают _setup
var story_path := STORY_PATH   # тесты подменяют
var save_path := SAVE_PATH     # тесты подменяют: настоящее сохранение они не трогают
var radiance_path := RADIANCE_PATH   # тесты подменяют
var gifts_path := GIFTS_PATH   # тесты подменяют
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
var play_time := 0.0           # секунд игры за всё время: идёт, пока игра запущена (меню, хаб, бой, пауза боя по P); в меню паузы по Esc стоит (дерево на паузе)
var last_run := {}             # {siege, result "win" / "loss" / "", wave, kills, radiance}; result "" — забега ещё не было
var run_index := 0             # сколько забегов начато за этот запуск
var save_locked := false       # сохранение от более новой версии: файл не перезаписывается, игра идёт в памяти
var save_warning := ""         # строка-предупреждение для хаба или ""
var story := {}                # дневник для хаба (load_story) или {} при ошибке
var active_gifts := {}         # дары забега, id -> уровень: start_run собирает из gift_levels (или из --gifts), сцена боя читает при старте; в сохранение не пишется
var radiance := 0              # Сияние: валюта меты, начисляется в конце забега, тратится в магазине даров
var gift_levels := {}          # id дара -> купленный уровень, 0 — не куплен
var gift_defs := {}            # дары из gifts.json (MODS.load_gifts) или {} при ошибке
var radiance_cfg := {}         # radiance.json (load_radiance_cfg) или {} при ошибке: тогда наград и покупок нет
var gifts_override = null      # набор из параметра --gifts (id -> уровень) или null: заменяет купленные дары в start_run


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


# radiance.json: wave_base, wave_step, win_bonus — целые не меньше 0; gift_prices — непустой массив целых не меньше 1 (цена уровня n — gift_prices[n - 1]).
# Значений по умолчанию нет. При ошибке push_error и пустой словарь.
static func load_radiance_cfg(path: String) -> Dictionary:
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
	for key in ["wave_base", "wave_step", "win_bonus"]:
		if not _whole(d.get(key)) or d[key] < 0:
			push_error("%s: нет целого поля %s (не меньше 0)" % [path, key])
			return {}
	var prices := PackedInt32Array()
	if d.get("gift_prices") is Array:
		for v in d.gift_prices:
			if not _whole(v) or v < 1:
				prices.clear()
				break
			prices.append(int(v))
	if prices.is_empty():
		push_error("%s: нет непустого массива gift_prices из целых (не меньше 1)" % path)
		return {}
	return {"wave_base": int(d.wave_base), "wave_step": int(d.wave_step), "win_bonus": int(d.win_bonus), "gift_prices": prices}


# Параметр «--gifts id:уровень,id:уровень» среди аргументов после «--»: словарь id -> уровень; параметра нет — null.
# «--gifts» без значения или с пустой строкой — пустой набор (забег без даров, что бы ни было куплено).
static func parse_gifts_arg(args: PackedStringArray) -> Variant:
	var at := args.find("--gifts")
	if at < 0:
		return null
	var out := {}
	if at + 1 < args.size():
		for part in args[at + 1].split(",", false):
			out[part.get_slice(":", 0)] = int(part.get_slice(":", 1))
	return out


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
	radiance_cfg = load_radiance_cfg(radiance_path)
	gift_defs = MODS.load_gifts(gifts_path)
	gifts_override = parse_gifts_arg(OS.get_cmdline_user_args())
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
	radiance = 0
	gift_levels = {}
	for id in gift_defs:
		gift_levels[id] = 0
	records = {}
	for s in range(1, siege_count + 1):
		records[s] = {"best_wave": 0, "wins": 0, "runs": 0}


func _clear_last_run() -> void:
	last_run = {"siege": 0, "result": "", "wave": 0, "kills": 0, "radiance": 0}


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
	# radiance и gift_levels — так же: нет поля или оно не того вида — 0 и пустой словарь; в gift_levels берутся только целые уровни не меньше 0
	var rad = d.get("radiance")
	var levels := {}
	if d.get("gift_levels") is Dictionary:
		for id in d.gift_levels:
			if _whole(d.gift_levels[id]) and d.gift_levels[id] >= 0:
				levels[str(id)] = int(d.gift_levels[id])
	return {"unlocked_siege": int(d.unlocked_siege), "last_siege": int(d.last_siege), "runs_total": int(d.runs_total),
		"records": recs, "diary_seen": seen, "completed": d.completed, "play_time": secs,
		"radiance": int(rad) if _whole(rad) and rad >= 0 else 0, "gift_levels": levels}


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
	radiance = d.radiance
	for id in d.gift_levels:
		if gift_defs.has(id):   # даров, которых нет в gifts.json, в памяти нет; уровень не выше числа уровней дара
			gift_levels[id] = mini(d.gift_levels[id], gift_defs[id].levels.size())
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
		"diary_seen": diary_seen, "completed": completed, "runs_total": runs_total, "play_time": snappedf(play_time, 0.1),
		"radiance": radiance, "gift_levels": gift_levels}, "\t")
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


# Сколько осад пройдено подряд с первой (у осады есть победа): поле не хранится, считается по рекордам.
func sieges_cleared() -> int:
	var n := 0
	while records.has(n + 1) and records[n + 1].wins > 0:
		n += 1
	return n


# Сияние за забег: за каждую пройденную волну w — wave_base + wave_step * w, за победу ещё win_bonus.
# wave — волна, на которой забег кончился: при поражении она не пройдена.
func run_reward(result: String, wave: int) -> int:
	if radiance_cfg.is_empty():
		return 0
	var passed := wave if result == "win" else wave - 1
	var sum := 0
	for w in range(1, passed + 1):
		sum += radiance_cfg.wave_base + radiance_cfg.wave_step * w
	return sum + (radiance_cfg.win_bonus if result == "win" else 0)


# Цена уровня дара (1..число уровней): prices дара или gift_prices из radiance.json; цены нет — -1.
func gift_price(id: String, level: int) -> int:
	if not gift_defs.has(id) or level < 1 or level > gift_defs[id].levels.size():
		return -1
	var own: PackedInt32Array = gift_defs[id].prices
	if not own.is_empty():
		return own[level - 1]
	if radiance_cfg.is_empty() or level > radiance_cfg.gift_prices.size():
		return -1
	return radiance_cfg.gift_prices[level - 1]


# Почему следующий уровень дара купить нельзя; пустая строка — можно.
func buy_block(id: String) -> String:
	if not gift_defs.has(id):
		return BLOCK_DATA
	var next: int = gift_levels.get(id, 0) + 1
	if next > gift_defs[id].levels.size():
		return BLOCK_MAX
	var price := gift_price(id, next)
	if price < 0:
		return BLOCK_DATA
	var req: int = gift_defs[id].req_sieges[next - 1]
	if sieges_cleared() < req:
		return BLOCK_SIEGE % roman(req)
	if radiance < price:
		return BLOCK_RADIANCE
	return ""


# Купить следующий уровень дара: списать Сияние, поднять уровень, сохранить. Нельзя — false, ничего не меняется.
func buy_gift(id: String) -> bool:
	if buy_block(id) != "":
		return false
	var next: int = gift_levels.get(id, 0) + 1
	radiance -= gift_price(id, next)
	gift_levels[id] = next
	save()
	return true


# Купленные дары: id -> уровень, только уровни от 1.
func owned_gifts() -> Dictionary:
	var out := {}
	for id in gift_levels:
		if gift_levels[id] > 0:
			out[id] = gift_levels[id]
	return out


# Новый забег с первой волны: сцена боя создаётся заново. Действуют все купленные дары; параметр --gifts их заменяет.
func start_run(s: int) -> void:
	if not cfg_ok:
		push_error("Забег не начат: %s не загружен" % run_path)
		return
	siege = clampi(s, 1, siege_count)
	last_siege = siege
	run_index += 1
	active_gifts = owned_gifts() if gifts_override == null else gifts_override.duplicate()
	_clear_last_run()
	get_tree().change_scene_to_file(MAIN_SCENE)


# Итог забега: result "win" или "loss", wave — волна, на которой он кончился, kills — убито зомби за забег.
# Победа на последней осаде в первый раз ставит completed. Сияние за забег начисляется здесь же (last_run.radiance). Итог сразу сохраняется.
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
	var earned := run_reward(result, wave)
	radiance += earned
	last_run = {"siege": siege, "result": result, "wave": wave, "kills": kills, "radiance": earned}
	save()


func go_hub() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)


func go_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# Кнопка «Выход»: сохранить и закрыть игру.
func quit_game() -> void:
	save()
	get_tree().quit()
