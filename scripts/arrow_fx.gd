extends Node2D
# Видимые стрелы лучников (задача 29). Только отрисовка: симуляцию и её ГСЧ не трогает. Источник — очередь стрел main (arrow_land,
# arrow_tick и массивы отрисовки arrow_from, arrow_t0, arrow_vid) и два события из main, только при включённой отрисовке:
# выстрел (_fire_arrow -> fire) и падение (_process_arrows -> land).
# Время картинки td — в тиках, как у юнитов (tick_counter - 1 + доля тика): стрела видна при arrow_t0 <= td < arrow_tick и
# долетает в точку падения ровно к тику падения.
# Полёт считает видеокарта (шейдер ARROW_SHADER): стрела пишется в буфер MultiMesh один раз при выстреле (слот), каждый кадр
# меняется только время (uniform td) — цена кадра не растёт с числом стрел. Один MultiMesh на две ноды: стрелы (над слоями) и
# тени (на земле, под юнитами). Слотов max_visible; стрел больше — выборка каждой N-й по номеру выстрела.
# Падение: попадание — искра на 1–3 кадра, промах — воткнутая стрела (кольцо max_stuck), гаснет за stuck_life по времени картинки
# в шейдере (на паузе стоит). Эффекты появляются, когда время картинки дошло до тика падения. ГСЧ — свой (fx_rng).
# Звуки выпуска и попаданий — через Audio, если запись есть в data/audio.json (проверяется при установке: без файлов вызовов и
# предупреждений нет). Настройки — data/arrows_fx.json.
const CFG_PATH := "res://data/arrows_fx.json"
const FPI := 12        # float на инстанс искр и воткнутых: 8 (трансформ 2D) + 4 (цвет)
const FPI_AIR := 16    # стрелы: 8 (трансформ: единичный базис, сдвиг — лучник) + 4 (цвет: t0, t1 от базы) + 4 (custom: путь, дуга)
const REBASE_TICKS := 64.0   # время в буфере — от базы (цвет и custom в GLES3 — half float): база сдвигается раз в столько тиков
# Шейдер полёта. Инстанс: трансформ — единичный базис со сдвигом в лучника (VERTEX - угол квадрата = лучник), COLOR = (t0, t1)
# от базы, INSTANCE_CUSTOM = (путь до точки падения, 4 * высота дуги). u = (td - t0) / (t1 - t0); вне [0, 1) — квадрат в точку.
# Стрела: земля + путь * u, выше на h0 (1 - u) + arc4 u (1 - u), повёрнута по касательной; тень (ground) — на земле, по пути.
# Воткнутые (STUCK_SHADER): трансформ — место и поворот, COLOR = (тик падения, тик конца) от базы; гаснут последние fade жизни.
const ARROW_SHADER := """shader_type canvas_item;
uniform float td = 0.0;
uniform float h0 = 0.0;
uniform vec2 size = vec2(1.0);
uniform bool ground = false;
uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
	vec2 corner = UV - vec2(0.5);
	vec2 a = VERTEX - corner;
	float t0 = COLOR.r;
	float t1 = COLOR.g;
	vec2 d = INSTANCE_CUSTOM.xy;
	float arc4 = INSTANCE_CUSTOM.z;
	float u = (td - t0) / max(t1 - t0, 0.001);
	if (t1 <= t0 || u < 0.0 || u >= 1.0) {
		VERTEX = vec2(0.0);   // все углы в одну точку — не рисуется
	} else {
		vec2 p = a + d * u;
		vec2 dir = d;
		if (!ground) {
			p.y -= h0 * (1.0 - u) + arc4 * u * (1.0 - u);
			dir = vec2(d.x, d.y + h0 - arc4 * (1.0 - 2.0 * u));
		}
		float l = length(dir);
		dir = l > 0.0001 ? dir / l : vec2(1.0, 0.0);
		vec2 c = corner * size;
		VERTEX = p + vec2(dir.x * c.x - dir.y * c.y, dir.y * c.x + dir.x * c.y);
	}
	COLOR = tint;
}
"""
const STUCK_SHADER := """shader_type canvas_item;
uniform float td = 0.0;
uniform float fade = 1.0;
void vertex() {
	float t0 = COLOR.r;
	float t1 = COLOR.g;
	float a = 0.0;
	if (td < t0 || td >= t1) {
		VERTEX = vec2(0.0);
	} else {
		a = min((t1 - td) / (fade * (t1 - t0)), 1.0);
	}
	COLOR = vec4(1.0, 1.0, 1.0, a);
}
"""

