extends RefCounted
# Сцены для съёмки (задача 31): data/cine_scenes.json, только отладочная сборка (Shots запускает по autostart_scene или
# --cine-scene=<id>). Бой — обычный main.gd без волн (waves_enabled = false до _ready, как в бенчах), стартовый состав заменяется
# составом сцены существующими функциями: _squad_create, _squad_add_units, _spawn_zombie, _spawn_hero. Дальше бой идёт по
# обычным правилам. Обычную игру не меняет.
const PATH := "res://data/cine_scenes.json"


static func all() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not (d is Dictionary and d.get("scenes") is Array):
		push_error("%s: нужен объект со списком scenes" % PATH)
		return []
	return d.scenes


static func find(id: String) -> Dictionary:
	for sc in all():
		if sc is Dictionary and sc.get("id") == id:
			return sc
	return {}


static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


# До _ready боя: без волн, свой seed, герой по сцене; физика стоит с готовности до build (иначе тики до сборки — сколько успеет
# пройти кадров — двигают генератор, и сцена каждый раз разная).
static func prepare(m: Node2D, sc: Dictionary) -> void:
	m.waves_enabled = false
	m.spawn_seed = int(sc.get("seed", 1))
	m.hero_mode = 1 if sc.get("hero", {}).get("on", false) else -1
	m.ready.connect(func(): m.set_physics_process(false), CONNECT_ONE_SHOT)


# После _ready: состав сцены вместо стартового; стены бессмертны (сцена не кончается поражением); замок по castle_visible.
static func build(m: Node2D, sc: Dictionary) -> void:
	m._clear_sel()
	m.count = 0
	m.hero_idx = -1
	m.zombie_alive = 0
	for s in m.SQUAD_MAX:
		if s >= m.START_SQUADS:
			m._squad_reset(s)
		else:
			m.squad_n[s] = 0
	var base_used := [false, false]   # отряды 0 (пехота) и 1 (лучники) есть всегда — первые отряды своего типа
	for q in sc.get("squads", []):
		var type: int = m.type_id[q.type]
		var base := 1 if q.type == "archer" else 0
		var s := base
		if base_used[base]:
			s = m._squad_create(base, type)
			if s < 0:
				push_warning("%s: сцена %s — свободных отрядов нет, отряд пропущен" % [PATH, sc.id])
				continue
		base_used[base] = true
		m.squad_width[s] = maxi(int(q.get("width", 1)), 1)
		m._squad_add_units(s, type, int(q.count))
		if q.has("hp"):   # HP бойцов отряда только в этой сцене (одинокий боец доживает до поздних кадров); правила боя не меняются
			for i in m.count:
				if m.unit_squad[i] == s:
					m.hp[i] = float(q.hp)
		var ang := deg_to_rad(float(q.get("facing_deg", 0.0))) - PI / 2.0
		m.squad_angle[s] = ang
		var c := _v(q.pos)
		for i in m.count:   # строй — сразу на месте (юниты на своих слотах вокруг центра)
			if m.unit_squad[i] == s:
				m.pos[i] = c + m.unit_slot[i].rotated(ang)
				m.unit_dir[i] = m._nearest_dir(ang)
		m.squad_pos[s] = c
		m._reanchor(s)
		var shift: Vector2 = c - m.squad_pos[s]
		m.squad_pos[s] += shift
		for i in m.count:
			if m.unit_squad[i] == s:
				m.pos[i] += shift
		m.squad_target[s] = _v(q.move_to) if q.has("move_to") else m.squad_pos[s]
	for s in m.START_SQUADS:   # базовый отряд без юнитов в сцене — у ворот, пустой
		if not base_used[s]:
			m.squad_pos[s] = m.gate_spot(s)
			m.squad_target[s] = m.squad_pos[s]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sc.get("seed", 1))
	for z in sc.get("zombies", []):
		var type: int = m.type_id[z.type]
		var area: Dictionary = z.area
		for k in int(z.count):
			if m.count >= m.MAX_UNITS:
				push_warning("%s: сцена %s — больше %d юнитов, остальные зомби не созданы" % [PATH, sc.id, m.MAX_UNITS])
				break
			var p: Vector2
			if area.has("rect"):
				var r: Array = area.rect
				p = Vector2(rng.randf_range(r[0], r[0] + r[2]), rng.randf_range(r[1], r[1] + r[3]))
			else:
				var a := rng.randf() * TAU
				p = _v(area.ring.center) + Vector2.from_angle(a) * float(area.ring.radius) * sqrt(rng.randf())
			m._spawn_zombie(p.clamp(Vector2.ZERO, Vector2(m.FIELD.x, m.WALL_Y - 20.0)), type)
	if m.hero_on:
		m._spawn_hero(1.0)
		var hp := _v(sc.hero.pos)
		m.pos[m.hero_idx] = hp
	m.prev_pos = m.pos.duplicate()
	m.gate_hp_max = 1e9
	m.gate_hp = 1e9
	if m.castle_sprite != null:
		m.castle_sprite.visible = bool(sc.get("castle_visible", true))
	if sc.get("start_paused", false):
		m._set_paused(true)
	m.set_physics_process(true)   # бой идёт с этого места
	m.queue_redraw()


# Камера сцены (после включения режима съёмки: предел приближения — cine_zoom_max).
static func camera(m: Node2D, sc: Dictionary) -> void:
	var cam: Dictionary = sc.get("camera", {})
	if m.camera == null or cam.is_empty():
		return
	var z := clampf(float(cam.get("zoom", 1.0)), float(m.cam_cfg.zoom_user_min), float(m.cam_cfg.zoom_user_max))
	m.zoom_user = z
	m.zoom_user_target = z
	var zz: float = m.camera_min_zoom() * z
	m.camera.zoom = Vector2.ONE * zz
	m.camera.position = m._camera_clamp(_v(cam.center), zz)
