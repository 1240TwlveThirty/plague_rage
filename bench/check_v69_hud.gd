extends SceneTree
# Тесты задачи 19 (без окна): верхняя панель боя из окошек и окошко «Сияние». Рамка окошка и полоса — в теме (FrameSlot, FrameBar),
# копии ×scale — ближайший сосед исходника; состав, порядок, размеры, иконки панели — из data/ui_layout.json (ничего не зашито);
# значения окошек = состоянию боя (Войска — сумма squad_n отрядов игрока, без героя); подпись не пересобирается без смены числа;
# числа с пробелом между тысячами, 5 цифр помещаются при кегле не меньше font_size, сокращение «к» — когда не помещается и при
# font_min; заливка ворот обрезается (не масштабируется); панель на экране и не задевает соседей; шестое окошко — правка данных.
# Хаб и экран итога: окошко «Сияние» справа сверху, в бою его нет. Временное сохранение user://bench_v69 (user://save.json не трогается).
const MAIN := "res://scripts/main.gd"
const UI := preload("res://scripts/ui.gd")
const TOP_HUD := preload("res://scripts/top_hud.gd")
const HUD_SLOT := preload("res://scripts/hud_slot.gd")
const ICONS := preload("res://scripts/icons.gd")
const DIR := "user://bench_v69"
const DT := 1.0 / 30.0
var fails := 0
var cfg: Dictionary   # data/ui_theme.json
var lay: Dictionary   # data/ui_layout.json, раздел top_hud
var corner: Dictionary

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == MAIN:
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_theme.json"))
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	lay = all.top_hud
	corner = all.corner_slot
	t_theme()
	t_format()
	await t_slot()
	await t_six()
	await t_battle()
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

func src_image(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGBA8)
	return img

# Текстура — исходник ×scale ближайшим соседом (у полностью прозрачных пикселей цвет не важен).
func scaled_ok(tex: Texture2D, src_path: String) -> bool:
	var src := src_image(src_path)
	var s := int(cfg.scale)
	src.resize(src.get_width() * s, src.get_height() * s, Image.INTERPOLATE_NEAREST)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_size() != src.get_size():
		return false
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y)
			var b := src.get_pixel(x, y)
			if a != b and not (a.a == 0.0 and b.a == 0.0):
				return false
	return true

func t_theme() -> void:
	print("тема: окошко и полоса")
	var s := int(cfg.scale)
	var sl: Dictionary = cfg.slot
	var bar: Dictionary = cfg.bar
	var t := ThemeDB.get_project_theme()
	var sb := t.get_stylebox("panel", UI.SLOT) as StyleBoxTexture
	var src := src_image(sl.file)
	var sl_slice := int(sl.get("slice", sl.corner))
	var pad_h := int(sl.corner) * s + int(sl.content_pad)
	var pad_v := int(sl.corner) * s + int(sl.content_pad_v)
	check("окошко: %s %dx%d -> x%d %s, срез %d (= %d x %d), поля содержимого %d / %d" % [sl.file, src.get_width(), src.get_height(), s,
		sb.texture.resource_path if sb != null else "-", sl_slice * s, sl_slice, s, pad_h, pad_v], sb != null and t.get_type_variation_base(UI.SLOT) == &"PanelContainer"
		and scaled_ok(sb.texture, sl.file) and sb.texture.resource_path.begins_with(cfg.out_dir) and sb.texture_margin_left == sl_slice * s
		and sb.texture_margin_top == sl_slice * s and sb.content_margin_left == pad_h and sb.content_margin_top == pad_v and sb.content_margin_bottom == pad_v)
	var fr: Texture2D = t.get_icon("frame", UI.BAR)
	var fl: Texture2D = t.get_icon("fill", UI.BAR)
	var fsrc := src_image(bar.frame)
	check("полоса: рамка %s и заливка %s %dx%d -> x%d (%dx%d), окно заливки %d..%d" % [bar.frame.get_file(), bar.fill.get_file(), fsrc.get_width(), fsrc.get_height(), s,
		fr.get_width(), fr.get_height(), int(bar.fill_left) * s, fr.get_width() - int(bar.fill_right) * s], scaled_ok(fr, bar.frame) and scaled_ok(fl, bar.fill)
		and t.get_constant("fill_left", UI.BAR) == int(bar.fill_left) * s and t.get_constant("fill_right", UI.BAR) == int(bar.fill_right) * s
		and t.get_constant("step", UI.BAR) == s)

