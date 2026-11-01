extends Node
# Режим скриншотов (задача 25) — автозагрузка Shots. Настройки — data/screenshot.json.
#   shot_key (F12): кадр size (1920x1080) без отладочных надписей (узлы группы shot_hidden: строка FPS, подсказка мыши) —
#     user://<dir>/shot_<дата>_<время>.png.
#   record_key (F10): запись последовательности кадров с частотой record_fps (реальное время) в user://<dir>/rec_<дата>_<время>/
#     для гифки; повторное нажатие — стоп; не больше record_max_frames кадров (дальше запись выключается сама).
#   Параметры запуска (после «--»): --scene=battle|respite|pick|hub|menu — заготовленная сцена с фиксированным seed на своём временном
#     сохранении (сохранение игрока не трогается); --shot — после сцены кадр и выход (печатает SHOT|путь); --shot-dir=<папка> —
#     куда класть кадры вместо user://<dir>; --shot-native — кадр в размере окна, без приведения к size (окно 1280x720 и т. п.).
#     Для хаба (задача 28в): --hub-tab=siege|gifts, --hub-scroll=top|bottom (список даров), --diary (дневник со всеми записями
#     открыт); --lang=ru|en — язык сцены (настройки игрока не меняются); --window=1280x720 — размер окна в пикселях экрана
#     (--resolution Godot на экране с масштабом Windows даёт окно крупнее). Бой и передышка: --banner=show — баннер не скрывать
#     (задача 30: баннер с кнопкой «×»).
# Ничего не меняет в симуляции: сцена battle прокручивает тики так же, как обычный бой, и с --shot останавливает физику для кадра.
signal saved(path: String)

const CFG := "res://data/screenshot.json"
const SCENES := ["battle", "respite", "pick", "hub", "menu"]
const HIDDEN_GROUP := &"shot_hidden"
const DT := 1.0 / 30.0

var cfg := {}
var shot_key := KEY_F12
var record_key := KEY_F10
var shot_dir := ""             # папка кадров (абсолютный путь)
var recording := false
var rec_dir := ""
var rec_n := 0
var rec_acc := 0.0
var rec_last_us := 0
var scene_arg := ""
var shot_and_quit := false
var shot_native := false       # --shot-native: кадр в размере окна
var scene_opts := {}           # --hub-tab, --hub-scroll, --diary, --lang


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var d = JSON.parse_string(FileAccess.get_file_as_string(CFG)) if FileAccess.file_exists(CFG) else null
	cfg = d if d is Dictionary else {}
	if cfg.is_empty():
		push_warning("%s не читается: режим скриншотов с клавишами по умолчанию (F12, F10)" % CFG)
	shot_key = _key(cfg.get("shot_key", "F12"), KEY_F12)
	record_key = _key(cfg.get("record_key", "F10"), KEY_F10)
	shot_dir = ProjectSettings.globalize_path("user://".path_join(str(cfg.get("dir", "screenshots"))))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_arg = a.trim_prefix("--scene=")
		elif a == "--shot":
			shot_and_quit = true
		elif a.begins_with("--shot-dir="):
			shot_dir = a.trim_prefix("--shot-dir=")
		elif a == "--shot-native":
			shot_native = true
		elif a == "--diary":
			scene_opts["diary"] = true
		else:
			for k in ["--hub-tab=", "--hub-scroll=", "--lang=", "--window=", "--banner="]:
				if a.begins_with(k):
					scene_opts[k.trim_prefix("--").trim_suffix("=")] = a.trim_prefix(k)
	if scene_arg != "":
		if scene_arg in SCENES:
			_run_scene.call_deferred(scene_arg)
		else:
			push_error("--scene=%s: нужна одна из %s" % [scene_arg, ", ".join(SCENES)])
			if shot_and_quit:
				get_tree().quit(2)


static func _key(name, fallback: Key) -> Key:
	var k := OS.find_keycode_from_string(str(name))
	return k if k != KEY_NONE else fallback


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == shot_key:
		capture()
		get_viewport().set_input_as_handled()
	elif k.keycode == record_key:
		set_recording(not recording)
		get_viewport().set_input_as_handled()


func _hide_debug(on: bool) -> void:
	for n in get_tree().get_nodes_in_group(HIDDEN_GROUP):
		if n is CanvasItem:
			if on:
				n.set_meta("shot_was_visible", n.visible)
				n.visible = false
			elif n.has_meta("shot_was_visible"):
				n.visible = n.get_meta("shot_was_visible")
				n.remove_meta("shot_was_visible")


# Кадр size без отладочных надписей. Возвращает путь (и сигнал saved); "" — не удалось.
func capture() -> String:
	if not recording:
		_hide_debug(true)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if not recording:
		_hide_debug(false)
	var path := shot_dir.path_join("shot_%s.png" % _stamp())
	if not _save(img, path, 0 if shot_native else 1):
		return ""
	print("SHOT|%s" % path)
	saved.emit(path)
	return path


func set_recording(on: bool) -> void:
	if on == recording:
		return
	recording = on
	if on:
		rec_dir = shot_dir.path_join("rec_%s" % _stamp())
		DirAccess.make_dir_recursive_absolute(rec_dir)
		rec_n = 0
		rec_acc = 1.0   # первый кадр сразу
		rec_last_us = Time.get_ticks_usec()
		_hide_debug(true)
		print("REC|start|%s" % rec_dir)
	else:
		_hide_debug(false)
		print("REC|stop|%s|кадров %d" % [rec_dir, rec_n])


