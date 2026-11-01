extends SceneTree
# Смоук задачи 31 (окно): режим съёмки и кадры F12 (Shots.capture — то же, что F12). Бой seed 3, эффекты карты выключены,
# физика стоит (кадры повторяемы). Мышь и клавиатуру не трогать.
#   F12 в режиме съёмки: кадр совпадает с кадром окна в режиме (capture не возвращает интерфейс), после кадра слои по-прежнему
#   скрыты; обычный кадр F12 отличается от него там, где верхняя панель (интерфейс был, в режиме — нет).
#   Экран выбора карточки в режиме: виден, его кадр F12 отличается от кадра без него в прямоугольнике карточки; выбор карточки
#   запускает анимацию, и её кадр F12 тоже с карточкой (анимация в кадре); в замедлении анимация идёт медленнее.
const DIFF := 0.08
var fails := 0
var m: Node2D

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func step(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	preload("res://bench/watchdog.gd").arm(self)
	_run.call_deferred()

func f12() -> Image:
	var p: String = await root.get_node("Shots").capture()
	var img := Image.load_from_file(p)
	DirAccess.remove_absolute(p)
	return img

func window() -> Image:
	await step(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)   # как Shots._save (кадр size)
	return img

# Доля точек прямоугольника r (px холста 1920x1080), где кадры различаются.
func diff_share(a: Image, b: Image, r: Rect2) -> float:
	var n := 0
	var d := 0
	var k := Vector2(a.get_width(), a.get_height()) / Vector2(1920, 1080)
	for y in range(int(r.position.y * k.y), int(r.end.y * k.y), 2):
		for x in range(int(r.position.x * k.x), int(r.end.x * k.x), 2):
			n += 1
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > DIFF or absf(p.g - q.g) > DIFF or absf(p.b - q.b) > DIFF:
				d += 1
	return d / float(maxi(n, 1))

func _run() -> void:
	node_added.connect(func(n): if n.get_script() != null and n.get_script().resource_path == "res://scripts/main.gd": n.fx_enabled = false)
	var g: Node = root.get_node("Game")
	g.save_path = "user://bench_v85sm/save.json"
	DirAccess.make_dir_recursive_absolute("user://bench_v85sm")
	DirAccess.remove_absolute(g.save_path)
	g._setup()
	g.run_seed = 3
	g.start_run(1)
	await step(12)
	m = current_scene
	m.set_physics_process(false)
	var hud: Rect2 = m.top_hud.get_global_rect()
	var normal := await f12()
	m.cine.set_on(true)
	await step(3)
	var cine_shot := await f12()
	var cine_win := await window()
	var whole := Rect2(0, 0, 1920, 1080)
	var same := diff_share(cine_shot, cine_win, whole)
	check("F12 в режиме = кадр окна в режиме (различий %.4f), слои после кадра скрыты" % same, same < 0.002 and m.cine._layers().all(func(l): return not l.visible))
	var hud_d := diff_share(normal, cine_shot, hud)
	check("обычный F12 и F12 в режиме различаются на месте верхней панели %s (%.2f)" % [str(hud), hud_d], hud_d > 0.2)
	# экран выбора карточки в режиме
	var before := await f12()
	m.wave_number = int(m.card_rules.pick_after_waves[0])
	m._offer_cards()
	await step(6)
	var cr: Rect2 = m.card_screen.card_rect(1, false)
	var pick := await f12()
	var cd := diff_share(before, pick, cr)
	check("экран карточек в режиме виден, кадр F12 с карточкой (%s, различий %.2f)" % [str(cr), cd], m.card_screen.visible and cd > 0.3)
	# анимация выбора: замедление 0.25 — за то же реальное время анимация прошла меньше
	m.cine.set_scale(0.25)
	m.card_screen._pick(1)   # как клик по средней карточке: выбор с анимацией
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 500:
		await process_frame
	var real := (Time.get_ticks_msec() - t0) / 1000.0
	var anim_t: float = m.card_screen.anim_t
	var during := await f12()
	var ad := diff_share(before, during, Rect2(0, 0, 1920, 1080))
	check("выбор в замедлении 0.25: анимация идёт (anim_on %s), за %.2f с реального — %.2f с анимации (меньше половины); кадр F12 с анимацией (%.2f)" % [
		m.card_screen.anim_on, real, anim_t, ad], m.card_screen.anim_on and anim_t > 0.0 and anim_t < real * 0.5 and ad > 0.02)
	m.cine.set_on(false)
	g.go_menu()
	await step(3)
	DirAccess.remove_absolute(g.save_path)
	DirAccess.remove_absolute("user://bench_v85sm")
	print("SMOKE: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
