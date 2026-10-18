extends SceneTree
# Тесты задачи 6d, этап D: в данных урон заменён скоростью боя. «Оружие» (shop.json stat attack_rate), «Закалённая сталь» (infantry),
# карточки №1 (infantry), 2, 17, 25, 27, 36, 37 (all_units), издержки №7 (archer), 31 и 33 (infantry) — attack_rate с прежними процентами;
# №3 и «Меткие стрелки» — по абляции v9 (STAT_3, STAT_MARKSMEN); №24 и №30 остаются на уроне. Валидатор, тексты ru и en.
const MAIN := "res://scripts/main.gd"
const CARDS := preload("res://scripts/cards.gd")
const STAT_3 := "damage"          # №3 «Зазубренные стрелы»: выбор этапа D по bench/card_ablation_v5.txt
const STAT_MARKSMEN := "damage"   # «Меткие стрелки»: выбор этапа D по bench/gift_ablation_v9.txt
# id -> [stat, target, value, издержка]
const WANT := {
	"meteor_blades": ["attack_rate", "infantry", 12, false], "silver_vs_dead": ["attack_rate", "all_units", 10, false],
	"last_stand": ["attack_rate", "all_units", 25, false], "desperate_charge": ["attack_rate", "all_units", 25, false],
	"long_spears": ["attack_rate", "all_units", 15, false], "reserve_fund": ["attack_rate", "all_units", 10, false],
	"blood_for_blood": ["attack_rate", "all_units", 5, false], "long_shot": ["attack_rate", "archer", -5, true],
	"iron_wall": ["attack_rate", "infantry", -10, true], "shield_cover": ["attack_rate", "infantry", -5, true]}
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	t_data()
	t_texts()
	t_shop()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Модификатор карточки: бонус (cost false) или издержка (cost true).
func find_mod(card: Dictionary, cost: bool) -> Dictionary:
	for e in card.mods:
		if e.get("cost", false) == cost:
			return e
	return {}

func t_data() -> void:
	print("данные")
	var defs := CARDS.load_cards("res://data/cards.json")
	check("data/cards.json проходит валидатор (%d карточек)" % defs.size(), defs.size() == 40)
	for id in WANT:
		var w: Array = WANT[id]
		var e := find_mod(defs[id], w[3])
		check("№%d %s: %s %s %+d%s" % [defs[id].num, id, w[0], w[1], w[2], " (издержка)" if w[3] else ""], e.stat == w[0] and e.target == w[1] and e.value == float(w[2]))
	var s3 := find_mod(defs.serrated_arrows, false)
	check("№3: %s archer +15 (выбор по v9)" % STAT_3, s3.stat == STAT_3 and s3.target == "archer" and s3.value == 15.0)
	var no_dmg := true
	for id in WANT:
		for e in defs[id].mods:
			no_dmg = no_dmg and e.stat != "damage"
	check("у перечисленных карточек нет damage", no_dmg)
	check("№24 и №30 не тронуты (особые K: vengeance и random_split по урону)", defs.vow_of_vengeance.get("special", "") == "vengeance"
		and defs.victory_sacrifice.on_pick.has("random_split"))
	var gifts := {}
	for g in JSON.parse_string(FileAccess.get_file_as_string("res://data/gifts.json")):
		gifts[g.id] = g
	check("«Закалённая сталь»: attack_rate infantry 6/12/18", gifts.tempered_steel.stat == "attack_rate" and gifts.tempered_steel.target == "infantry"
		and gifts.tempered_steel.levels == [6.0, 12.0, 18.0])
	check("«Меткие стрелки»: %s archer 8/16/24 (выбор по v9)" % STAT_MARKSMEN, gifts.marksmen.stat == STAT_MARKSMEN and gifts.marksmen.target == "archer"
		and gifts.marksmen.levels == [8.0, 16.0, 24.0])
	check("дары проходят загрузчик", preload("res://scripts/mods.gd").load_gifts("res://data/gifts.json").size() == gifts.size())
	var war_cry: Dictionary = gifts.war_cry
	check("Клич Благодати не тронут (способность, bonus_pct 30)", war_cry.type == "ability" and war_cry.levels[0].bonus_pct == 30.0)

func t_texts() -> void:
	print("тексты")
	var keys := ["CARD_METEOR_BLADES_DESC", "CARD_SILVER_VS_DEAD_DESC", "CARD_LAST_STAND_DESC", "CARD_DESPERATE_CHARGE_DESC", "CARD_LONG_SPEARS_DESC",
		"CARD_RESERVE_FUND_DESC", "CARD_BLOOD_FOR_BLOOD_DESC", "CARD_LONG_SHOT_DESC", "CARD_IRON_WALL_DESC", "CARD_SHIELD_COVER_DESC", "GIFT_TEMPERED_STEEL_DESC"]
	if STAT_3 == "attack_rate":
		keys.append("CARD_SERRATED_ARROWS_DESC")
	if STAT_MARKSMEN == "attack_rate":
		keys.append("GIFT_MARKSMEN_DESC")
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		var bad := []
		for k in keys:
			var t := tr(k)
			var ok := t.contains("скорост") and t.contains("атаки") and not t.contains("урон") if loc == "ru" else t.contains("attack speed") and not t.contains("damage")
			if not ok:
				bad.append("%s: %s" % [k, t])
		check("%s: описания говорят о скорости атаки, не об уроне" % loc, bad.is_empty(), "; ".join(bad))
	TranslationServer.set_locale("ru")

func t_shop() -> void:
	print("магазин")
	var m: Node2D = load(MAIN).new()
	m.record_path = "user://record_bench.json"
	m.debug_layer = 1
	m._setup_data()
	var k: int = m.SHOP_ITEMS.find("weapons")
	TranslationServer.set_locale("ru")
	var ru: String = m._shop_title(k)
	TranslationServer.set_locale("en")
	var en: String = m._shop_title(k)
	TranslationServer.set_locale("ru")
	check("«Оружие» в shop.json — attack_rate; название «%s» / «%s»" % [ru, en], m.weapon_stat == "attack_rate" and ru == "Оружие: скорость атаки +10%"
		and en == "Weapons: attack speed +10%")
	var d0: float = m.type_damage[m.infantry_type]
	var c0: float = m.type_cooldown[m.infantry_type]
	m.gold = 1000.0
	m.wave_state = m.WS_RESPITE
	m._buy(k)
	check("покупка: урон прежний, интервал удара пехоты короче в 1.1 раза", m.type_damage[m.infantry_type] == d0
		and absf(m._cd_actual(m.base_type_cooldown[m.infantry_type]) / m.type_cooldown[m.infantry_type] - 1.1) < 1e-4 and m.type_cooldown[m.infantry_type] < c0)
	m.free()
