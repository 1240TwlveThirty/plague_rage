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
const AUDIO := preload("res://scripts/audio.gd")   # шины Music и SFX
const FONTS := preload("res://scripts/fonts.gd")   # вариант шрифта (data/ui_theme.json, --font=...), задача 20
const VOLUME_DEFAULT := 0.8

var path := PATH
var persist := true            # false — не писать файл (тестовый запуск)
var fullscreen := false        # display/fullscreen: безрамочный полноэкранный режим
# display/screen_shake_level: тряска экрана при ударе героя (задача 23) — SHAKE_OFF..SHAKE_STRONG; множители амплитуды —
# data/fx.json shake_levels. Прежний ключ display/screen_shake (вкл/выкл) читается, если нового нет. screen_shake — вкл/выкл
# поверх уровня (тесты и старый код): выключить — уровень 0, включить — «обычная», если была выключена.
const SHAKE_OFF := 0
const SHAKE_NORMAL := 2
const SHAKE_LEVELS := ["UI_SHAKE_OFF", "UI_SHAKE_WEAK", "UI_SHAKE_NORMAL", "UI_SHAKE_STRONG"]
const GORE_LEVELS := ["UI_GORE_OFF", "UI_GORE_NORMAL"]   # gameplay/gore: 0 — без крови и кусков (искры, пыль, серые пятна), 1 — обычная
var screen_shake_level := SHAKE_NORMAL
var screen_shake: bool:
	get:
		return screen_shake_level > SHAKE_OFF
	set(on):
		if on != (screen_shake_level > SHAKE_OFF):
			screen_shake_level = SHAKE_NORMAL if on else SHAKE_OFF
var gore := 1
# display/card_pick_anim (задача 25): анимация выбора карточки — 0 выкл, 1 короткая, 2 полная (по умолчанию)
const CARD_ANIM_LEVELS := ["UI_CARD_ANIM_OFF", "UI_CARD_ANIM_SHORT", "UI_CARD_ANIM_FULL"]
var card_pick_anim := 2
var show_arrows := true            # display/show_arrows: видимые стрелы лучников (задача 29); выкл — для слабых машин
var squad_panel_expanded := true   # ui/squad_panel_expanded: панель отрядов развёрнута (задача 24)
var hints_enabled := true          # hints/enabled: подсказки первой минуты (задача 26)
var hints_seen: Array = []         # hints/seen: id показанных подсказок (каждая — один раз)
var language := "ru"           # general/language: "ru" или "en"
var music_volume := VOLUME_DEFAULT   # audio/music: линейная громкость шины Music, 0..1
var sfx_volume := VOLUME_DEFAULT     # audio/sfx: шины SFX


func _ready() -> void:
	FONTS.apply_project()   # пиксельный шрифт — до первых экранов
	process_mode = Node.PROCESS_MODE_ALWAYS   # F11 и на паузе
	ensure_code_actions()
	persist = get_tree().get_script() == null   # обычный запуск игры, не тестовый SceneTree
	if persist:
		load_settings()
		_apply_window(true)   # тестовое окно не трогать: размер задают тесты и проект
	else:
		language = "ru"       # тесты сверяют русские строки
		AudioServer.set_bus_mute(0, true)   # тесты без звука в колонках (плееры при этом играют)
	TranslationServer.set_locale(language)
	_apply_audio()


