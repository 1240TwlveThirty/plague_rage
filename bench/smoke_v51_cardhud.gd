extends SceneTree
# Смоук с окном (задача 6b, этап 1): список карточек в HUD боя. Скриншоты cardhud_off.png (условия не выполнены), cardhud_on.png
# («Держать» у пехоты: Стойкость горит), cardhud_steps.png (много ступеней: Кровь за кровь и Обет мести с процентами) и cardhud_split.png
# (сообщение после выбора «Жертвы ради победы»). Список целиком на экране. Подсказка при наведении в смоуке не снимается (синтетическое
# наведение её не вызывает): её текст проверяет check_v51, вид — вручную.
# Аргумент: папка для PNG (по умолчанию user://).
const DIR := "user://bench_v51h"
const SCREEN := Rect2(0, 0, 1920, 1080)
var fails := 0
var out_dir := ""

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await step(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name))

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var g: Node = root.get_node_or_null("Game")
	if g == null:
		print("SMOKE: нет автозагрузки Game")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.card_rules_path = ""
	g.card_rules = {}
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(5)
	var m := current_scene as Node2D
	for id in ["steadfast", "blood_for_blood", "vow_of_vengeance", "first_volley", "heavy_shields"]:
		g.pick_card(id)
	g.run_cards.append({"id": "victory_sacrifice", "result": {"good": "infantry", "bad": "archer"}})
	for t in [m.zombie_type, m.runner_type, m.knight_type]:   # бой не кончается сам
		m.base_type_hp[t] = 1e6
		m.base_type_damage[t] = 0.0
	m._start_wave()
	m.wave_t = 12.0   # первые 10 с прошли: Первый залп не горит
	m._update_card_conditions()
	m._update_ui()
	await shot("cardhud_off.png")
	check("условия не выполнены: 6 строк, ни одна не горит, список на экране", m.cards_rows.size() == 6 and not m.cards_rows.any(func(l): return l.text.begins_with("●"))
		and SCREEN.encloses(m.cards_box.get_global_rect()))
	m.squad_order[0] = m.ORDER_HOLD
	m._update_card_conditions()
	m._update_ui()
	await shot("cardhud_on.png")
	check("«Держать»: горит Стойкость", m.cards_rows[0].text.begins_with("●"), m.cards_rows[0].text)
	var n0: int = m.squad_start_n[0]
	m.squad_n[0] = n0 - roundi(n0 * 0.72)
	m.wave_fallen = 120
	m._update_card_conditions()
	m._update_ui()
	await shot("cardhud_steps.png")
	check("много ступеней: «Кровь за кровь +35%», «Обет мести +36%»", m.cards_rows[1].text.ends_with("+35%") and m.cards_rows[2].text.ends_with("+36%"),
		"%s | %s" % [m.cards_rows[1].text, m.cards_rows[2].text])
	check("подсказка у строки Тяжёлых щитов (текст есть)", m.cards_rows[4].tooltip_text.contains("Издержка"))
	m.squad_n[0] = n0
	g.run_cards.pop_back()
	m.card_pick_auto = "random"
	m.pending_offer = ["victory_sacrifice"]
	m.choose_card("victory_sacrifice")
	m._update_ui()
	await shot("cardhud_split.png")
	check("после выбора «Жертвы» — строка в HUD с результатом", m.hud_label.text.contains("Жертва ради победы: "), m.hud_msg)
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("PNG: " + out_dir)
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
