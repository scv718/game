extends SceneTree

var main: Node
var controller: Node
var camera: Camera3D
var frame := 0


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	main = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _aim(pivot: Vector3, size: float) -> void:
	controller.set_process(false)
	controller.position = Vector3(pivot.x, WorldCoords3D.GROUND_Y, pivot.z)
	camera.size = size


func _save(file_name: String) -> void:
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://test_results/" + file_name))


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 16:
		controller = get_first_node_in_group("camera_controller_3d")
		camera = controller.get_camera()
		_aim(Vector3(3, 0, 0), 70.0)
	if frame == 24:
		_save("terrain_default.png")
		_aim(Vector3(3, 0, -1), 43.0)
	if frame == 32:
		_save("terrain_village_core.png")
		_aim(Vector3(-7, 0, 0), 44.0)
	if frame == 40:
		_save("terrain_road_plaza.png")
		_aim(Vector3(-80, 0, 0), 72.0)
	if frame == 48:
		_save("terrain_portal_transition.png")
		_aim(Vector3(35, 0, 14), 47.0)
	if frame == 56:
		_save("terrain_farm_quarry.png")
		quit(0)
		return true
	return false
