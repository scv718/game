extends SceneTree

const PIVOT := Vector3(-175.0, 0.0, 0.0)
const ORTHO_SIZE := 96.0
var _frames := 0
var _camera_controller: Node
var _camera: Camera3D


func _initialize() -> void:
	var world := (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	root.add_child(world)
	_camera_controller = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	root.add_child(_camera_controller)
	root.add_child((load("res://scenes/environment_3d.tscn") as PackedScene).instantiate())
	var village := (load("res://scenes/village_composition_3d.tscn") as PackedScene).instantiate()
	root.add_child(village)
	village.apply_ground_tone(world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _camera == null:
		_camera = _camera_controller.get_camera()
		if _camera == null:
			return false
		_camera_controller.set_process(false)
		_camera_controller.pitch_degrees = -66.0
		_camera_controller._apply_fixed_orientation()
		_camera_controller.position = PIVOT
		_camera.size = ORTHO_SIZE
		return false
	if _frames < 45:
		return false
	var path := ProjectSettings.globalize_path("res://test_results/portal_abyss_final.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("portal screenshot failed")
	else:
		print("CAPTURED " + path)
	quit()
	return true
