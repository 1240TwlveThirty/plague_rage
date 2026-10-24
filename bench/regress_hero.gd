extends SceneTree
# Регрессия с героем (задача 13): рабочий scripts/main.gd против старой копии (аргумент — путь к .gd, например main.gd до правки:
# git show <коммит>:scripts/main.gd > <файл>) бок о бок, hero_mode 1, герой идёт к ближайшему зомби и бьёт в каждый тик, когда может
# (удержание J). Волна 10, seed 3, ворота бессмертны, до 1800 тиков; pos, hp, cooldown, count, золото, ворота, стрелы, убитые героем —
# на каждом тике. Два прогона: без дерева (только тики) и в дереве — между тиками по 2 кадра _process (эффекты ударов: кровь, куски,
# тряска) — кадры не должны менять симуляцию. Печатает REGRESS_HERO: провалов N.
const NEW := "res://scripts/main.gd"
const DT := 1.0 / 30.0
var fails := 0

func check(what: String, ok: bool, info := "") -> void:
	if not ok:
		fails += 1
	print("  %s: %s%s" % [what, "да" if ok else "НЕТ", "" if info == "" else " (" + info + ")"])

func make(path: String, tree: bool) -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = 3
	m.waves_enabled = true
	m.record_path = "user://record_bench.json"
	m.hero_mode = 1
	if tree:
		m.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(m)
	else:
		m._setup_data()
	m.hero_feed = func(_t): return chase(m)
	m.wave_number = 9
	m.wave_plan_for = -1
	m.gate_hp = 1e9
	m.gate_hp_max = 1e9
	m._start_wave()
	m.hp[m.hero_idx] = 1e6   # герой не гибнет весь замер (в обеих копиях одинаково)
	return m

# Ввод героя: к ближайшему живому зомби (стоит, если ближе 12 px), взгляд на него, удар в каждый тик (удержание J).
func chase(m: Node2D) -> Dictionary:
	var h: int = m.hero_idx
	if h < 0:
		return {"move": Vector2.ZERO}
	var best := -1
	var bd := INF
	for j in m.count:
		if m.team[j] == 1 and m.hp[j] > 0.0:
			var d: float = m.pos[h].distance_squared_to(m.pos[j])
			if d < bd:
				bd = d
				best = j
	if best < 0:
		return {"move": Vector2.ZERO, "attack": true}
	var to: Vector2 = m.pos[best] - m.pos[h]
	return {"move": to.normalized() if bd > 144.0 else Vector2.ZERO, "face": to.angle(), "attack": true}

func same(a: Node2D, b: Node2D) -> bool:
	if a.count != b.count or a.gold != b.gold or a.gate_hp != b.gate_hp or a.arrows_fired != b.arrows_fired or a.wave_state != b.wave_state \
			or a.hero_kills != b.hero_kills or a.hero_hits != b.hero_hits or a.hero_idx != b.hero_idx:
		return false
	for i in a.count:
		if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i] or a.cooldown[i] != b.cooldown[i]:
			return false
	return true

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not FileAccess.file_exists(args[0]):
		print("REGRESS_HERO: нужен путь к старой копии main.gd")
		quit(1)
		return
	var old: String = args[0]
	print("старая копия: " + old)
	for tree in [false, true]:
		var a := make(old, tree)
		var b := make(NEW, tree)
		if tree:
			await process_frame
		var first := -1
		var ticks := 0
		while b.wave_state == b.WS_BATTLE and ticks < 1800:
			a._physics_process(DT)
			b._physics_process(DT)
			if tree:
				for f in 2:
					a._process(1.0 / 60.0)
					b._process(1.0 / 60.0)
			ticks += 1
			if first < 0 and not same(a, b):
				first = ticks
		var fx := ""
		if tree:
			fx = ", всплесков %d, кусков не создано по лимиту %d" % [b.hit_bursts, b.gib_dropped]
		check("%s: волна 10 с героем (%d тиков, ударов %d, попаданий %d, убито героем %d, юнитов %d%s): как у старой копии на каждом тике" % [
			"в дереве, с кадрами эффектов" if tree else "без дерева", ticks, b.hero_swings, b.hero_hits, b.hero_kills, b.count, fx],
			first < 0 and ticks > 300 and b.hero_kills > 0 and (not tree or b.hit_bursts > 0), "первое расхождение: тик %d" % first)
		if tree:
			a.queue_free()
			b.queue_free()
			await process_frame
		else:
			a.free()
			b.free()
	print("REGRESS_HERO: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
