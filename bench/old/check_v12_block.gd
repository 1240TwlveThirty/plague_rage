extends SceneTree
# (а) модульный тест блока. В симуляции остаются 2 юнита: индекс 0 = жертва, индекс 1 = атакующий.
var m: Node2D

func copy_unit(dst: int, src: int) -> void:
	m.pos[dst] = m.pos[src]
	m.team[dst] = m.team[src]
	m.unit_type[dst] = m.unit_type[src]
	m.unit_squad[dst] = m.unit_squad[src]
	m.unit_slot[dst] = m.unit_slot[src]
	m.unit_slot_idx[dst] = m.unit_slot_idx[src]
	m.unit_rand[dst] = m.unit_rand[src]

# Возвращает урон по жертве. angle_deg — откуда пришёл удар относительно фронта жертвы.
func hit(victim_src: int, attacker_src: int, squad_angle: float, angle_deg: float, victim_cd: float) -> float:
	m = load("res://scripts/main.gd").new()
	m._setup_data()
	copy_unit(1, attacker_src)   # сначала атакующий: источник может быть индексом 0
	copy_unit(0, victim_src)
	m.count = 2
	m.squad_angle[0] = squad_angle
	var dir := Vector2.from_angle(squad_angle + deg_to_rad(angle_deg))
	m.pos[0] = Vector2(1000, 500)
	m.pos[1] = m.pos[0] + dir * 6.0   # в пределах дальности атаки (7 px)
	m.hp[0] = 3.0
	m.hp[1] = 3.0
	m.cooldown[0] = victim_cd
	m.cooldown[1] = 0.0
	m._build_grid()
	m._update_unit(1, 2.0 / 30.0)
	var dmg: float = 3.0 - m.hp[0]
	var res := "урон %.2f (blocked=%d, total=%d)" % [dmg, m.blocked_hits, m.total_hits]
	m.free()
	return dmg if res != "" else 0.0

func row(label: String, victim_src: int, attacker_src: int, sa: float, deg: float, cd: float) -> void:
	print("  %-46s урон %.2f" % [label, hit(victim_src, attacker_src, sa, deg, cd)])

func _initialize() -> void:
	var up := 0.0      # cooldown 0: давно не бил, щит поднят
	var down := 0.7    # с удара прошло 0.8 - 0.7 = 0.1 с < 0.25: щит опущен
	var edge := 0.55   # прошло ровно 0.25 с: щит уже поднят
	for sa in [0.0, PI, 1.0]:
		print("Жертва infantry (отряд 0, angle = %.2f), атакующий зомби:" % sa)
		row("спереди (0°), щит поднят", 0, 300, sa, 0.0, up)
		row("спереди (0°), щит опущен (0.1 с после удара)", 0, 300, sa, 0.0, down)
		row("спереди (0°), ровно 0.25 с после удара", 0, 300, sa, 0.0, edge)
		row("сбоку +59°, щит поднят", 0, 300, sa, 59.0, up)
		row("сбоку -59°, щит поднят", 0, 300, sa, -59.0, up)
		row("сбоку +61°, щит поднят", 0, 300, sa, 61.0, up)
		row("сбоку -61°, щит поднят", 0, 300, sa, -61.0, up)
		row("сбоку 90°, щит поднят", 0, 300, sa, 90.0, up)
		row("сзади (180°), щит поднят", 0, 300, sa, 180.0, up)
	print("Жертва зомби (без отряда, block_mult 1.0), атакующий infantry:")
	for deg in [0.0, 59.0, 90.0, 180.0]:
		for cd in [0.0, 0.7]:
			row("удар с %d°, cooldown жертвы %.1f" % [deg, cd], 300, 0, 0.0, deg, cd)
	quit()