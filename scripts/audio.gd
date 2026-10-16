extends Node
# Звук — автозагрузка Audio (работает и на паузе). Данные — data/audio.json: для каждого звука путь, шина (Music / SFX),
# громкость в dB и loop; время перехода между темами, очередь боевых тем, частота звука наведения, разброс высоты.
# Музыка: два плеера, переход Tween'ом. Какая тема нужна — по текущей сцене: меню — main_menu, хаб — hub, бой —
# respite в передышке (и на экране итога) и боевые темы во время волны: они чередуются по очереди battle_queue,
# очередная плавно вступает за crossfade_sec до конца текущей; индекс очереди живёт между волнами. Нужная тема уже
# играет — ничего не перезапускается. Эффекты: на каждую кнопку (get_tree().node_added) — наведение (hover, не чаще
# hover_min_interval_ms) и нажатие (звук из meta «sfx» кнопки, иначе clicks_in_hub); вкладки — clicks_in_hub.
# Нет файла или он не загрузился — предупреждение в лог, игра идёт без этого звука. ГСЧ симуляции и тики не трогаются:
# разброс высоты — свой RandomNumberGenerator.
const CONFIG_PATH := "res://data/audio.json"
const SILENT_DB := -60.0
const SFX_POOL := 6                # одновременных эффектов
const DEFAULT_SFX := "clicks_in_hub"

var cfg_path := CONFIG_PATH
var sounds := {}                   # имя -> {path, bus, volume_db, loop}
var crossfade := 1.75              # с, переход между темами
var hover_min_ms := 40
var pitch_jitter := 0.03
var battle_queue: Array = []
var battle_idx := 0                # какая боевая тема следующая (растёт без сброса между волнами)
var test_theme_len := 0.0          # > 0: тесты считают боевую тему такой длины, с — ускоренная проверка чередования
var streams := {}                  # имя -> AudioStream или null (не загрузился)
var music: Array[AudioStreamPlayer] = []
var active := 0                    # индекс плеера с текущей темой
var current := ""                  # имя текущей темы ("" — тишина)
var mode := ""                     # "main_menu", "hub", "respite", "battle" или "" (сцены нет)
var fade: Tween
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_next := 0
var rng := RandomNumberGenerator.new()
var last_hover_ms := -100000
var log_lines := PackedStringArray()   # «main_menu», «hub», … — смены музыки по порядку (тесты читают)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # пауза игры (Esc) музыку не останавливает
	ensure_buses()
	_load_config()
	rng.randomize()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.finished.connect(_on_music_finished.bind(i))
		add_child(p)
		music.append(p)
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_players.append(p)
	get_tree().node_added.connect(_on_node_added)


# Шины Music и SFX (в Master); нет — создать. Вызывает и Settings до применения громкости.
static func ensure_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


func _load_config() -> void:
	sounds = {}
	if not FileAccess.file_exists(cfg_path):
		push_warning("Нет %s: игра без звука" % cfg_path)
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(cfg_path))
	if not d is Dictionary or not d.get("sounds") is Dictionary:
		push_warning("%s: нет объекта sounds — игра без звука" % cfg_path)
		return
	crossfade = float(d.get("crossfade_sec", crossfade))
	hover_min_ms = int(d.get("hover_min_interval_ms", hover_min_ms))
	pitch_jitter = float(d.get("pitch_jitter", pitch_jitter))
	battle_queue = d.get("battle_queue", []) if d.get("battle_queue") is Array else []
	for name in d.sounds:
		var e = d.sounds[name]
		if not e is Dictionary or not e.get("path") is String or not e.get("bus") in ["Music", "SFX"]:
			push_warning("%s: звук %s без path или с шиной не Music/SFX — пропущен" % [cfg_path, name])
			continue
		sounds[name] = {"path": e.path, "bus": e.bus, "volume_db": float(e.get("volume_db", 0.0)), "loop": bool(e.get("loop", false))}


# Поток звука (загружается при первом обращении); нет записи или файла — null и одно предупреждение.
func _stream(name: String) -> AudioStream:
	if streams.has(name):
		return streams[name]
	var s: AudioStream = null
	if not sounds.has(name):
		push_warning("Звука %s нет в %s" % [name, cfg_path])
	elif not ResourceLoader.exists(sounds[name].path):
		push_warning("Нет файла звука %s: %s" % [name, sounds[name].path])
	else:
		s = load(sounds[name].path) as AudioStream
		if s == null:
			push_warning("Звук %s не загрузился: %s" % [name, sounds[name].path])
		else:
			_set_loop(s, sounds[name].loop)
	streams[name] = s
	return s


