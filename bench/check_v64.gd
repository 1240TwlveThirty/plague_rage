extends SceneTree
# Тесты задачи 14: карточки героя 41–45 и гарантированное место в тройке.
# Данные (cards.json, cards_rules.json, иконки, переводы), цель hero в Mods (прежние таблицы не изменились), валидатор;
# 41 — угол и радиус дуги при ударе, 42 — скорость удара, 43 — HP; 44 (hero_low) — порог и снижение урона по герою;
# 45 (hero_near) — расстояние от центра отряда до живого героя, пересчёт раз в 15 тиков; подбор тройки: место героя,
# без повторов, без карточек героя при выключенном герое (и генератор тратится как до задачи), детерминизм.
const MAIN := "res://scripts/main.gd"
const CARDS := preload("res://scripts/cards.gd")
const MODS := preload("res://scripts/mods.gd")
const ICONS := preload("res://scripts/icons.gd")
const FIX := "res://bench/fixtures_hero/"
const DT := 1.0 / 30.0
const HERO_IDS := ["wide_swing", "quick_hands", "commander_temper", "last_bastion", "commander_banner"]
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(ids: Array, mode := 1, rng_seed := 3, path := "", pick := "") -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.card_pick_auto = pick   # "random" — правила выбора без Game (тройка в сцене боя)
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.hero_mode = mode
	if path != "":
		m.hero_path = path
	m.active_cards = ids.map(func(id): return {"id": id})
	m._setup_data()
	return m

func near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-5

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await process_frame
	t_data()
	t_validator()
	t_arc()
	t_rate_hp()
	t_last_bastion()
	t_banner()
	t_offer()
	t_offer_scene()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные карточек героя")
	var defs := CARDS.load_cards("res://data/cards.json")
	var ok := true
	for k in HERO_IDS.size():
		var d: Dictionary = defs.get(HERO_IDS[k], {})
		ok = ok and not d.is_empty() and int(d.num) == 41 + k and d.builds == ["hero"] and CARDS.is_hero(d) and not d.get("disabled", false)
	check("41–45 в cards.json: номера по порядку, билд hero, включены", ok)
	var kinds := HERO_IDS.map(func(id): return defs[id].kind)
	check("типы: 41, 42, 43 — M; 44, 45 — C", kinds == ["M", "M", "M", "C", "C"], str(kinds))
	check("остальные 40 карточек — не героя", defs.keys().filter(func(id): return CARDS.is_hero(defs[id])).size() == 5)
	check("41: arc_angle +40 (add_flat), arc_range +15%", defs.wide_swing.mods == [{"stat": "arc_angle", "target": "hero", "op": "add_flat", "value": 40.0},
		{"stat": "arc_range", "target": "hero", "op": "add_pct", "value": 15.0}])
	check("42: attack_rate hero +20%; 43: hp hero +50%", defs.quick_hands.mods == [{"stat": "attack_rate", "target": "hero", "op": "add_pct", "value": 20.0}]
		and defs.commander_temper.mods == [{"stat": "hp", "target": "hero", "op": "add_pct", "value": 50.0}])
	check("44: hero_low frac 0.4, damage_taken hero −30%", defs.last_bastion.when == {"cond": "hero_low", "frac": 0.4}
		and defs.last_bastion.mods == [{"stat": "damage_taken", "target": "hero", "op": "add_pct", "value": -30.0}])
	var hd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	check("45: hero_near без параметров в карточке, радиус — hero.json hero_near_radius %s (> 0), attack_rate all_units +15%%" % hd.get("hero_near_radius"),
		defs.commander_banner.when == {"cond": "hero_near"} and float(hd.get("hero_near_radius", 0)) > 0.0
		and defs.commander_banner.mods == [{"stat": "attack_rate", "target": "all_units", "op": "add_pct", "value": 15.0}])
	var names := {}
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		var own := tr("CARD_LAST_BASTION_NAME")
		var dup := defs.keys().filter(func(id): return id != "last_bastion" and tr(defs[id].name_key) == own)
		names[loc] = own
		check("44 на %s: «%s», ни с одной карточкой не совпадает" % [loc, own], own == ("Из последних сил" if loc == "ru" else "Against the Odds") and dup.is_empty(), str(dup))
	TranslationServer.set_locale("ru")
	var m0 := make([])
	m0._load_hero()
	var desc: String = CARDS.fill_desc(tr("CARD_COMMANDER_BANNER_DESC"))
	check("описание 45 и подсказка условия — с радиусом из hero.json (%s)" % desc, ("%d px" % int(m0.hero_near_r)) in desc and not "{" in desc
		and ("%d" % int(m0.hero_near_r)) in m0.cond_text({"cond": "hero_near"}) and m0.hero_near_r == float(hd.hero_near_radius))
	m0.free()
	var rules := CARDS.load_rules("res://data/cards_rules.json")
	check("cards_rules.json: hero_guaranteed_slots 1, прежние поля те же", rules.get("hero_guaranteed_slots") == 1 and rules.offer_count == 3
		and rules.pick_build_continue_chance == 0.5 and Array(rules.pick_after_waves) == [2, 5, 8])
	var icons := HERO_IDS.map(func(id): return ICONS.of_card(id))
	check("иконки: range, reload, heart, shield, horn", icons == ["range", "reload", "heart", "shield", "horn"], str(icons))
	var tr_ok := true
	for id in HERO_IDS:
		tr_ok = tr_ok and CARDS.has_key(defs[id].name_key) and CARDS.has_key(defs[id].desc_key)
	check("тексты ru/en: CARD_<ID>_NAME / _DESC, условия COND_HERO_LOW / COND_HERO_NEAR, билд UI_BUILD_HERO", tr_ok and CARDS.has_key("COND_HERO_LOW")
		and CARDS.has_key("COND_HERO_NEAR") and CARDS.has_key("UI_BUILD_HERO"))
	check("Mods: цель hero; прежние пары и операции не изменились (hp, attack_rate — с hero в конце; damage, speed без hero)",
		"hero" in MODS.TARGETS and MODS.PAIRS.hp == ["all_units", "infantry", "archer", "spearman", "hero"] and MODS.PAIRS.attack_rate == ["all_units", "infantry", "archer", "hero"]
		and MODS.PAIRS.damage == ["all_units", "infantry", "archer", "spearman"] and MODS.STAT_OPS.attack_rate == ["add_pct"] and MODS.STAT_OPS.hp == ["add_pct", "mult"]
		and MODS.PAIRS.arc_angle == ["hero"] and MODS.PAIRS.arc_range == ["hero"] and MODS.STAT_OPS.arc_angle == ["add_flat"] and MODS.STAT_OPS.arc_range == ["add_pct"])