func t_format() -> void:
	print("числа")
	var cases := {0: "0", 7: "7", 999: "999", 1000: "1 000", 12345: "12 345", 99999: "99 999", 1234567: "1 234 567", -4500: "-4 500"}
	var bad := []
	for n in cases:
		if HUD_SLOT.group(n) != cases[n]:
			bad.append("%d -> «%s»" % [n, HUD_SLOT.group(n)])
	check("от 1000 — пробел между тысячами (%s)" % ", ".join(cases.values()), bad.is_empty(), ", ".join(bad))
	TranslationServer.set_locale("ru")
	var ru := HUD_SLOT.short(12345)
	TranslationServer.set_locale("en")
	var en := HUD_SLOT.short(12345)
	TranslationServer.set_locale("ru")
	check("сокращение: 12345 -> «%s» (ru), «%s» (en); до 1000 — как есть" % [ru, en], ru == "12.3к" and en == "12.3k" and HUD_SLOT.short(999) == "999")

func t_slot() -> void:
	print("окошко")
	var holder := Control.new()
	holder.size = Vector2(1920, 1080)
	root.add_child(holder)
	var w := 200.0
	for d in lay.slots:
		if not d.get("bar", false):
			w = d.width
			break
	var s := TOP_HUD.make_slot(lay, {"id": "t", "icon": "coin", "width": w})
	holder.add_child(s)
	await step(2)
	s.set_value(99999)
	await step(1)
	var px := int(s.label.get_theme_font_size("font_size"))
	check("5 цифр «%s» в окошке %d px рядом с иконкой %d px: кегль %d (не меньше %d), текст %.0f из %.0f px" % [s.label.text, int(w), 16 * int(lay.icon_scale), px,
		int(lay.font_size), s.text_px(), s.text_width], s.label.text == "99 999" and px >= int(lay.font_size) and s.text_px() <= s.text_width
		and s.size == Vector2(w, lay.height))
	s.label.text = "X"
	s.set_value(99999)
	check("то же число — подпись не пересобирается", s.label.text == "X")
	s.set_value(100000)
	check("другое число — подпись новая: «%s»" % s.label.text, s.label.text == "100 000")
	s.text_width = 60.0   # искусственно узко: при font_size не влезает — кегль вниз до font_min, дальше сокращение
	s.refresh()
	check("узкое место (60 px): кегль %d, «%s»" % [s.label.get_theme_font_size("font_size"), s.label.text], s.label.get_theme_font_size("font_size") == int(lay.font_min)
		and s.label.text == "100.0к")
	s.text_width = 60.0
	s.set_value(12345)
	var mid := int(s.label.get_theme_font_size("font_size"))
	check("чуть уже 5 цифр при %d (60 px): кегль %d — между %d и %d, без сокращения («%s»)" % [int(lay.font_size), mid, int(lay.font_min), int(lay.font_size),
		s.label.text], s.label.text == "12 345" and mid >= int(lay.font_min) and mid <= int(lay.font_size) and s.text_px() <= 60.0 and mid < int(lay.font_size))
	# ворота: заливка обрезается по доле, не растягивается
	var gw := 600.0
	for d in lay.slots:
		if d.get("bar", false):
			gw = d.width
	var g := TOP_HUD.make_slot(lay, {"id": "g", "icon": "gate", "width": gw, "bar": true})
	holder.add_child(g)
	await step(2)
	var t := ThemeDB.get_project_theme()
	var fill: Texture2D = t.get_icon("fill", UI.BAR)
	var win := fill.get_width() - g.fill_left - g.fill_right
	var res := []
	var ok := true
	for c in [[1500, 1500], [600, 1500], [0, 1500], [1, 1500]]:
		g.set_value(c[0], c[1])
		var want := 0.0 if c[0] <= 0 else g.fill_left + floorf(float(c[0]) / c[1] * win / g.fill_step) * g.fill_step
		var inner: TextureRect = g.bar_clip.get_child(0)
		ok = (ok and is_equal_approx(g.bar_clip.size.x, want) and g.bar_clip.clip_contents and inner.size == fill.get_size() and inner.texture == fill
			and g.label.text == HUD_SLOT.group(c[0]) + "/" + HUD_SLOT.group(c[1]))
		res.append("%d%% -> %d px" % [roundi(100.0 * c[0] / c[1]), int(g.bar_clip.size.x)])
	check("ворота: полоса %s в окошке %d, заливка обрезается (картинка %s без масштаба): %s; число поверх" % [str(g.bar.size), int(gw), str(fill.get_size()),
		", ".join(res)], ok and g.bar.size == fill.get_size() and g.bar.get_global_rect().end.x <= g.get_global_rect().end.x - UI.slot_margins().x / 2.0)
	holder.queue_free()
	await step(1)

