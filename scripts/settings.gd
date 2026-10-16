extends Node
# Настройки игрока — автозагрузка Settings, единственное место, где они хранятся. Файл user://settings.cfg (ConfigFile):
# загружается и применяется при старте, сохраняется при каждом изменении. F11 в любой момент переключает полный экран.
# Под тестовым скриптом (-s bench/...) файл игрока не читается и не пишется: тесты идут на значениях по умолчанию,
# а свои настройки проверяют, подменив path и вызвав load_settings.
signal changed(key: String)   # «display/fullscreen», «input» и т. п.: экраны настроек обновляют вид

const PATH := "user://settings.cfg"
const WINDOW_SIZE := Vector2i(1920, 1080)       # окно по умолчанию
const WINDOW_SIZE_SMALL := Vector2i(1280, 720)  # если экран меньше WINDOW_SIZE
const LANGUAGES := ["ru", "en"]

var path := PATH
var persist := true            # false — не писать файл (тестовый запуск)
var fullscreen := false        # display/fullscreen: безрамочный полноэкранный режим
var language := "ru"           # general/language: "ru" или "en"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # F11 и на паузе
	persist = get_tree().get_script() == null   # обычный запуск игры, не тестовый SceneTree
	if persist:
		load_settings()
		_apply_window(true)   # тестовое окно не трогать: размер задают тесты и проект
	else:
		language = "ru"       # тесты сверяют русские строки
	TranslationServer.set_locale(language)


# Прочитать файл и применить; нет файла или он битый — значения по умолчанию.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path) and cfg.load(path) != OK:
		push_warning("%s не читается: настройки по умолчанию" % path)
		cfg = ConfigFile.new()
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	language = str(cfg.get_value("general", "language", default_language()))
	if not language in LANGUAGES:
		language = default_language()
	TranslationServer.set_locale(language)
	_load_keys(cfg)


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("general", "language", language)
	_save_keys(cfg)
	if cfg.save(path) != OK:
		push_warning("Не удалось сохранить настройки в %s" % path)


func set_fullscreen(on: bool) -> void:
	if on == fullscreen:
		return
	fullscreen = on
	_apply_window(false)
	save_settings()
	changed.emit("display/fullscreen")


# Язык по умолчанию: русский, если язык системы русский, иначе английский.
static func default_language() -> String:
	return "ru" if OS.get_locale_language() == "ru" else "en"


# Сменить язык сразу: TranslationServer.set_locale, метки интерфейса переводятся сами (NOTIFICATION_TRANSLATION_CHANGED).
func set_language(l: String) -> void:
	if not l in LANGUAGES or l == language:
		return
	language = l
	TranslationServer.set_locale(l)
	save_settings()
	changed.emit("general/language")


func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)


# Полный экран — WINDOW_MODE_FULLSCREEN (безрамочный); окно — 1920x1080 или 1280x720 на маленьком экране, по центру.
# Без экрана (--headless) окна нет: ничего не делать.
func _apply_window(first: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var was_full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if first or was_full:
		var scr := DisplayServer.window_get_current_screen()
		var full := DisplayServer.screen_get_size(scr)
		var size := WINDOW_SIZE if full.x >= WINDOW_SIZE.x and full.y >= WINDOW_SIZE.y else WINDOW_SIZE_SMALL
		var area := DisplayServer.screen_get_usable_rect(scr)
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(area.position + (area.size - size).maxi(0) / 2)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


# --- Клавиши: действия InputMap (по умолчанию — секция [input] project.godot), переназначаемые хранятся в [input] файла ---

# Переназначаемые действия в порядке списка на вкладке «Управление» (подпись — action_title).
const REBINDABLE := ["squad_select_1", "squad_select_2", "squad_select_3", "squad_select_4", "squad_select_5", "squad_select_6",
	"squad_select_7", "squad_select_8", "squad_new", "squad_split", "squad_merge", "split_side", "wave_start", "buy_1", "buy_2",
	"buy_3", "buy_4"]
# Остальные действия игры: клавиши фиксированы (их нельзя занять переназначением).
const FIXED_ACTIONS := ["order_attack", "order_hold", "order_retreat", "about_face", "banner_toggle", "auto_width", "pause",
	"post_left", "post_top", "post_right", "post_back", "select_all", "to_hub", "debug_restart"]
# Не назначаются никогда: Esc, F1–F12, модификаторы (Shift добавляет к выбору).
const RESERVED_KEYS := [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]


# Клавиша действия для подсказок: «Z», «Space», «Ctrl+A»; нет действия или клавиши — «—». Работает и без автозагрузки
# (бенчи без дерева): читает InputMap.
static func key_label(action: String) -> String:
	var k := action_key_event(action)
	return "—" if k == null else OS.get_keycode_string(k.get_keycode_with_modifiers())


static func action_key_event(action: String) -> InputEventKey:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).keycode != KEY_NONE:
			return e
	return null