# Временный cards.json из одной карточки (поверх файла): загрузка должна отказать.
func bad_card(e: Dictionary) -> bool:
	var base := {"id": "x", "num": 1, "name_key": "CARD_PURSE_NAME", "desc_key": "CARD_PURSE_DESC", "builds": ["common"], "kind": "M", "mods": []}
	base.merge(e, true)
	var path := "user://cards_v64_bad.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify([base]))
	f.close()
	var out := CARDS.load_cards(path)
	DirAccess.remove_absolute(path)
	return out.is_empty()

func bad_rules(hs: Variant) -> bool:
	var path := "user://cards_rules_v64_bad.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"pick_after_waves": [2], "offer_count": 3, "pick_build_continue_chance": 0.5, "hero_guaranteed_slots": hs}))
	f.close()
	var out := CARDS.load_rules(path)
	DirAccess.remove_absolute(path)
	return out.is_empty()

func t_validator() -> void:
	print("валидатор (ниже ожидаются строки ERROR)")
	check("цель hero в карточке не билда hero — ошибка", bad_card({"mods": [{"stat": "hp", "target": "hero", "op": "add_pct", "value": 10}]}))
	check("билд hero без цели hero и условия hero_* — ошибка", bad_card({"builds": ["hero"], "mods": [{"stat": "hp", "target": "infantry", "op": "add_pct", "value": 10}]}))
	check("damage_taken у карточки M — ошибка", bad_card({"builds": ["hero"], "mods": [{"stat": "damage_taken", "target": "hero", "op": "add_pct", "value": -10}]}))
	check("hero_low с модификатором не damage_taken — ошибка", bad_card({"builds": ["hero"], "kind": "C", "when": {"cond": "hero_low", "frac": 0.4},
		"mods": [{"stat": "hp", "target": "hero", "op": "add_pct", "value": 10}]}))
	check("hero_low frac больше 1 — ошибка", bad_card({"builds": ["hero"], "kind": "C", "when": {"cond": "hero_low", "frac": 1.5},
		"mods": [{"stat": "damage_taken", "target": "hero", "op": "add_pct", "value": -10}]}))
	check("hero_near с radius в карточке (радиус теперь в hero.json) — ошибка", bad_card({"builds": ["hero"], "kind": "C", "when": {"cond": "hero_near", "radius": 150},
		"mods": [{"stat": "attack_rate", "target": "all_units", "op": "add_pct", "value": 10}]}))
	check("arc_angle add_pct (только add_flat) — ошибка", bad_card({"builds": ["hero"], "mods": [{"stat": "arc_angle", "target": "hero", "op": "add_pct", "value": 10}]}))
	check("hero_guaranteed_slots: -1, 1.5, 4 (больше offer_count) — ошибка", bad_rules(-1) and bad_rules(1.5) and bad_rules(4))

