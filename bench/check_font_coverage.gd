extends SceneTree
# Покрытие символов пиксельным шрифтом (задача 20): все символы, которые игра может показать, должны быть в каждом шрифте
# из data/ui_theme.json (fonts: варианты, кроме default). Источники символов:
#   data/translations.csv — колонки ru и en; data/*.json — все строки (дневник, названия, подписи);
#   scripts/*.gd — строковые литералы (собираемые в коде подписи: «%s — %d», «●», стрелки разведки);
#   обязательный набор: цифры, ASCII-знаки, × № · ● – — « » … ↑ ← → ↓, неразрывные пробелы U+00A0 и U+202F.
# Печатает отсутствующие символы с кодом и первым местом, где встретился. Отсутствие не считается провалом (решение — за
# автором переводов), провал — только если шрифт не загрузился. Итог: «COVERAGE: ...».
const THEME_CFG := "res://data/ui_theme.json"
const REQUIRED := "0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~×№·●–—«»…↑←→↓  "
var where := {}   # символ -> первое место

func add_text(text: String, src: String) -> void:
	for c in text:
		if c == "\n" or c == "\t" or c == "\r":
			continue
		if not where.has(c):
			where[c] = src

func _initialize() -> void:
	var fails := 0
	add_text(REQUIRED, "обязательный набор")
	var f := FileAccess.open("res://data/translations.csv", FileAccess.READ)
	var head := f.get_csv_line()
	var cols := [head.find("ru"), head.find("en")]
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < head.size():
			continue
		for c in cols:
			add_text(row[c], "translations.csv:" + row[0] + ":" + head[c])
	for name in DirAccess.get_files_at("res://data"):
		if name.ends_with(".json"):
			_json_strings(JSON.parse_string(FileAccess.get_file_as_string("res://data/" + name)), "data/" + name)
	for name in DirAccess.get_files_at("res://scripts"):
		if name.ends_with(".gd"):
			_literals("res://scripts/" + name)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(THEME_CFG))
	var variants: Dictionary = cfg.fonts.variants
	var chars := where.keys()
	chars.sort()
	print("символов: %d (из переводов ru/en, data/*.json, литералов scripts/*.gd и обязательного набора)" % chars.size())
	var summary := []
	for v in variants:
		var d: Dictionary = variants[v]
		if not d.has("file"):
			continue
		var font := load(d.file) as FontFile
		if font == null:
			print("FAIL  %s: шрифт %s не загрузился" % [v, d.file])
			fails += 1
			continue
		var missing := []
		for c in chars:
			if not font.has_char(c.unicode_at(0)):
				missing.append(c)
		print("%s (%s): отсутствует %d" % [v, d.file.get_file(), missing.size()])
		for c in missing:
			print("  U+%04X «%s» — %s" % [c.unicode_at(0), c, where[c]])
		summary.append("%s %d" % [v, missing.size()])
	print("COVERAGE: символов %d, отсутствует: %s%s" % [chars.size(), ", ".join(summary), "" if fails == 0 else "; шрифт не загрузился: %d" % fails])
	quit(1 if fails > 0 else 0)

func _json_strings(v: Variant, src: String) -> void:
	if v is String:
		add_text(v, src)
	elif v is Array:
		for e in v:
			_json_strings(e, src)
	elif v is Dictionary:
		for k in v:
			_json_strings(v[k], src + ":" + str(k))

# Строковые литералы "..." файла (комментарии # вне строк пропускаются, \n и \" — как символы строки).
func _literals(path: String) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for n in lines.size():
		var line: String = lines[n]
		var i := 0
		while i < line.length():
			var c := line[i]
			if c == "#":
				break
			if c == "\"" or c == "'":
				var q := c
				var j := i + 1
				var lit := ""
				while j < line.length() and line[j] != q:
					if line[j] == "\\" and j + 1 < line.length():
						var e := line[j + 1]
						lit += {"n": "", "t": "", "\\": "\\", "\"": "\"", "'": "'"}.get(e, "")
						if e == "u" and j + 5 < line.length():
							lit += char(line.substr(j + 2, 4).hex_to_int())
							j += 4
						j += 2
						continue
					lit += line[j]
					j += 1
				add_text(lit, "%s:%d" % [path.get_file(), n + 1])
				i = j + 1
				continue
			i += 1
