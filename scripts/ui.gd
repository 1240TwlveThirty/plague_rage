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


# --- Тёмная панель хаба и настроек (задача 24) -----------------------------------------------------------------------------
# data/ui_theme.json panel_dark: file — art/ui/ui_panel_dark_c<угол>.png (угол из имени), content_pad — поле внутри сверх угла.
# Нет файла — универсальная панель (panel) с затемнением fallback_modulate; одно предупреждение за запуск.
static func dark_panel_style() -> StyleBoxTexture:
	if _frames.has("panel_dark"):
		return _frames.panel_dark.style
	var c := theme_cfg()
	var s := int(c.get("scale", 2))
	var pd: Dictionary = c.get("panel_dark", {})
	var p: Dictionary = c.get("panel", {})
	var file := str(pd.get("file", "res://art/ui/ui_panel_dark_c8.png"))
	# ищется <имя>_c<угол>.png с любым углом (угол — из имени найденного файла), как у рамок кнопок
	var found := find_frame(frames_dir if frames_dir != "" else file.get_base_dir(), RegEx.create_from_string("\\d+\\.png$").sub(file.get_file(), ""))
	var path: String = found.get("path", file)
	var img: Image = null if found.is_empty() else _image(path)
	var corner := int(found.get("corner", 0))
	var slice := corner
	var mod := Color.WHITE
	var fallback := img == null or img.get_width() < corner * 2 + 1 or img.get_height() < corner * 2 + 1
	if fallback:
		_warn("panel_dark", "Тёмная панель: нет %s — универсальная панель с затемнением %s" % [path, str(pd.get("fallback_modulate", ""))])   # tr-skip: лог
		img = _image(str(p.get("file", "")))
		corner = int(p.get("corner", 0))
		slice = int(p.get("slice", corner))
		mod = Color(str(pd.get("fallback_modulate", "#ffffff")))
	var sb := StyleBoxTexture.new()
	if img != null:
		img.resize(img.get_width() * s, img.get_height() * s, Image.INTERPOLATE_NEAREST)
		sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(slice * s)
	sb.set_content_margin_all(float(corner * s + int(pd.get("content_pad", p.get("content_pad", 8)))))
	sb.modulate_color = mod
	_frames["panel_dark"] = {"style": sb, "path": "" if fallback else path, "corner": corner, "fallback": fallback}
	return sb


# Тёмная панель на PanelContainer или на подложке вкладок TabContainer (stylebox «panel»).
static func frame_panel_dark(c: Control) -> void:
	c.add_theme_stylebox_override("panel", dark_panel_style())
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# Окошко-рамка ui_slot за строкой (строки даров): PanelContainer без содержимого, размер задаёт вызывающий.
static func slot_frame() -> PanelContainer:
	var p := PanelContainer.new()
	frame_slot(p)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# Полоса прокрутки из data/ui_theme.json scrollbar (задача 28в): жёлоб и ползунок — плоские цвета палитры, толщина width (не
# стандартная серая полоса Godot). Без ключа — те же значения по умолчанию.
static func style_scrollbar(sb: ScrollBar) -> void:
	var c: Dictionary = {"width": 16, "track": "#262b44", "grabber": "#c0cbdc", "grabber_hover": "#feae34", "grabber_pressed": "#f77622",
		"border": "#181425", "border_width": 2}
	var t = theme_cfg().get("scrollbar")
	if t is Dictionary:
		c.merge(t, true)
	var half := float(c.width) * 0.5
	var track := StyleBoxFlat.new()
	track.bg_color = Color(str(c.track))
	track.border_color = Color(str(c.border))
	track.set_border_width_all(int(c.border_width))
	track.set_content_margin_all(half)   # толщина полосы = width (поля слева и справа)
	sb.add_theme_stylebox_override("scroll", track)
	sb.add_theme_stylebox_override("scroll_focus", track)
	for st in [["grabber", "grabber"], ["grabber_highlight", "grabber_hover"], ["grabber_pressed", "grabber_pressed"]]:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(str(c[st[1]]))
		g.border_color = Color(str(c.border))
		g.set_border_width_all(int(c.border_width))
		g.set_content_margin_all(half)
		sb.add_theme_stylebox_override(st[0], g)
	sb.custom_minimum_size.x = maxf(sb.custom_minimum_size.x, float(c.width))


# Относительная яркость и контраст (WCAG 2) — подбор фона дневника; тесты считают так же.
static func luminance(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


static func contrast(a: Color, b: Color) -> float:
	return (maxf(luminance(a), luminance(b)) + 0.05) / (minf(luminance(a), luminance(b)) + 0.05)


# Цвет середины арта светлой панели (panel.file); нет файла — белый.
static func panel_center_color() -> Color:
	var img := _image(str(theme_cfg().get("panel", {}).get("file", "")))
	return img.get_pixel(img.get_width() / 2, img.get_height() / 2) if img != null else Color.WHITE


# Текст дневника (задача 28в): ui_theme.json diary_text_color.
static func diary_text_color() -> Color:
	return Color(str(theme_cfg().get("diary_text_color", "#181425")))


# Цвет текста на светлой рамке слота (строки даров): ui_theme.json slot_text_color; контраст проверяет check_v74_ui.
static func slot_text_color() -> Color:
	return Color(str(theme_cfg().get("slot_text_color", "#181425")))
