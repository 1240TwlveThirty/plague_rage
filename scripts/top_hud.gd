extends HBoxContainer
# Верхняя панель боя (задача 19): ряд окошек scripts/hud_slot.gd по центру сверху. Состав и порядок окошек, ширины, высота,
# отступ сверху, зазор, масштаб иконок, кегль и иконки (по именам из data/icon_atlas.json) — data/ui_layout.json, раздел top_hud;
# шестое окошко — ещё одна запись в slots (id — одно из значений, которые отдаёт источник, см. main.gd _hud_value), код не правится.
# update() раз в 0.1 с спрашивает у источника значение каждого окошка; окошко меняет подпись и полосу, только если число другое.
# Тот же компонент — окошко «Сияние» в правом верхнем углу хаба и экрана итога (corner_slot, раздел corner_slot).
const SLOT := preload("res://scripts/hud_slot.gd")
const LAYOUT_PATH := "res://data/ui_layout.json"
# Значения по умолчанию (нет файла или поле неверно): как в data/ui_layout.json
const DEFAULT := {"top": 16, "gap": 12, "height": 56, "icon_scale": 2, "icon_gap": 8, "font_size": 18, "font_min": 16,
	"slots": [{"id": "wave", "icon": "hourglass", "width": 200}, {"id": "zombies_left", "icon": "skull", "width": 200},
		{"id": "troops", "icon": "soldiers", "width": 200}, {"id": "gate", "icon": "gate", "width": 600, "bar": true},
		{"id": "gold", "icon": "coin", "width": 200}]}
const DEFAULT_CORNER := {"id": "radiance", "icon": "radiance", "width": 200, "top": 16, "right": 16}

static var layout_path := LAYOUT_PATH   # тесты подменяют (своя раскладка в user://)
var cfg := {}
var slots := {}          # id -> окошко
var source := Callable() # source.call(id) -> Vector2i(значение, максимум или -1)


# Раздел key из data/ui_layout.json поверх defaults: числа — от 0, строки — непустые; slots — массив {id, icon, width > 0[, bar]}.
# Неверное — предупреждение и значение по умолчанию.
static func load_cfg(key: String, defaults: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	var all = JSON.parse_string(FileAccess.get_file_as_string(layout_path)) if FileAccess.file_exists(layout_path) else null
	var d = all.get(key) if all is Dictionary else null
	if not d is Dictionary:
		push_warning("%s: нет раздела %s — значения по умолчанию" % [layout_path, key])
		return out
	for k in out:
		if not d.has(k):
			continue
		var v = d[k]
		if k == "slots":
			if v is Array and not v.is_empty() and v.all(_slot_ok):
				out.slots = v
			else:
				push_warning("%s: %s.slots — массив {id, icon, width > 0}; остаётся по умолчанию" % [layout_path, key])
		elif out[k] is String and v is String and v != "":
			out[k] = v
		elif not out[k] is String and (v is float or v is int) and v >= 0:
			out[k] = v
		else:
			push_warning("%s: %s.%s — %s; остаётся %s" % [layout_path, key, k, "строка" if out[k] is String else "число от 0", str(out[k])])
	return out


static func _slot_ok(e: Variant) -> bool:
	return e is Dictionary and e.get("id") is String and e.get("icon") is String and (e.get("width") is float or e.get("width") is int) and e.width > 0


func _init() -> void:
	cfg = load_cfg("top_hud", DEFAULT)
	name = "TopHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(cfg.gap))
	for d in cfg.slots:
		var s := make_slot(cfg, d)
		add_child(s)
		slots[d.id] = s
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH   # по центру при любой ширине ряда
	position.y = cfg.top


# Окошко по записи d ({id, icon, width[, bar]}) с общими размерами c (раздел top_hud).
static func make_slot(c: Dictionary, d: Dictionary) -> SLOT:
	var s := SLOT.new()
	s.setup(d.id, d.icon, d.width, c.height, int(c.icon_scale), c.icon_gap, int(c.font_size), int(c.font_min), d.get("bar", false) == true)
	return s


# Окошко «Сияние» в правом верхнем углу (хаб, экран итога): запись corner_slot, размеры — как у панели боя.
static func corner_slot() -> SLOT:
	var c := load_cfg("top_hud", DEFAULT)
	var d := load_cfg("corner_slot", DEFAULT_CORNER)
	var s := make_slot(c, d)
	s.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	s.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	s.position = Vector2(-float(d.right) - float(d.width), float(d.top))
	return s


# Нижний край ряда (px от верха экрана): под ним — подписи, которые раньше шли под строкой HUD.
func bottom() -> float:
	return float(cfg.top) + float(cfg.height)


# Значения всех окошек из источника; меняются только те, где число другое.
func update() -> void:
	if not source.is_valid():
		return
	for id in slots:
		var v: Vector2i = source.call(id)
		slots[id].set_value(v.x, v.y)


# Смена языка: сокращения тысяч заново.
func refresh() -> void:
	for s in slots.values():
		s.refresh()


# Показанные значения: id -> число, у окошек с максимумом ещё id_max (тесты не зависят от текста и перевода).
func get_values() -> Dictionary:
	var out := {}
	for id in slots:
		out[id] = slots[id].value
		if slots[id].value_max >= 0:
			out[id + "_max"] = slots[id].value_max
	return out
