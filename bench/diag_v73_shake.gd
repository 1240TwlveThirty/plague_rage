extends SceneTree
# Диагностика задачи 23, этап A: тряска экрана при ударах героя в движении и на месте. Сцена боя в дереве и обычный цикл
# движка (кадры и тики идут сами), ввод — как у игрока: WASD — Input.action_press(move_*), J — нажатия клавиши событием окна
# (push_input, как с клавиатуры) и удержание (hold_repeat). Волна 10, seed 3, ворота и герой бессмертны.
# Фазы по PHASE_S с: «движение» — герой ходит влево-вправо у орды (смена стороны раз в 0.5 с) и бьёт; «на месте» — стоит и бьёт.
# По каждой фазе: ударов (hero_swing_n), ударов с попаданием и попаданий (hero_hits), запусков тряски за попадание
# (shake_hit_count) и за добивание (shake_count), кадров с ненулевым camera.offset и средний модуль смещения в px экрана.
# Печатает «DIAG|фаза|...» и вывод: какие причины подтверждаются (1 — попадания реже, 2 — тряска не доходит до камеры,
# 3 — доходит, но амплитуда мала). Проверка (SMOKE): в обеих фазах каждый удар с попаданием запускает тряску, и она доходит
# до камеры (кадров со смещением не меньше запусков); в движении попадания есть.
const PHASE_S := 6.0
var m: Node2D
var frames_offset := 0
var frames := 0
var offset_sum := 0.0

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	_run.call_deferred()

func key_j() -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_J
		e.physical_keycode = KEY_J
		e.pressed = pressed
		root.push_input(e, true)

# Герой у края орды: ближайший живой зомби (для «на месте» — взгляд на него через движение не нужен, удар сектором вперёд).
func nearest() -> int:
	var h: int = m.hero_idx
	var best := -1
	var bd := INF
	for j in m.count:
		if m.team[j] == 1 and m.hp[j] > 0.0:
			var d: float = m.pos[h].distance_squared_to(m.pos[j])
			if d < bd:
				bd = d
				best = j
	return best

# Короткий шаг к ближайшему зомби (2 кадра): герой поворачивается к орде, как игрок перед ударом на месте.
func face_horde() -> void:
	var j := nearest()
	if j < 0:
		return
	var to: Vector2 = m.pos[j] - m.pos[m.hero_idx]
	var act := ("move_right" if to.x > 0.0 else "move_left") if absf(to.x) > absf(to.y) else ("move_down" if to.y > 0.0 else "move_up")
	Input.action_press(act)
	await step(3)
	release_all()
	await step(2)

# Тряски за добивание (до задачи 23 был отдельный вид, shake_count; с задачи 23 — одна тряска на удар): 0, если поля нет.
func kill_shakes() -> int:
	var v = m.get("shake_count")
	return int(v) if v != null else 0

func release_all() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right", "hero_attack"]:
		Input.action_release(a)

func phase(name: String, moving: bool) -> Dictionary:
	var s0: int = m.hero_swing_n
	var h0: int = m.hero_hits
	var sw0: int = m.hero_swings
	var sh0: int = m.shake_hit_count
	var sk0 := kill_shakes()
	frames = 0
	frames_offset = 0
	offset_sum = 0.0
	var t0 := Time.get_ticks_msec()
	var side := 1
	var flip_at := 0.5
	var max_off := 0.0
	Input.action_press("hero_attack")   # удержание J (hold_repeat)
	while (Time.get_ticks_msec() - t0) / 1000.0 < PHASE_S:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		var j := nearest()
		if moving and j >= 0:
			var to: Vector2 = m.pos[j] - m.pos[m.hero_idx]
			# ход вдоль фронта орды (влево-вправо) и чуть к ней: герой всё время в движении, лицом по ходу
			if t >= flip_at:
				side = -side
				flip_at += 0.5
			release_all()
			Input.action_press("hero_attack")
			Input.action_press("move_right" if side > 0 else "move_left")
			if to.y < -20.0:
				Input.action_press("move_up")
			elif to.y > 20.0:
				Input.action_press("move_down")
		if frames % 4 == 0:
			key_j()   # и нажатия J событием (защёлка на ближайший тик)
		await process_frame
		frames += 1
		var off: Vector2 = m.shake_raw * m.camera.zoom   # px экрана; задача 28: до урезания краем поля
		if off != Vector2.ZERO:
			frames_offset += 1
			offset_sum += off.length()
			max_off = maxf(max_off, off.length())
	release_all()
	var r := {"name": name, "frames": frames, "swings": m.hero_swing_n - s0, "hit_swings": m.hero_swings - sw0, "hits": m.hero_hits - h0,
		"shake_hit": m.shake_hit_count - sh0, "shake_kill": kill_shakes() - sk0, "offset_frames": frames_offset,
		"offset_avg": offset_sum / maxf(frames_offset, 1), "offset_max": max_off}
	print("DIAG|%s|кадров %d|ударов %d|с попаданием %d|попаданий %d|тряска за попадание %d|за добивание %d|кадров со смещением %d (%.0f%%)|среднее %.2f px|макс %.1f px" % [
		name, r.frames, r.swings, r.hit_swings, r.hits, r.shake_hit, r.shake_kill, r.offset_frames, 100.0 * r.offset_frames / maxf(r.frames, 1),
		r.offset_avg, r.offset_max])
	return r