var main: Node2D
var cfg := {}
var cfg_path := CFG_PATH
var on := true                 # «Показывать стрелы» (настройки); main ставит каждый кадр
var tex: Texture2D
var arrow_size := Vector2.ONE  # размер стрелы в мире (px)
var from_art := false          # true — картинка art_path, false — нарисована кодом
# Полёт: слоты
var air_mm: MultiMesh
var air_node: MultiMeshInstance2D
var shadow_node: MultiMeshInstance2D
var air_mat: ShaderMaterial
var shadow_mat: ShaderMaterial
var air_buf := PackedFloat32Array()
var slot_vid := PackedInt32Array()     # номер выстрела в слоте; -1 — свободен
var slot_t0 := PackedFloat64Array()    # тики выпуска и падения (абсолютные: для сдвига базы)
var slot_t1 := PackedInt32Array()
var slot_next := 0                     # кольцо: следующий слот (новая стрела занимает место самой старой)
var air_until := -1.0                  # до этого тика в слотах есть стрелы в полёте (позже — ноды полёта скрыты)
var base := 0.0                        # база времени в буфере (тик)
var air_dirty := false
var h0 := 0.0
var arc_k := 0.0
var drawn := 0        # стрел записано в слоты за всё время (проверки)
var stride := 1       # выборка при выстреле: каждая stride-я по номеру выстрела
var skipped := 0      # выстрелов не в выборке или без свободного слота
var draw_calls := 0   # кадров отрисовки полёта (тесты: при выключенном флаге не растёт)
var lod_skip := false # прошлый кадр: стрела меньше порога на экране, полёт скрыт
var cost_us := 0      # время прошлого кадра стрел, мкс (замеры)
var registered := false   # слоты заполнены из очереди main (после включения)
var shown := true         # ноды показаны (флаг вкл)
# Искры и воткнутые
var spark_mm: MultiMesh
var stuck_mm: MultiMesh
var spark_node: MultiMeshInstance2D
var stuck_node: MultiMeshInstance2D
var spark_buf := PackedFloat32Array()
var stuck_buf := PackedFloat32Array()
var fx_rng := RandomNumberGenerator.new()   # свой ГСЧ эффектов: ГСЧ симуляции не трогается
# Очередь падений (ждут, пока время картинки дойдёт до тика падения)
var ev_to := PackedVector2Array()
var ev_dir := PackedVector2Array()
var ev_tgt := PackedVector2Array()
var ev_t := PackedInt32Array()
var ev_hit := PackedByteArray()
var ev_n := 0
var ev_min := 1 << 30   # самый ранний тик в очереди
var ev_dropped := 0
# Искры: позиция, кадров осталось, размер, цвет
var sp_pos := PackedVector2Array()
var sp_left := PackedInt32Array()
var sp_size := PackedFloat32Array()
var sp_col := PackedColorArray()
var spark_n := 0
# Воткнутые: кольцевой буфер (новая занимает место самой старой); угасание считает шейдер по времени картинки
var stuck_mat: ShaderMaterial
var st_pos := PackedVector2Array()
var st_t0 := PackedFloat64Array()    # тик падения и тик конца (абсолютные: для сдвига базы)
var st_t1 := PackedFloat64Array()
var st_next := 0
var stuck_dirty := false
var cur_td := 0.0                    # время картинки последнего кадра
var stuck_until := -1.0              # до этого тика есть видимые воткнутые (позже — нода скрыта)
# Числа из cfg (в событиях — без поиска по словарю)
var tps := 30.0
var sp_cnt := Vector2i.ONE
var sp_frames := Vector2i.ONE
var sp_sz := Vector2.ONE
var sp_jit := 0.0
var st_len := 1.0
var st_jit := 0.0
var st_life_ticks := Vector2.ONE
var hits_shown := 0     # искр-попаданий создано (тесты)
var stuck_shown := 0    # воткнутых создано (тесты)
# Звук
var audio: Node = null
var snd_whoosh := ""             # "" — звука нет (нет записи в data/audio.json)
var snd_hits: Array = []         # имена с записью
var whoosh_due := INF            # тик ближайшего выпуска, о котором ещё не свистели
var released := 0                # за этот кадр стрелы сорвались с тетивы (0/1)
var hits_frame := 0              # искр-попаданий за этот кадр
var whoosh_at := -1e9            # мс последнего звука
var hit_snd_at := -1e9
var whoosh_wanted := 0           # кадров, где был бы свист (тесты: код звука доходит до вызова и без файлов)
var hit_snd_wanted := 0
var sounds_played := 0


