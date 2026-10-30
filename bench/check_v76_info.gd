extends SceneTree
# Задача 26, этап 2 (без окна): характеристики выбранного отряда и «до → после» в магазине.
#   Панель отряда: поля из data/ui_layout.json squad_info_fields; показанные числа совпадают с данными симуляции (живые в отряде,
#   HP бойца, урон, дальность, ударов в секунду — интервал считается здесь заново по правилу симуляции, скорость строя).
#   Магазин: для «Оружия» (скорость атаки и урон), «Ворот» и набора пехоты «после» из подсказки равно тому, что стало в симуляции
#   после покупки, «до» — тому, что было; на кнопке улучшения — «до → после»; после покупки изменившееся число подсвечено
#   info_flash_time с. Временное сохранение user://bench_v76_info.
const UNITS := preload("res://scripts/units.gd")
const DIR := "user://bench_v76_info"
const CD_STEP := 2.0 / 30.0   # шаг решения юнита (CD_CARRY симуляции)
var fails := 0
var lay: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

# Интервал удара типа t так, как его проходит симуляция: с переносом остатка — cooldown, без — cooldown убывает шагами
# CD_STEP до нуля (float32, как в cooldown юнита), интервал — число шагов x CD_STEP.
func real_interval(m: Node2D, t: int) -> float:
	if m.type_cd_floor[t] != 0.0:
		return m.type_cooldown[t]
	var c := PackedFloat32Array([m.type_cooldown[t]])
	var n := 0
	while c[0] > 0.0:
		c[0] = maxf(c[0] - CD_STEP, 0.0)
		n += 1
	return n * CD_STEP

func real_damage(m: Node2D, t: int) -> float:
	return m.type_arrow_dmg[t] if m.type_range_far[t] > 0.0 else m.type_damage[t]

func _run() -> void:
	lay = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	node_added.connect(_on_node_added)
	await step(1)
	TranslationServer.set_locale("ru")
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	await t_panel(m)
	await t_shop(m)
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_panel(m: Node2D) -> void:
	print("панель отряда")
	m._clear_sel()
	m._update_squad_panel()
	check("без выбора панели нет", not m.squad_info.visible)
	m._select_only(0)
	m._update_squad_panel()
	var fields: Array = lay.squad_info_fields
	check("поля из ui_layout.json squad_info_fields (%s)" % ", ".join(fields), m.info_fields == fields and m.squad_info_labels.size() == fields.size())
	var r_info := Rect2(m.squad_info.position, m.squad_info.size)
	check("выбран отряд 1 — панель видна у левого края, не на панели отрядов и целиком на экране", m.squad_info.visible
		and not r_info.intersects(Rect2(m.squad_panel.position, m.squad_panel.size)) and Rect2(Vector2.ZERO, m.squad_info.get_viewport_rect().size).encloses(r_info)
		and r_info.position.x == m.squad_panel.position.x, str(r_info))
	for s in [0, 1]:
		m._select_only(s)
		m._update_squad_panel()
		var t: int = m.squad_type[s]
		var alive := 0
		var hp_sum := 0.0
		for i in m.count:
			if m.unit_squad[i] == s:
				alive += 1
				hp_sum += m.hp[i]
		var rng: float = m.type_range_far[t] if m.type_range_far[t] > 0.0 else sqrt(m.type_range_sq[t])
		var want := {"alive": tr("HUD_INFO_ALIVE") % alive, "hp": tr("HUD_INFO_HP") % [UNITS.num(hp_sum / alive, 1), UNITS.num(m.type_hp[t], 1)],
			"damage": tr("HUD_INFO_DAMAGE") % UNITS.num(real_damage(m, t), 2), "range": tr("HUD_INFO_RANGE") % UNITS.dist_text(rng),
			"attack_rate": tr("HUD_INFO_ATTACK_RATE") % UNITS.num(m.squad_atk_speed_mult[s] / real_interval(m, t), 2),
			"speed": tr("HUD_INFO_SPEED") % UNITS.dist_text(m.squad_speed[s] * m.squad_speed_mult[s])}
		var bad := []
		for f in fields:
			if m.squad_info_labels[f].text != want[f]:
				bad.append("%s: «%s» вместо «%s»" % [f, m.squad_info_labels[f].text, want[f]])
		check("отряд %d (%s): показанное совпадает с данными симуляции (%s)" % [s + 1, tr(m.type_label[t]),
			" · ".join(fields.map(func(f): return m.squad_info_labels[f].text))], bad.is_empty(), "; ".join(bad))
	m._select_only(0)
	m._update_squad_panel()

