extends RefCounted
# Временные карточки забега: данные (data/cards.json, data/cards_rules.json), проверка при загрузке, источник модификаторов для Mods,
# разовый эффект при выборе и подбор тройки для экрана выбора. Генератор — только Game.run_rng (или переданный бенчем), не ГСЧ симуляции.
# kind: M — модификаторы действуют всегда; C — по условию when, считаются на уровне отряда (main.gd, _update_card_conditions);
# K — особые (special, on_pick). Издержка — модификатор с "cost": true: она действует всегда, и у карточек C тоже (не только при условии).
const MODS := preload("res://scripts/mods.gd")
const KINDS := ["M", "C", "K"]
const BUILDS := ["shield", "archers", "gold", "risk", "common"]
# Условия карточек C и их параметры (числа)
const CONDS := {"hold": [], "retreat": [], "gate_low": ["frac"], "squad_low": ["frac"], "wave_time": ["seconds"], "gold_high": ["gold"], "lost_steps": ["step_pct", "max_steps"]}
const COND_STATS := ["damage", "hp", "speed"]   # что может давать условие: множитель урона, получаемого урона (hp), скорости отряда
const SPECIALS := ["vengeance", "gate_attack"]
const FIELDS := ["id", "num", "name_key", "desc_key", "builds", "kind", "mods", "when", "on_pick", "special", "per_unit_pct", "max_pct", "disabled", "disabled_reason"]


static func _num(v: Variant) -> bool:
	return v is float or v is int


static func _err(path: String, id: String, text: String) -> Dictionary:
	push_error("%s: карточка \"%s\": %s" % [path, id, text])
	return {}


# Ключ перевода есть в ru и en (таблица data/translations.csv, импортированные .translation).
static func has_key(key: String) -> bool:
	for loc in ["ru", "en"]:
		var t: Translation = TranslationServer.get_translation_object(loc)
		if t == null or String(t.get_message(key)) == "":
			return false
	return true


# Модификатор {stat, target, op, value[, cost]}: stat, target и op из таблиц Mods. Ошибка — текст, иначе "".
static func check_mod(e: Variant) -> String:
	if not e is Dictionary:
		return "модификатор не объект"   # tr-skip: текст ошибки загрузки (лог)
	for k in e:
		if not k in ["stat", "target", "op", "value", "cost"]:
			return "у модификатора неизвестное поле \"%s\"" % k   # tr-skip: текст ошибки загрузки (лог)
	if not e.get("stat") is String or not e.stat in MODS.STATS:
		return "неизвестный stat \"%s\"" % str(e.get("stat"))   # tr-skip: текст ошибки загрузки (лог)
	if not e.get("target") is String or not e.target in MODS.PAIRS[e.stat]:
		return "недопустимая цель \"%s\" для stat \"%s\"" % [str(e.get("target")), e.stat]   # tr-skip: текст ошибки загрузки (лог)
	if not e.get("op") is String or not e.op in MODS.STAT_OPS[e.stat]:
		return "недопустимая операция \"%s\" для stat \"%s\"" % [str(e.get("op")), e.stat]   # tr-skip: текст ошибки загрузки (лог)
	if not _num(e.get("value")):
		return "у модификатора %s нет числа value" % e.stat   # tr-skip: текст ошибки загрузки (лог)
	if e.has("cost") and not e.cost is bool:
		return "поле cost — не true / false"   # tr-skip: текст ошибки загрузки (лог)
	return ""