# data/arrows_fx.json. Не читается или неверный — {} и одна ошибка в лог: стрел на экране нет, игра идёт.
static func load_cfg(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Нет %s: стрелы не рисуются" % path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var nums := ["max_visible", "shaft_px", "arc_height_rel", "launch_height_px", "shadow_alpha", "lod_min_screen_px",
		"spark_jitter_px", "max_sparks", "stuck_fade", "stuck_len_rel", "stuck_angle_jitter_deg", "max_stuck", "max_events",
		"whoosh_min_interval_ms", "hit_sound_min_interval_ms"]
	var colors := ["shaft_color", "head_color", "outline_color", "shadow_color"]
	var sizes := ["art_size_px", "shadow_size_px"]
	var pairs := ["spark_count", "spark_frames", "spark_size_px", "stuck_life"]
	var ok: bool = d is Dictionary and d.get("art_path") is String
	for k in pairs:
		ok = ok and d.get(k) is Array and d[k].size() == 2 and d[k].all(func(x): return x is float and x >= 0.0) and d[k][0] <= d[k][1]
	ok = ok and d.get("sound_whoosh") is String and d.get("sound_hits") is Array and d.sound_hits.all(func(x): return x is String)
	ok = ok and d.get("spark_colors") is Array and not d.spark_colors.is_empty() and d.spark_colors.all(func(c): return c is String and Color.html_is_valid(c))
	for k in nums:
		ok = ok and d.get(k) is float and d[k] >= 0.0
	for k in colors:
		ok = ok and d.get(k) is String and Color.html_is_valid(d[k])
	for k in sizes:
		ok = ok and d.get(k) is Array and d[k].size() == 2 and d[k].all(func(x): return x is float and x > 0.0)
	ok = ok and d.max_visible >= 1.0 and d.shaft_px >= 1.0 and d.max_sparks >= 1.0 and d.max_stuck >= 1.0 and d.max_events >= 1.0
	ok = ok and d.stuck_fade > 0.0 and d.stuck_fade <= 1.0 and d.spark_frames[0] >= 1.0 and d.stuck_life[0] > 0.0
	if not ok:
		push_error("%s: нужны числа >= 0 (%s; max_visible, shaft_px, max_sparks, max_stuck, max_events >= 1; stuck_fade в (0, 1]), цвета hex (%s, spark_colors), размеры [ш, в] > 0 (%s), пары [от, до] (%s; spark_frames от 1, stuck_life от > 0), art_path — стрелы не рисуются" % [
			path, ", ".join(nums), ", ".join(colors), ", ".join(sizes), ", ".join(pairs)])
		return {}
	for k in colors:
		d[k] = Color(d[k])
	d.spark_colors = d.spark_colors.map(func(c): return Color(c))
	return d


# Стрела кодом: древко shaft_px светлым, наконечник на конце, тёмный контур 1 px вокруг; остриём вправо.
static func make_arrow_image(c: Dictionary) -> Image:
	var n := int(c.shaft_px)
	var img := Image.create(n + 2, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(1, n + 1):
		img.set_pixel(x, 0, c.outline_color)
		img.set_pixel(x, 2, c.outline_color)
		img.set_pixel(x, 1, c.head_color if x == n else c.shaft_color)
	img.set_pixel(0, 1, c.outline_color)
	img.set_pixel(n + 1, 1, c.outline_color)
	return img


# Единичный квадрат (центр в 0) с UV: размер, поворот и цвет — у инстанса (custom — у стрел).
static func quad_mm(n: int, custom := false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = custom
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mm.mesh = quad
	mm.instance_count = maxi(n, 1)
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-1e5, -1e5, 0.0), Vector3(2e5, 2e5, 0.0))
	return mm