# Покупка k: «до» и «после» из shop_preview против данных симуляции до и после _buy.
func buy_and_compare(m: Node2D, k: int, label: String, real: Callable) -> void:
	var pv: Array = m.shop_preview(k)
	var before: Array = real.call()
	var ok_buy: bool = m._buy(k)
	m._update_ui()
	m._update_squad_panel()
	var after: Array = real.call()
	var bad := []
	for q in pv.size():
		if not (is_equal_approx(float(pv[q][1]), float(before[q])) and is_equal_approx(float(pv[q][2]), float(after[q]))):
			bad.append("%s: показано %s → %s, было %s, стало %s" % [pv[q][0], pv[q][1], pv[q][2], before[q], after[q]])
	check("%s: покупка прошла, «до → после» в подсказке совпадает с симуляцией (%s)" % [label, ", ".join(pv.map(func(e): return "%s %s" % [e[0], m.preview_delta(e)]))],
		ok_buy and pv.size() == before.size() and bad.is_empty(), "; ".join(bad))

func t_shop(m: Node2D) -> void:
	print("магазин: до → после")
	m.gold = 1e7
	var wk: int = m.SHOP_ITEMS.find("weapons")
	var gk: int = m.SHOP_ITEMS.find("gate")
	var ik: int = m.SHOP_ITEMS.find("inf_pack")
	var types := [m.infantry_type, m.archer_type]
	if m.type_enabled[m.spearman_type] == 1:
		types.append(m.spearman_type)
	m._update_ui()
	var pv: Array = m.shop_preview(wk)
	var btn: Button = m.shop_buttons[wk]
	check("кнопка «Оружие»: во второй строке «до → после» (%s)" % btn.text.replace("\n", " / "), m.preview_delta(pv[0]) in btn.text.get_slice("\n", 1))
	check("подсказка «Оружие»: строка на каждый тип", pv.size() == types.size() and pv.all(func(e): return m.preview_delta(e) in btn.tooltip_text), btn.tooltip_text)
	var rate := func() -> Array: return types.map(func(t): return 1.0 / real_interval(m, t))
	for n in 2:
		var t0 := Time.get_ticks_msec()
		buy_and_compare(m, wk, "оружие (%s), покупка %d" % [m.weapon_stat, n + 1], rate)
		var until: int = m.info_flash.get("attack_rate", 0)
		check("после покупки скорость атаки на панели подсвечена %s с" % lay.info_flash_time,
			absi(until - t0 - int(lay.info_flash_time * 1000.0)) < 500 and m.squad_info_labels["attack_rate"].get_theme_color("font_color") == m.INFO_FLASH_COLOR,
			"до %d, сейчас %d" % [until, Time.get_ticks_msec()])
	m.info_flash.clear()
	m._update_squad_panel()
	check("без покупки подсветки нет", m.squad_info_labels["attack_rate"].get_theme_color("font_color") == Color.WHITE)
	m.weapon_stat = "damage"   # тот же товар на урон (shop.json weapons.stat)
	m._apply_wave_data()   # данные волны по новому правилу (как в начале волны)
	var dmg := func() -> Array: return types.map(func(t): return real_damage(m, t))
	buy_and_compare(m, wk, "оружие (damage)", dmg)
	check("после покупки урон на панели подсвечен", m.info_flash.get("damage", 0) > Time.get_ticks_msec())
	m.weapon_stat = "attack_rate"
	m._apply_wave_data()
	buy_and_compare(m, gk, "ворота", func() -> Array: return [m.gate_hp_max])
	check("после ремонта окошко ворот подсвечено", m.hud_flash.get("gate", 0) > Time.get_ticks_msec()
		and m.top_hud.slots["gate"].modulate == m.INFO_FLASH_COLOR)
	m._select_only(0)
	buy_and_compare(m, ik, "пехота в отряд 1", func() -> Array: return [m.squad_n[0]])
	check("после покупки число живых подсвечено (панель и окошко «Войска»)", m.info_flash.get("alive", 0) > Time.get_ticks_msec()
		and m.hud_flash.get("troops", 0) > Time.get_ticks_msec())
	TranslationServer.set_locale("en")
	m._update_ui()
	check("en: подсказка «Оружие» с «→» на английском", "→" in m.shop_buttons[wk].tooltip_text and "Key" in m.shop_buttons[wk].tooltip_text, m.shop_buttons[wk].tooltip_text)
	TranslationServer.set_locale("ru")