# Запись: кадр раз в 1/record_fps с реального времени (не скорость игры), не больше record_max_frames.
func _process(_delta: float) -> void:
	if not recording:
		return
	var now := Time.get_ticks_usec()
	rec_acc += (now - rec_last_us) / 1e6
	rec_last_us = now
	var period := 1.0 / maxf(float(cfg.get("record_fps", 15)), 1.0)
	if rec_acc < period:
		return
	rec_acc = fmod(rec_acc, period)
	var img := get_viewport().get_texture().get_image()
	_save(img, rec_dir.path_join("frame_%05d.png" % rec_n), maxi(int(cfg.get("record_downscale", 1)), 1))
	rec_n += 1
	if rec_n >= int(cfg.get("record_max_frames", 300)):
		print("REC|limit|%d" % rec_n)
		set_recording(false)


# Кадр в size (окно другого размера — масштаб), уменьшенный в down раз; папка создаётся.
func _save(img: Image, path: String, down: int) -> bool:
	var size: Array = cfg.get("size", [1920, 1080])
	if down == 0:   # --shot-native: как есть
		size = [img.get_width(), img.get_height()]
		down = 1
	var w := int(size[0]) / down
	var h := int(size[1]) / down
	if img.get_width() != w or img.get_height() != h:
		img.resize(w, h, Image.INTERPOLATE_LANCZOS if down == 1 else Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		push_error("Кадр не сохранён: %s (%d)" % [path, err])
	return err == OK


static func _stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [t.year, t.month, t.day, t.hour, t.minute, t.second, Time.get_ticks_msec() % 1000]


# Сцена боя добавлена: физика выключена с готовности узла, тики идут только из _run_scene.
func _freeze_main(n: Node) -> void:
	if n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		get_tree().node_added.disconnect(_freeze_main)
		n.ready.connect(func(): n.set_physics_process(false), CONNECT_ONE_SHOT)


# --- Заготовленные сцены ---------------------------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run_scene(which: String) -> void:
	var g: Node = get_node_or_null("/root/Game")
	if g == null:
		push_error("--scene: нет автозагрузки Game")
		return
	var save := "user://scene_save.json"   # своё сохранение: прогресс игрока не меняется
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	g.save_path = save
	g._setup()
	g.run_seed = int(cfg.get("scene_seed", 3))
	if scene_opts.has("lang"):
		TranslationServer.set_locale(str(scene_opts.lang))
	if scene_opts.has("window"):
		var wh := str(scene_opts.window).split("x")
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		await _frames(4)
	await _frames(2)
	match which:
		"menu":
			g.go_menu()
			await _frames(4)
		"hub":
			g.radiance = int(cfg.get("hub_radiance", 0))
			if scene_opts.get("diary", false):   # все записи дневника прочитаны
				g.diary_seen = [g.INTRO_ID]
				for e in g.story.get("entries", []):
					g.diary_seen.append(e.id)
			g.go_hub()
			await _frames(4)
			var h: Node = get_tree().current_scene
			if scene_opts.get("hub-tab", "") == "gifts":
				h.tabs.current_tab = 1
				await _frames(4)
				if scene_opts.get("hub-scroll", "top") == "bottom":
					h.gift_scroll.scroll_vertical = int(h.gift_scroll.get_v_scroll_bar().max_value)
			if scene_opts.get("diary", false):
				h._open_diary()
		_:
			if which == "battle":   # физика — только тики сцены: движок до них не прогоняет ни одного (кадр повторяем)
				get_tree().node_added.connect(_freeze_main)
			g.start_run(1)
			await _frames(6)
			var m: Node = get_tree().current_scene
			if scene_opts.get("banner", "") != "show":   # --banner=show (задача 30): баннер с «×» на кадре
				m.banner_hidden = true
				m.banner.visible = false
			if which == "battle":
				m.wave_number = int(cfg.get("battle_wave", 10)) - 1
				m.wave_plan_for = -1
				m._start_wave()
				m.set_physics_process(false)   # тики — здесь, ровно battle_ticks (кадр повторяем)
				for t in int(cfg.get("battle_ticks", 600)):
					if m.wave_state != m.WS_BATTLE:
						break
					m._physics_process(DT)
				m.set_physics_process(not shot_and_quit)
				m.banner.visible = false
				m._update_ui()
				m.shop_slide_step(1.0)   # магазин уже уехал (в бою закрыт), не на середине выезда
			elif which == "pick":
				m.wave_number = int(m.card_rules.pick_after_waves[0])
				m._offer_cards()
				if shot_and_quit and not m.card_screen.groups.is_empty():
					await _frames(3)   # ряд карточек разложен — их места на экране известны
					var r: Rect2 = m.card_screen.card_rect(1, false)
					m.card_screen.test_mouse = r.position + r.size * Vector2(0.8, 0.2)   # наведение с наклоном на средней
					m.card_screen._hover(1, true)
					await _frames(int(cfg.get("pick_hover_frames", 40)))   # наведение доходит до цели (реальное время)
	await _frames(int(cfg.get("scene_settle_frames", 12)))
	print("SCENE|%s|seed %d" % [which, int(cfg.get("scene_seed", 3))])
	if shot_and_quit:
		var p := await capture()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
		get_tree().quit(0 if p != "" else 1)
