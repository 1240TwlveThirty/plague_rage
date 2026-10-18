extends RefCounted
# Модификаторы забега: эффекты — данные (data/gifts.json), не код.
# Итог для одного ключа (stat, target): base * (1 + сумма add_pct / 100) * произведение mult; add_flat — отдельная сумма (get_flat).
# Проценты одного ключа складываются (16% + 20% = x1.36), mult перемножаются (под редкие карточки, пока не используется).
# Счётные статы (start_units) — get_count: целая прибавка к числу, процент от него округляется вниз, но не меньше +1.
# Сцена боя спрашивает Mods один раз при старте забега (main.gd, _apply_mods) и кладёт итог в свои массивы; тик сюда не ходит.
# Статы «в момент использования» (цены магазина, окно сигнала, разброс, награда Сиянием) — value(stat, base): читаются при покупке,
# при старте волны или в Game.run_reward и хранятся в переменной; горячие циклы симуляции value не вызывают.
# Модификаторы собираются из списка источников (sources): сейчас один — дары забега (Game.active_gifts), позже — временные карточки.
const STATS := ["damage", "hp", "bounty", "income", "gate_hp", "start_units", "unit_cost", "weapon_cost", "repair_cost", "signal_window", "spread", "radiance_pct"]
const TARGETS := ["all_units", "infantry", "archer", "gate", "player"]
const OPS := ["add_pct", "add_flat", "mult"]
# Допустимые сочетания: stat -> его target. Пары вне таблицы сцена боя не читает, дар с такой парой молча не действовал бы.
const PAIRS := {"damage": ["all_units", "infantry", "archer"], "hp": ["all_units", "infantry", "archer"], "bounty": ["player"], "income": ["player"],
	"gate_hp": ["gate"], "start_units": ["player"], "unit_cost": ["player"], "weapon_cost": ["player"], "repair_cost": ["player"], "signal_window": ["player"],
	"spread": ["archer"], "radiance_pct": ["player"]}
# Допустимые op для stat: сцена боя читает множители (get_mult), прибавку к числу (get_count) или value; остальное не действовало бы.
const STAT_OPS := {"damage": ["add_pct", "mult"], "hp": ["add_pct", "mult"], "bounty": ["add_pct", "mult"], "income": ["add_pct", "mult"],
	"gate_hp": ["add_pct", "mult"], "start_units": ["add_pct", "add_flat"], "unit_cost": ["add_pct"], "weapon_cost": ["add_pct"], "repair_cost": ["add_pct"],
	"signal_window": ["add_flat"], "spread": ["add_pct"], "radiance_pct": ["add_pct"]}
# Цены в value: итог не ниже COST_FLOOR базовой (против накопления скидок), затем округление до целого, не меньше 1.
const COSTS := ["unit_cost", "weapon_cost", "repair_cost"]
const COST_FLOOR := 0.2
const NON_NEGATIVE := ["signal_window", "spread"]   # в value не ниже 0

var defs := {}       # id дара -> {name_key, desc_key, stat, target, op, levels, req_sieges, prices, hidden}
var pct := {}        # ключ "stat|target" -> сумма add_pct, в процентах
var mult := {}       # ключ -> произведение mult
var flat := {}       # ключ -> сумма add_flat
var sources: Array = []   # источники модификаторов: [{name, defs, levels}], levels — id -> уровень


func _init(gift_defs := {}) -> void:
	defs = gift_defs


