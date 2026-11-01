extends Control
# Главное меню: логотип (или текстовый заголовок), «Играть» (в хаб), «Настройки» и «Выход». Интерфейс строится кодом, по центру
# экрана по горизонтали, сверху вниз — по data/ui_layout.json menu (задача 28в); тексты — ключи перевода (Label и Button переводятся сами).
const FONTS := preload("res://scripts/fonts.gd")   # кегли и контуры текста под вариант шрифта (задача 20)
const UI := preload("res://scripts/ui.gd")
const SETTINGS_MENU := preload("res://scripts/settings_menu.gd")
const LAYOUT := "res://data/ui_layout.json"
const LAYOUT_DEFAULT := {"logo_path": "res://art/ui/ui_logo.png", "logo_top_margin": 353, "title_gap": 24, "button_gap": 24, "title_font": 72}

var play_button: Button
var settings_button: Button
var quit_button: Button
var title_label: Label   # запасной заголовок: название игры — ключ GAME_TITLE (одно место: data/translations.csv); null, если есть логотип
var logo: TextureRect    # логотип; null — файла нет или он не загрузился
var logo_path := ""      # тесты: другой файл логотипа вместо menu.logo_path (до добавления в дерево)
var settings_menu: CanvasLayer   # экран «Настройки» поверх меню


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var cfg := _layout()
	var top := MarginContainer.new()   # отступ сверху до логотипа
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.add_theme_constant_override("margin_top", int(cfg.logo_top_margin))
	add_child(top)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", int(cfg.title_gap))
	top.add_child(col)
	var tex := _logo_texture(logo_path if logo_path != "" else str(cfg.logo_path))
	if tex != null:
		logo = TextureRect.new()
		logo.texture = tex
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # пиксельный арт, без сглаживания
		logo.stretch_mode = TextureRect.STRETCH_KEEP               # натуральный размер файла (арт уже x2)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(logo)
	else:
		title_label = Label.new()
		title_label.text = "GAME_TITLE"
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.add_theme_font_size_override("font_size", FONTS.px(int(cfg.title_font)))
		col.add_child(title_label)
	var box := VBoxContainer.new()   # кнопки одной ширины (по самой широкой), по центру под логотипом
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", int(cfg.button_gap))
	col.add_child(box)
	play_button = _button(box, "UI_MENU_PLAY")
	play_button.pressed.connect(_on_play)
	play_button.set_meta("sfx", "click_play")   # звук нажатия (Audio)
	settings_button = _button(box, "UI_MENU_SETTINGS")
	settings_button.pressed.connect(_open_settings)
	settings_button.set_meta("sfx", "click_settings")
	quit_button = _button(box, "UI_MENU_QUIT")
	quit_button.pressed.connect(_on_quit)
	quit_button.set_meta("sfx", "click_exit")
	settings_menu = SETTINGS_MENU.new()
	settings_menu.closed.connect(func(): settings_button.grab_focus())
	add_child(settings_menu)
	play_button.grab_focus()   # Enter нажимает «Играть»
	var f := get_node_or_null("/root/Focus")
	if f != null:
		f.hide_focus()   # задача 26: подсветка фокуса — только после клавиши


# data/ui_layout.json menu поверх значений по умолчанию (файла или ключа нет — по умолчанию).
func _layout() -> Dictionary:
	var out := LAYOUT_DEFAULT.duplicate()
	var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT)) if FileAccess.file_exists(LAYOUT) else null
	if d is Dictionary and d.get("menu") is Dictionary:
		out.merge(d.menu, true)
	return out


# Текстура логотипа: импортированная (игра, экспорт) или файл с диска (тесты: копия во временной папке). Нет файла — null без
# сообщений в логе: меню покажет текстовый заголовок.
static func _logo_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if path.begins_with("res://") or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


func _button(box: Container, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FONTS.px(36))
	UI.frame_button(b)
	box.add_child(b)
	return b


func _on_play() -> void:
	get_node("/root/Game").go_hub()


func _open_settings() -> void:
	settings_menu.open()


func _on_quit() -> void:
	get_node("/root/Game").quit_game()   # сохранить и выйти
