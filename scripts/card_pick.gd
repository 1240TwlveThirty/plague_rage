extends CanvasLayer
# Экран выбора карточки забега: в начале передышки после волн pick_after_waves (data/cards_rules.json) сцена боя показывает тройку.
# У карточки — клавиша, название, цветная метка основного билда, описание одной строкой (издержка — часть после «;» — красным).
# Выбор мышью или клавишами 1, 2, 3 (действия card_pick_1..3 InputMap; нет в проекте — добавляются при первом открытии); пропуска нет.
# Внизу — уже выбранные карточки. Пока экран открыт, клавиши игры (кроме Esc и F11) до боя не доходят.
# Анимация (задача 25, параметры — data/card_pick_fx.json): каждая карточка — CanvasGroup с шейдером scripts/card_pick.gdshader
# (наклон с поддельной перспективой, подсветка, блик, растворение). Время анимации — реальное (Time, не скорость игры и не пауза),
# случайности — свой ГСЧ fx_rng; симуляцию не трогает.
signal picked(id: String)
signal closed   # экран закрылся (после анимации выбора или сразу): следующая фаза

const DIM := Color(0.0, 0.0, 0.0, 0.85)
const FONTS := preload("res://scripts/fonts.gd")   # кегли и контуры текста под вариант шрифта (задача 20)
const ICONS := preload("res://scripts/icons.gd")
const CARDS := preload("res://scripts/cards.gd")   # fill_desc: {hero_near_radius} в описании
const FRAME_TIMER := "res://art/card_perk_timer.png"   # рамка временной карточки
const FRAME_META := "res://art/card_meta_perk.png"     # запасная рамка (дар), окрашивается в цвет билда
const FRAME_PX := Vector2(32, 48)    # размер рамки в пикселях арта
const SCALE := 10                    # целый масштаб рамки и иконки: 320 x 480 на экране
const ICON_AT := Vector2(8, 5)       # иконка 16 x 16 в окне рамки (окно — x 3..28, y 2..45; ленточки по краям сверху)
const TEXT_RECT := Rect2(7, 22, 21, 23)   # окно под текст в пикселях рамки: правее ленточки-закладки (она слева, x 2..6, до y 30)
const LIFT := 12.0                   # насколько карточка приподнимается при наведении, px
const INK := Color(0.22, 0.13, 0.07)      # текст на светлой карточке
const COST_ON_CARD := Color(0.72, 0.1, 0.08)   # издержка на карточке
const COST_COLOR := Color(1.0, 0.35, 0.3)
const BUILD_KEYS := {"shield": "UI_BUILD_SHIELD", "archers": "UI_BUILD_ARCHERS", "gold": "UI_BUILD_GOLD", "risk": "UI_BUILD_RISK", "common": "UI_BUILD_COMMON",
	"hero": "UI_BUILD_HERO"}
const BUILD_COLORS := {"shield": Color(0.35, 0.55, 1.0), "archers": Color(0.35, 0.85, 0.45), "gold": Color(1.0, 0.8, 0.2), "risk": Color(0.9, 0.35, 0.9),
	"common": Color(0.75, 0.75, 0.75), "hero": Color(0.95, 0.45, 0.2)}
const KEYS := [KEY_1, KEY_2, KEY_3]
const SETTINGS := preload("res://scripts/settings.gd")
const FX_PATH := "res://data/card_pick_fx.json"
const CARD_SHADER := preload("res://scripts/card_pick.gdshader")
const ANIM_OFF := 0      # настройка «Анимация выбора карточки» (Settings.card_pick_anim): выкл
const ANIM_SHORT := 1    # короткая: экран гаснет за short.fade_time, без сгорания, вспышки и колец
const ANIM_FULL := 2     # полная
const GROUP_MARGIN := 48.0   # поле CanvasGroup вокруг карточки: наклон и подсветка выходят за её край

