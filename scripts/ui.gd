extends RefCounted
# Общий вид меню, хаба, меню паузы и баннеров: чёрный фон, универсальные рамки кнопки и панели (задача 18).
# Рамки — вариации типов в теме проекта art/ui/theme.tres (gui/theme/custom), её собирает bench/make_ui_scaled.gd из
# data/ui_theme.json. Базовые Button/PanelContainer/Label тема не задаёт: контрол получает рамку, только если её назначить здесь.
const BG_COLOR := Color.BLACK
const BUTTON := &"FrameButton"
const PANEL := &"FramePanel"
const LABEL := &"FrameLabel"   # тёмный контур текста на светлой панели


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


# Подпись на панели: тёмный контур, чтобы светлый текст читался на светлой рамке.
static func frame_label(l: Label) -> void:
	l.theme_type_variation = LABEL