# Шестое окошко — только данные: своя раскладка в user:// с 6 записями, панель строит 6 окошек, значение — из источника.
func t_six() -> void:
	print("шестое окошко — правкой данных")
	DirAccess.make_dir_recursive_absolute(DIR)
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	all.top_hud.slots.append({"id": "kills", "icon": "sword", "width": 200})
	var path := DIR + "/layout6.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(all))
	f.close()
	TOP_HUD.layout_path = path
	var h := TOP_HUD.new()
	TOP_HUD.layout_path = TOP_HUD.LAYOUT_PATH
	h.source = func(id: String) -> Vector2i: return Vector2i(42 if id == "kills" else 1, -1)
	root.add_child(h)
	await step(2)
	h.update()
	var ids: Array = h.slots.keys()
	check("6 записей в slots -> окошек %d (%s), шестое показывает значение источника (%d)" % [h.get_child_count(), ", ".join(ids), h.get_values().get("kills", -1)],
		h.get_child_count() == 6 and ids[5] == "kills" and h.get_values().kills == 42)
	h.queue_free()
	DirAccess.remove_absolute(path)
	await step(1)

func troops(m: Node) -> int:
	var n := 0
	for s in m.SQUAD_MAX:
		if m.squad_used[s] == 1 and m.squad_team[s] == 0:
			n += m.squad_n[s]
	return n