# n зомби с большим HP (не умирают), позиции задаются тестом.
func zombies(m: Node2D, n: int) -> Array:
	var out := []
	for k in n:
		out.append(m.count)
		m._spawn_zombie(Vector2(5.0 + k, 5.0), m.zombie_type)
		m.hp[m.count - 1] = 1000.0
	return out

func swing(m: Node2D) -> void:
	m.cooldown[m.hero_idx] = 0.0
	m.hero_attack_in = true
	m.hero_move = Vector2.ZERO
	m.hero_face_in = NAN
	m._build_grid()
	m._update_hero(DT)
	m.hero_attack_in = false

# Зомби под углом (от взгляда героя вверх) и на расстоянии; задет ли он ударом.
func hit_at(ids: Array, ang_deg: float, dist: float) -> bool:
	var m := make(ids)
	var h: int = m.hero_idx
	m.hero_face_ang = -PI / 2.0
	var z := zombies(m, 1)
	m.pos[z[0]] = m.pos[h] + Vector2.from_angle(-PI / 2.0 + deg_to_rad(ang_deg)) * dist
	swing(m)
	var hit: bool = m.hp[z[0]] < 1000.0
	m.free()
	return hit

func t_arc() -> void:
	print("41 «Широкий замах»: дуга читается из Mods при ударе")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	var a0: float = d.arc_angle
	var r0: float = d.arc_range
	var m := make(["wide_swing"])
	var p := make([])
	check("угол %.0f° -> %.0f°, радиус x%.2f; без карточки — данные как есть (%.0f°, x1)" % [a0, m.hero_arc_angle(), m.hero_range_mult(), p.hero_arc_angle()],
		near(m.hero_arc_angle(), minf(a0 + 40.0, 360.0)) and near(m.hero_range_mult(), 1.15) and p.hero_arc_angle() == a0 and p.hero_range_mult() == 1.0)
	check("тип героя (дальность в таблице) не меняется: радиус — только при ударе", m.type_range_sq[m.hero_type] == p.type_range_sq[p.hero_type])
	m.free()
	p.free()
	var side := minf(a0 / 2.0 + 10.0, 179.0)   # за краем старой дуги, внутри новой
	check("зомби на %.0f° от взгляда, в 0.6 радиуса: без карточки не задет, с карточкой задет" % side,
		not hit_at([], side, r0 * 0.6) and hit_at(["wide_swing"], side, r0 * 0.6))
	check("зомби прямо по взгляду в 1.1 радиуса: без карточки не задет, с карточкой (x1.15) задет; в 1.2 — не задет и с ней",
		not hit_at([], 0.0, r0 * 1.1) and hit_at(["wide_swing"], 0.0, r0 * 1.1) and not hit_at(["wide_swing"], 0.0, r0 * 1.2))

func t_rate_hp() -> void:
	print("42 «Быстрые руки», 43 «Закалка командира»")
	var p := make([])
	var q := make(["quick_hands"])
	var h: int = p.hero_type
	check("42: интервал удара %.4f = %.4f / 1.2; у пехоты и лучников без изменений" % [q.type_cooldown[h], p.type_cooldown[h]], near(q.type_cooldown[h], p.base_type_cooldown[h] / 1.2)
		and q.type_cooldown[q.infantry_type] == p.type_cooldown[p.infantry_type] and q.type_cooldown[q.archer_type] == p.type_cooldown[p.archer_type])
	var both := make(["quick_hands", "long_spears"])
	check("42 + №27 (attack_rate all_units +15%): проценты складываются — интервал / 1.35", near(both.type_cooldown[h], p.base_type_cooldown[h] / 1.35))
	both.free()
	var z := zombies(q, 1)
	q.pos[z[0]] = q.pos[q.hero_idx] + Vector2(0, -8)
	q.hero_face_ang = -PI / 2.0
	q.hero_feed = func(_t): return {"move": Vector2.ZERO, "attack": true, "face": -PI / 2.0}
	var swings := 0
	for t in 300:
		q._physics_process(DT)
	swings = q.hero_swing_n
	var pz := zombies(p, 1)
	p.pos[pz[0]] = p.pos[p.hero_idx] + Vector2(0, -8)
	p.hero_feed = func(_t): return {"move": Vector2.ZERO, "attack": true, "face": -PI / 2.0}
	for t in 300:
		p._physics_process(DT)
	var k := float(swings) / maxf(float(p.hero_swing_n), 1.0)
	check("удержание J 10 с: ударов %d против %d без карточки (x%.2f, около 1.2)" % [swings, p.hero_swing_n, k], k > 1.12 and k < 1.28)
	q.free()
	var t := make(["commander_temper"])
	check("43: HP героя %.1f = %.1f x 1.5, герой появился с полным HP; HP пехоты прежнее" % [t.type_hp[h], p.base_type_hp[h]], near(t.type_hp[h], p.base_type_hp[h] * 1.5)
		and near(t.hp[t.hero_idx], t.type_hp[h]) and t.type_hp[t.infantry_type] == p.type_hp[p.infantry_type])
	t.free()
	p.free()