func _arrow_mat(ground: bool, size: Vector2, tint: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = ARROW_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("h0", h0)
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("ground", ground)
	mat.set_shader_parameter("tint", tint)
	return mat


# Установка (main._setup_arrow_fx): стрелы и искры — z air_z; тени и воткнутые — перед ground_before в дереве main (под юнитами).
func setup(m: Node2D, air_z: int, ground_before: Node) -> bool:
	main = m
	cfg = load_cfg(cfg_path)
	if cfg.is_empty():
		return false
	var art: String = cfg.art_path
	if art != "" and ResourceLoader.exists(art):
		tex = load(art) as Texture2D
	from_art = tex != null
	if from_art:
		arrow_size = Vector2(cfg.art_size_px[0], cfg.art_size_px[1])
	else:
		var img := make_arrow_image(cfg)
		tex = ImageTexture.create_from_image(img)
		arrow_size = Vector2(img.get_size())   # 1 тексель = 1 px мира
	h0 = float(cfg.launch_height_px)
	arc_k = float(cfg.arc_height_rel)
	var n := int(cfg.max_visible)
	air_buf.resize(n * FPI_AIR)
	air_buf.fill(0.0)
	slot_vid.resize(n)
	slot_t0.resize(n)
	slot_t1.resize(n)
	_free_all()
	air_mm = quad_mm(n, true)
	air_mm.buffer = air_buf
	air_mm.visible_instance_count = n
	air_mat = _arrow_mat(false, arrow_size, Color.WHITE)
	shadow_mat = _arrow_mat(true, Vector2(cfg.shadow_size_px[0], cfg.shadow_size_px[1]), Color(cfg.shadow_color, cfg.shadow_alpha))
	shadow_node = MultiMeshInstance2D.new()
	shadow_node.multimesh = air_mm
	shadow_node.material = shadow_mat
	shadow_node.name = "ArrowShadows"
	m.add_child(shadow_node)
	if ground_before != null and ground_before.get_parent() == m:
		m.move_child(shadow_node, ground_before.get_index())
	air_node = MultiMeshInstance2D.new()
	air_node.multimesh = air_mm
	air_node.material = air_mat
	air_node.texture = tex
	air_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	air_node.z_index = air_z
	air_node.name = "ArrowsAir"
	m.add_child(air_node)
	# воткнутые — на земле, над тенями, под юнитами; искры — над стрелами
	var ns := int(cfg.max_stuck)
	stuck_mm = quad_mm(ns)
	stuck_buf.resize(ns * FPI)
	stuck_buf.fill(0.0)
	stuck_mm.buffer = stuck_buf
	stuck_mm.visible_instance_count = ns
	st_pos.resize(ns)
	st_t0.resize(ns)
	st_t1.resize(ns)
	st_t1.fill(-1.0)
	var ssh := Shader.new()
	ssh.code = STUCK_SHADER
	stuck_mat = ShaderMaterial.new()
	stuck_mat.shader = ssh
	stuck_mat.set_shader_parameter("fade", float(cfg.stuck_fade))
	stuck_node = MultiMeshInstance2D.new()
	stuck_node.multimesh = stuck_mm
	stuck_node.material = stuck_mat
	stuck_node.texture = tex
	stuck_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stuck_node.name = "ArrowsStuck"
	m.add_child(stuck_node)
	m.move_child(stuck_node, shadow_node.get_index() + 1)
	var nk := int(cfg.max_sparks)
	spark_mm = quad_mm(nk)
	spark_buf.resize(nk * FPI)
	sp_pos.resize(nk)
	sp_left.resize(nk)
	sp_size.resize(nk)
	sp_col.resize(nk)
	spark_node = MultiMeshInstance2D.new()
	spark_node.multimesh = spark_mm
	spark_node.z_index = air_z
	spark_node.name = "ArrowSparks"
	m.add_child(spark_node)
	var ne := int(cfg.max_events)
	ev_to.resize(ne)
	ev_dir.resize(ne)
	ev_tgt.resize(ne)
	ev_t.resize(ne)
	ev_hit.resize(ne)
	fx_rng.seed = 2909
	tps = float(Engine.physics_ticks_per_second)
	sp_cnt = Vector2i(int(cfg.spark_count[0]), int(cfg.spark_count[1]))
	sp_frames = Vector2i(int(cfg.spark_frames[0]), int(cfg.spark_frames[1]))
	sp_sz = Vector2(cfg.spark_size_px[0], cfg.spark_size_px[1])
	sp_jit = float(cfg.spark_jitter_px)
	st_len = arrow_size.x * float(cfg.stuck_len_rel)
	st_jit = deg_to_rad(float(cfg.stuck_angle_jitter_deg))
	st_life_ticks = Vector2(cfg.stuck_life[0], cfg.stuck_life[1]) * tps
	setup_sound(m.get_node_or_null("/root/Audio"))
	return true


# Звуки, у которых есть запись в data/audio.json (has_sound); остальные не зовутся вовсе — без предупреждений на каждый вызов.
func setup_sound(au: Node) -> void:
	audio = au
	snd_whoosh = ""
	snd_hits = []
	if au == null or not au.has_method("has_sound"):
		return
	if au.has_sound(cfg.sound_whoosh):
		snd_whoosh = cfg.sound_whoosh
	snd_hits = cfg.sound_hits.filter(func(n): return au.has_sound(n))


# --- Полёт: слоты ------------------------------------------------------------------------------------------------------------

func _free_all() -> void:
	slot_vid.fill(-1)
	slot_t1.fill(-1)
	slot_next = 0
	air_buf.fill(0.0)   # t0 = t1 = 0: шейдер сворачивает квадрат
	air_dirty = true


# Выстрел (main._fire_arrow, индекс в очереди a — стрела уже в очереди; только при включённой отрисовке). Выборка: стрел в очереди
# больше max_visible — в слот идёт каждая stride-я по номеру выстрела. Слоты — кольцо: упавшую стрелу шейдер прячет сам (u >= 1),
# освобождать слот при падении не нужно; в выборке стрел в полёте не больше max_visible, и место берёт уже упавшая.
func fire(a: int) -> void:
	var vid: int = main.arrow_vid[a]
	stride = maxi(ceili(float(main.arrow_count) / slot_vid.size()), 1)
	if vid % stride != 0:
		skipped += 1
		return
	var k := slot_next
	slot_next = (k + 1) % slot_vid.size()
	var t0: float = main.arrow_t0[a]
	var t1: int = main.arrow_tick[a]
	var from: Vector2 = main.arrow_from[a]
	var d: Vector2 = main.arrow_land[a] - from
	slot_vid[k] = vid
	slot_t0[k] = t0
	slot_t1[k] = t1
	drawn += 1
	var o := k * FPI_AIR
	air_buf[o + 0] = 1.0
	air_buf[o + 1] = 0.0
	air_buf[o + 3] = from.x
	air_buf[o + 4] = 0.0
	air_buf[o + 5] = 1.0
	air_buf[o + 7] = from.y
	air_buf[o + 8] = t0 - base
	air_buf[o + 9] = t1 - base
	air_buf[o + 10] = 0.0
	air_buf[o + 11] = 1.0
	air_buf[o + 12] = d.x
	air_buf[o + 13] = d.y
	air_buf[o + 14] = 4.0 * arc_k * d.length()
	air_buf[o + 15] = 0.0
	air_dirty = true
	whoosh_due = minf(whoosh_due, t0)
	air_until = maxf(air_until, t1)


# Все стрелы очереди main — в слоты (отрисовку включили: события выстрелов до этого не приходили).
func register_queue() -> void:
	_free_all()
	for a in main.arrow_count:
		fire(a)
	registered = true


# Сдвиг базы времени: значения в буфере (half float в GLES3) остаются малыми. Слоты, чья стрела давно упала, обнуляются.
func _rebase(td: float) -> void:
	base = floorf(td)
	for k in slot_vid.size():
		if slot_vid[k] < 0:
			continue
		if slot_t1[k] < base - 1.0:
			slot_vid[k] = -1
			air_buf[k * FPI_AIR + 8] = 0.0
			air_buf[k * FPI_AIR + 9] = 0.0
			continue
		air_buf[k * FPI_AIR + 8] = slot_t0[k] - base
		air_buf[k * FPI_AIR + 9] = slot_t1[k] - base
	air_dirty = true
	for k in st_t1.size():
		if st_t1[k] < base:
			st_t1[k] = -1.0   # погасла
			stuck_buf[k * FPI + 8] = 0.0
			stuck_buf[k * FPI + 9] = 0.0
		else:
			stuck_buf[k * FPI + 8] = st_t0[k] - base
			stuck_buf[k * FPI + 9] = st_t1[k] - base
	stuck_dirty = true


# Положение и направление стрелы слота k в момент td, как в шейдере (проверки и кадры): [видна, точка, направление].
func flight_at(k: int, td: float, ground := false) -> Array:
	if k < 0 or slot_vid[k] < 0:
		return [false, Vector2.ZERO, Vector2.RIGHT]
	var o := k * FPI_AIR
	var t0 := air_buf[o + 8]
	var t1 := air_buf[o + 9]
	var u := (td - base - t0) / maxf(t1 - t0, 0.001)
	if t1 <= t0 or u < 0.0 or u >= 1.0:
		return [false, Vector2.ZERO, Vector2.RIGHT]
	var a := Vector2(air_buf[o + 3], air_buf[o + 7])
	var d := Vector2(air_buf[o + 12], air_buf[o + 13])
	var arc4 := air_buf[o + 14]
	var p := a + d * u
	var dir := d
	if not ground:
		p.y -= h0 * (1.0 - u) + arc4 * u * (1.0 - u)
		dir = Vector2(d.x, d.y + h0 - arc4 * (1.0 - 2.0 * u))
	return [true, p, dir.normalized() if dir.length() > 0.0001 else Vector2.RIGHT]


# Слот стрелы с номером выстрела vid (-1 — не рисуется; проверки и кадры).
func slot_for(vid: int) -> int:
	for k in slot_vid.size():
		if slot_vid[k] == vid:
			return k
	return -1


# Стрел в полёте на экране в момент td (проверки и кадры; в кадре не считается).
func count_in_flight(td: float) -> int:
	var n := 0
	for k in slot_vid.size():
		if slot_vid[k] >= 0 and slot_t0[k] <= td and td < slot_t1[k]:
			n += 1
	return n


# --- Падение -------------------------------------------------------------------------------------------------------------------

# Падение стрелы a очереди main (_process_arrows, до удаления из очереди; только при включённой отрисовке): попала ли, позиция
# цели. Эффект появится, когда время картинки дойдёт до тика падения.
func land(a: int, hit: bool, target: Vector2) -> void:
	if ev_n >= ev_t.size():
		ev_dropped += 1
		return
	var to: Vector2 = main.arrow_land[a]
	var t1: int = main.arrow_tick[a]
	ev_to[ev_n] = to
	ev_dir[ev_n] = (to - main.arrow_from[a]).normalized()
	ev_tgt[ev_n] = target
	ev_t[ev_n] = t1
	ev_hit[ev_n] = 1 if hit else 0
	ev_n += 1
	ev_min = mini(ev_min, t1)


# Всё убрать (отрисовка выключена): слоты, очередь, искры, воткнутые.
func clear() -> void:
	_free_all()
	air_mm.buffer = air_buf
	air_dirty = false
	registered = false
	ev_n = 0
	ev_min = 1 << 30
	spark_n = 0
	st_t1.fill(-1.0)
	stuck_buf.fill(0.0)
	stuck_mm.buffer = stuck_buf
	stuck_dirty = false
	whoosh_due = INF
	air_until = -1.0
	stuck_until = -1.0
	spark_mm.visible_instance_count = 0


# --- Кадр ----------------------------------------------------------------------------------------------------------------------

# Кадр (из main._process после юнитов): td — время картинки в тиках, dt — время кадра (0 на паузе), zoom — px экрана на px мира.
func frame(td: float, dt: float, zoom: float) -> void:
	var t_us := Time.get_ticks_usec()
	_frame(td, dt, zoom)
	cost_us = Time.get_ticks_usec() - t_us


func _frame(td: float, dt: float, zoom: float) -> void:
	if on != shown:
		shown = on
		for n in [air_node, shadow_node, spark_node, stuck_node]:
			n.visible = on
		if not on:
			clear()
	if not on:
		return
	if not registered:
		base = floorf(td)
		register_queue()
	hits_frame = 0
	released = 0
	cur_td = td
	if spark_n > 0:
		_age_sparks(dt)
	if ev_n > 0 and td >= ev_min:
		_land_effects(td)
	if spark_n > 0 or spark_mm.visible_instance_count > 0:
		_draw_sparks()
	lod_skip = maxf(arrow_size.x, arrow_size.y) * zoom < float(cfg.lod_min_screen_px)
	var flying := td < air_until   # нечего рисовать — ноды скрыты (без вызова отрисовки на видеокарте)
	air_node.visible = flying and not lod_skip
	shadow_node.visible = flying and not lod_skip
	stuck_node.visible = td < stuck_until
	_draw_flights(td)
	if td >= whoosh_due:
		released = 1
		whoosh_due = INF
	if dt > 0.0 and (released > 0 or hits_frame > 0):
		_sounds()


# Полёт: буфер — только если слоты менялись (выстрелы, падения, сдвиг базы); каждый кадр — время в шейдер.
func _draw_flights(td: float) -> void:
	draw_calls += 1
	if td - base >= REBASE_TICKS or td < base:
		_rebase(td)
	if air_dirty:
		air_mm.buffer = air_buf
		air_dirty = false
	if stuck_dirty:
		stuck_mm.buffer = stuck_buf
		stuck_dirty = false
	var rel := td - base
	air_mat.set_shader_parameter("td", rel)
	shadow_mat.set_shader_parameter("td", rel)
	stuck_mat.set_shader_parameter("td", rel)


# Свист — если стрелы сорвались с тетивы, удар — если были попадания; не чаще интервалов из данных.
func _sounds() -> void:
	var now := Time.get_ticks_msec()
	if released > 0 and now - whoosh_at >= float(cfg.whoosh_min_interval_ms):
		whoosh_at = now
		whoosh_wanted += 1
		if snd_whoosh != "":
			audio.play_sfx(snd_whoosh)
			sounds_played += 1
	if hits_frame > 0 and now - hit_snd_at >= float(cfg.hit_sound_min_interval_ms):
		hit_snd_at = now
		hit_snd_wanted += 1
		if not snd_hits.is_empty():
			audio.play_sfx(snd_hits[fx_rng.randi() % snd_hits.size()])
			sounds_played += 1


# Искры старше на кадр (только не на паузе).
func _age_sparks(dt: float) -> void:
	if dt <= 0.0:
		return
	var i := 0
	while i < spark_n:
		sp_left[i] -= 1
		if sp_left[i] <= 0:
			spark_n -= 1
			sp_pos[i] = sp_pos[spark_n]
			sp_left[i] = sp_left[spark_n]
			sp_size[i] = sp_size[spark_n]
			sp_col[i] = sp_col[spark_n]
			continue
		i += 1


# Эффекты падений, чей тик картинка уже показала.
func _land_effects(td: float) -> void:
	var e := 0
	ev_min = 1 << 30
	while e < ev_n:
		if float(ev_t[e]) > td:
			ev_min = mini(ev_min, ev_t[e])
			e += 1
			continue
		if ev_hit[e] == 1:
			_spawn_spark(ev_tgt[e])
		else:
			_spawn_stuck(ev_to[e], ev_dir[e], ev_t[e])
		ev_n -= 1
		ev_to[e] = ev_to[ev_n]
		ev_dir[e] = ev_dir[ev_n]
		ev_tgt[e] = ev_tgt[ev_n]
		ev_t[e] = ev_t[ev_n]
		ev_hit[e] = ev_hit[ev_n]


func _spawn_spark(p: Vector2) -> void:
	hits_shown += 1
	hits_frame += 1
	var cols: Array = cfg.spark_colors
	var j := sp_jit
	for q in fx_rng.randi_range(sp_cnt.x, sp_cnt.y):
		if spark_n >= sp_pos.size():
			return
		sp_pos[spark_n] = p + Vector2(fx_rng.randf_range(-j, j), fx_rng.randf_range(-j, j))
		sp_left[spark_n] = fx_rng.randi_range(sp_frames.x, sp_frames.y)
		sp_size[spark_n] = roundf(fx_rng.randf_range(sp_sz.x, sp_sz.y))
		sp_col[spark_n] = cols[fx_rng.randi() % cols.size()]
		spark_n += 1


# Воткнутая: остриё в точке падения, древко назад к лучнику; с тика падения t1 живёт stuck_life (в тиках), место в кольце —
# самой старой.
func _spawn_stuck(p: Vector2, dir: Vector2, t1: int) -> void:
	stuck_shown += 1
	var k := st_next
	st_next = (st_next + 1) % st_pos.size()
	var ang := dir.angle() + fx_rng.randf_range(-st_jit, st_jit)
	var c := cos(ang)
	var s := sin(ang)
	var h := arrow_size.y
	var at := p - dir * (st_len * 0.5)
	st_pos[k] = at
	st_t0[k] = t1
	st_t1[k] = t1 + fx_rng.randf_range(st_life_ticks.x, st_life_ticks.y)
	stuck_until = maxf(stuck_until, st_t1[k])
	var o := k * FPI
	stuck_buf[o + 0] = c * st_len
	stuck_buf[o + 1] = -s * h
	stuck_buf[o + 3] = at.x
	stuck_buf[o + 4] = s * st_len
	stuck_buf[o + 5] = c * h
	stuck_buf[o + 7] = at.y
	stuck_buf[o + 8] = st_t0[k] - base
	stuck_buf[o + 9] = st_t1[k] - base
	stuck_buf[o + 10] = 1.0
	stuck_buf[o + 11] = 1.0
	stuck_dirty = true


# Видимых воткнутых в момент td (по умолчанию — последнего кадра) и прозрачность k-й, как в шейдере (проверки и кадры).
func stuck_count(td := NAN) -> int:
	var t := cur_td if is_nan(td) else td
	var n := 0
	for k in st_t1.size():
		if st_t0[k] <= t and t < st_t1[k]:
			n += 1
	return n


func stuck_alpha(k: int, td: float) -> float:
	if td < st_t0[k] or td >= st_t1[k]:
		return 0.0
	return minf((st_t1[k] - td) / (float(cfg.stuck_fade) * (st_t1[k] - st_t0[k])), 1.0)


func _draw_sparks() -> void:
	for i in spark_n:
		var o := i * FPI
		var s := sp_size[i]
		var c := sp_col[i]
		spark_buf[o + 0] = s
		spark_buf[o + 1] = 0.0
		spark_buf[o + 3] = sp_pos[i].x
		spark_buf[o + 4] = 0.0
		spark_buf[o + 5] = s
		spark_buf[o + 7] = sp_pos[i].y
		spark_buf[o + 8] = c.r
		spark_buf[o + 9] = c.g
		spark_buf[o + 10] = c.b
		spark_buf[o + 11] = 1.0
	if spark_n > 0:
		spark_mm.buffer = spark_buf
	spark_mm.visible_instance_count = spark_n


# Середины искр и воткнутых (кадры отчёта).
func spark_center() -> Vector2:
	var c := Vector2.ZERO
	for i in spark_n:
		c += sp_pos[i]
	return c / maxf(spark_n, 1)


func stuck_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for k in st_t1.size():
		if st_t0[k] <= cur_td and cur_td < st_t1[k]:
			c += st_pos[k]
			n += 1
	return c / maxf(n, 1)
