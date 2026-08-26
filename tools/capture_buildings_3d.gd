extends SceneTree

## TASK-3D-BLD-001-4 Building HUMAN_CHECK 스크린샷 캡처(3D판).
## tools/capture_resources_3d.gd와 동일한 최소 구조의 건물 전용판이다.
## 실제 지형/조명/에셋은 VIS 도메인 소유이므로 이 도구는 캡처용 임시
## 라이트/환경만 스스로 구성하고 world scene은 수정하지 않는다.
##
## HUMAN_CHECK 판정 자료(큐 TASK-3D-BLD-001-4):
##   - Top-down에서 건물 형태가 즉시 읽히는지.
##   - 지붕 때문에 클릭/유닛 가독성이 지나치게 나빠지지 않는지.
##   - 건물 footprint와 실제 model scale이 자연스러운지.
##
## Example:
## Godot --path . --script res://tools/capture_buildings_3d.gd -- --output=res://test_results/buildings_3d_preview.png
## Godot --path . --script res://tools/capture_buildings_3d.gd -- --zoom=0.5 --output=res://test_results/buildings_3d_preview_far.png

var _frames := 0
var _output := "res://test_results/buildings_3d_preview.png"
var _zoom := 1.0
var _world: Node3D = null


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	root.add_child(world_scene)
	_world = world_scene
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	cam_scene.name = "CamController"
	root.add_child(cam_scene)

	# 캡처 전용 임시 조명/world environment(VIS 태스크가 최종 소유).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.2
	root.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.8)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	_place_village()


## 핵심 건물 5종(기존 world.tscn 배치) + Wall 라인 + Gate corridor 1개.
func _place_village() -> void:
	var layout := {
		"keep": Vector2(0, -148),
		"tavern": Vector2(-126, -48),
		"inn": Vector2(126, -48),
		"grocery": Vector2(-122, 116),
		"equipment": Vector2(122, 116),
	}
	var building_scene: PackedScene = load("res://scenes/core_building_3d.tscn")
	for core_type in layout:
		var building: StaticBody3D = building_scene.instantiate()
		building.core_type = core_type
		building.set_logical_position(layout[core_type])
		_world.add_child(building)
	var wall_scene: PackedScene = load("res://scenes/wall_3d.tscn")
	for pos in [Vector3(20, 0, 20), Vector3(22, 0, 20), Vector3(24, 0, 20)]:
		var wall: StaticBody3D = wall_scene.instantiate()
		wall.position = pos
		_world.add_child(wall)
	var gate: StaticBody3D = (load("res://scenes/gate_3d.tscn") as PackedScene).instantiate()
	gate.position = Vector3(0, 0, -80)
	gate.setup("north")
	_world.add_child(gate)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		var cam_ctl := root.get_node_or_null("CamController")
		if cam_ctl != null:
			cam_ctl.day_zoom = _zoom
			cam_ctl._zoom_target = _zoom
			# --script 실행은 delta가 실시간과 무관해 zoom lerp가 수렴하지 않으므로
			# 목표 size를 즉시 적용한다(컨트롤러의 zoom 의미 계약은 그대로).
			cam_ctl.get_camera().size = cam_ctl._ortho_size_for_zoom(_zoom)
			cam_ctl.position = Vector3(0.0, 0.0, 0.0)
	if _frames == 45:
		var absolute := ProjectSettings.globalize_path(_output)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var image := root.get_texture().get_image()
		var error := image.save_png(absolute)
		if error != OK:
			push_error("screenshot save failed: %d" % error)
			quit(1)
			return false
		print("CAPTURED " + absolute + " size=" + str(image.get_size()))
		quit()
	return false
