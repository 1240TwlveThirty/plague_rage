extends PanelContainer
# Подсказки первой минуты (задача 26): data/hints.json. У подсказки условие появления (when — имя условия, его значение даёт
# хозяин в poll), текст — ключ перевода в одну строку, время показа seconds и действие done_on, по которому она исчезает раньше.
# Каждая показывается один раз: id запоминается в настройках (Settings.hints_seen) в момент показа. Одновременно не больше
# одной; ждущие проверяются в порядке файла. {действие} в тексте (например {hero_attack}) — его клавиша сейчас. Выключены в настройках (Settings.hints_enabled) — не показываются.
# Время — реальное (Time.get_ticks_msec): пауза боя и скорость игры на него не влияют. Только интерфейс, симуляцию не трогает.
const UI := preload("res://scripts/ui.gd")
const FONTS := preload("res://scripts/fonts.gd")
const SETTINGS := preload("res://scripts/settings.gd")   # key_label: {действие} в тексте — его клавиша
const PATH := "res://data/hints.json"

var path := PATH                # тесты подменяют
var cfg := {}                   # hints.json целиком (после проверки) или {}
var defs: Array = []            # [{id, when, text, seconds, done_on}] в порядке файла
var current := {}               # показанная сейчас или {}
var shown_until_ms := 0
var shown_log: Array = []       # id в порядке показа (для тестов и отчёта)
var label: Label
var settings: Node              # /root/Settings или null (бенчи без автозагрузок)
var local_seen := {}            # без Settings: показанные за этот запуск
var now_ms := func() -> int: return Time.get_ticks_msec()   # тесты подменяют часы


func _ready() -> void:
	settings = get_node_or_null("/root/Settings")
	UI.frame_panel(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # клики по карте проходят сквозь подсказку
	label = Label.new()
	UI.frame_label(label)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF   # одна строка
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # текст собирает text_of (перевод и клавиши)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONTS.px(int(cfg.get("font_size", FONTS.DEFAULT_SIZE))))
	add_child(label)
	visible = false
	add_to_group(&"shot_hidden")   # служебный текст — не на скриншотах (F12)


# Загрузить и проверить data/hints.json; ошибка — подсказок нет (предупреждение).
func load_defs() -> void:
	defs = []
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (d is Dictionary and d.get("hints") is Array):
		push_warning("%s: нет списка hints — подсказок нет" % path)
		return
	cfg = d
	for e in d.hints:
		if not (e is Dictionary and e.get("id") is String and e.get("when") is String and e.get("text") is String
				and (e.get("seconds") is float or e.get("seconds") is int) and float(e.seconds) > 0.0):
			push_warning("%s: подсказка %s — нужны id, when, text и seconds > 0; пропущена" % [path, str(e)])
			continue
		defs.append({"id": e.id, "when": e.when, "text": e.text, "seconds": float(e.seconds), "done_on": str(e.get("done_on", ""))})


func enabled() -> bool:
	return settings == null or settings.hints_enabled


func seen(id: String) -> bool:
	return settings.hints_seen.has(id) if settings != null else local_seen.has(id)


func _mark_seen(id: String) -> void:
	if settings != null:
		settings.mark_hint_seen(id)
	else:
		local_seen[id] = true


# Раз в кадр интерфейса: conds — имя условия -> выполнено ли. Показанная истекла — скрыть; свободно — показать первую
# непоказанную с выполненным условием.
func poll(conds: Dictionary) -> void:
	if not current.is_empty():
		if now_ms.call() >= shown_until_ms or not enabled():
			dismiss()
		return
	if not enabled():
		return
	for d in defs:
		if conds.get(d.when, false) and not seen(d.id):
			_show(d)
			return


# Действие игрока (order, hero_attack, buy, ...): подсказка с таким done_on исчезает сразу.
func event(name: String) -> void:
	if not current.is_empty() and current.done_on == name:
		dismiss()


func dismiss() -> void:
	current = {}
	visible = false


func _show(d: Dictionary) -> void:
	current = d
	_mark_seen(d.id)
	shown_log.append(d.id)
	shown_until_ms = now_ms.call() + int(d.seconds * 1000.0)
	label.text = text_of(d.text)
	visible = true
	_place()


# Текст подсказки на текущем языке: перевод ключа, {действие} -> клавиша действия.
static func text_of(key: String) -> String:
	var t := String(TranslationServer.translate(key))
	var re := RegEx.create_from_string("\\{([a-z_0-9]+)\\}")
	for m in re.search_all(t):
		t = t.replace(m.get_string(), SETTINGS.key_label(m.get_string(1)))
	return t


# Внизу по центру экрана, над нижним краем на bottom px (hints.json).
func _place() -> void:
	size = get_combined_minimum_size()
	var vp := get_viewport_rect().size
	position = Vector2(roundf((vp.x - size.x) * 0.5), roundf(vp.y - float(cfg.get("bottom", 96)) - size.y))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and visible and not current.is_empty():
		label.text = text_of(current.text)
		_place.call_deferred()
