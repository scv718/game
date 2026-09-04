extends SceneTree

## Runtime-only acceptance captures for the corrected modular fortification.

const MAIN_SCENE := "res://scenes/main_3d.tscn"
const SETTLE_FRAMES := 14
var _main: Node
var _controller: Node
var _camera: Camera3D
var _frame := 0


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)


func _aim(pivot: Vector3, size: float) -> void:
	_controller.set_process(false)
	_controller.position = Vector3(pivot.x, WorldCoords3D.GROUND_Y, pivot.z)
	_camera.size = size


func _save(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := root.get_texture().get_image().save_png(absolute)
	if error != OK:
		push_error("fortification screenshot failed: %s" % path)
		quit(1)
		return
	print("CAPTURED %s" % absolute)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == SETTLE_FRAMES:
		_controller = get_first_node_in_group("camera_controller_3d")
		_camera = _controller.get_camera() if _controller else null
		if _camera == null:
			push_error("camera controller or Camera3D missing")
			quit(1)
			return true
		_aim(Vector3(10, 0, 4), 56.0)
	if _frame == SETTLE_FRAMES + 8:
		_save("res://test_results/fortification_corrected_default.png")
		_aim(Vector3(-5, 0, 4), 64.0)
	if _frame == SETTLE_FRAMES + 16:
		_save("res://test_results/fortification_corrected_overview.png")
		_aim(Vector3(-28, 0, 0), 26.0)
	if _frame == SETTLE_FRAMES + 24:
		_save("res://test_results/fortification_corrected_gate.png")
		quit(0)
		return true
	return false