static func action_key(action: String) -> Key:
	var k := action_key_event(action)
	return KEY_NONE if k == null else k.keycode


# Подпись действия на текущем языке: ACTION_<ИМЯ>, у squad_select_N — ACTION_SQUAD_SELECT с номером.
static func action_title(action: String) -> String:
	if action.begins_with("squad_select_"):
		return String(TranslationServer.translate("ACTION_SQUAD_SELECT")) % int(action.trim_prefix("squad_select_"))
	return String(TranslationServer.translate("ACTION_" + action.to_upper()))


static func _set_key(action: String, code: Key) -> void:
	InputMap.action_erase_events(action)
	if code != KEY_NONE:
		var e := InputEventKey.new()
		e.keycode = code
		InputMap.action_add_event(action, e)


# Занята ли клавиша фиксированным действием (без модификаторов: Ctrl+A не занимает A).
static func _fixed_owner(code: Key) -> String:
	for a in FIXED_ACTIONS:
		if InputMap.has_action(a):
			for e in InputMap.action_get_events(a):
				if e is InputEventKey and e.keycode == code and not (e.ctrl_pressed or e.alt_pressed or e.shift_pressed or e.meta_pressed):
					return a
	return ""


# Назначить клавишу переназначаемому действию. Занята другим переназначаемым — клавиши меняются местами.
# Результат: {ok, msg} — msg для показа игроку (пусто, если сказать нечего).
func rebind(action: String, code: Key) -> Dictionary:
	if not action in REBINDABLE:
		return {"ok": false, "msg": tr("MSG_KEY_NOT_REBINDABLE") % action}
	if code in RESERVED_KEYS or code == KEY_NONE:
		return {"ok": false, "msg": tr("MSG_KEY_RESERVED") % OS.get_keycode_string(code)}
	var fixed := _fixed_owner(code)
	if fixed != "":
		return {"ok": false, "msg": tr("MSG_KEY_FIXED") % OS.get_keycode_string(code)}
	var old := action_key(action)
	if old == code:
		return {"ok": true, "msg": ""}
	var msg := ""
	for r in REBINDABLE:
		if r != action and action_key(r) == code:
			_set_key(r, old)
			msg = tr("MSG_KEY_SWAPPED") % [OS.get_keycode_string(code), action_title(r)]
	_set_key(action, code)
	save_settings()
	changed.emit("input")
	return {"ok": true, "msg": msg}


# Клавиши по умолчанию (секция [input] project.godot).
func reset_keys() -> void:
	InputMap.load_from_project_settings()
	save_settings()
	changed.emit("input")


func _load_keys(cfg: ConfigFile) -> void:
	InputMap.load_from_project_settings()
	for r in REBINDABLE:
		var v = cfg.get_value("input", r, "")
		if not v is String or v == "":
			continue
		var code := OS.find_keycode_from_string(v)
		if code == KEY_NONE or code in RESERVED_KEYS or _fixed_owner(code) != "":
			push_warning("%s: клавиша «%s» для %s не подходит, оставлена по умолчанию" % [path, v, r])
			continue
		_set_key(r, code)


func _save_keys(cfg: ConfigFile) -> void:
	for r in REBINDABLE:
		cfg.set_value("input", r, OS.get_keycode_string(action_key(r)))
