extends SceneTree

func _init() -> void:
	var packed := load("res://assets/cuteskull-medieval-city/city16.fbx") as PackedScene
	if packed == null:
		push_error("Cuteskull FBX failed to load")
		quit(1)
		return
	var root_node := packed.instantiate()
	_dump(root_node, 0)
	root_node.free()
	quit()

func _dump(node: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + node.name + " [" + node.get_class() + "]"
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh:
			line += " aabb=" + str(mesh.get_aabb()) + " surfaces=" + str(mesh.get_surface_count())
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)
