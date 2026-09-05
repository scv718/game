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
	if frame == 12:
		controller = get_first_node_in_group("camera_controller_3d")
		camera = controller.get_camera()
		_aim(Vector3(3, 0, 0), 70.0)
	if frame == 18:
		_save("village_macro_default.png")
		_aim(Vector3(-18, 0, 0), 46.0)
	if frame == 24:
		_save("village_macro_gate_axis.png")
		_aim(Vector3(23, 0, -3), 38.0)
	if frame == 30:
		_save("village_macro_keep_water.png")
		_aim(Vector3(-32, 0, 0), 122.0)
	if frame == 36:
		_save("village_macro_overview.png")
		quit(0)
		return true
	return false
