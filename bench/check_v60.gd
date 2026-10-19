extends SceneTree
# Тесты задачи 10: экспериментальный герой. Этап A — данные data/hero.json, включение (hero_mode, enabled, игровой режим),
# тип героя последним в таблице типов. Разделы следующих этапов добавляются ниже.
const MAIN := "res://scripts/main.gd"
const FIX := "res://bench/fixtures_hero/"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(mode := 1, path := "", rng_seed := 3) -> Node2D:
	var m: Node2D = load(MAIN).new()
	m.spawn_seed = rng_seed
	m.debug_layer = 1
	m.record_path = "user://record_bench.json"
	m.hero_mode = mode
	if path != "":
		m.hero_path = path
	m._setup_data()
	return m

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await process_frame
	TranslationServer.set_locale("ru")
	t_data()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные героя")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/hero.json"))
	var m := make(1)
	var i: int = m.infantry_type
	var h: int = m.hero_type
	check("hero.json: enabled true (игровой режим), targets_per_swing 2, size_scale 1.6-2, revive_hp_fraction 1.0", d.enabled == true
		and d.targets_per_swing == 2 and d.size_scale >= 1.6 and d.size_scale <= 2.0 and d.revive_hp_fraction == 1.0)
	check("тип hero последним (номера типов из unit_types.json прежние), подпись «Командир»", h == m.type_hp.size() - 1 and h == m.type_id.size() - 1
		and tr(m.type_label[h]) == "Командир")
	check("урон x2 пехоты, интервал удара как у пехоты, HP x5 пехоты", is_equal_approx(m.base_type_damage[h], 2.0 * m.base_type_damage[i])
		and is_equal_approx(m.base_type_cooldown[h], m.base_type_cooldown[i]) and is_equal_approx(m.base_type_hp[h], 5.0 * m.base_type_hp[i]))
	var k: float = m.base_type_speed[h] / m.base_type_speed[i]
	check("скорость %.0f px/с (данные — мировые px/с) = %.2f пехоты (около 1.15)" % [m.base_type_speed[h], k], is_equal_approx(m.base_type_speed[h], d.speed) and absf(k - 1.15) < 0.02)
	check("дальность удара %.1f px (данные — мировые px), больше пехотной %.1f; щита нет, награды нет" % [sqrt(m.type_range_sq[h]), sqrt(m.type_range_sq[i])],
		is_equal_approx(sqrt(m.type_range_sq[h]), d.attack_range) and m.type_range_sq[h] > m.type_range_sq[i] and m.type_block_mult[h] == 1.0 and m.type_bounty_mult[h] == 0.0)
	m.free()
	var off := make(0)
	check("hero_mode 0 без синглтона Game (бенчи, регрессия): героя нет, типов столько же, сколько в unit_types.json", not off.hero_on and off.hero_type == -1
		and off.type_hp.size() == JSON.parse_string(FileAccess.get_file_as_string("res://data/unit_types.json")).size())
	off.free()
	var neg := make(-1)
	check("hero_mode -1: героя нет", not neg.hero_on and neg.hero_type == -1)
	neg.free()
	var dis := make(0, FIX + "disabled.json")
	check("enabled false: героя нет и в игровом режиме (проверка флага без Game — hero_on false)", not dis.hero_on)
	dis.free()
	print("  ниже ожидаются строки ERROR от повреждённых файлов")
	for f in ["no_hp", "bad_targets", "bad_revive", "bad_enabled"]:
		var b := make(1, FIX + f + ".json")
		check("%s.json: данные не загружены" % f, b.type_id.is_empty() or not b.is_physics_processing())
		b.free()
