extends SceneTree
# (а) регрессия: новый main.gd с leash = 100000 у infantry против bak13, 30 с, сравнение на каждом тике.
func compare(leash: float) -> String:
	var a: Node2D = load("res://bench/main_bak13.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a._setup_data()
	b._setup_data()
	b.type_leash_sq[b.type_id["infantry"]] = leash * leash
	var first := -1
	for t in range(1, 30 * 30 + 1):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp):
			first = t
	var res := "совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d (%.1f с)" % [first, first / 30.0]
	res += "; leash_returns %d" % b.leash_returns
	a.free()
	b.free()
	return res

func _initialize() -> void:
	print("(а) leash infantry = 100000: " + compare(100000.0))
	print("    контроль, leash = 12: " + compare(12.0))
	quit()