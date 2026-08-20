extends SceneTree

var _f := 0
var _prev_state := -1

func _process(_delta: float) -> bool:
	_f += 1
	if _f == 8:
		var main: Node = root.get_node("Main")
		var world: Node = main.get_node("World")
		var placement: Node = main.get_node("BuildingPlacement")
		var resources: Node = root.get_node("VillageResources")
		var miner: Node = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
		miner.position = Vector2(500, 140)
		world.add_child(miner)
		var deposits := get_nodes_in_group("stone_deposits")
		var deposit: Node = deposits[0]
		print("deposit at ", deposit.global_position, " miner at (500,140)")
		placement._set_building_type("quarry")
		resources._amounts["wood"] = 20
		placement._try_place_quarry_at(deposit.global_position)
		var quarry := get_nodes_in_group("quarries")[0]
		quarry.assign_worker(miner)
		print("assigned. quarry at ", quarry.global_position)
	if _f >= 8:
		var miners := get_nodes_in_group("miners")
		if miners.size() > 0:
			var m: Node = miners[0]
			if m.state != _prev_state:
				print("  f=", _f, " state->", m.state, " pos=", m.global_position, " stone=", root.get_node("VillageResources").get_amount("stone"))
				_prev_state = m.state
	if _f == 1500:
		var miners := get_nodes_in_group("miners")
		var m: Node = miners[0] if miners.size() > 0 else null
		if m != null:
			print("FINAL state=", m.state, " pos=", m.global_position, " stone=", root.get_node("VillageResources").get_amount("stone"))
		quit()
		return true
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
