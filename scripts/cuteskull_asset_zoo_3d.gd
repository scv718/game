extends Node3D
class_name CuteskullAssetZoo3D

## Audit-only viewer for the imported Cuteskull city16 FBX. This scene is
## intentionally independent from main_3d and never participates in gameplay.

const CITY := preload("res://assets/cuteskull-medieval-city/city16.fbx")
const ROOT_PATH := "88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/"
const PAGES := {
	1: ["Castle_Entrance", "Castle_Wall_Door", "Castle_Tower_3", "Church_1",
		"House_3_1", "House_4_1", "House_5_1", "House_7_1", "Market_2_1"],
	2: ["Castle_Wall", "Castle_Entrance", "Castle_Tower_1", "Castle_Tower_2",
		"Castle_Tower_4", "Castle_Tower_5", "Castle_Tower_6", "Castle_Tower_Door",
		"Castle_Roof_1", "Castle_Roof_2"],
	3: ["Environment_001/City_Ground", "Environment_001/Ground_1",
		"Environment_001/Ground_1_Alpha", "Environment_001/Ground_Bricks",
		"Environment_001/Water", "Environment_001/Stone_1",
		"Environment_001/Stone_2", "Environment_001/Stone_3",
		"Environment_001/Stone_4", "Environment_001/Tree_1",
		"Environment_001/Tree_4", "Environment_001/Grass_Blades_2"],
	4: ["Market/Bridge", "Market/Cart", "Market/Cart_1", "Market/Well",
		"Market/Wood_Fence_1", "Market/Market_1_1", "Market/Market_2_1",
		"Market/Barrel", "People/Farm_Tool", "People/Man_9_Farmer",
		"Environment_001/Wall"]
}

var page: int = 1
var _content: Node3D
var _city: Node3D
var _candidate_count := 0

func _ready() -> void:
	_city = CITY.instantiate()
	_content = Node3D.new()
	_content.name = "AssetCandidates"
	add_child(_content)
	_build_page()

func set_page(next_page: int) -> void:
	page = clampi(next_page, 1, 4)
	if is_instance_valid(_content):
		_build_page()

func _build_page() -> void:
	for child in _content.get_children():
		child.free()
	_candidate_count = 0
	var names: Array = PAGES.get(page, [])
	for i in names.size():
		var source_name: String = names[i]
		var display_name := source_name.get_file()
		var source := _city.get_node_or_null(ROOT_PATH + source_name) as Node3D
		if source == null:
			continue
		var model := source.duplicate() as Node3D
		model.name = display_name
		_normalize(model)
		model.basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))
		model.scale = Vector3.ONE * _scale_for(display_name, model)
		var col := i % 3
		var row := i / 3
		model.position = Vector3((col - 1) * 28.0, 0.0, (row - 1) * 23.0)
		_content.add_child(model)
		_add_label(model.position, display_name)
		_candidate_count += 1

func candidate_count() -> int:
	return _candidate_count

func _scale_for(source_name: String, model: Node3D) -> float:
	var extent := _model_extent(model)
	if extent <= 0.01:
		return 0.1
	# Keep every candidate legible in one audit tile while preserving silhouette.
	var target := 9.0
	if source_name in ["City_Ground", "Ground_1", "Ground_1_Alpha", "Water"]:
		target = 13.0
	if source_name.begins_with("Grass") or source_name == "Farm_Tool":
		target = 5.0
	return target / extent

func _model_extent(model: Node) -> float:
	var extent := 0.0
	for child in model.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var size := (child as MeshInstance3D).mesh.get_aabb().size
			extent = maxf(extent, maxf(size.x, maxf(size.y, size.z)))
		extent = maxf(extent, _model_extent(child))
	return extent

func _normalize(model: Node) -> void:
	for child in model.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var aabb := (child as MeshInstance3D).mesh.get_aabb()
			child.position = Vector3(-aabb.position.x - aabb.size.x * 0.5,
				-aabb.position.y - aabb.size.y * 0.5, -aabb.position.z)
			return

func _add_label(world_position: Vector3, text_value: String) -> void:
	var label := Label3D.new()
	label.name = "AssetLabel"
	label.text = text_value
	label.position = world_position + Vector3(0, 5.5, 0)
	label.font_size = 24
	label.fixed_size = false
	label.pixel_size = 0.03
	label.modulate = Color(1.0, 0.88, 0.55)
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_content.add_child(label)
