extends SceneTree

const CITY := preload("res://assets/cuteskull-medieval-city/city16.fbx")
const BUILDINGS := [
	"House_1_1", "House_1_2", "House_2_1", "House_2_2", "House_2_3",
	"House_3_1", "House_3_2", "House_4_1", "House_4_2",
	"House_5_1", "House_5_2", "House_5_3", "House_6_1", "House_6_2",
	"House_7_1", "House_7_2", "House_7_3", "Church_1", "Church_2",
]
const DEFENSE := [
	"Castle_Wall", "Castle_Entrance", "Castle_Entrance__2",
	"Castle_Tower_1", "Castle_Tower_2", "Castle_Tower_3",
	"Castle_Tower_4", "Castle_Tower_5", "Castle_Tower_6",
	"Castle_Wall_Door", "Castle_Tower_Door",
]
var _failures := 0

func _init() -> void:
	var source_root := CITY.instantiate()
	_check(BUILDINGS.size() == 19, "complete Cuteskull catalog has 19 entries")
	_check(DEFENSE.size() == 11, "defense catalog has 11 actual Cuteskull structures")
	for asset_name in BUILDINGS + DEFENSE:
		var source := source_root.get_node_or_null(
			"88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + asset_name) as Node3D
		_check(source != null, "%s source node exists" % asset_name)
		if source == null:
			continue
		var model := source.duplicate() as Node3D
		model.scale = Vector3.ONE * 0.17
		_normalize(model)
		model.basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
		_check(_mesh_count(model) > 0, "%s extracts as a renderable complete building" % asset_name)
		model.free()
	source_root.free()
	print("BUILDING_CATALOG_3D_RESULT=%s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)

func _normalize(model: Node) -> void:
	for child in model.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var aabb := (child as MeshInstance3D).mesh.get_aabb()
			child.position = Vector3(-aabb.position.x - aabb.size.x * 0.5,
				-aabb.position.y - aabb.size.y * 0.5, -aabb.position.z)
			return

func _mesh_count(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			total += 1
		total += _mesh_count(child)
	return total

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		print("FAIL: %s" % label)