# Прочитать файл и применить; нет файла или он битый — значения по умолчанию.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path) and cfg.load(path) != OK:
		push_warning("%s не читается: настройки по умолчанию" % path)
		cfg = ConfigFile.new()
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	var old_shake := bool(cfg.get_value("display", "screen_shake", true))
	screen_shake_level = clampi(int(cfg.get_value("display", "screen_shake_level", SHAKE_NORMAL if old_shake else SHAKE_OFF)), 0, SHAKE_LEVELS.size() - 1)
	gore = clampi(int(cfg.get_value("gameplay", "gore", 1)), 0, GORE_LEVELS.size() - 1)
	card_pick_anim = clampi(int(cfg.get_value("display", "card_pick_anim", 2)), 0, CARD_ANIM_LEVELS.size() - 1)
	show_arrows = bool(cfg.get_value("display", "show_arrows", true))
	squad_panel_expanded = bool(cfg.get_value("ui", "squad_panel_expanded", true))
	hints_enabled = bool(cfg.get_value("hints", "enabled", true))
	var hs = cfg.get_value("hints", "seen", [])
	hints_seen = Array(hs).map(func(x): return str(x)) if (hs is Array or hs is PackedStringArray) else []
	language = str(cfg.get_value("general", "language", default_language()))
	if not language in LANGUAGES:
		language = default_language()
	TranslationServer.set_locale(language)
	music_volume = clampf(float(cfg.get_value("audio", "music", VOLUME_DEFAULT)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", VOLUME_DEFAULT)), 0.0, 1.0)
	_apply_audio()
	_load_keys(cfg)


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "screen_shake", screen_shake)   # прежний ключ — для старых сборок
	cfg.set_value("display", "screen_shake_level", screen_shake_level)
	cfg.set_value("gameplay", "gore", gore)
	cfg.set_value("display", "card_pick_anim", card_pick_anim)
	cfg.set_value("display", "show_arrows", show_arrows)
	cfg.set_value("ui", "squad_panel_expanded", squad_panel_expanded)
	cfg.set_value("hints", "enabled", hints_enabled)
	cfg.set_value("hints", "seen", hints_seen)
	cfg.set_value("general", "language", language)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
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


func set_screen_shake(on: bool) -> void:
	if on == screen_shake:
		return
	screen_shake = on
	save_settings()
	changed.emit("display/screen_shake")


func set_screen_shake_level(level: int) -> void:
	level = clampi(level, 0, SHAKE_LEVELS.size() - 1)
	if level == screen_shake_level:
		return
	screen_shake_level = level
	save_settings()
	changed.emit("display/screen_shake")


# Панель отрядов в бою: развёрнутая (строки, действия, Клич) или свёрнутая (квадратики и числа живых); сохраняется.
func set_squad_panel_expanded(on: bool) -> void:
	if on == squad_panel_expanded:
		return
	squad_panel_expanded = on
	save_settings()
	changed.emit("ui/squad_panel_expanded")


# Подсказки первой минуты (задача 26): вкл/выкл, отметка показанной, сброс (все покажутся снова).
func set_hints_enabled(on: bool) -> void:
	if on == hints_enabled:
		return
	hints_enabled = on
	save_settings()
	changed.emit("hints/enabled")


func mark_hint_seen(id: String) -> void:
	if id in hints_seen:
		return
	hints_seen.append(id)
	save_settings()


func reset_hints() -> void:
	hints_seen = []
	save_settings()
	changed.emit("hints/seen")


func set_card_pick_anim(level: int) -> void:
	level = clampi(level, 0, CARD_ANIM_LEVELS.size() - 1)
	if level == card_pick_anim:
		return
	card_pick_anim = level
	save_settings()
	changed.emit("display/card_pick_anim")


func set_show_arrows(on: bool) -> void:
	if on == show_arrows:
		return
	show_arrows = on
	save_settings()
	changed.emit("display/show_arrows")


func set_gore(level: int) -> void:
	level = clampi(level, 0, GORE_LEVELS.size() - 1)
	if level == gore:
		return
	gore = level
	save_settings()
	changed.emit("gameplay/gore")


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


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save_settings()
	changed.emit("audio/music")


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_audio()
	save_settings()
	changed.emit("audio/sfx")


# Линейная громкость 0..1 -> dB шины; 0 — шина выключена.
func _apply_audio() -> void:
	AUDIO.ensure_buses()
	for pair in [["Music", music_volume], ["SFX", sfx_volume]]:
		var idx := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(pair[1], 0.0001)))
		AudioServer.set_bus_mute(idx, pair[1] <= 0.0)


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
	"buy_3", "buy_4", "buy_spear", "war_cry", "move_up", "move_down", "move_left", "move_right", "hero_attack", "shop_toggle",
	"squad_panel_toggle", "camera_zoom_reset"]