func _run() -> void:
	Engine.max_fps = 60   # как в игре: время тряски в кадрах — как у игрока
	var st := root.get_node_or_null("Settings")
	if st != null:
		st.screen_shake = true
	m = load("res://scenes/main.tscn").instantiate()
	m.spawn_seed = 3
	m.hero_mode = 1
	m.record_path = "user://record_bench.json"
	root.add_child(m)
	current_scene = m
	await step(5)
	m.banner.visible = false
	m.wave_number = 9
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	m.hp[m.hero_idx] = 1e6
	# подход орды: герой выходит навстречу и ждёт, пока зомби рядом
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		var j := nearest()
		if j >= 0 and m.pos[j].distance_to(m.pos[m.hero_idx]) < 40.0:
			break
		Input.action_press("move_up")
		await process_frame
	release_all()
	await step(2)
	print("герой у орды: зомби ближе 40 px, тик %d, живых зомби %d" % [m.tick_counter, m.zombie_alive])
	var a := await phase("движение", true)
	await face_horde()
	var b := await phase("на месте", false)
	var a_rate: float = float(a.hits) / maxf(a.swings, 1)
	var b_rate: float = float(b.hits) / maxf(b.swings, 1)
	var a_shake: float = float(a.shake_hit) / maxf(a.hit_swings, 1)
	var b_shake: float = float(b.shake_hit) / maxf(b.hit_swings, 1)
	var a_reach: float = float(a.offset_frames) / maxf(a.shake_hit + a.shake_kill, 1)
	var b_reach: float = float(b.offset_frames) / maxf(b.shake_hit + b.shake_kill, 1)
	print("SUMMARY|попаданий на удар: движение %.2f, на месте %.2f|тряска на удар с попаданием: %.2f / %.2f|кадров смещения на запуск тряски: %.2f / %.2f|средний сдвиг %.2f / %.2f px" % [
		a_rate, b_rate, a_shake, b_shake, a_reach, b_reach, a.offset_avg, b.offset_avg])
	var c1: bool = a_rate < b_rate * 0.6
	var c2: bool = a.shake_hit > 0 and a_reach < b_reach * 0.5
	var c3: bool = not c1 and not c2
	print("ПРИЧИНЫ|(1) попадания в движении реже: %s|(2) тряска не доходит до камеры: %s|(3) доходит, амплитуда мала: %s" % [
		"подтверждается" if c1 else "нет", "подтверждается" if c2 else "нет", "подтверждается" if c3 else "нет"])
	var fails := 0
	for r in [a, b]:
		var ok: bool = r.shake_hit == r.hit_swings and r.offset_frames >= r.shake_hit + r.shake_kill
		print("  %s: тряска на каждом ударе с попаданием (%d из %d) и доходит до камеры (%d кадров): %s" % [r.name, r.shake_hit, r.hit_swings, r.offset_frames,
			"да" if ok else "НЕТ"])
		fails += 0 if ok else 1
	print("  в движении попадания есть (%d): %s" % [a.hits, "да" if a.hits > 0 else "НЕТ"])
	fails += 0 if a.hits > 0 else 1
	m.queue_free()
	await step(2)
	print("DIAG: готово")
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
