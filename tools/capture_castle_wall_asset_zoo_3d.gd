extends SceneTree

## Runtime screenshots for the temporary Castle Wall Kit asset inventory.

const ZOO_SCENE := "res://scenes/castle_wall_asset_zoo_3d.tscn"
const CAMERA_TARGET := Vector3(0, 0, 0)
const CAMERA_POSITION := Vector3(0, 72, 58)
const ORTHO_SIZE := 148.0
const SETTLE_FRAMES := 18

var _zoo: Node
var _camera: Camera3D
var _frame := 0
var _page := 0


func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	_zoo = (load(ZOO_SCENE) as PackedScene).instantiate()
	root.add_child(_zoo)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#26313a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b7c7d1")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	_zoo.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -25, 0)
	light.light_energy = 1.35
	light.shadow_enabled = true
	_zoo.add_child(light)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(138, 90)
	ground.mesh = ground_mesh
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color("#52616a")
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	ground.position.y = -0.05
	_zoo.add_child(ground)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ORTHO_SIZE
	_camera.position = CAMERA_POSITION
	_zoo.add_child(_camera)
	_camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET)
	_camera.current = true


func _save(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var image := root.get_texture().get_image()
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Asset Zoo screenshot failed: %s" % path)
		quit(1)
		return
	print("CAPTURED %s size=%s" % [absolute, str(image.get_size())])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		print("ASSET_ZOO_DISCOVERED=%d pages=%d" % [
			_zoo.get_entry_count(), _zoo.get_page_count()])
	if _frame == SETTLE_FRAMES:
		_zoo.build_page(_page)
	if _frame == SETTLE_FRAMES + 12:
		_save("res://test_results/castle_wall_asset_zoo_01.png")
		_page = 1
		_zoo.build_page(_page)
	if _frame == SETTLE_FRAMES + 24:
		_save("res://test_results/castle_wall_asset_zoo_02.png")
		_page = 2
		_zoo.build_page(_page)
	if _frame == SETTLE_FRAMES + 36:
		_save("res://test_results/castle_wall_asset_zoo_03.png")
		_page = 3
		_zoo.build_page(_page)
	if _frame == SETTLE_FRAMES + 48:
		_save("res://test_results/castle_wall_asset_zoo_04.png")
		quit(0)
		return true
	return false
