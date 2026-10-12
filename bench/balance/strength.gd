extends RefCounted
# Метрика «сила армии» для калибровки осады I (этап 1: только измерения). Один код для игрока и для врага.
#   Сила = H * D,   H = сумма hp по юнитам армии,   D = сумма dps по юнитам армии.
#   dps юнита: ближний бой — damage * множитель урона команды / cooldown; стрелок (range_far > 0) — arrow_dmg / volley_period.
# Произведение, а не сумма по юнитам, — закон Ланчестера: и H, и D пропорциональны числу юнитов N, сила растёт как N^2.
# Игрок (player): живые юниты team 0 перед стартом волны, после покупок — hp текущее, урон уже с покупками оружия.
# Враг (enemy): весь состав волны по wave_plan после _start_wave — hp типа * wave_hp_mult, урон * team_dmg_mult[1].
# В метрику не входят: щит пехоты (block_mult), дальность, разброс и промахи стрел, одиночный огонь и ближний бой лучников,
# скорость, ворота, подход орды всплесками (враг считается так, будто вся волна на поле сразу).

# Урон в секунду одного юнита типа t команды team (0 — игрок, 1 — орда).
static func type_dps(m: Node2D, t: int, team: int) -> float:
	if m.type_range_far[t] > 0.0:
		return m.type_arrow_dmg[t] / m.type_volley_period[t]
	return m.type_damage[t] * m.team_dmg_mult[team] / m.type_cooldown[t]


# Армия из групп [число, hp одного, dps одного]: {n, hp, dps, power}.
static func army(groups: Array) -> Dictionary:
	var n := 0
	var h := 0.0
	var d := 0.0
	for g in groups:
		n += g[0]
		h += g[0] * g[1]
		d += g[0] * g[2]
	return {"n": n, "hp": h, "dps": d, "power": h * d}


static func player(m: Node2D) -> Dictionary:
	var cnt := {}
	var hps := {}
	for i in m.count:
		if m.team[i] == 0:
			var t: int = m.unit_type[i]
			cnt[t] = cnt.get(t, 0) + 1
			hps[t] = hps.get(t, 0.0) + m.hp[i]
	var groups := []
	for t in cnt:
		groups.append([cnt[t], hps[t] / cnt[t], type_dps(m, t, 0)])
	return army(groups)


# Вызывать после _start_wave: тогда wave_plan, wave_hp_mult и team_dmg_mult[1] относятся к этой волне.
static func enemy(m: Node2D) -> Dictionary:
	var groups := []
	for r in m.wave_plan:
		groups.append([r.count, m.type_hp[r.type] * m.wave_hp_mult, type_dps(m, r.type, 1)])
	return army(groups)
