extends RefCounted
# Игровые единицы расстояния (задача 26): игроку расстояния показываются в «шагах», а не в px мира.
# Один шаг — data/ui_layout.json world_unit_px; по умолчанию это ширина бойца пехоты в строю (шаг строя SLOT_SPACING
# из scripts/main.gd, его же сверяет тест). Нет поля — берётся SLOT_SPACING. Значение округляется до 0,5 шага.
# Слово единицы — в переводах: UNIT_PACE_ONE / _FEW / _MANY (ru: шаг / шага / шагов; en: pace / paces / paces).
const LAYOUT := "res://data/ui_layout.json"
const MAIN := "res://scripts/main.gd"

static var _unit_px := -1.0


# px мира в одном шаге (читается один раз за запуск).
static func world_unit_px() -> float:
	if _unit_px > 0.0:
		return _unit_px
	var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT)) if FileAccess.file_exists(LAYOUT) else null
	var v = d.get("world_unit_px") if d is Dictionary else null
	if (v is float or v is int) and float(v) > 0.0:
		_unit_px = float(v)
	else:
		_unit_px = float((load(MAIN) as GDScript).get_script_constant_map()["SLOT_SPACING"])
	return _unit_px


# Расстояние px мира в шагах, округление до 0,5.
static func paces(px: float) -> float:
	return roundf(px / world_unit_px() * 2.0) * 0.5


# Число шагов текстом: целое без дроби, иначе одна цифра после запятой (ru — запятая, en — точка).
static func paces_number(v: float) -> String:
	if v == floorf(v):
		return "%d" % int(v)
	var s := "%.1f" % v
	return s.replace(".", ",") if TranslationServer.get_locale().begins_with("ru") else s


# Ключ слова единицы под число: ru — 1, 21 шаг; 2–4, 22 шага; 5–20 шагов; дробное — шага; en — 1 pace, иначе paces.
static func pace_key(v: float) -> String:
	if not TranslationServer.get_locale().begins_with("ru"):
		return "UNIT_PACE_ONE" if v == 1.0 else "UNIT_PACE_MANY"
	if v != floorf(v):
		return "UNIT_PACE_FEW"
	var n := int(v) % 100
	if n % 10 == 1 and n != 11:
		return "UNIT_PACE_ONE"
	if n % 10 >= 2 and n % 10 <= 4 and (n < 12 or n > 14):
		return "UNIT_PACE_FEW"
	return "UNIT_PACE_MANY"


# Число для игрока: не больше digits знаков после запятой, без лишних нулей; ru — запятая.
static func num(v: float, digits := 1) -> String:
	var s := String.num(snappedf(v, pow(10.0, -digits)), digits)
	if "." in s:
		s = s.rstrip("0").trim_suffix(".")
	return s.replace(".", ",") if TranslationServer.get_locale().begins_with("ru") else s


# Расстояние px мира текстом для игрока: «12,5 шага», «20 paces».
static func dist_text(px: float) -> String:
	var v := paces(px)
	return "%s %s" % [paces_number(v), TranslationServer.translate(pace_key(v))]