func t_last_bastion() -> void:
	print("44 «Последний рубеж» (hero_low): порог 40%, урон по герою −30%")
	var m := make(["last_bastion"])
	m._start_wave()
	var h: int = m.hero_idx
	var mx: float = m.type_hp[m.hero_type]
	m.hp[h] = 0.41 * mx
	m._update_card_conditions()
	check("HP 41%: не действует (множитель 1.0, индикатор выключен)", m.hero_taken_mult == 1.0 and not m.card_state.last_bastion.on)
	m.hp[h] = 0.4 * mx
	m._update_card_conditions()
	check("HP ровно 40%: не действует (условие «ниже 40%»)", m.hero_taken_mult == 1.0)
	m.hp[h] = 0.39 * mx
	m._update_card_conditions()
	check("HP 39%%: урон по герою x%.2f, индикатор включён; отряды не задеты" % m.hero_taken_mult, near(m.hero_taken_mult, 0.7) and m.card_state.last_bastion.on
		and m.squad_taken_mult[0] == 1.0 and m.squad_rate_mult[0] == 1.0)
	m.hp[h] = 0.8 * mx
	m._update_card_conditions()
	check("HP снова 80%: снова 1.0", m.hero_taken_mult == 1.0)
	m.free()
	var a := lost(["last_bastion"])
	var b := lost([])
	check("зомби бьёт героя с HP 30%% 3 с: потеря %.3f с карточкой = 0.7 x %.3f без неё" % [a, b], b > 0.0 and absf(a - 0.7 * b) < 1e-3 * b)
	var c := lost(["last_bastion"], 0.9)
	var e := lost([], 0.9)
	check("с HP 90%%: потеря та же, что без карточки (%.3f)" % c, c == e and c > 0.0)

# Герой с долей HP frac стоит, рядом зомби с большим HP; сколько HP герой потерял за 3 с (условия — в начале волны и раз в 15 тиков).
# После каждого тика HP героя возвращается к доле frac: потеря не зависит от баланса (порог не пересекается, герой не гибнет).
func lost(ids: Array, frac := 0.3) -> float:
	var m := make(ids, 1, 5)
	m.hero_feed = func(_t): return Vector2.ZERO
	for i in m.count:
		if m.team[i] == 1:
			m.hp[i] = 0.0
	m._remove_dead()
	var z := zombies(m, 1)
	m.pos[m.hero_idx] = Vector2(500, 500)
	m.pos[z[0]] = Vector2(508, 500)
	m.wave_state = m.WS_BATTLE
	m._prepare_cards()
	var h0: float = frac * m.type_hp[m.hero_type]
	m.hp[m.hero_idx] = h0
	m._update_card_conditions()
	var out := 0.0
	for t in 90:
		m._physics_process(DT)
		out += h0 - m.hp[m.hero_idx]
		m.hp[m.hero_idx] = h0
		m.pos[z[0]] = m.pos[m.hero_idx] + Vector2(8, 0)
		m.hp[z[0]] = 1000.0
	m.free()
	return out

