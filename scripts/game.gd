extends Node
# Каркас забега: какая осада идёт, что открыто, рекорды и итог последнего забега. Автозагрузка с именем Game.
# Состояние живёт, только пока работает процесс: на диск ничего не пишется.
const RUN_PATH := "res://data/run.json"
const MAIN_SCENE := "res://scenes/main.tscn"
const HUB_SCENE := "res://scenes/hub.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

var run_path := RUN_PATH       # тесты подменяют и вызывают _setup
var cfg_ok := false            # run.json загрузился; иначе забег не начать
var waves_per_run := 0
var siege_count := 0
var siege := 1                 # текущая осада, 1..siege_count
var unlocked_siege := 1        # до какой осады открыто
var records := {}              # осада -> {best_wave, wins, runs}
var last_run := {}             # {siege, result "win" / "loss" / "", wave, kills}; result "" — забега ещё не было
var run_index := 0             # сколько забегов начато


func _ready() -> void:
	_setup()


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


# Сброс состояния к началу процесса. Конфиг не загрузился — cfg_ok false, забег не начинается.
func _setup() -> void:
	siege = 1
	unlocked_siege = 1
	run_index = 0
	records = {}
	_clear_last_run()
	var cfg := load_run_cfg(run_path)
	cfg_ok = not cfg.is_empty()
	if not cfg_ok:
		waves_per_run = 0
		siege_count = 0
		return
	waves_per_run = cfg.waves_per_run
	siege_count = cfg.siege_count
	for s in range(1, siege_count + 1):
		records[s] = {"best_wave": 0, "wins": 0, "runs": 0}


func _clear_last_run() -> void:
	last_run = {"siege": 0, "result": "", "wave": 0, "kills": 0}


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


# Новый забег с первой волны: сцена боя создаётся заново.
func start_run(s: int) -> void:
	if not cfg_ok:
		push_error("Забег не начат: %s не загружен" % run_path)
		return
	siege = clampi(s, 1, siege_count)
	run_index += 1
	_clear_last_run()
	get_tree().change_scene_to_file(MAIN_SCENE)


# Итог забега: result "win" или "loss", wave — волна, на которой он кончился, kills — убито зомби за забег.
func end_run(result: String, wave: int, kills: int) -> void:
	if not records.has(siege):
		push_error("Нет рекордов осады %d" % siege)
		return
	var r: Dictionary = records[siege]
	r.runs += 1
	r.best_wave = maxi(r.best_wave, wave)
	if result == "win":
		r.wins += 1
		unlocked_siege = mini(siege_count, maxi(unlocked_siege, siege + 1))
	last_run = {"siege": siege, "result": result, "wave": wave, "kills": kills}


func go_hub() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)


func go_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
