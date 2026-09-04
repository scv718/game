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

func _save(name: String) -> void:
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://test_results/" + name))

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 16:
		controller = get_first_node_in_group("camera_controller_3d")
		camera = controller.get_camera()
		_aim(Vector3(2, 0, 2), 58.0)
	if frame == 24:
		_save("real_village_default.png")
		_aim(Vector3(-24, 0, 2), 82.0)
	if frame == 32:
		_save("real_village_overview.png")
		_aim(Vector3(5, 0, -2), 28.0)
	if frame == 40:
		_save("real_village_keep_plaza.png")
		_aim(Vector3(-30, 0, 0), 34.0)
	if frame == 48:
		_save("real_village_gate.png")
		_aim(Vector3(3, 0, -20), 28.0)
	if frame == 56:
		_save("real_village_residential.png")
		_aim(Vector3(23, 0, 8), 32.0)
	if frame == 64:
		_save("real_village_production.png")
		quit(0)
		return true
	return false