func t_banner() -> void:
	var m := make(["commander_banner"])
	var r: float = m.hero_near_r
	print("45 «Знамя командира» (hero_near): центр отряда ближе hero_near_radius (%s px) к живому герою" % r)
	m._start_wave()
	var h: int = m.hero_idx
	var c0: Vector2 = m.squad_pos[0]
	m.pos[h] = c0 + Vector2(r - 1.0, 0)
	m._update_card_conditions()
	var in0: float = m.squad_rate_mult[0]
	var arch: float = m.squad_rate_mult[1]
	check("пехота: центр в radius − 1 px — скорость боя x%.2f, индикатор +15%%" % in0, near(in0, 1.15) and m.card_state.commander_banner.on and near(m.card_state.commander_banner.pct, 15.0))
	m.pos[h] = c0 + Vector2(r + 1.0, 0)
	m._update_card_conditions()
	check("radius + 1 px — не действует", m.squad_rate_mult[0] == 1.0)
	m.hero_near_r = r * 2.0
	m._update_card_conditions()
	check("радиус вдвое больше (как из hero.json) — снова действует", near(m.squad_rate_mult[0], 1.15))
	m.hero_near_r = r
	m.pos[h] = m.squad_pos[1] + Vector2(0, 100)
	m._update_card_conditions()
	var far0: bool = m.squad_pos[0].distance_to(m.pos[h]) >= r
	check("герой у лучников (100 px от их центра): лучники x1.15%s" % ("" if far0 else ", пехота тоже рядом"), near(m.squad_rate_mult[1], 1.15) and (not far0 or m.squad_rate_mult[0] == 1.0))
	m.hp[h] = 0.0
	m._update_card_conditions()
	check("герой с HP 0 (ещё не удалён) — не живой: не действует", m.squad_rate_mult[1] == 1.0)
	m._remove_dead()
	m._update_card_conditions()
	check("героя нет (пал, hero_idx -1) — не действует", m.hero_idx == -1 and m.squad_rate_mult[1] == 1.0)
	m.free()
	# Пересчёт раз в 15 тиков: герой подходит сразу после пересчёта — множитель меняется только на тике, кратном 15.
	var n := make(["commander_banner"])
	n._start_wave()
	n.hero_feed = func(_t): return Vector2.ZERO
	n.pos[n.hero_idx] = n.squad_pos[0] + Vector2(400, 0)
	n._update_card_conditions()   # в начале волны герой у ворот мог быть рядом с пехотой: множитель с этого места — 1.0
	n._physics_process(DT)
	while (n.tick_counter + 1) % n.COND_EVERY != 1:
		n._physics_process(DT)
	n.pos[n.hero_idx] = n.squad_pos[0] + Vector2(20, 0)
	var changes := []
	for k in n.COND_EVERY:
		n._physics_process(DT)
		changes.append(n.squad_rate_mult[0] != 1.0)
	check("герой подошёл сразу после пересчёта: множитель меняется только на тике, кратном 15 (через %d тиков)" % (changes.find(true) + 1),
		changes.count(true) == 1 and changes[-1] and n.tick_counter % n.COND_EVERY == 0)
	n.free()
	var p := make([], -1)
	check("без героя (hero_mode -1) карточка не нужна: pool без карточек героя (см. ниже), условие не выполняется", p.hero_idx == -1 and p.cond_factor("hero_near", {"cond": "hero_near"}, 0) == 0.0)
	p.free()

