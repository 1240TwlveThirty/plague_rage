extends SceneTree
# Тесты задачи 25 (без окна): анимация выбора карточки. Параметры — data/card_pick_fx.json, тряска — data/fx.json.
#   Выбор кликом применяет карточку ровно один раз; двойной клик и клик во время анимации второй раз не применяют.
#   Пропуск (клик или клавиша во время анимации) — сразу конечное состояние: экран закрыт, следующая фаза (closed).
#   «Выкл» — экран закрывается сразу, «короткая» — без сгорания, вспышки и колец, не дольше short.fade_time; «полная» —
#   доходит до удара, кольца, вспышка не ярче flash_alpha. Длительность полной по данным не больше max_total_time и 1.5 с.
#   «Тряска экрана: выкл» — ударной тряски нет, иначе смещение целыми px не больше shake_px x уровень. Настройка сохраняется
#   в файле настроек и читается обратно.
# Временное сохранение user://bench_v75 (user://save.json и settings.cfg игрока не трогаются).
const CARD_PICK := preload("res://scripts/card_pick.gd")
const DIR := "user://bench_v75"
const LIMIT := 1.5   # требование задачи: полная последовательность не длиннее 1.5 с
var fails := 0
var fx: Dictionary
var closed_n := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _on_node_added(n: Node) -> void:
	if n.get_parent() == root and n is Node2D and n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd":
		n.process_mode = Node.PROCESS_MODE_DISABLED

func _initialize() -> void:
	_run.call_deferred()

func click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e