var row: HBoxContainer
var owned_label: Label
var buttons: Array[Button] = []
var offer: Array = []
var shown_defs := {}   # для пересборки при смене языка
var shown_owned: Array = []
var fx := {}                         # data/card_pick_fx.json
var groups: Array[CanvasGroup] = []  # карточка k: группа с шейдером (содержимое — Face)
var hover_k := -1                    # карточка под курсором; -1 — нет
var hover_t := PackedFloat32Array()  # сглаженное наведение 0..1
var tilt := PackedVector2Array()     # сглаженный наклон, рад
var shine := PackedVector2Array()    # сглаженное положение блика, доли карточки
var fx_rng := RandomNumberGenerator.new()   # свой ГСЧ анимации (не симуляции)
var last_us := 0                     # реальное время прошлого кадра анимации, мкс
var chosen := -1                     # выбранная карточка (эффект уже применён); -1 — выбора ещё не было
var anim_on := false                 # идёт анимация выбора: ввод заблокирован, клик или клавиша — пропуск
var anim_mode := ANIM_FULL           # режим текущей анимации
var anim_t := 0.0                    # время с момента выбора, с (реальное)
var impact_done := false
var shake_dir := Vector2.ZERO
var sel_from := Rect2()              # выбранная карточка на экране в момент выбора (px холста)
var sparks: Array = []               # искры сгорания: {p, v, age, life, color}
var spark_debt := PackedFloat32Array()   # сколько искр карточке k ещё «должно» появиться (дробная часть)
var gore_on := true
var fx_layer: Control                # вспышка, кольца, искры (поверх карточек)
var flash_tex: GradientTexture2D
var fade_nodes: Array[CanvasItem] = []   # гаснут в конце анимации
var test_mouse: Variant = null       # тесты и снимки: курсор (Vector2, px холста) вместо настоящего


func _ready() -> void:
	layer = 90
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS   # анимация идёт в реальном времени и на паузе
	fx = load_fx()
	fx_rng.randomize()
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # клики по полю под экраном не проходят
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	center.add_child(box)
	var title := Label.new()
	title.text = "UI_CARDS_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONTS.px(56))
	box.add_child(title)
	row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	box.add_child(row)
	var hint := Label.new()
	hint.text = "UI_CARDS_HINT"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", FONTS.px(24))
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	owned_label = Label.new()
	owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owned_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	owned_label.custom_minimum_size = Vector2(1400, 0)
	owned_label.add_theme_font_size_override("font_size", FONTS.px(22))
	box.add_child(owned_label)
	fx_layer = Control.new()   # вспышка, кольца и искры выбора — поверх всего экрана
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.draw.connect(_draw_fx)
	add_child(fx_layer)
	fade_nodes = [dim, center, fx_layer]
	flash_tex = GradientTexture2D.new()   # круглое пятно: белое в центре, прозрачное к краю
	flash_tex.width = 128
	flash_tex.height = 128
	flash_tex.fill = GradientTexture2D.FILL_RADIAL
	flash_tex.fill_from = Vector2(0.5, 0.5)
	flash_tex.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	flash_tex.gradient = gr


static func ensure_actions() -> void:
	for k in KEYS.size():
		var a := "card_pick_%d" % (k + 1)
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var e := InputEventKey.new()
			e.keycode = KEYS[k]
			InputMap.action_add_event(a, e)


# Показать тройку ids (карточки defs); owned — названия уже выбранных (ключи перевода).
func open(ids: Array, defs: Dictionary, owned: Array) -> void:
	ensure_actions()
	offer = ids.duplicate()
	shown_defs = defs
	shown_owned = owned.duplicate()
	for c in row.get_children():
		c.queue_free()
	buttons.clear()
	groups.clear()
	hover_k = -1
	_reset_anim()
	for k in ids.size():
		var d: Dictionary = defs[ids[k]]
		var b := _card(k, d)
		row.add_child(b)
		buttons.append(b)
		groups.append(b.get_node("Group"))
	hover_t = PackedFloat32Array()
	hover_t.resize(ids.size())
	tilt = PackedVector2Array()
	tilt.resize(ids.size())
	shine = PackedVector2Array()
	shine.resize(ids.size())
	shine.fill(Vector2(0.5, 0.5))
	last_us = Time.get_ticks_usec()
	owned_label.text = tr("UI_CARDS_OWNED") % (", ".join(owned.map(func(key): return tr(key))) if not owned.is_empty() else tr("UI_CARDS_NONE"))
	visible = true