func t_battle() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	g.radiance = 12345
	var scr := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	print("хаб")
	g.go_hub()
	await step(3)
	var h := current_scene
	var hr: Rect2 = h.radiance_slot.get_global_rect()
	check("хаб: окошко «Сияние» %s справа сверху (отступы %d / %d), баланс %d, иконка %s" % [str(hr), int(corner.right), int(corner.top), h.radiance_slot.value, corner.icon],
		h.radiance_slot.value == 12345 and is_equal_approx(hr.end.x, scr.end.x - float(corner.right)) and is_equal_approx(hr.position.y, float(corner.top))
		and hr.size == Vector2(corner.width, lay.height) and h.radiance_slot.theme_type_variation == UI.SLOT)
	var clash := []
	for tab in 2:
		h.tabs.current_tab = tab
		await step(2)
		for c in [h.tabs, h.gifts_panel, h.start_button]:
			if c.is_visible_in_tree() and c.get_global_rect().intersects(hr):
				clash.append(c.name)
	h._open_diary()
	await step(2)
	if h.diary_panel.get_global_rect().intersects(hr):
		clash.append("дневник")
	h._close_diary()
	h.tabs.current_tab = 0
	check("хаб: окошко не задевает вкладки, дары и дневник (они не сдвинуты)", clash.is_empty(), ", ".join(clash))
	print("бой")
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	var th = m.top_hud
	var widths := []
	var ok: bool = th.get_child_count() == lay.slots.size()
	for k in lay.slots.size():
		var d: Dictionary = lay.slots[k]
		var s = th.get_child(k)
		ok = ok and s.id == d.id and s.size == Vector2(d.width, lay.height) and s.theme_type_variation == UI.SLOT
		var ic: Control = s.get_child(0).get_child(0)
		ok = ok and ic.size == Vector2.ONE * ICONS.cell * int(lay.icon_scale)
		widths.append("%s %d" % [d.id, int(s.size.x)])
	var r: Rect2 = th.get_global_rect()
	var total := 0.0
	for d in lay.slots:
		total += float(d.width)
	total += float(lay.gap) * (lay.slots.size() - 1)
	check("панель из ui_layout.json: %s; высота %d, зазор %d, иконки x%d; ширина %d = сумма" % [", ".join(widths), int(lay.height), int(lay.gap), int(lay.icon_scale), int(r.size.x)],
		ok and is_equal_approx(r.size.x, total))
	check("по центру сверху: отступ %d, середина %.0f, целиком на экране %s" % [int(lay.top), r.get_center().x, str(scr.size)], is_equal_approx(r.position.y, float(lay.top))
		and absf(r.get_center().x - scr.get_center().x) < 1.0 and scr.encloses(r))
	m.war_cry_level = 1
	m._setup_war_cry_ui(m.squad_panel.get_parent())
	m._update_squad_panel()
	m._update_ui()
	await step(2)
	var hit := []
	var near := [m.squad_panel, m.shop_panel, m.cards_box, m.info_label, m.war_cry_button, m.burst_label, m.pause_label, m.hero_fallen_panel]
	for c in near:
		if c.get_global_rect().intersects(r):
			hit.append(c.name)
	check("панель не задевает отряды, магазин, карточки, разведку, Клич, всплеск, «ПАУЗА», «Командир пал»", hit.is_empty(), ", ".join(hit))
	check("в бою окошка «Сияние» нет", not m.radiance_slot.visible)
	m._start_wave()
	for t in 120:
		m._physics_process(DT)
	m._update_ui()
	var v: Dictionary = th.get_values()
	check("значения в бою = состоянию: %s (зомби: zombies — живые, zombies_left — живые и ещё не вышедшие; войска — сумма squad_n %d, герой не считается)" % [str(v), troops(m)], v.wave == m.wave_number and v.wave_max == m.waves_per_run
		and v.get("zombies", m.zombie_alive) == m.zombie_alive and v.get("zombies_left", m.zombie_alive + m.wave_remaining) == m.zombie_alive + m.wave_remaining
		and (v.has("zombies") or v.has("zombies_left")) and v.troops == troops(m) and v.gate == ceili(maxf(m.gate_hp, 0.0)) and v.gate_max == roundi(m.gate_hp_max)
		and v.gold == floori(m.gold) and m.zombie_alive > 0)
	var labels := {}
	for id in th.slots:
		labels[id] = th.slots[id].label
		th.slots[id].label.text = "X"
	m._update_ui()
	var same := 0
	for id in labels:
		same += 1 if labels[id].text == "X" else 0
	check("повторное обновление без изменений: подписи не пересобираются (%d из %d)" % [same, labels.size()], same == labels.size())
	m.gold += 1000.0
	m._update_ui()
	check("золото +1000: подпись «Золото» новая («%s»), остальные — нет" % labels.gold.text, labels.gold.text == HUD_SLOT.group(floori(m.gold))
		and labels.wave.text == "X")
	for id in th.slots:
		th.slots[id].refresh()
	m.gate_hp = -5.0
	m._update_ui()
	v = th.get_values()
	check("ворота разрушены: число 0, полоса пустая", v.gate == 0 and th.slots.gate.bar_clip.size.x == 0.0)
	m._on_defeat()
	m._update_ui()
	await step(2)
	var rr: Rect2 = m.radiance_slot.get_global_rect()
	check("итог забега: «Сияние» справа сверху (%s), баланс %d, под ним заработанное «%s»; не задевает панель и баннер" % [str(rr), m.radiance_slot.value,
		m.radiance_earned_label.text], m.radiance_slot.visible and m.radiance_slot.value == g.radiance and m.radiance_earned_label.visible
		and m.radiance_earned_label.text == m.banner_radiance and not rr.intersects(r) and not rr.intersects(m.banner.get_global_rect()) and scr.encloses(rr)
		and not m.cards_box.get_global_rect().intersects(m.radiance_earned_label.get_global_rect()))
	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
