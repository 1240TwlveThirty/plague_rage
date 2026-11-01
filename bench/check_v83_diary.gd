extends SceneTree
# Задача 28в, этап 3 (без окна): текст дневника в хабе. Цвета — data/ui_theme.json (diary_text_color, diary_panel_color, contrast_min),
# тест читает их оттуда. Своё временное сохранение (user://bench_v83), все записи дневника прочитаны, ru и en.
#   Фон под текстом — середина арта светлой панели (panel.file); светлый — заливки нет, светлый он или нет — по контрасту
#   diary_text_color к нему; тёмный — панель залита diary_panel_color.
#   Весь текст дневника (заголовок, заголовки записей, записи; пустой дневник) — цвета diary_text_color, контраст каждой метки
#   к фону (текст с прозрачностью — смешанный с фоном) не меньше contrast_min; относительная яркость — формула WCAG, без библиотек.
const DIR := "user://bench_v83"
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

# Относительная яркость (WCAG 2): каналы sRGB -> линейные, веса 0.2126 / 0.7152 / 0.0722.
static func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

static func contrast(a: Color, b: Color) -> float:
	return (maxf(lum(a), lum(b)) + 0.05) / (minf(lum(a), lum(b)) + 0.05)

static func over(text: Color, bg: Color) -> Color:
	return Color(lerpf(bg.r, text.r, text.a), lerpf(bg.g, text.g, text.a), lerpf(bg.b, text.b, text.a))

func _run() -> void:
	var UI = load("res://scripts/ui.gd")
	var th: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_theme.json"))
	var minc: float = th.contrast_min
	var ink := Color(th.diary_text_color)
	var img: Image = UI._image(th.panel.file)
	var art := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	var light := contrast(ink, art) >= minc
	print("CONTRAST|панель дневника %s (середина арта %s), яркость %.3f, текст %s — %.2f: %s" % [th.panel.file.get_file(), art.to_html(false), lum(art),
		ink.to_html(false), contrast(ink, art), "светлая, заливки нет" if light else "тёмная — заливка diary_panel_color " + str(th.get("diary_panel_color", "?"))])
	var g: Node = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	for mode in ["empty", "full"]:
		g.diary_seen = []
		if mode == "full":
			g.diary_seen = [g.INTRO_ID]
			for e in g.story.entries:
				g.diary_seen.append(e.id)
		for l in ["ru", "en"]:
			TranslationServer.set_locale(l)
			g.go_hub()
			await step(3)
			var h: Control = current_scene
			h._open_diary()
			await step(2)
			var sb: StyleBox = h.diary_panel.get_theme_stylebox("panel")
			var bg := art
			if sb is StyleBoxFlat:
				bg = (sb as StyleBoxFlat).bg_color
			check("%s, %s: фон дневника — %s" % [l, mode, "арт панели" if light else "заливка diary_panel_color"],
				(light and not sb is StyleBoxFlat) or (not light and sb is StyleBoxFlat and bg == Color(th.diary_panel_color)))
			var labels: Array = h.diary_panel.find_children("*", "Label", true, false)
			var worst := 99.0
			var wrong := []
			for lab in labels:
				var c: Color = lab.get_theme_color("font_color")
				worst = minf(worst, contrast(over(c, bg), bg))
				if Color(c.r, c.g, c.b) != Color(ink.r, ink.g, ink.b):
					wrong.append("%s %s" % [tr(lab.text).left(20), c.to_html(false)])
			var texts: int = h.diary_box.get_child_count()
			check("%s, %s: меток %d (записей и заголовков %d), все цвета diary_text_color %s, худший контраст %.2f >= %.1f" % [l, mode, labels.size(), texts,
				ink.to_html(false), worst, minc], labels.size() >= 2 and wrong.is_empty() and worst >= minc and (mode == "empty" or texts > 2), ", ".join(wrong))
			h._close_diary()
			g.go_menu()
			await step(2)
	TranslationServer.set_locale("ru")
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
