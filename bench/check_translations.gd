extends SceneTree
# Проверка переводов: data/translations.csv (keys, ru, en) — у каждого ключа заполнены оба языка, ключи не повторяются,
# импортированные .translation отдают те же строки; все ключи из кода (scripts/*.gd) и данных (data/*.json) есть в таблице;
# в коде нет русских строк для игрока мимо tr() (кроме комментариев, логов push_error/push_warning/print и строк «# tr-skip»).
const CSV := "res://data/translations.csv"
const KEY_RE := "^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$"
# Префиксы ключей перевода: строковые литералы с ними в коде считаются ключами
const PREFIXES := ["UI_", "HUD_", "MSG_", "HUB_", "GIFT_", "SHOP_", "UNIT_", "ORDER_", "SIDE_", "SPLIT_MODE_", "END_",
	"STORY_", "SIEGE_", "ACTION_", "DEBUG_FPS"]
const SETTINGS := preload("res://scripts/settings.gd")
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func _initialize() -> void:
	print("CHECK translations")
	var table := {}   # ключ -> [ru, en]
	var f := FileAccess.open(CSV, FileAccess.READ)
	var head := f.get_csv_line()
	check("заголовок keys, ru, en", Array(head) == ["keys", "ru", "en"], str(head))
	var empty := []
	var dup := []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 1 and row[0] == "":
			continue
		if row.size() != 3 or row[1].strip_edges() == "" or row[2].strip_edges() == "":
			empty.append(row[0])
		if table.has(row[0]):
			dup.append(row[0])
		table[row[0]] = [row[1] if row.size() > 1 else "", row[2] if row.size() > 2 else ""]
	check("строк в таблице %d, у всех оба языка" % table.size(), empty.is_empty() and table.size() > 0, ", ".join(empty))
	check("ключи не повторяются", dup.is_empty(), ", ".join(dup))
	var re := RegEx.create_from_string(KEY_RE)
	var bad_form := []
	for k in table:
		if re.search(k) == null:
			bad_form.append(k)
	check("ключи вида ГРУППА_ИМЯ заглавными", bad_form.is_empty(), ", ".join(bad_form))
	# импорт: строки из .translation совпадают с таблицей
	var mism := []
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		for k in table:
			var want: String = table[k][0 if loc == "ru" else 1].c_unescape()
			if String(TranslationServer.translate(k)) != want:
				mism.append("%s:%s" % [loc, k])
	check("импортированные переводы ru и en совпадают с таблицей (переимпортируй CSV, если нет)", mism.is_empty(), ", ".join(mism.slice(0, 10)))
	TranslationServer.set_locale("ru")
	# ключи из кода и данных
	var used := {}
	var lit := RegEx.create_from_string("\"([A-Z][A-Z0-9_]+)\"")
	for dir in ["res://scripts", "res://data"]:
		for file in DirAccess.get_files_at(dir):
			if not (file.ends_with(".gd") or file.ends_with(".json")):
				continue
			var text := FileAccess.get_file_as_string(dir.path_join(file))
			for m in lit.search_all(text):
				var k := m.get_string(1)
				if re.search(k) != null and PREFIXES.any(func(p): return k.begins_with(p)):
					used[k] = dir.path_join(file)
	# ключи, собираемые в коде из частей
	for a in SETTINGS.REBINDABLE:
		used["ACTION_SQUAD_SELECT" if a.begins_with("squad_select_") else "ACTION_" + a.to_upper()] = "settings.gd: action_title"
	for l in SETTINGS.LANGUAGES:
		used["UI_SETTINGS_LANG_" + l.to_upper()] = "settings_menu.gd"
	var missing := []
	for k in used:
		if not table.has(k):
			missing.append("%s (%s)" % [k, used[k]])
	check("ключей в коде и данных %d, все есть в таблице" % used.size(), missing.is_empty(), ", ".join(missing))
	# русские строки в коде мимо tr()
	var cyr := RegEx.create_from_string("\"[^\"]*[А-Яа-яЁё][^\"]*\"")
	var raw := []
	for file in DirAccess.get_files_at("res://scripts"):
		if not file.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string("res://scripts".path_join(file)).split("\n")
		for i in lines.size():
			var line := lines[i]
			if "tr-skip" in line:
				continue
			var code := _strip_comment(line)
			var prev := lines[i - 1] if i > 0 else ""
			if "push_error" in code or "push_warning" in code or "print(" in code or "push_error(" in prev or "push_warning(" in prev:
				continue
			if cyr.search(code) != null:
				raw.append("%s:%d" % [file, i + 1])
	check("в scripts/*.gd нет русских строк для игрока мимо таблицы", raw.is_empty(), ", ".join(raw))
	# сцены: тексты меток
	var scene_raw := []
	for file in DirAccess.get_files_at("res://scenes"):
		var text := FileAccess.get_file_as_string("res://scenes".path_join(file))
		if cyr.search(text) != null:
			scene_raw.append(file)
	check("в scenes/*.tscn нет русских текстов", scene_raw.is_empty(), ", ".join(scene_raw))
	print("CHECK: провалов %d" % fails)
	quit()

# Строка без комментария (# вне строковых литералов).
func _strip_comment(line: String) -> String:
	var q := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			q = not q
		elif ch == "#" and not q:
			return line.substr(0, i)
	return line