func t_offer() -> void:
	print("подбор тройки (CARDS.offer)")
	var defs := CARDS.load_cards("res://data/cards.json")
	var rules := CARDS.load_rules("res://data/cards_rules.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var ok := true
	var dup := false
	var hero_any := false
	var all_ids := CARDS.active_ids(defs)
	for k in 1000:
		var owned := []   # случайный набор взятых: 0–3 карточки героя и 0–6 прочих (генератор теста, отдельный)
		var hs := HERO_IDS.duplicate()
		var n_h := k % 4
		for i in n_h:
			owned.append({"id": hs.pop_at((k * 7 + i * 3) % hs.size())})
		for i in k % 7:
			var id: String = all_ids[(k * 13 + i * 5) % all_ids.size()]
			if not CARDS.is_hero(defs[id]) and not owned.any(func(r): return r.id == id):
				owned.append({"id": id})
		var o := CARDS.offer(defs, owned, rules, rng, true)
		var heroes := o.filter(func(id): return CARDS.is_hero(defs[id]))
		ok = ok and o.size() == 3 and heroes.size() >= 1 and not o.any(func(id): return owned.any(func(r): return r.id == id))
		dup = dup or o.size() != _distinct(o)
		var off := CARDS.offer(defs, owned.filter(func(r): return not CARDS.is_hero(defs[r.id])), rules, rng, false)
		hero_any = hero_any or off.any(func(id): return CARDS.is_hero(defs[id])) or off.size() != 3
	check("герой включён, 1000 троек (0–3 карточки героя и до 6 прочих уже взяты): в каждой 3 карточки, из них хотя бы одна героя, взятых нет", ok)
	check("повторов в тройке нет", not dup)
	check("герой выключен, 1000 троек: карточек героя нет ни разу, по 3", not hero_any)
	var four := HERO_IDS.slice(0, 4).map(func(id): return {"id": id})
	var last_ok := true
	for k in 200:
		var o := CARDS.offer(defs, four, rules, rng, true)
		last_ok = last_ok and "commander_banner" in o and o.size() == 3
	check("взяты 4 карточки героя: пятая (45) в каждой тройке", last_ok)
	var five := HERO_IDS.map(func(id): return {"id": id})
	var none_ok := true
	for k in 200:
		var o := CARDS.offer(defs, five, rules, rng, true)
		none_ok = none_ok and o.size() == 3 and not o.any(func(id): return CARDS.is_hero(defs[id])) and _distinct(o.map(func(id): return defs[id].builds[0])) == 3
	check("взяты все 5 карточек героя: тройка из общего пула, как раньше (3 разных билда)", none_ok)
	# Герой выключен: генератор тратится как до задачи 14 — тройки те же, что с пулом без карточек героя.
	var old_defs := {}
	for id in defs:
		if not CARDS.is_hero(defs[id]):
			old_defs[id] = defs[id]
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	var same := true
	for s in [1, 2, 3, 7, 11]:
		r1.seed = s
		r2.seed = s
		var owned := [{"id": "purse"}] if s % 2 == 1 else []
		for k in 50:
			same = same and CARDS.offer(defs, owned, rules, r1, false) == CARDS.offer(old_defs, owned, rules, r2) and r1.state == r2.state
	check("герой выключен: тройки и состояние генератора те же, что у пула без карточек героя (5 seed x 50 троек)", same)
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	var det := true
	for k in 100:
		det = det and CARDS.offer(defs, [{"id": "purse"}], rules, a, true) == CARDS.offer(defs, [{"id": "purse"}], rules, b, true)
	check("детерминизм: тот же seed генератора забега — те же 100 троек с героем", det)
	var r0 := rules.duplicate()
	r0.hero_guaranteed_slots = 0
	var c1 := RandomNumberGenerator.new()
	c1.seed = 5
	var zero_ok := true
	var no_hero := 0
	for k in 300:
		var x := CARDS.offer(defs, [], r0, c1, true)
		zero_ok = zero_ok and x.size() == 3 and _distinct(x) == 3
		if not x.any(func(id): return CARDS.is_hero(defs[id])):
			no_hero += 1
	check("hero_guaranteed_slots 0: место не резервируется — без карточки героя %d троек из 300" % no_hero, zero_ok and no_hero > 0)

func _distinct(a: Array) -> int:
	var d := {}
	for x in a:
		d[x] = true
	return d.size()

# Сцена боя: после волны из pick_after_waves тройка на генераторе забега бенча; с героем — карточка героя в тройке.
func offer_in_scene(mode: int, rng_seed: int, path := "") -> Array:
	var m := make([], mode, 3, path, "random")
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	m.bench_card_rng = rng
	m.wave_number = 2
	m._offer_cards()
	var o: Array = m.pending_offer.duplicate()
	m.free()
	return o

func t_offer_scene() -> void:
	print("тройка в сцене боя (_offer_cards)")
	var defs := CARDS.load_cards("res://data/cards.json")
	var ok := true
	var off_ok := true
	for s in range(1, 21):
		var o := offer_in_scene(1, s)
		ok = ok and o.size() == 3 and o.any(func(id): return CARDS.is_hero(defs[id]))
		var f := offer_in_scene(-1, s)
		off_ok = off_ok and f.size() == 3 and not f.any(func(id): return CARDS.is_hero(defs[id]))
	check("после волны 2, seed 1–20: с героем (hero_mode 1) карточка героя в каждой тройке", ok)
	check("без героя (hero_mode -1) карточек героя нет", off_ok)
	var dis_ok := true
	for s in range(1, 11):
		var o := offer_in_scene(0, s, FIX + "disabled.json")
		dis_ok = dis_ok and o.size() == 3 and not o.any(func(id): return CARDS.is_hero(defs[id]))
	check("hero.json enabled false: карточек героя нет", dis_ok)
	check("детерминизм: тот же seed — та же тройка", offer_in_scene(1, 7) == offer_in_scene(1, 7))
