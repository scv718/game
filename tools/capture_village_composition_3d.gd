extends SceneTree

## TASK-3D-VIS-001-5 Visual Village Composition Prototype 스크린샷 캡처.
## world3d + camera_controller_3d + environment_3d + village_composition_3d를
## 실제 렌더링해 완료조건 3장(overview / zoom-in / NIGHT)을 남긴다.
##
## - 마을 구성/배치는 village_composition_3d scene이 소유하고, 이 도구는
##   카메라 구도만 잡는다(capture_character_prototype_3d 관례).
## - overview는 전체 구성(x[-35,30], z[-31,22])이 읽히는 광역 프레임,
##   zoom-in은 벌목꾼 작업 장면의 타이트한 프레임이다. 두 프레임 모두
##   gameplay zoom clamp와 무관하게 ortho size를 직접 설정한다(기존 캡처
##   도구의 "즉시 size 적용" 관례 — gameplay camera 정책 무수정).
## - NIGHT 컷은 overview와 동일 구도를 EnvironmentLighting3D NIGHT preset으로
##   재촬영해 낮/밤 분위기 차이를 직접 비교할 수 있게 한다.
## - 캡처는 실제 렌더가 필요하므로 --headless 없이 실행한다(headless는 dummy
##   rasterizer라 get_texture가 null이다. 기존 캡처 도구와 동일한 실행 조건).
##
## Example:
## Godot --path . --script res://tools/capture_village_composition_3d.gd

var _frames := 0
var _saved_overview := false
var _saved_zoom := false
var _village: Node3D = null
var _env: Node = null
var _cam_ctl: Node = null
var _env_script: GDScript = null

## 전체 구성이 읽히는 overview 프레임(마을 중심 살짝 서쪽).
const OVERVIEW_PIVOT := Vector3(-2.0, 0.0, -4.0)
const OVERVIEW_ORTHO_SIZE := 48.0
## 벌목꾼(stump station) 작업 관찰 프레임.
const WORKER_PIVOT := Vector3(-24.1, 0.0, 7.7)
const WORKER_ORTHO_SIZE := 6.5


func _initialize() -> void:
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
	var village_scene: Node = (load("res://scenes/village_composition_3d.tscn") as PackedScene).instantiate()
	village_scene.name = "Village"
	root.add_child(village_scene)
	_village = village_scene
	_village.apply_ground_tone(world_scene)


func _aim(pivot: Vector3, ortho_size: float) -> void:
	_cam_ctl.position = pivot
	# zoom lerp(_process)가 clamp 범위로 되돌리므로 캡처 동안만 정지시키고
	# 원하는 size를 직접 적용한다(gameplay camera 정책 무수정).
	_cam_ctl.set_process(false)
	_cam_ctl.get_camera().size = ortho_size


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
		_aim(OVERVIEW_PIVOT, OVERVIEW_ORTHO_SIZE)
	if _frames == 55 and not _saved_overview:
		_save("res://test_results/village_composition_overview.png")
		_saved_overview = true
		_aim(WORKER_PIVOT, WORKER_ORTHO_SIZE)
	if _frames == 110 and not _saved_zoom:
		_save("res://test_results/village_composition_worker_zoom.png")
		_saved_zoom = true
		# 같은 overview 구도를 그대로 NIGHT 기본 look으로 재촬영한다.
		_env.apply_phase(_env_script.Phase.NIGHT)
		_aim(OVERVIEW_PIVOT, OVERVIEW_ORTHO_SIZE)
	if _frames == 165:
		_save("res://test_results/village_composition_night.png")
		quit()
	return false
