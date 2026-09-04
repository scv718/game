extends Node3D

## Temporary visual inventory for the Loafbrr Castle Wall Kit.
## It instantiates every individual authored scene under the kit's scenes tree,
## excluding only aggregate/test/GridMap scenes that are not standalone entries.

const ASSET_ROOT := "res://assets/LoafbrrAssets/CastleWallKit/scenes"
const COLUMNS := 5
const CELL_SPACING := 24.0
const ITEMS_PER_PAGE := 30

var _entries: Array[String] = []
var _page_root: Node3D


func _ready() -> void:
	_entries = _discover_scene_paths(ASSET_ROOT)


func get_page_count() -> int:
	return maxi(1, ceili(float(_entries.size()) / ITEMS_PER_PAGE))


func get_entry_count() -> int:
	return _entries.size()


func build_page(page: int) -> void:
	if is_instance_valid(_page_root):
		_page_root.queue_free()
	_page_root = Node3D.new()
	_page_root.name = "AssetPage_%02d" % (page + 1)
	add_child(_page_root)
	var first := clampi(page * ITEMS_PER_PAGE, 0, _entries.size())
	var last := mini(first + ITEMS_PER_PAGE, _entries.size())
	for index in range(first, last):
		var scene_path := _entries[index]
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("Asset Zoo failed to load: %s" % scene_path)
			continue
		var item := packed.instantiate() as Node3D
		if item == null:
			push_error("Asset Zoo root is not Node3D: %s" % scene_path)
			continue
		var local_index := index - first
		var col := local_index % COLUMNS
		var row := local_index / COLUMNS
		item.name = "Asset_%03d_%s" % [index + 1, item.get_name()]
		item.position = Vector3(
			(float(col) - (COLUMNS - 1) * 0.5) * CELL_SPACING,
			0.0,
			(float(row) - 2.5) * CELL_SPACING)
		item.scale = Vector3.ONE * 0.82
		_page_root.add_child(item)
		_add_label(item, scene_path.get_file().get_basename())
	print("ASSET_ZOO_PAGE=%d/%d entries=%d range=%d..%d" % [
		page + 1, get_page_count(), _entries.size(), first + 1, last])


func _add_label(parent: Node3D, text: String) -> void:
	var label := Label3D.new()
	label.name = "AssetFilenameLabel"
	label.text = text
	label.position = Vector3(0.0, 7.0, 0.0)
	label.font_size = 10
	label.pixel_size = 0.002
	label.fixed_size = true
	label.no_depth_test = true
	label.outline_size = 2
	label.modulate = Color(1.0, 0.92, 0.68)
	label.outline_modulate = Color(0.04, 0.05, 0.06, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)


func _discover_scene_paths(directory: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		push_error("Asset Zoo directory missing: %s" % directory)
		return paths
	for entry in dir.get_files():
		if not entry.ends_with(".tscn"):
			continue
		var path := directory.path_join(entry)
		if path.contains("/GridMaps/") or path.ends_with("/GridMapTest.tscn") \
				or path.ends_with("/MatTest.tscn") \
				or path.ends_with("/CastleWallsKit.tscn"):
			continue
		paths.append(path)
	for subdir in dir.get_directories():
		paths.append_array(_discover_scene_paths(directory.path_join(subdir)))
	paths.sort()
	return paths
