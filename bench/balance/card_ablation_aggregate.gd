extends SceneTree
# Абляция карточек (задача 6, этап E): сборщик bench/balance/card_ablation_v1_runs/*.txt (card_ablation_run.sh) -> bench/card_ablation_v1.txt.
# Аргумент (необязательный): сколько секунд шли забеги. Метрика — непрерывная волна смерти (волна смерти + доля убитых зомби этой волны),
# медиана по seed 1-5, сдвиг — от набора без карточек того же бота. Сила армии на волне 4: гладкая (sqrt(H * D)) и по порогам урона
# (bench/balance/strength.gd, BREAKPOINTS) — отношение к базе. Нет файлов или они пустые — строки с «—», сборщик не падает.
const CARDS := preload("res://scripts/cards.gd")
const OUT := "res://bench/card_ablation_v1.txt"
const DIR := "res://bench/balance/card_ablation_v1_runs/"
const BOTS := ["B2", "B5"]
const SEEDS := [1, 2, 3, 4, 5]
const PICK_SEEDS := 200
const ALIVE := 41.0
const PAIRS := [["serrated_arrows", "long_shot"], ["infantry_temper", "steadfast"], ["marauders", "armorer_discount"], ["last_stand", "desperate_charge"], ["first_volley", "quick_reload"]]
const VARIANTS := [["meteor_blades", "v_meteor_blades_as"], ["silver_vs_dead", "v_silver_vs_dead_as"], ["long_spears", "v_long_spears_as"],
	["v_tempered_steel_1", "v_tempered_steel_as_1"], ["v_tempered_steel_2", "v_tempered_steel_as_2"], ["v_tempered_steel_3", "v_tempered_steel_as_3"]]
const BOT_BLIND_CONDS := ["hold", "retreat"]          # боты не меняют приказ
const BOT_BLIND_STATS := ["signal_window", "repair_cost"]   # боты не ремонтируют ворота и не реагируют на сигнал
var defs := {}

func load_run(name: String) -> Dictionary:
	var path := DIR + name + ".txt"
	var r := {"waves": [], "defeat": -1, "death": -1.0, "gold": 0, "cards": []}
	if not FileAccess.file_exists(path):
		return r
	var frac := 0.0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var f := line.strip_edges().split(",")
		if f[0] == "WAVE" and f.size() >= 20:
			r.waves.append({"p": sqrt(float(f[12]) * float(f[13])), "pb": sqrt(float(f[12]) * float(f[19])), "e": sqrt(float(f[14]) * float(f[15]))})
			r.gold = int(f[17])
			frac = float(f[18]) / float(f[9]) if int(f[9]) > 0 else 0.0
		elif f[0] == "RUN":
			r.defeat = int(f[3]) if int(f[3]) > 0 else (int(ALIVE) if int(f[4]) == 1 else -1)
			r.death = -1.0 if r.defeat < 0 else (ALIVE if r.defeat == int(ALIVE) else r.defeat + minf(frac, 0.99))
		elif f[0] == "CARDS":
			r.cards = Array(f.slice(1)).map(func(x): return x.get_slice(":", 0))
	return r

func runs(cfg: String, bot: String, seeds := SEEDS) -> Array:
	var out := []
	for s in seeds:
		var r := load_run("%s_%s_s%d" % [cfg, bot, s])
		if r.death >= 0.0:
			out.append(r)
	return out

func median(rs: Array) -> float:
	if rs.is_empty():
		return -1.0
	var d := rs.map(func(r): return r.death)
	d.sort()
	return d[d.size() / 2]

func quant(vals: Array, q: float) -> float:
	if vals.is_empty():
		return -1.0
	var v := vals.duplicate()
	v.sort()
	return v[clampi(int(q * (v.size() - 1) + 0.5), 0, v.size() - 1)]

func gmean4(rs: Array, key: String) -> float:
	var s := 0.0
	var n := 0
	for r in rs:
		if r.waves.size() >= 4:
			s += log(r.waves[3][key])
			n += 1
	return exp(s / n) if n > 0 else 0.0

