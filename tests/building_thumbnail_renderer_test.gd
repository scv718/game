extends SceneTree

const RENDERER_SCRIPT := preload("res://scripts/building_thumbnail_renderer.gd")
const CITY := preload("res://assets/cuteskull-medieval-city/city16.fbx")
const ASSETS := [
	"House_1_1", "House_1_2", "House_2_1", "House_2_2", "House_2_3",
	"House_3_1", "House_3_2", "House_4_1", "House_4_2",
	"House_5_1", "House_5_2", "House_5_3", "House_6_1", "House_6_2",
	"House_7_1", "House_7_2", "House_7_3", "Church_1", "Church_2",
	"Castle_Wall", "Castle_Entrance", "Castle_Entrance__2",
	"Castle_Tower_1", "Castle_Tower_2", "Castle_Tower_3",
	"Castle_Tower_4", "Castle_Tower_5", "Castle_Tower_6",
	"Castle_Wall_Door", "Castle_Tower_Door",
	"Castle_Roof_1", "Castle_Roof_2",
]
var _failures := 0


func _init() -> void:
	var renderer := RENDERER_SCRIPT.new()
	renderer.configure(CITY)
	get_root().add_child(renderer)
	var all_assets := ASSETS.duplicate()
	var source_paths := {}
	var source_root := CITY.instantiate()
	var source_groups := {"Market": "Market", "Environment_001": "Environment_001", "People_empty": "People_empty"}
	for source_group in source_groups:
		var parent := source_root.get_node_or_null(
			"88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + source_group)
		if parent == null:
			continue
		for child in parent.get_children():
			if child is Node3D and _contains_mesh(child):
				all_assets.append(child.name)
				source_paths[child.name] = "88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/%s/%s" % [source_group, child.name]
	source_root.free()
	renderer.set_source_paths(source_paths)
	for asset_name in all_assets:
		var texture: Texture2D = renderer.get_thumbnail(asset_name)
		_check(texture != null, "%s thumbnail generated" % asset_name)
		if texture != null:
			_check(texture.get_width() == 256 and texture.get_height() == 256,
				"%s thumbnail is 256x256" % asset_name)
	for _i in 2:
		await process_frame
	_check(renderer.cached_thumbnail_count() == all_assets.size(),
		"all registered assets are cached (%d)" % all_assets.size())
	renderer.free()
	print("BUILDING_THUMBNAIL_RESULT=%s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)


func _contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return true
	for child in node.get_children():
		if _contains_mesh(child):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		print("FAIL: %s" % label)
