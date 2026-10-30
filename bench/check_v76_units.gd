extends SceneTree
# Задача 26, этап 1: расстояния для игрока в шагах, а не в px.
# Ни одна строка перевода (ru, en) и ни один текст в data/*.json, который видит игрок, не содержит px / пикс (исключения — строки
# разрешения экрана: ключи с RESOLUTION). Тексты data — строковые значения вне полей-комментариев «_…», кроме путей res:// и цветов.
# Шаг — data/ui_layout.json world_unit_px, равен шагу строя пехоты SLOT_SPACING; округление до 0,5; склонение ru, слово en.
const CSV := "res://data/translations.csv"
const UNITS := preload("res://scripts/units.gd")
const CARDS := preload("res://scripts/cards.gd")
const MAIN := preload("res://scripts/main.gd")
var fails := 0
var px_re := RegEx.create_from_string("(?i)(\\d\\s*px\\b|\\bpx\\b|пикс)")

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

# Строки data, которые может увидеть игрок: всё, кроме полей «_…» (комментарии), путей и цветов.
func data_strings(v: Variant, out: Array, where: String) -> void:
	if v is Dictionary:
		for k in v:
			if not str(k).begins_with("_"):
				data_strings(v[k], out, where + "." + str(k))
	elif v is Array:
		for i in v.size():
			data_strings(v[i], out, "%s[%d]" % [where, i])
	elif v is String:
		if not (v.begins_with("res://") or v.begins_with("user://") or v.begins_with("#")):
			out.append([where, v])

func _initialize() -> void:
	print("CHECK v76 units")
	# 1. переводы
	var bad := []
	var f := FileAccess.open(CSV, FileAccess.READ)
	f.get_csv_line()
	var n := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3 or "RESOLUTION" in row[0]:
			continue
		n += 1
		for c in [1, 2]:
			if px_re.search(row[c]) != null:
				bad.append("%s: %s" % [row[0], row[c]])
	check("строк перевода %d: ни в ru, ни в en нет px / пикс" % n, n > 0 and bad.is_empty(), "; ".join(bad))
	# 2. тексты data
	bad = []
	var all := []
	for file in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json"):
			data_strings(JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file)), all, file)
	for it in all:
		if px_re.search(it[1]) != null:
			bad.append("%s: %s" % it)
	check("строк в data/*.json вне комментариев %d: нет px / пикс" % all.size(), all.size() > 0 and bad.is_empty(), "; ".join(bad.slice(0, 5)))
	# 3. единица
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	check("ui_layout.json world_unit_px = шагу строя пехоты SLOT_SPACING (%s)" % MAIN.SLOT_SPACING,
		layout.has("world_unit_px") and float(layout.world_unit_px) == MAIN.SLOT_SPACING and UNITS.world_unit_px() == MAIN.SLOT_SPACING)
	var u := UNITS.world_unit_px()
	check("округление до 0,5 шага", UNITS.paces(u * 3.2) == 3.0 and UNITS.paces(u * 3.3) == 3.5 and UNITS.paces(u * 3.74) == 3.5
		and UNITS.paces(u * 3.76) == 4.0 and UNITS.paces(0.0) == 0.0)
	TranslationServer.set_locale("ru")
	var ru := {1.0: "1 шаг", 2.0: "2 шага", 4.0: "4 шага", 5.0: "5 шагов", 11.0: "11 шагов", 12.5: "12,5 шага", 14.0: "14 шагов",
		21.0: "21 шаг", 22.0: "22 шага", 0.5: "0,5 шага", 111.0: "111 шагов"}
	var wrong := []
	for v in ru:
		if UNITS.dist_text(v * u) != ru[v]:
			wrong.append("%s → %s" % [v, UNITS.dist_text(v * u)])
	check("ru: шаг / шага / шагов и дробь через запятую", wrong.is_empty(), ", ".join(wrong))
	TranslationServer.set_locale("en")
	var en := {1.0: "1 pace", 2.0: "2 paces", 12.5: "12.5 paces", 21.0: "21 paces"}
	wrong = []
	for v in en:
		if UNITS.dist_text(v * u) != en[v]:
			wrong.append("%s → %s" % [v, UNITS.dist_text(v * u)])
	check("en: pace / paces и дробь через точку", wrong.is_empty(), ", ".join(wrong))
	# 4. где показывается
	var hero: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		var want := UNITS.dist_text(float(hero.hero_near_radius))
		var desc := CARDS.fill_desc(TranslationServer.translate("CARD_COMMANDER_BANNER_DESC"))
		var cond := String(TranslationServer.translate("COND_HERO_NEAR")) % want
		var prev := String(TranslationServer.translate("HUD_PREVIEW_MANY")) % [3, UNITS.dist_text(20.0 * u)]
		check("%s: описание «Знамени Командира», условие и подпись протяжки — в шагах («%s», «%s»)" % [loc, desc, prev],
			want in desc and want in cond and UNITS.dist_text(20.0 * u) in prev and px_re.search(desc + cond + prev) == null)
	TranslationServer.set_locale("ru")
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
