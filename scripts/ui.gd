extends RefCounted
# Общий вид меню, хаба, меню паузы и баннеров: чёрный фон, универсальные рамки кнопки и панели (задача 18).
# Рамки — вариации типов в теме проекта art/ui/theme.tres (gui/theme/custom), её собирает bench/make_ui_scaled.gd из
# data/ui_theme.json. Базовые Button/PanelContainer/Label тема не задаёт: контрол получает рамку, только если её назначить здесь.
const BG_COLOR := Color.BLACK
const BUTTON := &"FrameButton"
const PANEL := &"FramePanel"
const LABEL := &"FrameLabel"   # тёмный контур текста на светлой панели
const SLOT := &"FrameSlot"     # окошко верхней панели боя и Сияния (задача 19)
const BAR := &"FrameBar"       # полоса HP окошка: иконки frame, fill и окно заливки (константы)


# Универсальная рамка кнопки. menu — кнопка меню: не меньше min_width x min_height темы (размер рамки арта на экране);
# иначе размер прежний (кнопки действий отряда, Клич, «Купить» в таблице даров).
static func frame_button(b: Button, menu := true) -> void:
	b.theme_type_variation = BUTTON
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # пиксельный арт и при растяжении окна
	if menu:
		var t := ThemeDB.get_project_theme()
		if t != null:
			b.custom_minimum_size = b.custom_minimum_size.max(Vector2(t.get_constant("min_width", BUTTON), t.get_constant("min_height", BUTTON)))


# Универсальная панель-подложка (PanelContainer): рамка с углом темы, внутренние отступы не меньше угла.
static func frame_panel(p: PanelContainer) -> void:
	p.theme_type_variation = PANEL
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# Поля панели темы слева+справа и сверху+снизу (вне дерева сцены контрол вариацию темы проекта ещё не видит).
static func panel_margins() -> Vector2:
	var t := ThemeDB.get_project_theme()
	return t.get_stylebox("panel", PANEL).get_minimum_size() if t != null and t.has_stylebox("panel", PANEL) else Vector2.ZERO


# Окошко (scripts/hud_slot.gd): рамка ui_slot с углом темы.
static func frame_slot(p: PanelContainer) -> void:
	p.theme_type_variation = SLOT
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# Поля окошка слева+справа и сверху+снизу (как panel_margins).
static func slot_margins() -> Vector2:
	var t := ThemeDB.get_project_theme()
	return t.get_stylebox("panel", SLOT).get_minimum_size() if t != null and t.has_stylebox("panel", SLOT) else Vector2.ZERO


# Подпись на панели: тёмный контур, чтобы светлый текст читался на светлой рамке.
static func frame_label(l: Label) -> void:
	l.theme_type_variation = LABEL


# --- Рамки кнопок магазина и строк отрядов (задача 24) ---------------------------------------------------------------------
# data/ui_theme.json frames.<вид>: dir и prefix файла (<prefix><угол>.png, угол 9-slice — из имени, как у универсальной кнопки),
# states — состояний столбиком (state_rows: normal, hover, pressed, disabled), content_margin [слева, сверху, справа, снизу] —
# поля текста на экране. Файла нет или он не подходит — универсальная кнопка (button) с fallback_modulate по состояниям; в лог
# одно предупреждение на вид за запуск. Арт увеличивается x scale ближайшим соседом при первой кнопке вида (кэш на запуск).
const CFG := "res://data/ui_theme.json"
const STATES := ["normal", "hover", "pressed", "disabled"]
static var _cfg := {}
static var _frames := {}      # вид + центр -> {"styles": {состояние: StyleBox}, "path": файл, "corner": угол, "fallback": bool}
static var warnings := {}     # вид -> число предупреждений за запуск (тесты: не больше одного)
static var frames_dir := ""   # тесты: папка рамок вместо frames.<вид>.dir


static func theme_cfg() -> Dictionary:
	if _cfg.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(CFG)) if FileAccess.file_exists(CFG) else null
		_cfg = d if d is Dictionary else {}
	return _cfg


# Тесты: забыть собранные рамки и предупреждения (следующая кнопка ищет файл заново).
static func reset_frames(dir := "") -> void:
	_frames = {}
	warnings = {}
	frames_dir = dir


# Файл рамки в dir: <prefix><угол>.png (в экспорте — .png.import). {} — нет; несколько — первый по имени.
static func find_frame(dir: String, prefix: String) -> Dictionary:
	var re := RegEx.create_from_string("^" + prefix + "(\\d+)\\.png$")
	var found := []
	for f in DirAccess.get_files_at(dir):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if re.search(n) != null and not n in found:
			found.append(n)
	if found.is_empty():
		return {}
	found.sort()
	return {"path": dir.path_join(found[0]), "corner": int(re.search(found[0]).get_string(1))}


