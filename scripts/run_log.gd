extends RefCounted
# Журнал забегов (задача 26): строка в user://runs.csv на каждый законченный забег (Game.end_run). Файла нет — создаётся
# с заголовком. Только запись итогов: симуляцию не трогает.
# Колонки: дата (локальное время), версия игры (application/config/version), номер забега (законченных за всё время),
# осада, итог (win / loss), достигнутая волна, длительность (с игрового времени, без меню паузы), выбранные карточки
# (id через «;» в порядке выбора), смерти героя, потрачено золота (в магазине боя).
const PATH := "user://runs.csv"
const COLUMNS := ["date", "version", "run", "siege", "result", "wave", "duration_s", "cards", "hero_deaths", "gold_spent"]


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


# Дописать строку row (значения по COLUMNS). Возвращает, удалось ли.
static func append(path: String, row: Dictionary) -> bool:
	var exists := FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		push_warning("Журнал забегов %s не открывается (%d)" % [path, FileAccess.get_open_error()])
		return false
	if exists:
		f.seek_end()
	else:
		f.store_csv_line(PackedStringArray(COLUMNS))
	var line := PackedStringArray()
	for c in COLUMNS:
		line.append(str(row.get(c, "")))
	f.store_csv_line(line)
	f.close()
	return true