# Карточка: рамка временной карточки (art/card_perk_timer.png) в масштабе SCALE (32 x 48 -> 320 x 480), иконка карточки в окне рамки
# (16 x 16 в точке ICON_AT рамки — над ленточкой-закладкой), под ней клавиша, название, метка билда и описание (издержка красным) —
# в пределах окна рамки. Нет текстуры рамки — рамка card_meta_perk.png, окрашенная в цвет билда. Всё — в CanvasGroup «Group»
# с шейдером карточки: наведение, наклон, блик, сгорание (задача 25).
func _card(k: int, d: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(FRAME_PX.x * SCALE, FRAME_PX.y * SCALE + LIFT)
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.pressed.connect(_pick.bind(k))
	var group := CanvasGroup.new()   # рисует карточку в буфер, шейдер наклоняет и подсвечивает её (задача 25)
	group.name = "Group"
	group.fit_margin = GROUP_MARGIN
	group.clear_margin = GROUP_MARGIN
	group.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = CARD_SHADER
	group.material = mat
	b.add_child(group)
	var face := Control.new()   # содержимое карточки
	face.name = "Face"
	face.position = Vector2(0, LIFT)
	face.size = FRAME_PX * SCALE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(face)
	var frame := TextureRect.new()
	frame.name = "Frame"
	var timer_frame := ResourceLoader.exists(FRAME_TIMER)
	frame.texture = load(FRAME_TIMER if timer_frame else FRAME_META)
	if not timer_frame:
		frame.modulate = BUILD_COLORS[d.builds[0]].lerp(Color.WHITE, 0.35)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.size = FRAME_PX * SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(frame)
	var icon := ICONS.make(ICONS.of_card(d.id), SCALE)
	icon.name = "Icon"
	icon.position = ICON_AT * SCALE
	face.add_child(icon)
	var key := _text(face, "[%s]" % key_text(k), 20, INK.lerp(Color.TRANSPARENT, 0.35))
	key.name = "Key"
	key.autowrap_mode = TextServer.AUTOWRAP_OFF
	key.position = Vector2(24 * SCALE, 3 * SCALE)   # правый верхний угол окна (ленточка слева)
	var col := VBoxContainer.new()
	col.position = TEXT_RECT.position * SCALE + Vector2(6, 0)
	col.size = TEXT_RECT.size * SCALE - Vector2(12, 0)
	col.custom_minimum_size.x = col.size.x
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(col)
	var nm := _text(col, d.name_key, 24, INK)
	nm.name = "Name"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var build: String = d.builds[0]
	var tag := _text(col, BUILD_KEYS[build], 18, BUILD_COLORS[build].darkened(0.45))
	tag.name = "Build"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var desc := RichTextLabel.new()
	desc.name = "Desc"
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.add_theme_font_size_override("normal_font_size", FONTS.px(18))
	desc.add_theme_color_override("default_color", INK)
	desc.custom_minimum_size.x = col.size.x
	desc.text = desc_bbcode(CARDS.fill_desc(tr(d.desc_key)), COST_ON_CARD)
	col.add_child(desc)
	b.mouse_entered.connect(_hover.bind(k, true))
	b.mouse_exited.connect(_hover.bind(k, false))
	return b


func _hover(k: int, on: bool) -> void:
	if on:
		hover_k = k
	elif hover_k == k:
		hover_k = -1


# data/card_pick_fx.json; нет файла или он битый — пусто (анимации нет, выбор как раньше), с предупреждением.
static func load_fx() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(FX_PATH)) if FileAccess.file_exists(FX_PATH) else null
	if not d is Dictionary:
		push_warning("%s не читается: выбор карточки без анимации" % FX_PATH)
		return {}
	return d


# Кадр анимации в реальном времени: шаг — от прошлого кадра по Time, не delta (скорость игры и пауза на анимацию не влияют).
func _process(_delta: float) -> void:
	if not visible:
		return
	var now := Time.get_ticks_usec()
	var dt := minf((now - last_us) / 1e6, 0.1)
	last_us = now
	fx_step(dt)


