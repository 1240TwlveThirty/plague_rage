extends Node
# Подсветка фокуса клавиатуры (задача 26, автозагрузка Focus): рамка фокуса видна только после ввода с клавиатуры или
# геймпада; движение или кнопка мыши её прячут. Меню при открытии вызывают hide_focus(): фокус у кнопки остаётся (Enter
# нажимает её, стрелки ходят по кнопкам), но подсвечена она станет только после клавиши.
# Как: в теме проекта стиль focus (у вкладок — tab_focus) всех типов контролов на время «мыши» подменяется пустым
# StyleBoxEmpty, а цвет текста в фокусе font_focus_color (у рамок кнопок фокус виден именно им — золотой текст) — обычным
# font_color; при «клавиатуре» возвращаются исходные. Файл темы не меняется — только ресурс в памяти.
const BOX_TYPES := [&"Button", &"CheckBox", &"CheckButton", &"OptionButton", &"MenuButton", &"LinkButton", &"HSlider", &"VSlider",
	&"LineEdit", &"SpinBox", &"ItemList", &"Tree", &"ScrollContainer", &"TextEdit"]
const TAB_TYPES := [&"TabBar", &"TabContainer"]
const JOY_DEADZONE := 0.5

var keyboard := false           # true — последний ввод с клавиатуры или геймпада: фокус виден
var _saved := {}                # тема -> {boxes: [[тип, имя стиля]], colors: [тип]} — что подменяется
var _saved_colors := {}         # тема -> исходные значения: "тип/имя" -> StyleBox, тип -> font_focus_color
var _empty := StyleBoxEmpty.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # и в меню паузы (дерево на паузе)
	_apply()


func _input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed) or (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventJoypadMotion and absf(event.axis_value) >= JOY_DEADZONE):
		set_keyboard(true)
	elif (event is InputEventMouseMotion and event.relative != Vector2.ZERO) or (event is InputEventMouseButton and event.pressed):
		set_keyboard(false)


func set_keyboard(on: bool) -> void:
	if on == keyboard:
		return
	keyboard = on
	_apply()


# Открытие меню: ни одна кнопка не подсвечена, пока не нажата клавиша.
func hide_focus() -> void:
	set_keyboard(false)


# Что подменять в теме th: стили фокуса [тип, имя] и типы с цветом текста в фокусе. В теме по умолчанию — базовые типы из
# списков; в теме проекта — только то, что в ней уже задано (вариации вроде FrameButton): базовых типов она не получает.
func _targets(th: Theme, base: bool) -> Dictionary:
	var boxes := []
	var colors := []
	var types: Array = BOX_TYPES + TAB_TYPES if base else Array(th.get_type_list()).map(func(x): return StringName(x))
	for ty in types:
		for name in ["focus", "tab_focus"]:
			if th.has_stylebox(name, ty):
				boxes.append([ty, name])
		if th.has_color("font_focus_color", ty):
			colors.append(ty)
	return {"boxes": boxes, "colors": colors}


func _apply() -> void:
	var proj := ThemeDB.get_project_theme()
	for th in [ThemeDB.get_default_theme(), proj]:
		if th == null:
			continue
		if not _saved.has(th):
			_saved[th] = _targets(th, th != proj)
			var orig := {}
			for p in _saved[th].boxes:
				orig["%s/%s" % p] = th.get_stylebox(p[1], p[0])
			for ty in _saved[th].colors:
				orig[ty] = th.get_color("font_focus_color", ty)
			_saved_colors[th] = orig
		var o: Dictionary = _saved_colors[th]
		for p in _saved[th].boxes:
			th.set_stylebox(p[1], p[0], o["%s/%s" % p] if keyboard else _empty)
		for ty in _saved[th].colors:
			th.set_color("font_focus_color", ty, o[ty] if keyboard else _font_color(th, ty))


# Обычный цвет текста типа ty в теме th (у вариации — её или базового типа), иначе из темы по умолчанию.
static func _font_color(th: Theme, ty: StringName) -> Color:
	var cur := ty
	while cur != &"":
		if th.has_color("font_color", cur):
			return th.get_color("font_color", cur)
		cur = th.get_type_variation_base(cur)
	var d := ThemeDB.get_default_theme()
	for b in [ty, th.get_type_variation_base(ty), &"Button"]:
		if b != &"" and d.has_color("font_color", b):
			return d.get_color("font_color", b)
	return Color.WHITE


# Видна ли подсветка фокуса у контрола c сейчас (тесты): фокус у него и его стиль focus не пустой.
static func focus_drawn(c: Control) -> bool:
	if not c.has_focus():
		return false
	var name := "tab_focus" if (c is TabBar or c is TabContainer) else "focus"
	if not (c.get_theme_stylebox(name) is StyleBoxEmpty):
		return true
	return c is Button and c.get_theme_color("font_focus_color") != c.get_theme_color("font_color")
