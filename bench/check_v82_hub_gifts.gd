extends SceneTree
# Задача 28в, этап 2 (без окна): вкладка «Дары» — крупные строки в прокрутке. Параметры — data/ui_layout.json (hub_*), цвета полосы —
# data/ui_theme.json scrollbar; тест читает их оттуда. Своё временное сохранение (user://bench_v82), сохранение игрока не трогается.
#   ru и en: кегль строк hub_row_font, высота строки — не меньше hub_row_height и двух строк текста; «Купить» не меньше hub_buy_size
#   (и 160 x 48); колонка «Следующий уровень» — самая широкая из текстовых; шапка таблицы — вне прокрутки, её колонки над колонками
#   строк; горизонтальной прокрутки нет, строки не шире области; все строки достижимы (последняя целиком видна внизу прокрутки);
#   «Откроется после осады II» — целиком (все строки текста видны, в рамке строки); полоса — видна, толщина не меньше 12 px,
#   стили из темы (не серые по умолчанию).
#   Прокрутка: колесо, PageUp/PageDown и стрелки с фокусом на списке, PageDown с фокусом на «Купить»; покупка не сбрасывает
#   прокрутку; покупка работает как раньше (уровень, Сияние). Список короче области — полосы нет.
const DIR := "user://bench_v82"
const BAR_MIN := 12.0
var fails := 0
var g: Node
var h: Control

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	_run.call_deferred()

func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	root.push_input(e)
	await step(2)

