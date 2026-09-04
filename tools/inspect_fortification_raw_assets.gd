extends SceneTree

const ASSETS := [
	"res://assets/LoafbrrAssets/CastleWallKit/gltf/CastleWallsKit.gltf",
	"res://assets/third_party/hakanbacon/towers-n-castles-basics/TowerPackDemo.glb",
]

func _init() -> void:
	for path in ASSETS:
		print("=== ASSET ", path, " ===")
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("LOAD_FAILED " + path)
			continue
		var root := packed.instantiate()
		print("root=", root.name, " type=", root.get_class())
		_dump(root, 0)
		root.free()
	quit()

func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var line := indent + node.name + " [" + node.get_class() + "]"
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh:
			line += " mesh=" + mesh.get_class() + " surfaces=" + str(mesh.get_surface_count()) + " aabb=" + str(mesh.get_aabb())
	if node is Node3D:
		line += " pos=" + str((node as Node3D).position)
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)
