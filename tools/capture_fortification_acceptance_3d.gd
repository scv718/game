extends SceneTree

## Runtime-only fortification acceptance captures.
## This deliberately boots the production main scene without staging gameplay input.

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const DEFAULT_PIVOT := Vector3(10, 0, 4)
const DEFAULT_SIZE := 56.0
const GATE_PIVOT := Vector3(-30, 0, 0)
const GATE_SIZE := 28.0
const SETTLE_FRAMES := 12

var _main: Node
var _camera: Camera3D
var _controller: Node
var _frame := 0
var _shot := 0


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_main)


func _aim(pivot: Vector3, size: float) -> void:
	_controller.set_process(false)
	_controller.position = Vector3(pivot.x, WorldCoords3D.GROUND_Y, pivot.z)
	_camera.size = size


func _save(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var image := root.get_texture().get_image()
	var error := image.save_png(absolute)
	if error != OK:
		push_error("screenshot save failed: %s" % path)
		quit(1)
		return
	print("CAPTURED %s size=%s" % [absolute, str(image.get_size())])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == SETTLE_FRAMES:
		_controller = get_first_node_in_group("camera_controller_3d")
		_camera = _controller.get_camera() if _controller else null
		if _camera == null:
			push_error("camera controller or Camera3D missing")
			quit(1)
			return true
		_aim(DEFAULT_PIVOT, DEFAULT_SIZE)
		return false
	if _frame == SETTLE_FRAMES + 8:
		_save("res://test_results/fortification_default_zoom.png")
		_save("res://test_results/fortification_overview.png")
		_aim(GATE_PIVOT, GATE_SIZE)
		return false
	if _frame == SETTLE_FRAMES + 16:
		_save("res://test_results/fortification_gate_close.png")
		quit(0)
		return true
	return false
