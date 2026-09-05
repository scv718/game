extends SceneTree

const WORLD_SCENE := "res://scenes/world3d.tscn"
const CAMERA_SCENE := "res://scenes/camera_controller_3d.tscn"
const ENV_SCENE := "res://scenes/environment_3d.tscn"
const VILLAGE_SCENE := "res://scenes/village_composition_3d.tscn"
const PIVOT := Vector3(-2.0, 0.0, -4.0)
const ORTHO_SIZE := 48.0
const CANDIDATES := [
	{"name": "before", "pitch": -74.0},
	{"name": "candidate_a", "pitch": -70.0},
	{"name": "candidate_b", "pitch": -66.0},
	{"name": "candidate_c", "pitch": -62.0},
	{"name": "final", "pitch": -66.0},
]

var _camera_controller: Node
var _camera: Camera3D
var _index := 0
var _wait := 0


func _initialize() -> void:
	var world := (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(world)
	_camera_controller = (load(CAMERA_SCENE) as PackedScene).instantiate()
	root.add_child(_camera_controller)
	root.add_child((load(ENV_SCENE) as PackedScene).instantiate())
	var village := (load(VILLAGE_SCENE) as PackedScene).instantiate()
	root.add_child(village)
	village.apply_ground_tone(world)


func _apply_candidate() -> void:
	var candidate: Dictionary = CANDIDATES[_index]
	_camera_controller.pitch_degrees = candidate["pitch"]
	_camera_controller._apply_fixed_orientation()
	_camera_controller.position = PIVOT
	_camera.size = ORTHO_SIZE
	_wait = 0


func _save_current() -> void:
	var name: String = CANDIDATES[_index]["name"]
	var path := ProjectSettings.globalize_path("res://test_results/camera_readability_%s.png" % name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("camera readability screenshot failed: %s" % name)
	else:
		print("CAPTURED %s pitch=%s" % [path, str(CANDIDATES[_index]["pitch"])])


func _process(_delta: float) -> bool:
	if _camera == null:
		_camera = _camera_controller.get_camera()
		if _camera == null:
			return false
		_camera_controller.set_process(false)
		_apply_candidate()
		return false
	_wait += 1
	if _wait < 35:
		return false
	_save_current()
	_index += 1
	if _index >= CANDIDATES.size():
		quit()
		return true
	_apply_candidate()
	return false