# Картинка: импортированная текстура (игра, экспорт), иначе файл с диска (неимпортированный, например user:// в тестах).
static func _image(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		img = tex.get_image() if tex != null else null
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


# Предупреждение один раз за запуск на ключ (обе версии стилей вида — с серединой и без — не повторяют его).
static func _warn(kind: String, msg: String) -> void:
	if warnings.has(kind):
		return
	warnings[kind] = 1
	push_warning(msg)


# Стили кнопки вида kind (center false — без середины рамки: под ней видна иллюстрация отряда).
static func frame_styles(kind: String, center := true) -> Dictionary:
	var key := "%s/%s" % [kind, center]
	if _frames.has(key):
		return _frames[key]
	var c := theme_cfg()
	var s := int(c.get("scale", 2))
	var fd: Dictionary = c.get("frames", {}).get(kind, {})
	var b: Dictionary = c.get("button", {})
	var dir: String = frames_dir if frames_dir != "" else str(fd.get("dir", "res://art/ui"))
	var prefix: String = str(fd.get("prefix", "ui_btn_%s_c" % kind))
	var states := int(fd.get("states", 4))
	var found := find_frame(dir, prefix)
	var img: Image = null
	var corner := 0
	var why := ""
	if found.is_empty():
		why = "нет %s/%s<угол>.png" % [dir, prefix]   # tr-skip: лог
	else:
		img = _image(found.path)
		corner = found.corner
		if img == null:
			why = "%s не загружается" % found.path   # tr-skip: лог
		elif img.get_height() % states != 0 or img.get_width() < corner * 2 + 1 or img.get_height() / states < corner * 2 + 1:
			why = "%s: %d x %d — не %d состояний столбиком с углом %d" % [found.path, img.get_width(), img.get_height(), states, corner]   # tr-skip: лог
			img = null
		elif fd.has("art_size") and Vector2i(img.get_width(), img.get_height() / states) != Vector2i(int(fd.art_size[0]), int(fd.art_size[1])):
			_warn(kind + "/size", "%s: состояние %d x %d, ожидалось %d x %d — растягивается 9-slice" % [found.path, img.get_width(),   # tr-skip: лог
				img.get_height() / states, int(fd.art_size[0]), int(fd.art_size[1])])
	var fallback := img == null
	var rows: Dictionary = fd.get("state_rows", {"normal": 0, "hover": 1, "pressed": 2, "disabled": 3})
	var mods: Dictionary = {}
	var slice := corner
	if fallback:
		_warn(kind, "Рамка «%s»: %s — универсальная кнопка %s" % [kind, why, b.get("file", "")])   # tr-skip: лог
		img = _image(str(b.get("file", "")))
		corner = int(b.get("corner", 0))
		slice = int(b.get("slice", corner))
		states = int(b.get("states", 1))
		rows = b.get("state_rows", {})
		mods = fd.get("fallback_modulate", b.get("state_modulate", {}))
	var out := {}
	var m: Array = fd.get("content_margin", [8, 4, 8, 4])
	if img != null:
		img.resize(img.get_width() * s, img.get_height() * s, Image.INTERPOLATE_NEAREST)
		var tex := ImageTexture.create_from_image(img)
		var sh := img.get_height() / states
		for st in STATES:
			var sb := StyleBoxTexture.new()
			sb.texture = tex
			sb.region_rect = Rect2(0, clampi(int(rows.get(st, 0)), 0, states - 1) * sh, img.get_width(), sh)
			sb.set_texture_margin_all(slice * s)
			sb.content_margin_left = float(m[0])
			sb.content_margin_top = float(m[1])
			sb.content_margin_right = float(m[2])
			sb.content_margin_bottom = float(m[3])
			sb.draw_center = center
			sb.modulate_color = Color(mods.get(st, "#ffffff"))
			out[st] = sb
		out["hover_pressed"] = out.pressed
	out["focus"] = StyleBoxEmpty.new()
	_frames[key] = {"styles": out, "path": "" if fallback else str(found.path), "corner": corner, "fallback": fallback}
	return _frames[key]


# Кнопка вида kind ("shop", "squad") в своей рамке: цвета текста универсальной кнопки, рамка — frame_styles.
static func frame_kind(b: Button, kind: String, center := true) -> void:
	b.theme_type_variation = BUTTON
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.set_meta("frame_kind", kind)
	var st: Dictionary = frame_styles(kind, center).styles
	for k in st:
		b.add_theme_stylebox_override(k, st[k])
