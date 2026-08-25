extends SceneTree

## TASK-3D-VIS-001-4 Character / Outfit / Animation Prototype 스크린샷 캡처.
## world3d + camera_controller_3d + environment_3d + character_prototype_3d를
## 실제 렌더링해 캐릭터 라인업의 DAY/NIGHT 스크린샷을 남긴다(완료조건 1의
## 화면 증거. headless는 dummy rasterizer라 캡처 불가 — 기존 캡처 도구와 동일한
## 실행 조건).
##
## - 리그 4종(base male / worker peasant male+axe / worker peasant female /
##   mercenary ranger+sword)이 각자 initial_action(idle/work/walk/combat)을
##   재생한 상태 그대로 캡처한다. 배치/액션은 scene 파일이 소유하고 이 도구는
##   카메라/지면 톤만 구성한다.
## - 캐릭터 판독을 위해 orthographic size를 controller zoom clamp와 무관하게
##   직접 설정한다(capture_environment_3d의 "즉시 size 적용" 관례 확장).
##   gameplay camera 정책 자체는 수정하지 않는다.
##
## Example:
## Godot --path . --script res://tools/capture_character_prototype_3d.gd

## 캡처 도구의 임시 지면 톤(capture_environment_3d와 같은 값).
const GROUND_ALBEDO := Color(0.42, 0.62, 0.35)

## 리그 4종의 중심(WorkerPeasantMale ~ MercenaryRanger 라인업).
const LINEUP_CENTER := Vector3(2.7, 0.9, 0.0)
## 캐릭터 신장(~1.8 unit)이 화면 세로의 절반 정도가 되는 타이트한 시야.
const CLOSEUP_ORTHO_SIZE := 4.5

var _frames := 0
var _day_saved := false
var _day_output := "res://test_results/character_prototype_day.png"
var _night_output := "res://test_results/character_prototype_night.png"
var _env: Node = null
var _cam_ctl: Node = null
var _env_script: GDScript = null


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--day-output="):
			_day_output = arg.trim_prefix("--day-output=")
		elif arg.begins_with("--night-output="):
			_night_output = arg.trim_prefix("--night-output=")
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	cam_scene.name = "CamController"
	root.add_child(cam_scene)
	_cam_ctl = cam_scene
	var env_scene: Node = (load("res://scenes/environment_3d.tscn") as PackedScene).instantiate()
	root.add_child(env_scene)
	_env = env_scene
	_env_script = load("res://scripts/environment_lighting_3d.gd")
	var proto_scene: Node = (load("res://scenes/character_prototype_3d.tscn") as PackedScene).instantiate()
	root.add_child(proto_scene)

	_dress_ground(world_scene)


## placeholder 지면에만 임시 잔디 톤(world scene 무수정).
func _dress_ground(world: Node3D) -> void:
	var ground_visual: MeshInstance3D = world.get_node_or_null("GroundVisual") as MeshInstance3D
	if ground_visual == null:
		push_error("GroundVisual not found; screenshot ground tone will be placeholder")
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_ALBEDO
	material.roughness = 1.0
	ground_visual.material_override = material


func _aim_closeup() -> void:
	_cam_ctl.position = LINEUP_CENTER
	# zoom lerp(_process)가 ortho size를 clamp 범위로 되돌리므로 캡처 동안만
	# 정지시키고 타이트한 size를 직접 적용한다(gameplay camera 정책 무수정).
	_cam_ctl.set_process(false)
	var camera: Camera3D = _cam_ctl.get_camera()
	camera.size = CLOSEUP_ORTHO_SIZE


func _save(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var image := root.get_texture().get_image()
	var error := image.save_png(absolute)
	if error != OK:
		push_error("screenshot save failed: %d" % error)
		quit(1)
		return
	print("CAPTURED " + absolute + " size=" + str(image.get_size()))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_aim_closeup()
	# initial_action들이 최소 1사이클 진입한 뒤 캡처한다.
	if _frames == 90 and not _day_saved:
		_save(_day_output)
		_day_saved = true
		if _env != null:
			_env.apply_phase(_env_script.Phase.NIGHT)
	if _frames == 130:
		_save(_night_output)
		quit()
	return false