# gifts.json: непустой массив даров {id, name, stat, target, op, levels}; levels — непустой массив чисел (значение уровня n — levels[n - 1]).
# Пара stat / target — из таблицы PAIRS. Для магазина даров, по желанию: req_sieges — сколько осад пройдено для покупки уровня n
# (нет поля — 0, 1, 2, ...), prices — цены уровней в Сиянии (нет поля — пустой массив: цены по умолчанию из radiance.json); длина обоих — как у levels.
# op — из STAT_OPS своего stat. hidden (по желанию, нет поля — false): дар скрыт — хаб его не показывает, build и забег его пропускают.
# Остального по умолчанию нет: чего нет — ошибка. Результат: id -> {name_key, desc_key, stat, target, op, levels, req_sieges, prices, hidden};
# при ошибке push_error и пустой словарь.
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
		if not e.op in STAT_OPS[e.stat]:
			push_error("%s: у дара \"%s\" op \"%s\" недопустим для stat \"%s\"" % [path, e.id, e.op, e.stat])
			return {}
		if not e.get("hidden", false) is bool:
			push_error("%s: у дара \"%s\" поле hidden — не true / false" % [path, e.id])
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
		out[e.id] = {"name_key": e.name_key, "desc_key": e.desc_key, "stat": e.stat, "target": e.target, "op": e.op, "levels": levels, "req_sieges": req, "prices": prices,
			"hidden": e.get("hidden", false)}
	return out


# Источник «дары забега»: defs — дары из gifts.json, levels — id -> уровень (Game.active_gifts).
static func gifts_source(gift_defs: Dictionary, levels: Dictionary) -> Dictionary:
	return {"name": "gifts", "defs": gift_defs, "levels": levels}


# Собрать суммы из активных даров: id -> уровень (целое от 1 до числа уровней дара). Пустой словарь — модификаторов нет.
# Это список источников из одного — даров с defs этого Mods.
func build(active: Dictionary) -> bool:
	return build_sources([gifts_source(defs, active)])


# Собрать суммы по всем источникам списка; другой источник (карточки забега) — ещё один элемент с теми же полями.
# Скрытый дар (hidden) пропускается молча, какой бы ни был уровень. Неизвестный id или уровень вне диапазона — push_error и false (суммы при этом пустые).
func build_sources(list: Array) -> bool:
	sources = list
	pct = {}
	mult = {}
	flat = {}
	var p := {}
	var m := {}
	var f := {}
	for src in list:
		var src_defs: Dictionary = src.defs
		for id in src.levels:
			if not src_defs.has(id):
				push_error("Активный дар \"%s\" (%s): такого нет" % [str(id), src.name])
				return false
			var d: Dictionary = src_defs[id]
			if d.get("hidden", false):
				continue
			var lvl = src.levels[id]
			if not (lvl is float or lvl is int) or lvl != floorf(lvl) or lvl < 1 or lvl > d.levels.size():
				push_error("Активный дар \"%s\" (%s): уровень %s вне 1..%d" % [id, src.name, str(lvl), d.levels.size()])
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


# Целая прибавка к числу base для счётного стата: floor(base * сумма add_pct / 100), но не меньше 1, если процент больше 0, плюс сумма add_flat.
# Без модификаторов 0.
func get_count(stat: String, target: String, base: int) -> int:
	var key := stat + "|" + target
	var p: float = pct.get(key, 0.0)
	var n := 0
	if p > 0.0:
		n = maxi(1, floori(base * p / 100.0 + 1e-9))   # 1e-9: 300 * 15 / 100 не уходит в 44.999...
	return n + int(flat.get(key, 0.0))


# Значение стата на лету: base * (1 + сумма add_pct / 100) * произведение mult + сумма add_flat — тот же порядок, что в _apply_mods
# (множитель get_mult, затем прибавка get_flat). target по умолчанию — единственный допустимый у stat (PAIRS[stat][0]).
# Модификаторов этого ключа нет — base как есть, без ограничений и округления (бит в бит с игрой без даров).
# Есть: цены (COSTS) — не ниже COST_FLOOR * base, округление до целого, не меньше 1; NON_NEGATIVE — не ниже 0.
func value(stat: String, base: float, target := "") -> float:
	var t: String = target if target != "" else PAIRS[stat][0]
	var key := stat + "|" + t
	if not (pct.has(key) or mult.has(key) or flat.has(key)):
		return base
	var v := base * get_mult(stat, t) + get_flat(stat, t)
	if stat in COSTS:
		v = maxf(1.0, roundf(maxf(v, COST_FLOOR * base)))
	elif stat in NON_NEGATIVE:
		v = maxf(v, 0.0)
	return v


# Особые правила (дары с поведением, которого нет в числах): заготовка, пока ни одного.
func has_rule(_id: String) -> bool:
	return false
