extends RefCounted
# Модификаторы забега: эффекты — данные (data/gifts.json), не код.
# Итог для одного ключа (stat, target): base * (1 + сумма add_pct / 100) * произведение mult; add_flat — отдельная сумма (get_flat).
# Проценты одного ключа складываются (16% + 20% = x1.36), mult перемножаются (под редкие карточки, пока не используется).
# Сцена боя спрашивает Mods один раз при старте забега (main.gd, _apply_mods) и кладёт итог в свои массивы; тик сюда не ходит.
const STATS := ["damage", "hp", "bounty", "income", "gate_hp", "start_units"]
const TARGETS := ["all_units", "infantry", "archer", "gate", "player"]
const OPS := ["add_pct", "add_flat", "mult"]
# Допустимые сочетания: stat -> его target. Пары вне таблицы сцена боя не читает, дар с такой парой молча не действовал бы.
const PAIRS := {"damage": ["all_units", "infantry", "archer"], "hp": ["all_units", "infantry", "archer"], "bounty": ["player"], "income": ["player"],
	"gate_hp": ["gate"], "start_units": ["player"]}

var defs := {}       # id дара -> {name, stat, target, op, levels, req_sieges, prices}
var pct := {}        # ключ "stat|target" -> сумма add_pct, в процентах
var mult := {}       # ключ -> произведение mult
var flat := {}       # ключ -> сумма add_flat


func _init(gift_defs := {}) -> void:
	defs = gift_defs


# gifts.json: непустой массив даров {id, name, stat, target, op, levels}; levels — непустой массив чисел (значение уровня n — levels[n - 1]).
# Пара stat / target — из таблицы PAIRS. Для магазина даров, по желанию: req_sieges — сколько осад пройдено для покупки уровня n
# (нет поля — 0, 1, 2, ...), prices — цены уровней в Сиянии (нет поля — пустой массив: цены по умолчанию из radiance.json); длина обоих — как у levels.
# Остального по умолчанию нет: чего нет — ошибка. Результат: id -> {name, stat, target, op, levels, req_sieges, prices}; при ошибке push_error и пустой словарь.
static func load_gifts(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: %s" % path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("%s: битый JSON" % path)
		return {}
	if not data is Array or data.is_empty():
		push_error("%s: ожидается непустой JSON-массив даров" % path)
		return {}
	var out := {}
	for e in data:
		if not e is Dictionary or not e.get("id") is String or e.id == "":
			push_error("%s: дар без строкового поля id" % path)
			return {}
		if out.has(e.id):
			push_error("%s: дар \"%s\" повторяется" % [path, e.id])
			return {}
		for key in ["name_key", "desc_key", "stat", "target", "op"]:
			if not e.get(key) is String:
				push_error("%s: у дара \"%s\" нет строкового поля %s" % [path, e.id, key])
				return {}
		if not e.stat in STATS:
			push_error("%s: у дара \"%s\" неизвестный stat \"%s\"" % [path, e.id, e.stat])
			return {}
		if not e.target in TARGETS:
			push_error("%s: у дара \"%s\" неизвестный target \"%s\"" % [path, e.id, e.target])
			return {}
		if not e.target in PAIRS[e.stat]:
			push_error("%s: у дара \"%s\" недопустимая пара stat \"%s\" и target \"%s\"" % [path, e.id, e.stat, e.target])
			return {}
		if not e.op in OPS:
			push_error("%s: у дара \"%s\" неизвестный op \"%s\"" % [path, e.id, e.op])
			return {}
		if not e.get("levels") is Array or e.levels.is_empty():
			push_error("%s: у дара \"%s\" нет непустого массива levels" % [path, e.id])
			return {}
		var levels := PackedFloat64Array()
		for v in e.levels:
			if not (v is float or v is int):
				push_error("%s: у дара \"%s\" в levels не число" % [path, e.id])
				return {}
			levels.append(v)
		var req := PackedInt32Array(range(levels.size()))
		var prices := PackedInt32Array()
		for key in ["req_sieges", "prices"]:
			if not e.has(key):
				continue
			var low := 0 if key == "req_sieges" else 1
			var ok: bool = e[key] is Array and e[key].size() == levels.size()
			if ok:
				for v in e[key]:
					ok = ok and (v is float or v is int) and v == floorf(v) and v >= low
			if not ok:
				push_error("%s: у дара \"%s\" поле %s — не массив целых (не меньше %d) той же длины, что levels" % [path, e.id, key, low])
				return {}
			if key == "req_sieges":
				req = PackedInt32Array(e[key])
			else:
				prices = PackedInt32Array(e[key])
		out[e.id] = {"name_key": e.name_key, "desc_key": e.desc_key, "stat": e.stat, "target": e.target, "op": e.op, "levels": levels, "req_sieges": req, "prices": prices}
	return out


# Собрать суммы из активных даров: id -> уровень (целое от 1 до числа уровней дара). Пустой словарь — модификаторов нет.
# Неизвестный id или уровень вне диапазона — push_error и false (суммы при этом пустые).
func build(active: Dictionary) -> bool:
	pct = {}
	mult = {}
	flat = {}
	var p := {}
	var m := {}
	var f := {}
	for id in active:
		if not defs.has(id):
			push_error("Активный дар \"%s\": такого дара нет" % str(id))
			return false
		var d: Dictionary = defs[id]
		var lvl = active[id]
		if not (lvl is float or lvl is int) or lvl != floorf(lvl) or lvl < 1 or lvl > d.levels.size():
			push_error("Активный дар \"%s\": уровень %s вне 1..%d" % [id, str(lvl), d.levels.size()])
			return false
		var v: float = d.levels[int(lvl) - 1]
		var key: String = d.stat + "|" + d.target
		match d.op:
			"add_pct":
				p[key] = p.get(key, 0.0) + v
			"mult":
				m[key] = m.get(key, 1.0) * v
			"add_flat":
				f[key] = f.get(key, 0.0) + v
	pct = p
	mult = m
	flat = f
	return true


# Множитель ключа: (1 + сумма add_pct / 100) * произведение mult. Без модификаторов — ровно 1.0.
func get_mult(stat: String, target: String) -> float:
	var key := stat + "|" + target
	return (1.0 + pct.get(key, 0.0) / 100.0) * mult.get(key, 1.0)


# Сумма add_flat ключа; без модификаторов 0.
func get_flat(stat: String, target: String) -> float:
	return flat.get(stat + "|" + target, 0.0)


# Особые правила (дары с поведением, которого нет в числах): заготовка, пока ни одного.
func has_rule(_id: String) -> bool:
	return false
