extends SceneTree

var _f := 0
var _prev_state := -1
var _gather_count := 0
var _last_wood := -1

func _process(_delta: float) -> bool:
	_f += 1
	if _f == 8:
		var main: Node = root.get_node("Main")
		var world: Node = main.get_node("World")
		var ly: Node = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate()
		ly.name = "Lumberyard1"
		ly.position = Vector2(300, 260)
		world.add_child(ly)
		var lj: Node = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
		world.add_child(lj)
		ly.assign_worker(lj)
		var nav_map: RID = world.get_world_2d().get_navigation_map()
		# DepositPoint global
		var dp: Node2D = ly.get_node_or_null("DepositPoint")
		var dpg: Vector2 = dp.global_position
		print("DepositPoint=", dpg)
		# path from each grove tree back to deposit
		for t in get_nodes_in_group("interactable"):
			if String(t.name).begins_with("Tree"):
				var p: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, t.global_position, dpg, true)
				print("  ", t.name, " at ", t.global_position, " -> deposit path nodes=", p.size())
	if _f >= 8:
		var ljs := get_nodes_in_group("lumberjacks")
		if ljs.size() > 0:
			var lj: Node = ljs[0]
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			if wood > _last_wood:
				print("  WOOD++ -> ", wood, " at f=", _f, " state=", lj.state)
				_last_wood = wood
			if lj.state != _prev_state:
				print("  f=", _f, " state->", lj.state, " target=", (lj.target_tree.name if lj.target_tree != null else "none"), " carried=", lj.carried_amount, " pos=", lj.global_position)
				_prev_state = lj.state
	if _f == 3000:
		var ljs := get_nodes_in_group("lumberjacks")
		var lj: Node = ljs[0] if ljs.size() > 0 else null
		if lj != null:
			print("FINAL state=", lj.state, " carried=", lj.carried_amount, " wood=", root.get_node("VillageResources").get_amount("wood"), " pos=", lj.global_position)
		quit()
		return true
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
