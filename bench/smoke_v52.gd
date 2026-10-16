extends SceneTree
# Смоук v52 с окном: звук. Автопереход меню -> хаб -> забег (передышка) -> волна -> передышка -> волна -> хаб; лог Audio
# должен идти main_menu, hub, respite, battle_theme, battle_theme_2, battle_theme, respite, battle_theme_2, hub
# (боевые темы чередуются, очередь продолжается со следующей волной). Для скорости только в тесте: боевая тема считается
# длиной THEME_LEN с, переход CROSSFADE с (data/audio.json не меняется). Мастер-шина под тестом приглушена (Settings).
# Ещё: пауза (Esc) музыку не останавливает; звуки кнопок из meta «sfx», hover не чаще раза в 40 мс и не на отключённых
# кнопках, разброс высоты в пределах ±3%, нет файла — без падения. Аргументы нет.
const THEME_LEN := 4.0
const CROSSFADE := 1.0
const DIR := "user://bench_v52"
var fails := 0
var au: Node
var g: Node

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout

# Ждать, пока в логе не станет n записей (не дольше limit с).
func wait_log(n: int, limit: float) -> void:
	var t := 0.0
	while au.log_lines.size() < n and t < limit:
		await wait(0.1)
		t += 0.1

func sfx_playing(name: String) -> bool:
	for p in au.sfx_players:
		if p.playing and p.stream == au.streams.get(name):
			return true
	return false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("SMOKE v52: звук")
	au = root.get_node("Audio")
	g = root.get_node("Game")
	DirAccess.make_dir_recursive_absolute(DIR)
	g.save_path = DIR + "/save.json"
	g._setup()
	check("шины Music и SFX есть, мастер под тестом приглушён", AudioServer.get_bus_index("Music") > 0 and AudioServer.get_bus_index("SFX") > 0 and AudioServer.is_bus_mute(0))
	check("audio.json: 10 звуков, переход 1.5–2 с, pickupCoin не используется", au.sounds.size() == 10 and au.crossfade >= 1.5 and au.crossfade <= 2.0
		and not au.sounds.has("pickupCoin"), "%d, %.2f" % [au.sounds.size(), au.crossfade])
	au.test_theme_len = THEME_LEN
	au.crossfade = CROSSFADE
	au.log_lines.clear()
	au.current = ""
	au.mode = "?"
	au.battle_idx = 0
	var t0 := Time.get_ticks_msec()
	g.go_menu()
	await wait_log(1, 3.0)
	var mn := current_scene
	await wait(0.5)
	check("меню: main_menu играет циклом", au.current == "main_menu" and au.music[au.active].playing
		and (au.music[au.active].stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD)
	# эффекты
	mn.play_button.mouse_entered.emit()
	mn.settings_button.mouse_entered.emit()   # сразу второй — меньше 40 мс: не звучит
	var hovers := 0
	for p in au.sfx_players:
		hovers += int(p.playing and p.stream == au.streams.get("hover"))
	check("hover: одно наведение звучит, второе в пределах 40 мс — нет", hovers == 1, str(hovers))
	await wait(0.06)
	mn.settings_button.pressed.emit()
	check("«Настройки» — click_settings", sfx_playing("click_settings"))
	mn.settings_menu.close()
	var pitches := []
	for p in au.sfx_players:
		if p.playing:
			pitches.append(p.pitch_scale)
	check("разброс высоты в пределах ±3%", pitches.all(func(x): return absf(x - 1.0) <= 0.0301), str(pitches))
	var dis := Button.new()
	dis.disabled = true
	mn.add_child(dis)
	await wait(0.06)
	for p in au.sfx_players:
		p.stop()
	dis.mouse_entered.emit()
	check("отключённая кнопка: hover не звучит", not sfx_playing("hover"))
	check("нет звука: без падения, null", au._stream("no_such_sound") == null)
	mn.play_button.pressed.emit()   # «Играть» -> хаб
	check("«Играть» — click_play", sfx_playing("click_play"))
	await wait_log(2, 3.0)
	await wait(0.5)
	check("хаб: hub", au.current == "hub")
	current_scene.start_button.pressed.emit()
	await wait_log(3, 3.0)
	var m := current_scene
	m.set_physics_process(false)   # бой не идёт сам: волна не кончится раньше времени
	check("забег, передышка: respite", au.current == "respite" and m.wave_state == m.WS_RESPITE)
	# пауза (Esc) музыку не останавливает
	var pos0: float = au.music[au.active].get_playback_position()
	m._open_esc_menu()
	await wait(0.6)
	check("пауза Esc: дерево на паузе, музыка играет дальше", paused and au.music[au.active].playing and au.music[au.active].get_playback_position() > pos0,
		"%.2f -> %.2f" % [pos0, au.music[au.active].get_playback_position()])
	m.esc_menu.close()
	m._start_wave()
	await wait_log(6, 3.0 * THEME_LEN + 3.0)   # battle_theme, battle_theme_2, battle_theme
	check("волна: боевые темы чередуются (battle_theme, battle_theme_2, battle_theme)", Array(au.log_lines.slice(3, 6)) == ["battle_theme", "battle_theme_2", "battle_theme"], str(au.log_lines))
	m.wave_state = m.WS_RESPITE   # конец волны (без симуляции)
	await wait_log(7, 3.0)
	check("конец волны: respite с переходом", au.log_lines.size() >= 7 and au.log_lines[6] == "respite")
	m.wave_state = m.WS_BATTLE
	await wait_log(8, 3.0)
	check("следующая волна продолжает очередь: battle_theme_2", au.log_lines.size() >= 8 and au.log_lines[7] == "battle_theme_2", str(au.log_lines))
	# переход не сработал (тема доиграла): следующая сразу
	au.test_theme_len = 1000.0
	au._on_music_finished(au.active)
	check("тема доиграла без перехода: следующая (battle_theme) сразу", au.log_lines[-1] == "battle_theme")
	m._abandon_run()
	g.go_hub()
	await wait_log(10, 3.0)
	check("бой -> хаб: hub", au.log_lines[-1] == "hub")
	g.go_hub()   # та же сцена с той же музыкой: ничего не перезапускается
	await wait(0.5)
	check("хаб -> хаб: тема не перезапущена", au.log_lines[-1] == "hub" and au.log_lines.size() == 10)
	print("AUDIO LOG: %s (%.1f с)" % [" -> ".join(au.log_lines), (Time.get_ticks_msec() - t0) / 1000.0])
	check("порядок: main_menu, hub, respite, battle_theme, battle_theme_2, battle_theme, respite, battle_theme_2, battle_theme, hub",
		Array(au.log_lines) == ["main_menu", "hub", "respite", "battle_theme", "battle_theme_2", "battle_theme", "respite", "battle_theme_2", "battle_theme", "hub"])
	print("SMOKE: провалов %d" % fails)
	quit()