# cards.json: непустой массив карточек. Проверяется всё: поля, ключи перевода (ru и en), билды, тип, модификаторы, условия, особые эффекты.
# Результат: id -> карточка (порядок файла); при ошибке push_error с понятным текстом и пустой словарь.
static func load_cards(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: %s" % path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Array or data.is_empty():
		push_error("%s: ожидается непустой JSON-массив карточек" % path)
		return {}
	var out := {}
	for e in data:
		if not e is Dictionary or not e.get("id") is String or e.id == "":
			push_error("%s: карточка без строкового поля id" % path)
			return {}
		var id: String = e.id
		if out.has(id):
			return _err(path, id, "id повторяется")   # tr-skip: текст ошибки загрузки (лог)
		for k in e:
			if not k in FIELDS:
				return _err(path, id, "неизвестное поле \"%s\"" % k)   # tr-skip: текст ошибки загрузки (лог)
		for k in ["name_key", "desc_key"]:
			if not e.get(k) is String:
				return _err(path, id, "нет строкового поля %s" % k)   # tr-skip: текст ошибки загрузки (лог)
			if not has_key(e[k]):
				return _err(path, id, "ключа перевода %s нет в data/translations.csv (ru и en)" % e[k])   # tr-skip: текст ошибки загрузки (лог)
		if not e.get("builds") is Array or e.builds.is_empty():
			return _err(path, id, "нет непустого массива builds")   # tr-skip: текст ошибки загрузки (лог)
		for b in e.builds:
			if not b is String or not b in BUILDS:
				return _err(path, id, "неизвестный билд \"%s\" (допустимы %s)" % [str(b), ", ".join(BUILDS)])   # tr-skip: текст ошибки загрузки (лог)
		if not e.get("kind") is String or not e.kind in KINDS:
			return _err(path, id, "kind — не M, C или K")   # tr-skip: текст ошибки загрузки (лог)
		if not e.get("mods") is Array:
			return _err(path, id, "нет массива mods")   # tr-skip: текст ошибки загрузки (лог)
		for mod in e.mods:
			var why := check_mod(mod)
			if why != "":
				return _err(path, id, why)
		if e.has("disabled") and not e.disabled is bool:
			return _err(path, id, "поле disabled — не true / false")   # tr-skip: текст ошибки загрузки (лог)
		if e.get("disabled", false) and not (e.get("disabled_reason") is String and e.disabled_reason != ""):
			return _err(path, id, "disabled без причины disabled_reason")   # tr-skip: текст ошибки загрузки (лог)
		if e.kind == "C":
			var w = e.get("when")
			if not w is Dictionary or not w.get("cond") is String or not CONDS.has(w.cond):
				return _err(path, id, "у карточки C нет условия when.cond из %s" % ", ".join(CONDS.keys()))   # tr-skip: текст ошибки загрузки (лог)
			for k in w:
				if k != "cond" and not k in CONDS[w.cond]:
					return _err(path, id, "у условия %s неизвестный параметр \"%s\"" % [w.cond, k])   # tr-skip: текст ошибки загрузки (лог)
			for k in CONDS[w.cond]:
				if not _num(w.get(k)) or w[k] <= 0:
					return _err(path, id, "у условия %s нет числа %s больше 0" % [w.cond, k])   # tr-skip: текст ошибки загрузки (лог)
			if w.cond in ["gate_low", "squad_low"] and w.frac > 1.0:
				return _err(path, id, "у условия %s frac больше 1" % w.cond)   # tr-skip: текст ошибки загрузки (лог)
			for mod in e.mods:
				if not mod.get("cost", false) and (not mod.stat in COND_STATS or mod.op != "add_pct" or not mod.target in ["all_units", "infantry", "archer"]):
					return _err(path, id, "условный модификатор %s %s %s: условие даёт только add_pct к %s" % [mod.stat, mod.target, mod.op, ", ".join(COND_STATS)])   # tr-skip: текст ошибки загрузки (лог)
		elif e.has("when"):
			return _err(path, id, "условие when бывает только у карточек C")   # tr-skip: текст ошибки загрузки (лог)
		if e.has("special"):
			if e.kind != "K" or not e.special is String or not e.special in SPECIALS:
				return _err(path, id, "special бывает только у K и только %s" % ", ".join(SPECIALS))   # tr-skip: текст ошибки загрузки (лог)
			if e.special == "vengeance" and not (_num(e.get("per_unit_pct")) and _num(e.get("max_pct")) and e.per_unit_pct > 0 and e.max_pct > 0):
				return _err(path, id, "у vengeance нет чисел per_unit_pct и max_pct больше 0")   # tr-skip: текст ошибки загрузки (лог)
		if e.has("on_pick"):
			var why := _check_on_pick(e.on_pick)
			if why != "":
				return _err(path, id, why)
		if e.kind == "K" and not e.has("special") and not e.has("on_pick"):
			return _err(path, id, "у карточки K нет special или on_pick")   # tr-skip: текст ошибки загрузки (лог)
		out[id] = e
	return out


static func _check_on_pick(o: Variant) -> String:
	if not o is Dictionary or o.size() != 1:
		return "on_pick — объект с одним эффектом (grant_units или random_split)"   # tr-skip: текст ошибки загрузки (лог)
	if o.has("grant_units"):
		return "" if _num(o.grant_units) and o.grant_units >= 1 and o.grant_units == floorf(o.grant_units) else "grant_units — целое не меньше 1"   # tr-skip: текст ошибки загрузки (лог)
	if o.has("random_split"):
		var r = o.random_split
		if not r is Dictionary or not r.get("stat") is String or not r.stat in ["damage", "hp", "speed"] or not r.get("targets") is Array or r.targets.size() != 2:
			return "random_split: нужны stat (damage, hp, speed) и два targets"   # tr-skip: текст ошибки загрузки (лог)
		for t in r.targets:
			if not t is String or not t in MODS.PAIRS[r.stat]:
				return "random_split: недопустимая цель \"%s\"" % str(t)   # tr-skip: текст ошибки загрузки (лог)
		if not (_num(r.get("good")) and _num(r.get("bad")) and r.good > 0 and r.bad > 0):
			return "random_split: нужны числа good и bad больше 0"   # tr-skip: текст ошибки загрузки (лог)
		return ""
	return "on_pick: неизвестный эффект \"%s\"" % str(o.keys()[0])   # tr-skip: текст ошибки загрузки (лог)


# cards_rules.json: pick_after_waves — непустой массив возрастающих целых от 1; offer_count — целое от 1; pick_build_continue_chance — 0..1.
static func load_rules(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: %s" % path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		push_error("%s: ожидается JSON-объект" % path)
		return {}
	var waves := PackedInt32Array()
	if d.get("pick_after_waves") is Array:
		for v in d.pick_after_waves:
			if not _num(v) or v != floorf(v) or v < 1 or (not waves.is_empty() and v <= waves[-1]):
				waves.clear()
				break
			waves.append(int(v))
	if waves.is_empty():
		push_error("%s: pick_after_waves — непустой массив возрастающих целых от 1" % path)
		return {}
	var n = d.get("offer_count")
	if not _num(n) or n != floorf(n) or n < 1:
		push_error("%s: offer_count — целое от 1" % path)
		return {}
	var c = d.get("pick_build_continue_chance")
	if not _num(c) or c < 0.0 or c > 1.0:
		push_error("%s: pick_build_continue_chance — число от 0 до 1" % path)
		return {}
	return {"pick_after_waves": waves, "offer_count": int(n), "pick_build_continue_chance": float(c)}


# Источник модификаторов для Mods.build_sources по выбранным карточкам (записи {id[, result]}): модификаторы M и K,
# издержки всех карточек (и C); условные модификаторы C сюда не входят (их считает сцена боя по отрядам).
# random_split (карточка 30) — по результату в записи: mult good у одной цели, bad у другой.
static func source(defs: Dictionary, records: Array) -> Dictionary:
	var list := []
	for r in records:
		var d: Dictionary = defs.get(r.id, {})
		if d.is_empty() or d.get("disabled", false):
			continue
		for mod in d.mods:
			if d.kind != "C" or mod.get("cost", false):
				list.append(mod)
		if r.has("result"):
			var sp: Dictionary = d.on_pick.random_split
			list.append({"stat": sp.stat, "target": r.result.good, "op": "mult", "value": sp.good})
			list.append({"stat": sp.stat, "target": r.result.bad, "op": "mult", "value": sp.bad})
	return {"name": "cards", "mods": list}


# Запись выбранной карточки: {id}; для random_split генератор забега выбирает, какой цели good (результат хранится в записи).
static func make_record(d: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var r := {"id": d.id}
	if d.has("on_pick") and d.on_pick.has("random_split"):
		var t: Array = d.on_pick.random_split.targets
		var k := rng.randi_range(0, 1)
		r["result"] = {"good": t[k], "bad": t[1 - k]}
	return r


# Активные (не disabled) карточки в порядке файла.
static func active_ids(defs: Dictionary) -> Array:
	return defs.keys().filter(func(id): return not defs[id].get("disabled", false))


# Тройка для выбора: без повторов и уже выбранных, без disabled; основные билды (первый тег builds) разные;
# с вероятностью pick_build_continue_chance одна карточка продолжает основной билд, в котором у игрока уже есть карточка (если такая найдётся);
# разных билдов не хватает — добор из оставшихся. Генератор — переданный (Game.run_rng).
static func offer(defs: Dictionary, records: Array, rules: Dictionary, rng: RandomNumberGenerator) -> Array:
	var taken := records.map(func(r): return r.id)
	var pool := active_ids(defs).filter(func(id): return not id in taken)
	var owned := {}
	for id in taken:
		if defs.has(id):
			owned[defs[id].builds[0]] = true
	var out := []
	var used := {}
	if not owned.is_empty() and rng.randf() < rules.pick_build_continue_chance:
		var cont := pool.filter(func(id): return owned.has(defs[id].builds[0]))
		if not cont.is_empty():
			var id: String = cont[rng.randi_range(0, cont.size() - 1)]
			out.append(id)
			used[defs[id].builds[0]] = true
	while out.size() < rules.offer_count:
		var cand := pool.filter(func(id): return not id in out and not used.has(defs[id].builds[0]))
		if cand.is_empty():
			cand = pool.filter(func(id): return not id in out)
		if cand.is_empty():
			break
		var id: String = cand[rng.randi_range(0, cand.size() - 1)]
		out.append(id)
		used[defs[id].builds[0]] = true
	return out
