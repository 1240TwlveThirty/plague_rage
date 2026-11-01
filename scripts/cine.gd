extends Node
# Режим съёмки (задача 31) — дочерний узел боя (main.gd). Настройки — data/cine.json. Только отрисовка, ввод и обвязка времени:
# симуляция идёт теми же тиками (main._physics_process берёт ровный шаг тика при любом Engine.time_scale).
#   cine_key (F9): вкл/выкл. Включён — слои интерфейса боя (CanvasLayer — дети main, кроме экрана выбора карточки и меню Esc)
#     скрыты целиком, нарисованное поверх поля (main._draw, кольцо и HP героя) не рисуется; выключен — слои в прежнем виде.
#     Слой, который игра сама показала, пока режим включён (подсказка), снова скрывается, а при выходе остаётся показанным.
#   Курсор скрыт (cine_hide_cursor), в меню Esc — виден.
#   Скорость: time_scales, клавиши slower_key / faster_key / reset_key; звук — по cine_audio_follows_time_scale.
#   Камера: cine_zoom_max, cine_camera_smooth, панорама pan_keys (cine_pan_speed, реальное время).
# Скорость 1.0 и обычный звук — при выходе из режима, уходе из боя (узел покидает дерево) и закрытии игры.
const CFG := "res://data/cine.json"
const DEFAULTS := {"cine_enabled": true, "cine_key": "F9", "cine_hide_cursor": true, "time_scales": [0.1, 0.25, 0.5, 1.0, 2.0],
	"slower_key": "BracketLeft", "faster_key": "BracketRight", "reset_key": "BackSlash", "cine_audio_follows_time_scale": false,
	"cine_osd": false, "osd_seconds": 1.0, "osd_font": 30, "osd_color": "#ffffff", "osd_margin": [24, 24], "cine_zoom_max": 4.0,
	"cine_camera_smooth": 6.0, "cine_pan_speed": 600.0, "pan_keys": {"left": "Kp 4", "right": "Kp 6", "up": "Kp 8", "down": "Kp 2"},
	"autostart_scene": ""}
const FONTS := preload("res://scripts/fonts.gd")

var main: Node2D
var cfg := {}
var on := false
var keys := {}                 # действие -> физическая клавиша
var layer_vis := {}            # слой -> видимость, которую вернуть при выходе
var scale_idx := -1            # индекс в time_scales; -1 — скорость 1.0 вне списка
var cam_saved := {}            # zoom_user_max, zoom_smooth обычной игры
var mouse_saved := Input.MOUSE_MODE_VISIBLE
var osd_layer: CanvasLayer
var osd_label: Label
var osd_until_ms := 0
var scale_changes := 0         # смен скорости (тесты)


static func load_cfg() -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	var d = JSON.parse_string(FileAccess.get_file_as_string(CFG)) if FileAccess.file_exists(CFG) else null
	if not d is Dictionary:
		push_warning("%s не читается: режим съёмки по умолчанию" % CFG)
		return out
	for k in out:
		if not d.has(k):
			continue
		var num: bool = (d[k] is float or d[k] is int) and (out[k] is float or out[k] is int)
		if num or typeof(d[k]) == typeof(out[k]):
			out[k] = d[k]
		else:
			push_warning("%s: %s — не того вида; остаётся %s" % [CFG, k, str(out[k])])
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # меню Esc ставит дерево на паузу: курсор там должен быть виден
	cfg = load_cfg()
	for k in ["cine_key", "slower_key", "faster_key", "reset_key"]:
		keys[k] = _key(str(cfg[k]))
	for k in ["left", "right", "up", "down"]:
		keys["pan_" + k] = _key(str(cfg.pan_keys.get(k, DEFAULTS.pan_keys[k])))
	scale_idx = (cfg.time_scales as Array).find(1.0)


static func _key(name: String) -> Key:
	var k := OS.find_keycode_from_string(name)
	if k == KEY_NONE:
		push_warning("%s: клавиша «%s» не найдена" % [CFG, name])
	return k


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or get_tree().paused:
		return   # меню Esc и настройки (переназначение клавиш) — их ввод
	var k: Key = (event as InputEventKey).physical_keycode
	if k == keys.cine_key and keys.cine_key != KEY_NONE:
		if cfg.cine_enabled:
			set_on(not on)
			get_viewport().set_input_as_handled()
		return
	if not on:
		return
	if k == keys.slower_key:
		step_scale(-1)
	elif k == keys.faster_key:
		step_scale(1)
	elif k == keys.reset_key:
		set_scale(1.0)
	else:
		return
	get_viewport().set_input_as_handled()


