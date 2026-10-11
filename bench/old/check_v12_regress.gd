extends SceneTree
# (б) регрессия: новый main.gd с block_mult = 1.0 у infantry против bak12, 30 с, сравнение на каждом тике.
func compare(mult: float) -> String:
	var a: Node2D = load("res://bench/old/main_bak12.gd").new()
	var b: Node2D = load("res://scripts/main.gd").new()
	a._setup_data()
	b._setup_data()
	b.type_block_mult[b.type_id["infantry"]] = mult
	var first := -1
	for t in range(1, 30 * 30 + 1):
		a._physics_process(1.0 / 30.0)
		b._physics_process(1.0 / 30.0)
		if first < 0 and (a.count != b.count or a.pos != b.pos or a.hp != b.hp):
			first = t
	var res := "совпадает на всех 900 тиках" if first < 0 else "расходится с тика %d (%.1f с)" % [first, first / 30.0]
	res += "; удары %d, заблокировано %d" % [b.total_hits, b.blocked_hits]
	a.free()
	b.free()
	return res

func _initialize() -> void:
	print("(б) block_mult infantry = 1.0: " + compare(1.0))
	print("    контроль, block_mult = 0.3: " + compare(0.3))
	quit()