# Сдвиг медианы набора cfg от базы бота; нет данных — NAN.
func shift(cfg: String, bot: String) -> float:
	var a := median(runs("none", bot))
	var b := median(runs(cfg, bot))
	return NAN if a < 0.0 or b < 0.0 else b - a

func fs(v: float) -> String:
	return "     —" if is_nan(v) else "%+6.2f" % v

func ratio4(cfg: String, key: String) -> float:
	var vals := []
	for bot in BOTS:
		var b := gmean4(runs("none", bot), key)
		var c := gmean4(runs(cfg, bot), key)
		if b > 0.0 and c > 0.0:
			vals.append(c / b)
	if vals.is_empty():
		return NAN
	return sqrt(vals[0] * vals[-1]) if vals.size() == 2 else vals[0]

func has_cost(d: Dictionary) -> bool:
	return d.mods.any(func(e): return e.get("cost", false))

func bot_blind(d: Dictionary) -> bool:
	return (d.has("when") and d.when.cond in BOT_BLIND_CONDS) or d.mods.any(func(e): return e.stat in BOT_BLIND_STATS)

func _initialize() -> void:
	if root.has_node("Game"):
		root.get_node("Game").free()
	TranslationServer.set_locale("ru")
	defs = CARDS.load_cards("res://data/cards.json")
	var args := OS.get_cmdline_user_args()
	var secs := int(args[0]) if args.size() > 0 else 0
	var L: Array[String] = []
	var active := CARDS.active_ids(defs)
	L.append("card_ablation_v1: абляция карточек (задача 6, этап E), только измерения. Карточки и баланс не менялись по её итогам.")
	L.append("Пересчёт (из корня проекта):  sh bench/balance/card_ablation_run.sh \"<путь к godot.exe>\"")
	L.append("Время прогона: %s; до 10 процессов сразу, %d потоков процессора." % ["%d мин %02d с" % [secs / 60, secs % 60] if secs > 0 else "не измерялось (сборщик запущен отдельно)", OS.get_processor_count()])
	L.append("Боты B2 (по кругу пехота, оружие) и B5 (по кругу пехота, лучники), осада I, волны без предела; отряды на старте, приказ «атака», всё золото — в передышке.")
	L.append("Метрика — непрерывная волна смерти (волна + доля убитых зомби волны смерти); медиана по seed 1-5; сдвиг — от «без карточек» того же бота.")
	var base := PackedStringArray()
	for bot in BOTS:
		var rs := runs("none", bot)
		base.append("%s %s (%s)" % [bot, "—" if rs.is_empty() else "%.2f" % median(rs), "/".join(rs.map(func(r): return "%.2f" % r.death))])
	L.append("База без карточек: " + "; ".join(base))
	L.append("P4 — сила армии на старте волны 4 после покупок с карточкой / без, среднее геометрическое по seed и двум ботам: гладкая (урон непрерывный) и по порогам")
	L.append("  (урон удара = HP цели / ceil(HP цели / урон), взвешенно по составу волны). Карточка с одной издержкой из 15 — «изд.».")
	L.append("Пометки: МЁРТВАЯ — сдвиг < +0.2 у обоих ботов; СИЛЬНАЯ — > +2 у любого; ИЗДЕРЖКА МЯГКАЯ — с издержкой, а сдвиг (среднее ботов) больше среднего")
	L.append("  карточек того же основного билда без издержки; БОТ НЕ УМЕЕТ — условие hold / retreat или стат signal_window / repair_cost (боты не меняют приказ,")
	L.append("  не ремонтируют ворота, не реагируют на сигнал: ноль здесь не провал); НЕТ БОЕВОГО ЭФФЕКТА — heal (база лечения полная) и radiance_pct (только Сияние).")
	L.append("")
	# 1. Каждая карточка
	var rows := []
	var by_build := {}
	for id in active:
		var d: Dictionary = defs[id]
		var s2 := shift(id, "B2")
		var s5 := shift(id, "B5")
		var avg := NAN if is_nan(s2) or is_nan(s5) else (s2 + s5) / 2.0
		rows.append({"id": id, "d": d, "b2": s2, "b5": s5, "avg": avg, "p": ratio4(id, "p"), "pb": ratio4(id, "pb")})
		if not has_cost(d) and not is_nan(avg):
			by_build[d.builds[0]] = by_build.get(d.builds[0], []) + [avg]
	var build_mean := {}
	for b in by_build:
		build_mean[b] = by_build[b].reduce(func(a, x): return a + x, 0.0) / by_build[b].size()
	var flagged := {}
	L.append("1. Каждая активная карточка (порядок таблицы задания).")
	L.append("  №  | %-30s | билд          | тип | изд. |    B2 |    B5 | средн. | P4 гладк. | P4 пороги | пометки" % "карточка")
	for r in rows:
		var d: Dictionary = r.d
		var flags := PackedStringArray()
		if d.mods.any(func(e): return e.stat in ["heal", "radiance_pct"] and not e.get("cost", false)):
			flags.append("НЕТ БОЕВОГО ЭФФЕКТА")
		elif bot_blind(d):
			flags.append("БОТ НЕ УМЕЕТ")
		if not is_nan(r.b2) and r.b2 < 0.2 and r.b5 < 0.2:
			flags.append("МЁРТВАЯ")
		if not is_nan(r.b2) and (r.b2 > 2.0 or r.b5 > 2.0):
			flags.append("СИЛЬНАЯ")
		if has_cost(d) and not is_nan(r.avg) and build_mean.has(d.builds[0]) and r.avg > build_mean[d.builds[0]]:
			flags.append("ИЗДЕРЖКА МЯГКАЯ (%+.2f > %+.2f у билда)" % [r.avg, build_mean[d.builds[0]]])
		r["flags"] = flags
		if not flags.is_empty():
			flagged[r.id] = flags
		L.append("  %2d | %-30s | %-13s |  %s  | %s | %s | %s | %s |     %s |     %s | %s" % [int(d.num), tr(d.name_key).left(30), "+".join(d.builds), d.kind,
			" да " if has_cost(d) else "  — ", fs(r.b2), fs(r.b5), fs(r.avg), "—" if is_nan(r.p) else "%.3f" % r.p, "—" if is_nan(r.pb) else "%.3f" % r.pb, ", ".join(flags)])
	L.append("  Средний сдвиг карточек без издержки по основному билду: %s" % ", ".join(build_mean.keys().map(func(b): return "%s %+.2f" % [b, build_mean[b]])))
	L.append("")
	# 2. Топ и низ
	var valid := rows.filter(func(r): return not is_nan(r.avg))
	valid.sort_custom(func(a, b): return a.avg > b.avg)
	L.append("2. Сильнейшие и слабейшие (среднее двух ботов).")
	for k in mini(5, valid.size()):
		var r = valid[k]
		L.append("  топ %d: №%d %s — %+.2f (B2 %+.2f, B5 %+.2f)" % [k + 1, int(r.d.num), tr(r.d.name_key), r.avg, r.b2, r.b5])
	for k in mini(5, valid.size()):
		var r = valid[valid.size() - 1 - k]
		L.append("  низ %d: №%d %s — %+.2f (B2 %+.2f, B5 %+.2f)" % [k + 1, int(r.d.num), tr(r.d.name_key), r.avg, r.b2, r.b5])
	L.append("")
	# 3. Синергии
	L.append("3. Пары: сдвиг пары и сумма сдвигов карточек по отдельности; «сильнее суммы» — пара больше суммы на 0.3 и больше хотя бы у одного бота.")
	for pr in PAIRS:
		var cfg := "pair_%s__%s" % pr
		var cells := PackedStringArray()
		var strong := false
		for bot in BOTS:
			var sp := shift(cfg, bot)
			var ss := shift(pr[0], bot) + shift(pr[1], bot)
			cells.append("%s: пара %s, сумма %s" % [bot, fs(sp).strip_edges(), fs(ss).strip_edges()])
			strong = strong or (not is_nan(sp) and not is_nan(ss) and sp - ss >= 0.3)
		L.append("  №%d + №%d (%s + %s): %s%s" % [int(defs[pr[0]].num), int(defs[pr[1]].num), tr(defs[pr[0]].name_key), tr(defs[pr[1]].name_key), "; ".join(cells),
			" — СИЛЬНЕЕ СУММЫ" if strong else ""])
	L.append("")
	# 4. Варианты
	L.append("4. Варианты (bench/card_variants.json, в пул не входят): скорость удара пехоты (attack_speed) вместо урона, те же проценты.")
	L.append("  «Закалённая сталь» — дар как карточка с начала забега (урон пехоты +6/12/18%) и его вариант (скорость удара +6/12/18%).")
	for pr in VARIANTS:
		var a: String = pr[0]
		var b: String = pr[1]
		var ca := a if not a.begins_with("v_") else "var_" + a
		var cb := "var_" + b
		L.append("  %-22s B2 %s, B5 %s | %-22s B2 %s, B5 %s" % [a, fs(shift(ca, "B2")), fs(shift(ca, "B5")), b, fs(shift(cb, "B2")), fs(shift(cb, "B5"))])
	L.append("")
	# 5. Случайные билды
	L.append("5. Случайные билды: настоящий выбор (--pick random — случайная карточка из тройки после волн 2, 5, 8), seed 1-%d." % PICK_SEEDS)
	for pset in ["pick_none", "pick_gifts1"]:
		for bot in BOTS:
			var rs := runs(pset, bot, range(1, PICK_SEEDS + 1))
			L.append("  %s, %s: прогонов %d" % ["без даров" if pset == "pick_none" else "все видимые дары ур. 1", bot, rs.size()])
			if rs.is_empty():
				L.append("    нет данных")
				continue
			var deaths := rs.map(func(r): return r.death)
			var hist := {}
			for v in deaths:
				var w := int(floorf(v))
				hist[w] = hist.get(w, 0) + 1
			var hk := hist.keys()
			hk.sort()
			L.append("    волна смерти: медиана %.2f, 10%% — %.2f, 90%% — %.2f; по волнам: %s" % [quant(deaths, 0.5), quant(deaths, 0.1), quant(deaths, 0.9),
				", ".join(hk.map(func(k): return "%s: %d" % ["≥40" if k >= 41 else str(k), hist[k]]))])
			var sorted := rs.duplicate()
			sorted.sort_custom(func(a, b): return a.death > b.death)
			var n10 := maxi(1, rs.size() / 10)
			var top := sorted.slice(0, n10)
			var bottom := sorted.slice(sorted.size() - n10)
			var builds := {}
			for r in rs:
				var seen := {}
				for id in r.cards:
					if defs.has(id):
						seen[defs[id].builds[0]] = true
				for b in seen:
					builds[b] = builds.get(b, []) + [r]
			var cells := PackedStringArray()
			for b in CARDS.BUILDS:
				var list: Array = builds.get(b, [])
				var in_top := top.filter(func(r): return list.has(r)).size()
				var in_bot := bottom.filter(func(r): return list.has(r)).size()
				cells.append("%s: прогонов %d, медиана %s, в лучших 10%% %d из %d, в худших %d" % [b, list.size(), "—" if list.is_empty() else "%.2f" % median(list), in_top, n10, in_bot])
			L.append("    по билдам (прогон считается в билде, если в нём есть карточка этого основного билда):")
			for c in cells:
				L.append("      " + c)
			for part in [["лучших", top], ["худших", bottom]]:
				var freq := {}
				for r in part[1]:
					for id in r.cards:
						freq[id] = freq.get(id, 0) + 1
				var ids := freq.keys()
				ids.sort_custom(func(a, b): return freq[a] > freq[b] or (freq[a] == freq[b] and a < b))
				L.append("    чаще всего в %s 10%% (%d прогонов): %s" % [part[0], n10, ", ".join(ids.slice(0, 6).map(func(id): return "%s %d" % [tr(defs[id].name_key) if defs.has(id) else id, freq[id]]))])
	L.append("")
	L.append("Помеченные карточки: %d из %d." % [flagged.size(), active.size()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	for l in L:
		print(l)
	quit()