# Шаг анимации на dt с (тесты и снимки зовут напрямую с ровным шагом).
func fx_step(dt: float) -> void:
	if fx.is_empty() or groups.is_empty():
		return
	if anim_on:
		_anim_step(dt)
	else:
		_hover_step(dt)


# --- Анимация выбора (этап 3) ---------------------------------------------------------------------------------------------------

# Полная длительность анимации режима mode по данным fx (с): полная — до конца колец или затухания, что позже.
static func total_time(f: Dictionary, mode: int) -> float:
	if mode == ANIM_OFF or f.is_empty():
		return 0.0
	if mode == ANIM_SHORT:
		return float(f.short.fade_time)
	var i: Dictionary = f.impact
	var t_hit := float(f.move.move_time) + float(f.move.punch_time)
	var rings := float(i.ring_time) + float(i.ring_delay) * maxf(float(i.ring_count) - 1.0, 0.0) if int(i.ring_count) > 0 else 0.0
	return t_hit + maxf(maxf(float(i.hold_time) + float(i.fade_time), rings), maxf(float(i.flash_time), float(i.shake_time)))


# Момент удара (с от выбора).
func impact_time() -> float:
	return float(fx.move.move_time) + float(fx.move.punch_time)


func _reset_anim() -> void:
	chosen = -1
	anim_on = false
	anim_t = 0.0
	impact_done = false
	sparks.clear()
	offset = Vector2.ZERO
	for n in fade_nodes:
		n.modulate.a = 1.0
	if fx_layer != null:
		fx_layer.queue_redraw()


func _start_anim() -> void:
	anim_t = 0.0
	impact_done = false
	sparks.clear()
	spark_debt = PackedFloat32Array()
	spark_debt.resize(groups.size())
	var st := get_node_or_null("/root/Settings")
	gore_on = st == null or int(st.gore) > 0
	sel_from = card_rect(chosen, false)
	var g := groups[chosen]
	g.top_level = true   # выезжает из ряда: положение — в координатах холста
	g.z_index = 10
	for k in groups.size():
		(groups[k].material as ShaderMaterial).set_shader_parameter("burn_seed", fx_rng.randf() * 100.0)
		if k != chosen:
			var e: Array = fx.burn.edge_colors if gore_on else fx_dust_colors()
			_set_card(k, {"edge_a": Color(e[0]), "edge_b": Color(e[mini(1, e.size() - 1)]), "burn_edge": float(fx.burn.burn_edge)})
	_anim_step(0.0)


# Цвета пыли («Жестокость: выкл»): data/fx.json dust_colors — кромка и искры без огня.
static func fx_dust_colors() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/fx.json"))
	var c = d.get("dust_colors") if d is Dictionary else null
	return c if c is Array and not c.is_empty() else ["#8b9bb4", "#5a6988"]


