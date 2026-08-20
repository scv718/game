extends SceneTree

var _f := 0
var _last_pos := Vector2.ZERO
var _last_log := 0

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
		var deposit := get_nodes_in_group("stone_deposits")[0]
		placement._set_building_type("quarry")
		resources._amounts["wood"] = 20
		placement._try_place_quarry_at(deposit.global_position)
		var quarry := get_nodes_in_group("quarries")[0]
		quarry.assign_worker(miner)
		_last_pos = miner.global_position
	if _f >= 8 and _f % 60 == 0:
		var miners := get_nodes_in_group("miners")
		if miners.size() > 0:
			var m: Node = miners[0]
			var moved: float = m.global_position.distance_to(_last_pos)
			_last_pos = m.global_position
			print("f=", _f, " state=", m.state, " pos=", m.global_position, " moved60=", int(moved), " stone=", root.get_node("VillageResources").get_amount("stone"))
	if _f == 1500:
		quit()
		return true
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
