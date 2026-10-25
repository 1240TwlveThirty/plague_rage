extends RefCounted
# Шрифт игры (задача 20): вариант — data/ui_theme.json font_variant, параметр запуска --font=default|fusion12|fusion10 важнее.
# default — встроенный шрифт Godot, кегли и контуры как заданы в коде. Пиксельный вариант (fonts.variants: file, native,
# outline_max) — шрифт проекта (тема и запасной шрифт ThemeDB), кегль — native x k (задача 21: правило fonts.rounding —
# nearest: ближайший, при равной разнице больший; down: вниз, как в задаче 20), k не меньше fonts.min_scale (2 — не мельче
# двойного родного); контур текста — не толще outline_max. Все кегли и контуры в коде задаются через px() и outline().
# Чёткость: в импорте шрифтов fonts/fusion_pixel/*.ttf.import сглаживание, хинтинг и субпиксельное позиционирование выключены.
const CFG := "res://data/ui_theme.json"
const DEFAULT_SIZE := 16   # кегль темы Godot по умолчанию (кнопки магазина, отрядов, вкладки без своего кегля)

static var _loaded := false
static var variant := "default"
static var native := 0          # родной кегль пиксельного варианта; 0 — default
static var outline_max := 0
static var min_scale := 2       # наименьший множитель родного кегля
static var rounding := "nearest"   # nearest (при равной разнице — больший) | down
static var font: FontFile = null
static var _applied := false
static var override := ""       # тесты: вариант вместо font_variant и --font (после reset)


# Тесты: забыть загруженный вариант (следующий px() прочитает заново, с override).
static func reset(v := "") -> void:
	override = v
	_loaded = false
	variant = "default"
	native = 0
	outline_max = 0
	min_scale = 2
	rounding = "nearest"
	font = null


# Вариант из ui_theme.json и параметра запуска (один раз).
static func load_cfg() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg = JSON.parse_string(FileAccess.get_file_as_string(CFG)) if FileAccess.file_exists(CFG) else null
	var variants: Dictionary = cfg.fonts.variants if cfg is Dictionary and cfg.get("fonts") is Dictionary else {}
	variant = cfg.get("font_variant", "default") if cfg is Dictionary else "default"
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--font="):
			variant = a.trim_prefix("--font=")
	if override != "":
		variant = override
	var d = variants.get(variant)
	if variant != "default" and not d is Dictionary:
		push_warning("%s: нет варианта шрифта «%s» — default" % [CFG, variant])
		variant = "default"
		return
	if variant == "default" or not d.has("file"):
		return
	font = load(d.file) as FontFile
	if font == null:
		push_warning("Шрифт %s не загрузился — default" % d.file)
		variant = "default"
		return
	native = maxi(int(d.get("native", 0)), 1)
	outline_max = int(d.get("outline_max", 4))
	var f: Dictionary = cfg.fonts
	min_scale = maxi(int(d.get("min_scale", f.get("min_scale", 2))), 1)   # у варианта своё — важнее общего
	rounding = str(d.get("rounding", f.get("rounding", "nearest")))
	if rounding != "nearest" and rounding != "down":
		push_warning("%s: fonts.rounding «%s» — nearest или down; беру nearest" % [CFG, rounding])
		rounding = "nearest"


# Кегль для заданного в коде size: default — как есть; пиксельный — native x k, k по правилу rounding и не меньше min_scale.
static func px(size: int) -> int:
	load_cfg()
	if native <= 0:
		return size
	var k := size / native if rounding == "down" else (size * 2 + native) / (native * 2)   # nearest: floor(size/native + 0.5)
	return native * maxi(k, min_scale)


# Толщина контура текста: default — как есть; пиксельный — не толще outline_max.
static func outline(size: int) -> int:
	load_cfg()
	return size if native <= 0 else mini(size, outline_max)


# Кегли для подгонки текста от base вниз до minimum: default — каждый; пиксельный — только допустимые (native x k, k >= min_scale).
static func fit_sizes(base: int, minimum: int) -> Array:
	load_cfg()
	var out := []
	if native <= 0:
		for f in range(base, minimum - 1, -1):
			out.append(f)
		return out
	var f := px(base)
	while f >= px(minimum):
		out.append(f)
		f -= native
	return out


# Подключить вариант ко всему проекту (один раз, автозагрузка Settings): шрифт и кегль темы проекта и запасной шрифт ThemeDB
# (им рисуются подписи через draw_string), контуры вариаций темы — не толще outline_max. Для default ничего не меняет.
static func apply_project() -> void:
	load_cfg()
	if _applied or font == null:
		return
	_applied = true
	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = px(DEFAULT_SIZE)
	var t := ThemeDB.get_project_theme()
	if t != null:
		t.default_font = font
		t.default_font_size = px(DEFAULT_SIZE)
		for type in t.get_type_list():
			if t.has_constant("outline_size", type):
				t.set_constant("outline_size", type, outline(t.get_constant("outline_size", type)))
