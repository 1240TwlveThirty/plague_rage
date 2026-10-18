extends SceneTree
# Тесты задачи 6c: система иконок. У каждой карточки (cards.json) и каждого дара (gifts.json) есть id иконки из списка;
# data/icon_atlas.json — 27 id по порядку задания, индексы 0..26; без атласа art/icons.png — ячейки заглушки art/icons_placeholder.png;
# без заглушки — рамка с буквой, нарисованная кодом (без ошибок); свой атлас: непустая ячейка — из него, пустая (прозрачная) — заглушка;
# экран выбора: рамка, иконка, текст в окне рамки.
const ICONS := preload("res://scripts/icons.gd")
const CARDS := preload("res://scripts/cards.gd")
const MODS := preload("res://scripts/mods.gd")
const CARD_PICK := preload("res://scripts/card_pick.gd")
const IDS := ["sword", "arrow", "reload", "range", "spear", "shield", "heart", "cross", "boot", "gate", "hammer", "coin", "purse", "anvil",
	"weapons", "pick", "soldiers", "skull", "horn", "eye", "line", "cry", "hourglass", "fire", "radiance", "blood", "scales"]
const TMP_ATLAS := "user://bench_v56_icons.png"
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	TranslationServer.set_locale("ru")
	t_data()
	t_sources()
	await t_screen()
	ICONS.atlas_path = ICONS.ATLAS_PATH
	ICONS.placeholder_path = ICONS.PLACEHOLDER_PATH
	ICONS.reset()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func t_data() -> void:
	print("данные иконок")
	ICONS.reset()
	ICONS.load_all()
	var order: Array = ICONS.order.keys()
	order.sort_custom(func(a, b): return ICONS.order[a] < ICONS.order[b])
	check("icon_atlas.json: 27 id в порядке задания, индексы 0..26, ячейка 16, по 8 в ряду", order == IDS and ICONS.order.values().all(func(v): return v >= 0 and v < 27)
		and ICONS.cell == 16 and ICONS.per_row == 8, str(order))
	var cards := CARDS.load_cards("res://data/cards.json")
	var bad := []
	for id in cards:
		if not ICONS.of_card(id) in IDS:
			bad.append(id)
	check("у всех 40 карточек иконка из списка", cards.size() == 40 and bad.is_empty(), ", ".join(bad))
	check("карта карточек как в задании (выборочно): 1 sword, 13 fire, 24 blood, 30 scales, 39 radiance, 40 cross",
		ICONS.of_card("meteor_blades") == "sword" and ICONS.of_card("boiling_pitch") == "fire" and ICONS.of_card("vow_of_vengeance") == "blood"
		and ICONS.of_card("victory_sacrifice") == "scales" and ICONS.of_card("grace_blessing") == "radiance" and ICONS.of_card("field_kitchen") == "cross")
	var gifts := MODS.load_gifts("res://data/gifts.json")
	bad = []
	for id in gifts:
		if not ICONS.of_gift(id) in IDS:
			bad.append(id)
	check("у всех %d даров иконка из списка (Клич Благодати — cry, Рудник — pick, Дозор — eye)" % gifts.size(), bad.is_empty() and ICONS.of_gift("war_cry") == "cry"
		and ICONS.of_gift("mine") == "pick" and ICONS.of_gift("watch") == "eye", ", ".join(bad))

func t_sources() -> void:
	print("загрузка: атлас, заглушка, рамка с буквой")
	ICONS.atlas_path = "res://art/нет_такого_атласа.png"
	ICONS.placeholder_path = ICONS.PLACEHOLDER_PATH
	ICONS.reset()
	var c := ICONS.make("sword", 2)
	check("без art/icons.png: ячейки заглушки (TextureRect 32 x 32 при масштабе 2, nearest)", c is TextureRect and c.texture != null and c.custom_minimum_size == Vector2(32, 32)
		and c.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and ICONS.source.values().all(func(v): return v == "placeholder"))
	c.free()
	ICONS.placeholder_path = "res://art/нет_заглушки.png"
	ICONS.reset()
	var p := ICONS.make("hammer", 3)
	var letter: Label = p.get_child(0) if p.get_child_count() > 0 else null
	check("без атласа и заглушки: рамка с буквой «H», 48 x 48, без ошибок", p is Panel and letter != null and letter.text == "H" and p.custom_minimum_size == Vector2(48, 48))
	p.free()
	var u := ICONS.make("нет_такой_иконки", 1)
	check("неизвестный id иконки — тоже рамка с буквой", u is Panel)
	u.free()
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(0, 0, 16, 16), Color.RED)          # sword (ячейка 0) нарисован
	img.fill_rect(Rect2i(16 * 3, 16 * 2, 16, 16), Color.BLUE)   # ячейка 19 — eye
	img.save_png(TMP_ATLAS)
	ICONS.atlas_path = TMP_ATLAS
	ICONS.placeholder_path = ICONS.PLACEHOLDER_PATH
	ICONS.reset()
	ICONS.load_all()
	var s := ICONS.make("sword", 1) as TextureRect
	check("свой атлас: sword и eye — из него, остальные (пустые ячейки) — из заглушки", ICONS.source.sword == "atlas" and ICONS.source.eye == "atlas"
		and ICONS.source.arrow == "placeholder" and s.texture.get_image().get_pixel(4, 4) == Color.RED, str(ICONS.source.sword))
	s.free()
	DirAccess.remove_absolute(TMP_ATLAS)

func t_screen() -> void:
	print("экран выбора")
	ICONS.atlas_path = ICONS.ATLAS_PATH
	ICONS.placeholder_path = ICONS.PLACEHOLDER_PATH
	ICONS.reset()
	var defs := CARDS.load_cards("res://data/cards.json")
	var scr: CanvasLayer = CARD_PICK.new()
	root.add_child(scr)
	await step(1)
	scr.open(["meteor_blades", "heavy_shields", "victory_sacrifice"], defs, [])
	await step(3)
	var ok: bool = scr.buttons.size() == 3
	for b in scr.buttons:
		var frame: TextureRect = b.find_child("Frame", true, false)
		var icon: Control = b.find_child("Icon", true, false)
		ok = (ok and frame != null and frame.texture != null and frame.texture.resource_path.ends_with("card_perk_timer.png") and icon != null
			and frame.get_global_rect().encloses(icon.get_global_rect()) and b.size == Vector2(320, 480 + CARD_PICK.LIFT))
	check("три карточки: рамка временной карточки 320 x 480, иконка внутри рамки", ok)
	var b0: Button = scr.buttons[0]
	var face: Control = b0.find_child("Face", true, false)
	var shine: Control = b0.find_child("Shine", true, false)
	b0.mouse_entered.emit()
	var up: bool = face.position.y == 0.0 and shine.visible
	b0.mouse_exited.emit()
	check("наведение: карточка приподнимается на %d px и появляется блик; уход мыши — обратно" % int(CARD_PICK.LIFT), up and face.position.y == CARD_PICK.LIFT and not shine.visible)
	scr.queue_free()
	await step(2)