func _anim_step(dt: float) -> void:
	anim_t += dt
	var t := anim_t
	var total := total_time(fx, anim_mode)
	var alpha := 1.0
	if anim_mode == ANIM_SHORT:
		alpha = 1.0 - clampf(t / maxf(total, 0.001), 0.0, 1.0)
		for k in groups.size():
			_set_card(k, {"hover": 0.0, "shine_alpha": 0.0})
	else:
		var mv: Dictionary = fx.move
		var im: Dictionary = fx.impact
		var t_move := float(mv.move_time)
		var t_hit := impact_time()
		# выбранная: дуга к центру экрана с замедлением, рост; удар — быстрый рост
		var vs := get_viewport().get_visible_rect().size
		var c0 := sel_from.get_center()
		var c1 := vs * 0.5
		var sc0 := sel_from.size.x / (FRAME_PX.x * SCALE)
		var sc := sc0
		var c := c1
		if t < t_move:
			var e := 1.0 - pow(1.0 - t / t_move, float(mv.move_ease_power))
			var ctrl := (c0 + c1) * 0.5 - Vector2(0, float(mv.arc_px))
			c = c0.lerp(ctrl, e).lerp(ctrl.lerp(c1, e), e)   # квадратичная кривая Безье
			sc = lerpf(sc0, float(mv.center_scale), e)
		elif t < t_hit:
			sc = lerpf(float(mv.center_scale), float(mv.punch_scale), pow((t - t_move) / float(mv.punch_time), float(mv.punch_ease_power)))
		else:
			sc = float(mv.punch_scale)
		var g := groups[chosen]
		var size := FRAME_PX * SCALE * sc
		g.scale = Vector2(sc, sc)
		g.global_position = Vector2(roundf(c.x - size.x * 0.5), roundf(c.y - size.y * 0.5)) - Vector2(0, LIFT) * sc
		var calm := clampf(1.0 - t / maxf(t_move, 0.001), 0.0, 1.0)   # наклон и блик уходят к центру
		tilt[chosen] = tilt[chosen] * calm
		_set_card(chosen, {"hover": calm, "tilt": tilt[chosen], "shine_alpha": float(fx.hover.shine_alpha) * calm, "dim": 1.0})
		# остальные сгорают
		var bt := float(fx.burn.burn_time)
		var burn := clampf(t / maxf(bt, 0.001), 0.0, 1.0)
		for k in groups.size():
			if k == chosen:
				continue
			_set_card(k, {"burn": burn, "hover": 0.0, "shine_alpha": 0.0, "dim": 1.0, "alpha": 0.0 if burn >= 1.0 else 1.0})
			if t <= bt and dt > 0.0:
				spark_debt[k] += float(fx.burn.sparks_per_card) * dt / maxf(bt, 0.001)
				while spark_debt[k] >= 1.0:
					spark_debt[k] -= 1.0
					_spark(card_rect(k, false))
		# удар: тряска (настройка «Тряска экрана»), вспышка и кольца рисует fx_layer
		if t >= t_hit and not impact_done:
			impact_done = true
			shake_dir = Vector2.from_angle(fx_rng.randf() * TAU)
		var st_t := t - t_hit
		var amp := float(im.shake_px) * shake_mult() * (1.0 - st_t / maxf(float(im.shake_time), 0.001)) if impact_done else 0.0
		if amp > 0.0 and st_t < float(im.shake_time):
			shake_dir = shake_dir.rotated(PI * 0.5 + fx_rng.randf_range(-0.6, 0.6))   # каждый кадр в другую сторону
			var o := shake_dir * maxf(roundf(amp), 1.0)
			offset = Vector2(roundf(o.x), roundf(o.y))
		else:
			offset = Vector2.ZERO
		alpha = 1.0 - clampf((t - t_hit - float(im.hold_time)) / maxf(float(im.fade_time), 0.001), 0.0, 1.0)
	for i in range(sparks.size() - 1, -1, -1):
		var sp: Dictionary = sparks[i]
		sp.age += dt
		if sp.age >= sp.life:
			sparks.remove_at(i)
			continue
		sp.v += Vector2(0, float(fx.burn.spark_gravity)) * dt
		sp.p += sp.v * dt
	for n in fade_nodes:
		n.modulate.a = alpha
	_set_card(chosen, {"alpha": alpha})   # выбранная — top_level: прозрачность экрана ей не передаётся, гаснет шейдером
	fx_layer.queue_redraw()
	if t >= total:
		_finish()


# Множитель тряски выбора: уровень настройки «Тряска экрана» (data/fx.json shake_levels; выкл — 0, тряски нет).
func shake_mult() -> float:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/fx.json"))
	if not d is Dictionary or not d.get("screen_shake_enabled", true):
		return 0.0
	var levels: Array = d.get("shake_levels", [0.0, 0.5, 1.0, 1.5])
	var st := get_node_or_null("/root/Settings")
	var lvl: int = st.screen_shake_level if st != null else 2
	return float(levels[clampi(lvl, 0, levels.size() - 1)])


# Искра у случайной точки сгорающей карточки r: вверх и в стороны.
func _spark(r: Rect2) -> void:
	var b: Dictionary = fx.burn
	var cols: Array = b.spark_colors if gore_on else fx_dust_colors()
	var dir := Vector2.from_angle(-PI * 0.5 + fx_rng.randf_range(-1.1, 1.1))
	sparks.append({"p": r.position + Vector2(fx_rng.randf(), fx_rng.randf()) * r.size,
		"v": dir * fx_rng.randf_range(b.spark_speed[0], b.spark_speed[1]), "age": 0.0,
		"life": fx_rng.randf_range(b.spark_life[0], b.spark_life[1]), "color": Color(cols[fx_rng.randi() % cols.size()])})