# Включить или выключить режим.
func set_on(v: bool) -> void:
	if v == on:
		return
	on = v
	if on:
		layer_vis.clear()
		for c in _layers():
			layer_vis[c] = c.visible
			c.visible = false
		cam_saved = {"zoom_user_max": main.cam_cfg.zoom_user_max, "zoom_smooth": main.cam_cfg.zoom_smooth}
		main.cam_cfg.zoom_user_max = maxf(float(cfg.cine_zoom_max), float(main.cam_cfg.zoom_user_min))
		main.cam_cfg.zoom_smooth = float(cfg.cine_camera_smooth)
		mouse_saved = Input.mouse_mode
	else:
		for c in layer_vis:
			if is_instance_valid(c):
				c.visible = layer_vis[c]
		layer_vis.clear()
		set_scale(1.0)
		if not cam_saved.is_empty():
			main.cam_cfg.zoom_user_max = cam_saved.zoom_user_max
			main.cam_cfg.zoom_smooth = cam_saved.zoom_smooth
			main.zoom_user_target = clampf(main.zoom_user_target, float(main.cam_cfg.zoom_user_min), float(main.cam_cfg.zoom_user_max))
		Input.mouse_mode = mouse_saved
		if osd_layer != null:
			osd_layer.visible = false
	main.cine_on = on
	main.queue_redraw()
	if main.hero_view != null:
		main.hero_view.queue_redraw()
	_cursor()
	print("CINE|режим съёмки %s" % ("включён" if on else "выключен"))


# Слои интерфейса боя: CanvasLayer — дети main, кроме экрана выбора карточки (снимается целиком), меню Esc и своей надписи.
func _layers() -> Array:
	var out := []
	for c in main.get_children():
		if c is CanvasLayer and c != main.card_screen and c != main.esc_menu and c != osd_layer:
			out.append(c)
	return out


func step_scale(d: int) -> void:
	var list: Array = cfg.time_scales
	var i := scale_idx
	if i < 0:   # скорость вне списка: ближайший шаг в нужную сторону
		i = 0
		while i < list.size() - 1 and float(list[i]) < Engine.time_scale:
			i += 1
		if d < 0 and float(list[i]) >= Engine.time_scale:
			i -= 1
		d = 0
	set_scale(float(list[clampi(i + d, 0, list.size() - 1)]))


# Скорость игры (Engine.time_scale) и, по настройке, звука.
func set_scale(v: float) -> void:
	var changed := Engine.time_scale != v
	Engine.time_scale = v
	scale_idx = (cfg.time_scales as Array).find(v)
	AudioServer.playback_speed_scale = v if on and cfg.cine_audio_follows_time_scale else 1.0
	if not changed:
		return
	scale_changes += 1
	print("CINE|скорость ×%s" % String.num(v))
	if on and cfg.cine_osd:
		_osd("×" + String.num(v).replace(".", "," if TranslationServer.get_locale().begins_with("ru") else "."))


func _osd(text: String) -> void:
	if osd_layer == null:
		osd_layer = CanvasLayer.new()
		osd_layer.layer = 95   # над боем, под меню Esc
		osd_label = Label.new()
		osd_label.add_theme_font_size_override("font_size", FONTS.px(int(cfg.osd_font)))
		osd_label.add_theme_color_override("font_color", Color(str(cfg.osd_color)))
		osd_label.add_theme_color_override("font_outline_color", Color.BLACK)
		osd_label.add_theme_constant_override("outline_size", FONTS.outline(6))
		osd_label.position = Vector2(cfg.osd_margin[0], cfg.osd_margin[1])
		osd_label.add_to_group(&"shot_hidden")   # кадры F12 и F10 — без неё
		osd_layer.add_child(osd_label)
		add_child(osd_layer)
	osd_label.text = text
	osd_layer.visible = true
	osd_until_ms = Time.get_ticks_msec() + int(float(cfg.osd_seconds) * 1000.0)


func _process(delta: float) -> void:
	if not on:
		return
	_cursor()
	if get_tree().paused:
		return   # меню Esc: только курсор
	# слой, который игра показала сама (подсказка), снова скрыт; при выходе он вернётся показанным
	for c in _layers():
		if c.visible:
			layer_vis[c] = true
			c.visible = false
		elif not layer_vis.has(c):
			layer_vis[c] = false
	if osd_layer != null and osd_layer.visible and Time.get_ticks_msec() >= osd_until_ms:
		osd_layer.visible = false
	# панорама клавишами: реальное время (delta / скорость игры), px мира — как на экране при множителе зума 1
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(keys.pan_left):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(keys.pan_right):
		dir.x += 1.0
	if Input.is_physical_key_pressed(keys.pan_up):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(keys.pan_down):
		dir.y += 1.0
	if dir != Vector2.ZERO and main.camera != null:
		var real_dt := delta / Engine.time_scale if Engine.time_scale > 0.0 else delta
		pan(dir.normalized() * float(cfg.cine_pan_speed) * real_dt / main.zoom_user)


# Сдвиг камеры на d px мира, в пределах поля; идущий зум продолжается от нового вида.
func pan(d: Vector2) -> void:
	var cam: Camera2D = main.camera
	cam.position = main._camera_clamp(cam.position + d, cam.zoom.x)
	main.zoom_anchor_world = main.screen_to_world(main.zoom_anchor_screen)
	main.queue_redraw()


# Нужный режим курсора: скрыт в режиме съёмки (cine_hide_cursor), кроме меню Esc; иначе — как до включения.
func cursor_mode() -> Input.MouseMode:
	if on and cfg.cine_hide_cursor and not (main.esc_menu != null and main.esc_menu.visible):
		return Input.MOUSE_MODE_HIDDEN
	return mouse_saved


func _cursor() -> void:
	var want := cursor_mode()
	if Input.mouse_mode != want:
		Input.mouse_mode = want


# Уход из боя (хаб, меню, перезапуск) и закрытие игры: скорость и звук обычные, курсор виден.
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	if on:
		Input.mouse_mode = mouse_saved


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0