# Действия, которых нет в [input] project.godot: клавиша по умолчанию задаётся здесь, действие добавляется после каждой загрузки InputMap
# (war_cry — «Клич Благодати»: с задачи 10 U, D занята движением героя; move_* — движение героя WASD, задача 10; hero_attack — удар
# героя J, задача 11).
const CODE_DEFAULTS := {"war_cry": KEY_U, "buy_spear": KEY_B, "move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "hero_attack": KEY_J}   # buy_spear — пакет копейщиков (B свободна)
# Фиксированные действия, чья клавиша из [input] project.godot заменяется кодом после каждой загрузки InputMap (задача 10:
# W занята героем — «Держать» на Y). project.godot не меняется.
const CODE_REMAP := {"order_hold": KEY_Y}
# Клавиша по умолчанию до задачи 10: в старом файле настроек (без move_up) такое значение считается старым умолчанием и не грузится.
const OLD_DEFAULTS := {"war_cry": "D"}
# Остальные действия игры: клавиши фиксированы (их нельзя занять переназначением).
const FIXED_ACTIONS := ["order_attack", "order_hold", "order_retreat", "about_face", "banner_toggle", "auto_width", "pause",
	"post_left", "post_top", "post_right", "post_back", "select_all", "to_hub", "debug_restart"]
# Не назначаются никогда: Esc, F1–F12, модификаторы (Shift добавляет к выбору).
const RESERVED_KEYS := [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]


# Кнопки мыши, которые можно назначить переназначаемому действию: боковые (4, 5). ЛКМ (выбор), ПКМ (приказ), колесо
# (зум, с Shift — поворот) и средняя (зажатое колесо — перетаскивание камеры, задача 28; раньше назначалась) заняты.
# Подписи — ключи перевода (MOUSE_LABELS: и для занятых, в подсказках).
const MOUSE_BINDABLE := {MOUSE_BUTTON_XBUTTON1: "UI_MOUSE_X1", MOUSE_BUTTON_XBUTTON2: "UI_MOUSE_X2"}
const MOUSE_LABELS := {MOUSE_BUTTON_MIDDLE: "UI_MOUSE_MIDDLE", MOUSE_BUTTON_XBUTTON1: "UI_MOUSE_X1", MOUSE_BUTTON_XBUTTON2: "UI_MOUSE_X2"}
const MOUSE_TOKEN := "Mouse"   # в файле настроек кнопка мыши — «Mouse8» (номер кнопки Godot)


# Переназначаемые действия, которых нет на вкладке «Управление»: движение и удар героя, если он выключен в data/hero.json; покупка выключенного в данных товара (buy_spear — копейщики в v1:
# shop.json spear_pack или unit_types.json spearman с enabled: false). Действие остаётся в InputMap, но ничего не покупает.
static func hidden_actions() -> Array:
	var shop = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop.json"))
	var types = JSON.parse_string(FileAccess.get_file_as_string("res://data/unit_types.json"))
	var on: bool = shop is Dictionary and shop.get("spear_pack", {}).get("enabled", true)
	if on and types is Array:
		for e in types:
			if e is Dictionary and e.get("name") == "spearman":
				on = e.get("enabled", true)
	var out := [] if on else ["buy_spear"]
	var hero = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	if not (hero is Dictionary and hero.get("enabled", false) == true):   # герой выключен в данных: клавиш движения нет на вкладке
		out.append_array(["move_up", "move_down", "move_left", "move_right", "hero_attack"])
	return out


# Клавиша или кнопка мыши действия для подсказок: «Z», «Space», «Ctrl+A», «Мышь 4»; нет действия или привязки — «—».
# Работает и без автозагрузки (бенчи без дерева): читает InputMap.
static func key_label(action: String) -> String:
	return event_label(action_event(action))


static func event_label(e: InputEvent) -> String:
	if e is InputEventKey:
		return OS.get_keycode_string((e as InputEventKey).get_keycode_with_modifiers())
	if e is InputEventMouseButton:
		var b: int = (e as InputEventMouseButton).button_index
		return String(TranslationServer.translate(MOUSE_LABELS[b])) if MOUSE_LABELS.has(b) else "%s %d" % [MOUSE_TOKEN, b]
	return "—"


# Привязка действия: первая клавиша или кнопка мыши; нет — null.
static func action_event(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if (e is InputEventKey and (e as InputEventKey).keycode != KEY_NONE) or e is InputEventMouseButton:
			return e
	return null


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.keycode == b.keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false


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
	_set_event(action, _key_event(code) if code != KEY_NONE else null)


static func _key_event(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e


static func _mouse_event(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


# Единственная привязка действия: копия e без модификаторов и состояния нажатия; null — без привязки.
static func _set_event(action: String, e: InputEvent) -> void:
	InputMap.action_erase_events(action)
	if e is InputEventKey:
		InputMap.action_add_event(action, _key_event(e.keycode))
	elif e is InputEventMouseButton:
		InputMap.action_add_event(action, _mouse_event(e.button_index))


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
	return rebind_event(action, _key_event(code))


# То же для клавиши (InputEventKey) или кнопки мыши (InputEventMouseButton, только MOUSE_BINDABLE).
func rebind_event(action: String, e: InputEvent) -> Dictionary:
	if not action in REBINDABLE:
		return {"ok": false, "msg": tr("MSG_KEY_NOT_REBINDABLE") % action}
	if e is InputEventKey:
		var code: Key = e.keycode
		if code in RESERVED_KEYS or code == KEY_NONE:
			return {"ok": false, "msg": tr("MSG_KEY_RESERVED") % OS.get_keycode_string(code)}
		if _fixed_owner(code) != "":
			return {"ok": false, "msg": tr("MSG_KEY_FIXED") % OS.get_keycode_string(code)}
	elif not (e is InputEventMouseButton and MOUSE_BINDABLE.has(e.button_index)):
		return {"ok": false, "msg": tr("MSG_KEY_RESERVED") % event_label(e)}
	var old := action_event(action)
	if _same(old, e):
		return {"ok": true, "msg": ""}
	var msg := ""
	for r in REBINDABLE:
		if r != action and _same(action_event(r), e):
			_set_event(r, old)
			if not r in hidden_actions():   # скрытое действие молча забирает старую клавишу
				msg = tr("MSG_KEY_SWAPPED") % [event_label(e), action_title(r)]
	_set_event(action, e)
	save_settings()
	changed.emit("input")
	return {"ok": true, "msg": msg}


# Клавиши по умолчанию (секция [input] project.godot).
func reset_keys() -> void:
	InputMap.load_from_project_settings()
	ensure_code_actions()
	save_settings()
	changed.emit("input")


func _load_keys(cfg: ConfigFile) -> void:
	InputMap.load_from_project_settings()
	ensure_code_actions()
	var old_file := not cfg.has_section_key("input", "move_up")   # файл до задачи 10
	for r in REBINDABLE:
		var v = cfg.get_value("input", r, "")
		if not v is String or v == "":
			continue
		if old_file and OLD_DEFAULTS.get(r, "") == v:
			continue   # Клич на D — прежнее умолчание; теперь D — движение героя вправо, Клич на U
		if v.begins_with(MOUSE_TOKEN):
			var b: int = v.trim_prefix(MOUSE_TOKEN).to_int()
			if not MOUSE_BINDABLE.has(b):
				push_warning("%s: кнопка мыши «%s» для %s не подходит, оставлена по умолчанию" % [path, v, r])
				continue
			_set_event(r, _mouse_event(b))
			continue
		var code := OS.find_keycode_from_string(v)
		if code == KEY_NONE or code in RESERVED_KEYS or _fixed_owner(code) != "":
			push_warning("%s: клавиша «%s» для %s не подходит, оставлена по умолчанию" % [path, v, r])
			continue
		_set_key(r, code)


# Действия CODE_DEFAULTS с клавишей по умолчанию, если их ещё нет в InputMap. Работает и без автозагрузки (бенчи).
static func ensure_code_actions() -> void:
	for a in CODE_DEFAULTS:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			_set_key(a, CODE_DEFAULTS[a])
	var dk := data_keys()
	for a in dk:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			_set_key(a, dk[a])
	for a in CODE_REMAP:
		if InputMap.has_action(a) and action_key(a) != CODE_REMAP[a]:
			_set_key(a, CODE_REMAP[a])


# Клавиши по умолчанию из data/ui_layout.json keys (задача 24: свернуть магазин и панель отрядов; задача 27: сброс зума): действие -> Key.
# Нет файла, поля или клавиша не распознана — DATA_KEYS_DEFAULT (с предупреждением).
const UI_LAYOUT := "res://data/ui_layout.json"
const DATA_KEYS_DEFAULT := {"shop_toggle": KEY_TAB, "squad_panel_toggle": KEY_L, "camera_zoom_reset": KEY_HOME}   # camera_zoom_reset — сброс зума (задача 27)
static func data_keys() -> Dictionary:
	var out := DATA_KEYS_DEFAULT.duplicate()
	var d = JSON.parse_string(FileAccess.get_file_as_string(UI_LAYOUT)) if FileAccess.file_exists(UI_LAYOUT) else null
	var keys = d.get("keys") if d is Dictionary else null
	if not keys is Dictionary:
		push_warning("%s: нет keys — клавиши сворачивания панелей по умолчанию" % UI_LAYOUT)
		return out
	for a in out:
		var code := OS.find_keycode_from_string(str(keys.get(a, "")))
		if code == KEY_NONE:
			push_warning("%s: keys.%s «%s» — не клавиша; остаётся %s" % [UI_LAYOUT, a, str(keys.get(a, "")), OS.get_keycode_string(out[a])])
		else:
			out[a] = code
	return out


# Клавиша — её имя («N», «Space»), кнопка мыши — «Mouse8».
func _save_keys(cfg: ConfigFile) -> void:
	for r in REBINDABLE:
		var e := action_event(r)
		cfg.set_value("input", r, "%s%d" % [MOUSE_TOKEN, e.button_index] if e is InputEventMouseButton else OS.get_keycode_string(action_key(r)))