# Вспышка (пятно, не на весь экран, гаснет линейно — без мерцания), кольца-волны из центра, искры — квадраты целых px.
func _draw_fx() -> void:
	if not anim_on or anim_mode != ANIM_FULL:
		return
	var px := float(fx.burn.spark_px)
	for sp in sparks:
		var col: Color = sp.color
		col.a = 1.0 - sp.age / sp.life
		fx_layer.draw_rect(Rect2(sp.p.round() - Vector2(px, px) * 0.5, Vector2(px, px)), col)
	if not impact_done:
		return
	var im: Dictionary = fx.impact
	var t := anim_t - impact_time()
	var c := fx_layer.get_viewport_rect().size * 0.5
	if t < float(im.flash_time):
		var fc := Color(im.flash_color)
		fc.a = float(im.flash_alpha) * (1.0 - t / float(im.flash_time))
		var r := float(im.flash_radius_px)
		fx_layer.draw_texture_rect(flash_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, fc)
	for n in int(im.ring_count):
		var rt := (t - float(im.ring_delay) * n) / float(im.ring_time)
		if rt <= 0.0 or rt >= 1.0:
			continue
		var rc := Color(im.ring_color)
		rc.a = 1.0 - rt
		var e := 1.0 - pow(1.0 - rt, 2.0)   # быстро в начале, медленнее к краю
		fx_layer.draw_arc(c, maxf(float(im.ring_radius_px) * e, 1.0), 0.0, TAU, 96, rc, float(im.ring_px))


# Конец: экран закрыт, всё на местах для следующего открытия; closed — следующая фаза.
func _finish() -> void:
	var was := chosen
	anim_on = false
	visible = false
	offset = Vector2.ZERO
	sparks.clear()
	for n in fade_nodes:
		n.modulate.a = 1.0
	if was >= 0 and was < groups.size():
		groups[was].top_level = false
	closed.emit()


# Наведение: подъём, увеличение, наклон к курсору и блик за ним — экспоненциальное сглаживание (hover.smooth); остальные темнее.
func _hover_step(dt: float) -> void:
	var h: Dictionary = fx.hover
	var a := 1.0 - exp(-float(h.smooth) * dt)   # доля пути к цели за dt
	var mouse: Vector2 = test_mouse if test_mouse is Vector2 else get_viewport().get_mouse_position() - Vector2(offset)
	var top := 0.0   # наведение карточки под курсором (для затемнения остальных)
	if hover_k >= 0 and hover_k < hover_t.size():
		top = hover_t[hover_k]
	for k in groups.size():
		var on := k == hover_k
		hover_t[k] = lerpf(hover_t[k], 1.0 if on else 0.0, a)
		var target := Vector2.ZERO
		var sh := Vector2(0.5, 0.5)
		if on:
			var r := card_rect(k, false)
			var rel := ((mouse - r.get_center()) / (r.size * 0.5)).clamp(Vector2(-1, -1), Vector2(1, 1))
			var mx := deg_to_rad(float(h.tilt_max_deg))
			target = Vector2(-rel.y * mx, rel.x * mx)   # край карточки под курсором уходит «вглубь»
			sh = (mouse - r.position) / r.size
		tilt[k] = tilt[k].lerp(target, a)
		shine[k] = shine[k].lerp(sh, a)
		var e := hover_t[k]
		place_card(k, lerpf(1.0, float(h.scale), e), Vector2(0, -float(h.lift_px) * e))
		_set_card(k, {"hover": e, "tilt": tilt[k], "shine_pos": shine[k], "shine_alpha": float(h.shine_alpha) * e,
			"dim": 1.0 if on else lerpf(1.0, float(h.others_dim), top)})


