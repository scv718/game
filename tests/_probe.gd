extends SceneTree

func _process(_delta: float) -> bool:
	if _frame >= 8:
		var main: Node = root.get_node("Main")
		var world: Node = main.get_node("World")
		print("WORLD CHILDREN (trees):")
		for child in world.get_children():
			if String(child.name).begins_with("Tree") or String(child.name).begins_with("ForestTree"):
				var s: GDScript = child.get_script() if child.get_script() != null else null
				print("  ", child.name, " pos=", child.global_position, " script=", (s.resource_path if s != null else "NONE"), " in_interactable=", child.is_in_group("interactable"), " in_stone_dep=", child.is_in_group("stone_deposits"))
		print("interactable size=", get_nodes_in_group("interactable").size())
		print("stone_deposits size=", get_nodes_in_group("stone_deposits").size())
		quit()
		return true
	_frame += 1
	return false

var _frame := 0

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