func wheel(down: bool, at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		e.pressed = pressed
		e.position = at
		e.global_position = at
		e.factor = 1.0
		root.push_input(e, true)   # без окна: координаты окна (иначе событие мыши не доходит до контролов)
	await step(2)

func hub() -> void:
	g.go_hub()
	await step(3)
	h = current_scene
	h.tabs.current_tab = 1
	await step(4)

func _run() -> void:
	g = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	var lay: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	var th: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_theme.json"))
	var cols: Dictionary = lay.hub_columns
	var shown := 0
	for id in g.gift_defs:
		shown += 0 if g.gift_defs[id].hidden else 1
	# строка с пометкой «Откроется после осады II»: дар со следующим уровнем, закрытым до осады II
	var siege2 := ""
	for id in g.gift_defs:
		if not g.gift_defs[id].hidden and siege2 == "":
			for lv in range(g.gift_defs[id].levels.size()):
				g.gift_levels[id] = lv
				if g.buy_block(id) == tr("GIFT_BLOCK_SIEGE") % g.roman(2):
					siege2 = id
					break
			if siege2 == "":
				g.gift_levels.erase(id)
	g.radiance = 100000
	for l in ["ru", "en"]:
		TranslationServer.set_locale(l)
		await hub()
		var any_row: Dictionary = h.gift_rows.values()[0]
		var font: Font = any_row.effect.get_theme_font("font")
		var fs: int = any_row.effect.get_theme_font_size("font_size")
		var row_h: float = (any_row.frame as Control).size.y
		var same_font := true
		var same_h := true
		for r in h.gift_rows.values():
			for k in ["name", "level", "effect", "price", "reason"]:
				same_font = same_font and r[k].get_theme_font_size("font_size") == fs
			same_h = same_h and is_equal_approx(r.frame.size.y, row_h)
		check("%s: строк %d из %d показанных даров, кегль строк %d (hub_row_font %d)" % [l, h.gift_rows.size(), shown, fs, int(lay.hub_row_font)],
			h.gift_rows.size() == shown and fs == int(lay.hub_row_font) and same_font)
		check("%s: высота строки %.0f — не меньше hub_row_height %d и двух строк текста (%.0f)" % [l, row_h, int(lay.hub_row_height), font.get_height(fs) * 2.0],
			row_h >= float(lay.hub_row_height) and row_h >= font.get_height(fs) * 2.0 and same_h, str(h.gift_rows.values().map(func(r): return r.frame.size.y)))
		var bs: Vector2 = any_row.button.size
		check("%s: «Купить» %s — не меньше hub_buy_size %s и 160 x 48" % [l, str(bs), str(lay.hub_buy_size)], bs.x >= maxf(160.0, lay.hub_buy_size[0]) and bs.y >= maxf(48.0, lay.hub_buy_size[1]))
		var widest := is_equal_approx(any_row.effect.size.x, float(cols.next))
		for k in ["name", "level", "price", "reason"]:
			widest = widest and any_row.effect.size.x > any_row[k].size.x
		check("%s: «Следующий уровень» (%.0f) шире названия, уровня, цены и причины" % [l, any_row.effect.size.x], widest)
		# шапка
		var heads: Array = h.gift_head.get_children().filter(func(c): return c is Label)
		var aligned := heads.size() == 4
		for k in heads.size():
			var cell: Control = [any_row.name, any_row.level, any_row.effect, any_row.price][k] if k < 4 else null
			aligned = aligned and cell != null and absf(heads[k].get_global_rect().position.x - cell.get_global_rect().position.x) <= 0.5
		check("%s: шапка таблицы вне прокрутки, над списком, колонки шапки над колонками строк" % l, not h.gift_scroll.is_ancestor_of(h.gift_head)
			and h.gift_head.get_global_rect().end.y <= h.gift_scroll.get_global_rect().position.y and aligned)
		# прокрутка
		var sc: ScrollContainer = h.gift_scroll
		var bar := sc.get_v_scroll_bar()
		var st := bar.get_theme_stylebox("scroll")
		var gr := bar.get_theme_stylebox("grabber")
		check("%s: прокрутка только вертикальная, строки не шире области (%.0f <= %.0f)" % [l, h.gift_list.size.x, sc.size.x], sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
			and not sc.get_h_scroll_bar().visible and h.gift_list.size.x <= sc.size.x)
		check("%s: полоса видна (список %.0f > области %.0f), толщина %.0f >= %.0f, цвета темы (жёлоб %s, ползунок %s)" % [l, h.gift_list.size.y, sc.size.y, bar.size.x, BAR_MIN,
			th.scrollbar.track, th.scrollbar.grabber], h.gift_list.size.y > sc.size.y and bar.visible and bar.size.x >= BAR_MIN and bar.size.x >= float(th.scrollbar.width)
			and st is StyleBoxFlat and (st as StyleBoxFlat).bg_color == Color(th.scrollbar.track) and gr is StyleBoxFlat and (gr as StyleBoxFlat).bg_color == Color(th.scrollbar.grabber))
		check("%s: вкладка «Дары» целиком на экране %s" % [l, str(h.gifts_panel.get_global_rect())], root.get_visible_rect().encloses(h.gifts_panel.get_global_rect()))
		sc.scroll_vertical = int(bar.max_value)
		await step(2)
		var last: Control = h.gift_rows.values()[-1].frame
		check("%s: последняя строка достижима — внизу прокрутки целиком видна" % l, sc.get_global_rect().grow(0.5).encloses(last.get_global_rect()))
		if siege2 != "":
			var r: Dictionary = h.gift_rows[siege2]
			sc.ensure_control_visible(r.frame)
			await step(2)
			var lab: Label = r.reason
			check("%s: «%s» — целиком (строк %d, видно %d), в рамке строки" % [l, tr(lab.text), lab.get_line_count(), lab.get_visible_line_count()],
				tr(lab.text) == tr("GIFT_BLOCK_SIEGE") % g.roman(2) and lab.get_visible_line_count() >= lab.get_line_count()
				and lab.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and r.frame.get_global_rect().encloses(lab.get_global_rect()) and r.button.disabled)
		else:
			check("%s: есть дар с уровнем, закрытым до осады II" % l, false)
	TranslationServer.set_locale("ru")
	# клавиши и колесо
	var sc: ScrollContainer = h.gift_scroll
	sc.scroll_vertical = 0
	sc.grab_focus()
	await step(2)
	await key(KEY_PAGEDOWN)
	var p1 := sc.scroll_vertical
	await key(KEY_DOWN)
	var p2 := sc.scroll_vertical
	await key(KEY_PAGEUP)
	var p3 := sc.scroll_vertical
	check("фокус на списке: PageDown (%d), стрелка вниз (%d), PageUp (%d) листают" % [p1, p2, p3], p1 > 0 and p2 > p1 and p3 < p2)
	sc.scroll_vertical = 0
	await step(2)
	await wheel(true, sc.get_global_rect().get_center())
	var w1 := sc.scroll_vertical
	await wheel(false, sc.get_global_rect().get_center())
	check("колесо мыши над списком: вниз (%d), вверх (%d)" % [w1, sc.scroll_vertical], w1 > 0 and sc.scroll_vertical < w1)
	# покупка в середине списка: прокрутка на месте
	var mid_id: String = h.gift_rows.keys()[h.gift_rows.size() / 2]
	var mid: Dictionary = h.gift_rows[mid_id]
	g.gift_levels.erase(mid_id)
	h._refresh_gifts()
	sc.ensure_control_visible(mid.frame)
	await step(2)
	mid.button.grab_focus()
	await step(2)
	var before := sc.scroll_vertical
	var rad: int = g.radiance
	mid.button.pressed.emit()
	await step(3)
	check("покупка «%s» (прокрутка %d): уровень 1, Сияние списано, прокрутка на месте (%d)" % [tr(g.gift_defs[mid_id].name_key), before, sc.scroll_vertical],
		before > 0 and g.gift_levels.get(mid_id, 0) == 1 and g.radiance < rad and tr(mid.level.text).begins_with("1 /") and sc.scroll_vertical == before)
	var fb := sc.scroll_vertical
	var focus := root.gui_get_focus_owner()
	await key(KEY_PAGEDOWN)
	check("фокус на «Купить» (%s): PageDown листает (%d -> %d)" % [focus.get_class() if focus != null else "-", fb, sc.scroll_vertical], focus is Button and sc.scroll_vertical > fb)
	# короткий список: полосы нет
	var hidden := {}
	var keep := 2
	for id in g.gift_defs:
		hidden[id] = g.gift_defs[id].hidden
		if not g.gift_defs[id].hidden:
			if keep > 0:
				keep -= 1
			else:
				g.gift_defs[id].hidden = true
	await hub()
	check("список короче области (строк %d): полосы нет" % h.gift_rows.size(), h.gift_rows.size() == 2 and not h.gift_scroll.get_v_scroll_bar().visible
		and h.gift_list.size.y <= h.gift_scroll.size.y)
	for id in hidden:
		g.gift_defs[id].hidden = hidden[id]
	g.go_menu()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