# Группа карточки k: масштаб sc вокруг центра карточки и сдвиг shift (px) от её места в ряду.
func place_card(k: int, sc: float, shift: Vector2) -> void:
	var size := FRAME_PX * SCALE
	var g := groups[k]
	g.scale = Vector2(sc, sc)
	g.position = Vector2(size.x, size.y + 2.0 * LIFT) * 0.5 * (1.0 - sc) + shift   # центр Face (0, LIFT)..size остаётся на месте


# Прямоугольник карточки (Face) на экране: px холста; screen_uv — в долях экрана (для шейдера).
func card_rect(k: int, screen_uv := true) -> Rect2:
	var xf := groups[k].get_global_transform_with_canvas()
	var r := Rect2(xf * Vector2(0, LIFT), FRAME_PX * SCALE * xf.get_scale())
	if screen_uv:
		var vs := get_viewport().get_visible_rect().size
		r = Rect2(r.position / vs, r.size / vs)
	return r


# Параметры шейдера карточки k (+ её место на экране).
func _set_card(k: int, p: Dictionary) -> void:
	var m := groups[k].material as ShaderMaterial
	var h: Dictionary = fx.hover
	var r := card_rect(k, false)
	var uv := card_rect(k)
	m.set_shader_parameter("card_uv_rect", Vector4(uv.position.x, uv.position.y, uv.size.x, uv.size.y))
	m.set_shader_parameter("card_px", r.size)
	m.set_shader_parameter("perspective_px", float(h.perspective_px))
	m.set_shader_parameter("glow_color", Color(h.glow_color))
	m.set_shader_parameter("glow_px", float(h.glow_px))
	m.set_shader_parameter("shine_radius", float(h.shine_radius))
	m.set_shader_parameter("burn_cells", FRAME_PX * SCALE / maxf(float(fx.burn.burn_cell_px), 1.0))
	for key in p:
		m.set_shader_parameter(key, p[key])


# Описание: часть после «;» (издержка) — красным.
static func desc_bbcode(text: String, cost := COST_COLOR) -> String:
	var at := text.find(";")
	if at < 0:
		return text
	return "%s;[color=#%s]%s[/color]" % [text.left(at), cost.to_html(false), text.substr(at + 1)]


# Подпись клавиши выбора k-й карточки: «1», «2», «3» (или что назначено действию card_pick_N).
static func key_text(k: int) -> String:
	ensure_actions()
	return SETTINGS.key_label("card_pick_%d" % (k + 1))


func _text(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", FONTS.px(size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# Смена языка при открытом экране: описания и список выбранных собраны через tr() — собрать заново.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and visible and not offer.is_empty() and chosen < 0:
		open(offer, shown_defs, shown_owned)


# Выбор k: эффект карточки применяется сразу и ровно один раз (picked; повторный выбор, двойной клик — не действуют), дальше —
# только вид: анимация по настройке (выкл — экран закрывается сразу), в конце — closed.
func _pick(k: int) -> void:
	if not visible or k >= offer.size() or chosen >= 0:
		return
	chosen = k
	anim_mode = setting_mode() if not fx.is_empty() else ANIM_OFF
	anim_on = anim_mode != ANIM_OFF
	if anim_on:
		_start_anim()
	picked.emit(offer[k])
	if not anim_on:
		_finish()


# Настройка «Анимация выбора карточки» (Settings.card_pick_anim); без автозагрузки — полная.
func setting_mode() -> int:
	var st := get_node_or_null("/root/Settings")
	var v = st.get("card_pick_anim") if st != null else null
	return int(v) if v != null else ANIM_FULL


# Пропуск: сразу конечное состояние и следующая фаза (эффект уже применён при выборе).
func finish_now() -> void:
	if anim_on:
		_finish()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if anim_on:   # анимация: ввод заблокирован; клик или любая клавиша (кроме Esc и F11) — пропуск
		var key := event as InputEventKey
		if key != null and (key.keycode == KEY_ESCAPE or key.keycode == KEY_F11):
			return
		if (key != null and key.pressed and not key.echo) or (event is InputEventMouseButton and event.pressed):
			finish_now()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_F11:
		return   # меню паузы и полный экран работают и здесь
	for k in offer.size():
		if event.is_action_pressed("card_pick_%d" % (k + 1)):
			_pick(k)
			break
	get_viewport().set_input_as_handled()