# Цикл по типу ресурса: loop у MP3 и Ogg, loop_mode у WAV (конец цикла — конец данных); .import не трогается.
static func _set_loop(s: AudioStream, on: bool) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.set("loop", on)


func _process(_delta: float) -> void:
	var want := _scene_mode()
	if want != mode:
		set_mode(want)
	elif mode == "battle" and battle_queue.size() > 0 and (fade == null or not fade.is_running()):
		# боевая тема подходит к концу: следующая по очереди вступает за crossfade до конца
		var p := music[active]
		if p.playing and p.stream != null:
			var length := test_theme_len if test_theme_len > 0.0 else p.stream.get_length()
			if length - p.get_playback_position() <= crossfade:
				_next_battle()


# Тема по текущей сцене: Menu — main_menu, Hub — hub, бой — battle во время волны, иначе respite.
func _scene_mode() -> String:
	var sc := get_tree().current_scene
	if sc == null:
		return ""
	if sc.name == "Menu":
		return "main_menu"
	if sc.name == "Hub":
		return "hub"
	if "wave_state" in sc and "WS_BATTLE" in sc:
		return "battle" if sc.wave_state == sc.WS_BATTLE else "respite"
	return ""


func set_mode(m: String) -> void:
	mode = m
	if m == "":
		return
	if m == "battle":
		if current in battle_queue:
			return   # боевая тема уже играет
		_next_battle()
	else:
		play_music(m)


func _next_battle() -> void:
	if battle_queue.is_empty():
		return
	var name: String = battle_queue[battle_idx % battle_queue.size()]
	battle_idx += 1
	play_music(name, true)


# Сменить тему с переходом; та же тема уже играет — ничего (force — боевая очередь: следующая может совпасть по имени
# с текущей только при очереди из одной темы, тогда тоже перезапуск с переходом).
func play_music(name: String, force := false) -> void:
	if name == current and not force:
		return
	var from := current
	current = name
	log_lines.append(name)
	print("Audio: музыка %s -> %s" % [from if from != "" else "тишина", name])
	var stream := _stream(name)
	var old := music[active]
	var new := music[1 - active]
	if fade != null and fade.is_running():
		fade.kill()
		fade = null
	new.stop()   # мог ещё затухать с прошлого перехода
	fade = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if stream != null:
		new.stream = stream
		new.volume_db = SILENT_DB
		new.play()
		fade.tween_property(new, "volume_db", sounds[name].volume_db, crossfade)
		active = 1 - active
	if old.playing:
		fade.tween_property(old, "volume_db", SILENT_DB, crossfade)
		fade.chain().tween_callback(old.stop)


# Тема доиграла (переход почему-то не сработал): в бою — следующая по очереди сразу.
func _on_music_finished(i: int) -> void:
	if i == active and mode == "battle" and current in battle_queue:
		_next_battle()


func play_sfx(name: String) -> void:
	var stream := _stream(name)
	if stream == null:
		return
	var p := sfx_players[sfx_next]
	sfx_next = (sfx_next + 1) % sfx_players.size()
	p.stream = stream
	p.volume_db = sounds[name].volume_db
	p.pitch_scale = 1.0 + rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _on_node_added(n: Node) -> void:
	if n.has_meta("audio_hooked"):
		return
	if n is BaseButton:
		n.set_meta("audio_hooked", true)
		n.mouse_entered.connect(_on_hover.bind(n))
		n.pressed.connect(_on_pressed.bind(n))
	elif n is TabBar:
		n.set_meta("audio_hooked", true)
		n.tab_clicked.connect(func(_t): play_sfx(DEFAULT_SFX))


func _on_hover(b: BaseButton) -> void:
	if b.disabled:
		return
	var now := Time.get_ticks_msec()
	if now - last_hover_ms < hover_min_ms:
		return
	last_hover_ms = now
	play_sfx("hover")


func _on_pressed(b: BaseButton) -> void:
	play_sfx(str(b.get_meta("sfx", DEFAULT_SFX)))


# Выход: переход и плееры остановить, потоки отпустить (иначе при закрытии «ресурсы ещё используются»).
func _exit_tree() -> void:
	if fade != null:
		fade.kill()
		fade = null
	for p in music + sfx_players:
		p.stop()
		p.stream = null
	streams.clear()