func _run() -> void:
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://data/card_pick_fx.json"))
	var st: Node = root.get_node("Settings")
	if root.has_node("Game"):
		root.get_node("Game").free()
		await step(1)
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://scripts/game.gd").new()
	g.name = "Game"
	g.save_path = DIR + "/save.json"
	root.add_child(g)
	node_added.connect(_on_node_added)
	g.start_run(1)
	await step(3)
	var m := current_scene as Node2D
	var cs: CanvasLayer = m.card_screen
	cs.closed.connect(func(): closed_n += 1)
	cs.set_process(false)   # время анимации — только fx_step

	# длительность
	var full: float = CARD_PICK.total_time(fx, CARD_PICK.ANIM_FULL)
	var short: float = CARD_PICK.total_time(fx, CARD_PICK.ANIM_SHORT)
	check("полная длительность по данным %.2f с <= max_total_time %.2f <= %.1f; короткая %.2f; выкл 0" % [full, float(fx.max_total_time), LIMIT, short],
		full <= float(fx.max_total_time) and float(fx.max_total_time) <= LIMIT and short == float(fx.short.fade_time)
		and CARD_PICK.total_time(fx, CARD_PICK.ANIM_OFF) == 0.0)

	# полная: клик применяет один раз, двойной клик и клик во время анимации — нет
	st.card_pick_anim = CARD_PICK.ANIM_FULL
	st.screen_shake_level = 2
	await offer(m)
	var before: int = applied(m)
	cs.buttons[1].pressed.emit()
	cs.buttons[1].pressed.emit()   # двойной клик
	cs.buttons[0].pressed.emit()
	var once: bool = applied(m) == before + 1 and m._cards()[-1].id == cs.offer[1]
	check("полная: клик применяет карточку сразу и ровно один раз (повторный и чужой клик — нет), экран ещё открыт, ввод заблокирован",
		once and cs.visible and cs.anim_on and closed_n == 0, "применено %d" % (applied(m) - before))
	# доходит до удара: тряска, вспышка не ярче данных, кольца
	var t_hit: float = cs.impact_time()
	var max_off := 0.0
	var all_int := true
	var impact_seen := false
	var t := 0.0
	var dt := 1.0 / 60.0
	while cs.anim_on and t < full + 0.5:
		cs.fx_step(dt)
		t += dt
		impact_seen = impact_seen or cs.impact_done
		max_off = maxf(max_off, cs.offset.length())
		all_int = all_int and cs.offset == cs.offset.round()
	var fxd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/fx.json"))
	var cap := float(fx.impact.shake_px) * float(fxd.shake_levels[2]) * sqrt(2.0)
	check("полная: удар (%.2f с), тряска до %.1f px целыми (не больше %.1f), закрылась за %.2f с (данные %.2f), closed один раз" % [t_hit, max_off, cap, t, full],
		impact_seen and max_off > 0.0 and max_off <= cap + 0.01 and all_int and not cs.visible and absf(t - full) <= dt * 1.5 and closed_n == 1
		and applied(m) == before + 1)

	# клик во время анимации — пропуск: сразу конец и следующая фаза, второй раз не применяется
	await offer(m)
	before = applied(m)
	closed_n = 0
	cs.buttons[2].pressed.emit()
	cs.fx_step(0.1)
	cs._input(click())
	check("пропуск кликом во время анимации: экран закрыт сразу, closed, карточка применена один раз", not cs.visible and not cs.anim_on
		and closed_n == 1 and applied(m) == before + 1 and cs.offset == Vector2.ZERO)
	await offer(m)
	before = applied(m)
	closed_n = 0
	var k1 := InputEventKey.new()
	k1.keycode = KEY_1
	k1.pressed = true
	cs._input(k1)
	cs._input(k1)   # та же клавиша ещё раз — уже пропуск, не второй выбор
	check("клавиша 1, затем клавиша ещё раз: выбрана один раз, второе нажатие — пропуск", applied(m) == before + 1 and not cs.visible and closed_n == 1)

	# короткая: без сгорания, вспышки, колец, удара
	st.card_pick_anim = CARD_PICK.ANIM_SHORT
	await offer(m)
	closed_n = 0
	cs.buttons[0].pressed.emit()
	var burned := false
	t = 0.0
	while cs.anim_on and t < 2.0:
		cs.fx_step(dt)
		t += dt
		for k in cs.groups.size():
			var bv = (cs.groups[k].material as ShaderMaterial).get_shader_parameter("burn")
			burned = burned or (bv != null and float(bv) > 0.0)
		burned = burned or cs.impact_done or not cs.sparks.is_empty()
	check("короткая: без сгорания, искр, удара и колец; закрылась за %.2f с (short.fade_time %.2f)" % [t, short], not burned and not cs.visible
		and t <= short + dt * 1.5 and closed_n == 1)

	# выкл: экран закрывается сразу
	st.card_pick_anim = CARD_PICK.ANIM_OFF
	await offer(m)
	closed_n = 0
	before = applied(m)
	cs.buttons[0].pressed.emit()
	check("выкл: карточка применена, экран закрыт сразу, анимации нет", applied(m) == before + 1 and not cs.visible and not cs.anim_on and closed_n == 1)

	# тряска выкл — ударной тряски нет
	st.card_pick_anim = CARD_PICK.ANIM_FULL
	st.screen_shake_level = 0
	await offer(m)
	cs.buttons[0].pressed.emit()
	max_off = 0.0
	impact_seen = false
	while cs.anim_on:
		cs.fx_step(dt)
		impact_seen = impact_seen or cs.impact_done
		max_off = maxf(max_off, cs.offset.length())
	check("«Тряска экрана: выкл»: удар есть, смещения нет", impact_seen and max_off == 0.0)
	st.screen_shake_level = 2

	# настройка сохраняется в файле настроек
	var saved_path: String = st.path
	st.path = DIR + "/settings.cfg"
	st.persist = true
	st.card_pick_anim = CARD_PICK.ANIM_FULL
	st.set_card_pick_anim(CARD_PICK.ANIM_SHORT)
	st.card_pick_anim = CARD_PICK.ANIM_FULL
	st.load_settings()
	var cfg := ConfigFile.new()
	cfg.load(st.path)
	check("настройка «Анимация выбора карточки» в файле настроек (display/card_pick_anim = %s) и читается обратно" % str(cfg.get_value("display", "card_pick_anim")),
		st.card_pick_anim == CARD_PICK.ANIM_SHORT and int(cfg.get_value("display", "card_pick_anim", -1)) == CARD_PICK.ANIM_SHORT)
	st.persist = false
	st.path = saved_path
	st.card_pick_anim = CARD_PICK.ANIM_FULL
	DirAccess.remove_absolute(DIR + "/settings.cfg")
	var fresh: Node = load("res://scripts/settings.gd").new()
	check("по умолчанию — полная", fresh.card_pick_anim == CARD_PICK.ANIM_FULL)
	fresh.free()

	m.queue_free()
	await step(2)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute(DIR)
	print("CHECK: провалов %d" % fails)
	quit(1 if fails > 0 else 0)

# Выбранные карточки забега.
func applied(m: Node2D) -> int:
	return m._cards().size()

# Новая тройка на экране выбора (как в начале передышки).
func offer(m: Node2D) -> void:
	var have: Array = m._cards().map(func(r): return r.id)
	m.pending_offer = m.card_defs.keys().filter(func(id): return not id in have).slice(0, 3)
	m.card_screen.open(m.pending_offer, m.card_defs, [])
	await step(2)
