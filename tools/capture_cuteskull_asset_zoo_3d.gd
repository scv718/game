extends SceneTree

var zoo: Node
var frame := 0
var page := 1

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	zoo = (load("res://scenes/cuteskull_asset_zoo_3d.tscn") as PackedScene).instantiate()
	root.add_child(zoo)

func _save(name: String) -> void:
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_results/" + name))

func _process(_delta: float) -> bool:
	frame += 1
	if frame in [8, 16, 24, 32]:
		page = frame / 8
		zoo.set_page(page)
	if frame in [14, 22, 30, 38]:
		_save(["cuteskull_asset_zoo_buildings.png", "cuteskull_asset_zoo_fortification.png",
			"cuteskull_asset_zoo_ground_paths.png", "cuteskull_asset_zoo_nature_props.png"][page - 1])
	if frame == 40:
		quit(0)
		return true
	return false
