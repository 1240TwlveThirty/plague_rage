extends SceneTree
# Тесты v26 (дневник в баннерах): (а) регрессия против bak26, (б) концовки, (в) записи по волнам, (г) битый story.json.
const STORY := "res://data/story.json"

func new_main(path: String, seed: int, waves: bool, story := "") -> Node2D:
	var m: Node2D = load(path).new()
	m.spawn_seed = seed
	m.waves_enabled = waves
	m.record_path = "user://record_bench.json"
	if story != "":
		m.story_path = story
	m._setup_data()
	return m

func _initialize() -> void:
	# (а)
	var a := new_main("res://bench/old/main_bak26.gd", 1, false)
	var b := new_main("res://scripts/main.gd", 1, false)
	var first := -1
	for t in range(1, 901):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0:
			if a.count != b.count or a.gate_hp != b.gate_hp:
				first = t
			else:
				for i in a.count:
					if a.pos[i] != b.pos[i] or a.hp[i] != b.hp[i]:
						first = t
						break
	print("(а) waves off против bak26: " + ("совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d" % first) + "; юнитов %d / %d" % [a.count, b.count])
	a.free()
	b.free()
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STORY))
	# (б) концовки: ожидаемый порог считается здесь по story.json независимо от main.gd
	var m := new_main("res://scripts/main.gd", 1, true)
	var ok_b := true
	var rows := []
	for w in [0, 4, 5, 14, 15, 24, 25, 40]:
		var best := {}
		for e in story.endings:
			if e.min_wave <= w and (best.is_empty() or e.min_wave > best.min_wave):
				best = e
		var expect: String = best.text.replace("{wave}", str(w))
		m.wave_number = w
		m.wave_state = m.WS_BATTLE
		m._on_defeat()
		var got: String = m.banner_parts[2]
		var hint_ok: bool = m.banner_parts[3] == "Рекорд: день %d. R — заново" % m.best_wave and m.banner_parts[0] == "" and m.banner_parts[1] == ""
		var good: bool = got == expect and not got.contains("{wave}") and got.contains(str(w)) and hint_ok and m.wave_state == m.WS_DEFEAT
		ok_b = ok_b and good
		rows.append("%d→порог %d%s" % [w, int(best.min_wave), "" if good else " ОШИБКА"])
	print("(б) концовки: %s; {wave} подставлен, подсказка «Рекорд: день M. R — заново»: %s" % [", ".join(rows), ok_b])
	# (в) записи: после каждой волны 1..40 баннер передышки, запись только у волн из entries
	var want := {}
	for e in story.entries:
		want[int(e.wave)] = e.text
	var shown := []
	var ok_c := true
	for w in range(1, 41):
		m.wave_number = w
		m.wave_state = m.WS_BATTLE
		m._wave_cleared()
		var got: String = m.banner_parts[2]
		if got != "":
			shown.append(w)
		ok_c = ok_c and got == want.get(w, "") and m.banner_parts[1].begins_with("Волна %d пройдена" % w) and m.banner_parts[0] == "" and m.banner_parts[3] == ""
	var keys := want.keys()
	keys.sort()
	print("(в) записи показаны после волн %s, в entries волны %s, тексты и строка итога верны: %s" % [shown, keys, ok_c and shown == keys])
	m.free()
	# (г) битый story.json: загрузка не проходит, симуляция остановлена (push_error уходит в stderr)
	for name in ["nofield", "badtype", "badwave", "empty", "missing"]:
		var x := new_main("res://scripts/main.gd", 1, true, "res://bench/story_bad_%s.json" % name)
		print("(г) story_bad_%s: остановка %s" % [name, x.type_id.is_empty() and not x.is_physics_processing() and not x.is_processing()])
		x.free()
	quit()
