extends Node
# Настройки игрока — автозагрузка Settings, единственное место, где они хранятся. Файл user://settings.cfg (ConfigFile):
# загружается и применяется при старте, сохраняется при каждом изменении. F11 в любой момент переключает полный экран.
# Под тестовым скриптом (-s bench/...) файл игрока не читается и не пишется: тесты идут на значениях по умолчанию,
# а свои настройки проверяют, подменив path и вызвав load_settings.
signal changed(key: String)   # «display/fullscreen» и т. п.: экраны настроек обновляют вид

const PATH := "user://settings.cfg"
const WINDOW_SIZE := Vector2i(1920, 1080)       # окно по умолчанию
const WINDOW_SIZE_SMALL := Vector2i(1280, 720)  # если экран меньше WINDOW_SIZE

var path := PATH
var persist := true            # false — не писать файл (тестовый запуск)
var fullscreen := false        # display/fullscreen: безрамочный полноэкранный режим


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # F11 и на паузе
	persist = get_tree().get_script() == null   # обычный запуск игры, не тестовый SceneTree
	if persist:
		load_settings()
		_apply_window(true)   # тестовое окно не трогать: размер задают тесты и проект


# Прочитать файл и применить; нет файла или он битый — значения по умолчанию.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path) and cfg.load(path) != OK:
		push_warning("%s не читается: настройки по умолчанию" % path)
		cfg = ConfigFile.new()
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	if cfg.save(path) != OK:
		push_warning("Не удалось сохранить настройки в %s" % path)


func set_fullscreen(on: bool) -> void:
	if on == fullscreen:
		return
	fullscreen = on
	_apply_window(false)
	save_settings()
	changed.emit("display/fullscreen")


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
