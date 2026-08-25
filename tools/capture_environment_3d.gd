extends SceneTree

## TASK-3D-VIS-001-3 Environment / Lighting Prototype DAY/NIGHT 스크린샷 캡처.
## world3d + camera_controller_3d + environment_3d(이번 태스크의 최종 환경 레이어)를
## 실제 렌더링해 DAY/NIGHT 스크린샷을 남긴다(완료조건 1·2).
##
## - 이전 캡처 도구(capture_resources_3d / capture_quaternius_preview)는 임시
##   라이트/환경을 스스로 구성했다. 이 도구부터는 VIS 소유 environment_3d scene을
##   사용해 "최종 라이팅 그대로"의 화면을 검증한다.
## - placeholder GroundVisual은 기본 흰 머티리얼이라 stylized 지형 톤과 다르므로,
##   이 도구가 임시 잔디 머티리얼만 입힌다. world scene 파일은 수정하지 않으며
##   실제 terrain/ground visual 교체는 VIS-001-5 소유다.
## - 마을 구성물은 catalog 키 조회로만 배치한다(Scene -> 파일 경로 직접 참조 없음).
##   배치는 건물/마을 조립 wiring(VIS-002)이 아니라 라이팅 판독용 최소 구성이다.
## - 캡처는 실제 렌더가 필요하므로 --headless 없이 실행한다(headless는 dummy
##   rasterizer라 get_texture가 null이다. 기존 캡처 도구와 동일한 실행 조건).
##
## Example:
## Godot --path . --script res://tools/capture_environment_3d.gd -- --zoom=2.0
## Godot --path . --script res://tools/capture_environment_3d.gd -- \
##   --day-output=res://test_results/environment_3d_day.png \
##   --night-output=res://test_results/environment_3d_night.png

## 캡처 도구의 임시 지면 톤. task3dvis0013_test 가독성 밴드 검증과 같은 값이다.
const GROUND_ALBEDO := Color(0.42, 0.62, 0.35)

var _frames := 0
var _day_saved := false
var _zoom := 2.0
var _day_output := "res://test_results/environment_3d_day.png"
var _night_output := "res://test_results/environment_3d_night.png"
var _world: Node3D = null
var _env: Node = null
var _cam_ctl: Node = null
var _catalog: GDScript = null
var _env_script: GDScript = null


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--day-output="):
			_day_output = arg.trim_prefix("--day-output=")
		elif arg.begins_with("--night-output="):
			_night_output = arg.trim_prefix("--night-output=")
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	_world = world_scene
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	cam_scene.name = "CamController"
	root.add_child(cam_scene)
	var env_scene: Node = (load("res://scenes/environment_3d.tscn") as PackedScene).instantiate()
	root.add_child(env_scene)
	_env = env_scene
	_cam_ctl = cam_scene
	_catalog = load("res://scripts/visual_asset_catalog_3d.gd")
	_env_script = load("res://scripts/environment_lighting_3d.gd")

	_dress_ground()
	_place_village()


## placeholder 지면에만 임시 잔디 톤을 입힌다(world scene 무수정).
func _dress_ground() -> void:
	var ground_visual: MeshInstance3D = _world.get_node_or_null("GroundVisual") as MeshInstance3D
	if ground_visual == null:
		push_error("GroundVisual not found; screenshot ground tone will be placeholder")
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_ALBEDO
	material.roughness = 1.0
	ground_visual.material_override = material


## 라이팅 판독용 최소 마을 구성. 결정적 배치로 반복 실행에서도 동일 화면.
## 항목: { key, pos, yaw(선택, deg), scale(선택, 균일 배율) }.
## Medieval Village 벽 모듈은 2m 그리드라 가옥 footprint를 4x4 모듈로 맞추고,
## 6x6 지붕은 0.58 배율(4.8m)로 처마 끝을 0.4m 걸치게 얹는다. 이 배치 조립
## 자체는 wiring 태스크(VIS-002) 소유이며, 여기서는 라이팅 판독용 최소 구성이다.
func _place_village() -> void:
	var layout := [
		# -- 중앙 가옥(바닥 4x4m + 벽 + 지붕) --
		{"key": "bld/floor_brick", "pos": Vector3(-1, 0, -2)},
		{"key": "bld/floor_brick", "pos": Vector3(1, 0, -2)},
		{"key": "bld/floor_brick", "pos": Vector3(-1, 0, 0)},
		{"key": "bld/floor_brick", "pos": Vector3(1, 0, 0)},
		{"key": "bld/wall_brick_straight", "pos": Vector3(-1, 0, -3)},
		{"key": "bld/wall_brick_straight", "pos": Vector3(1, 0, -3)},
		{"key": "bld/wall_brick_straight", "pos": Vector3(-2, 0, -2), "yaw": 90.0},
		{"key": "bld/wall_brick_straight", "pos": Vector3(-2, 0, 0), "yaw": 90.0},
		{"key": "bld/wall_brick_straight", "pos": Vector3(2, 0, -2), "yaw": 90.0},
		{"key": "bld/wall_brick_straight", "pos": Vector3(2, 0, 0), "yaw": 90.0},
		{"key": "bld/wall_brick_window_wide", "pos": Vector3(-1, 0, 1)},
		{"key": "bld/wall_brick_door_flat", "pos": Vector3(1, 0, 1)},
		# 6x6 라운드타일 지붕 실측: span 8.25x8.03, origin이 능선 부근(eave -0.78).
		# 0.58 배율 -> 4.8m 폭(4m 가옥에 처마 0.4m 걸침), eave가 벽 상단(3.12)에
		# 오도록 y = 3.12 + 0.78*0.58 = 3.57에 얹는다.
		{"key": "bld/roof_roundtiles_6x6", "pos": Vector3(0, 3.57, -1), "scale": 0.58},
		{"key": "bld/chimney", "pos": Vector3(1.3, 3.2, -1.3)},
		{"key": "prop/lantern_wall", "pos": Vector3(0.2, 1.6, 1.25)},
		# -- 서쪽 숲(Stylized Nature) --
		{"key": "tree/common_1", "pos": Vector3(-12, 0, -7)},
		{"key": "tree/common_1", "pos": Vector3(-9, 0, -11)},
		{"key": "tree/common_3", "pos": Vector3(-14, 0, -3)},
		{"key": "tree/common_3", "pos": Vector3(-8, 0, -6)},
		{"key": "tree/pine_1", "pos": Vector3(-11, 0, -13)},
		{"key": "tree/pine_1", "pos": Vector3(-15, 0, -9)},
		{"key": "tree/pine_2", "pos": Vector3(-7, 0, -14)},
		{"key": "veg/bush_common", "pos": Vector3(-10, 0, -9)},
		{"key": "veg/bush_common", "pos": Vector3(-6, 0, -9)},
		{"key": "veg/grass_common_tall", "pos": Vector3(-12, 0, -11)},
		{"key": "veg/grass_common_tall", "pos": Vector3(-5, 0, -12)},
		# -- 남동쪽 채석장 느낌 암반 --
		{"key": "rock/medium_1", "pos": Vector3(9, 0, 8)},
		{"key": "rock/medium_1", "pos": Vector3(12, 0, 10)},
		{"key": "rock/medium_3", "pos": Vector3(10.5, 0, 6.5)},
		{"key": "prop/torch_metal", "pos": Vector3(8, 0, 9.5)},
		# -- 마을 props / 시장 느낌 --
		{"key": "prop/barrel", "pos": Vector3(3.5, 0, -2.5)},
		{"key": "prop/barrel", "pos": Vector3(3.8, 0, -1.6)},
		{"key": "prop/crate_wooden", "pos": Vector3(4.5, 0, -2.2)},
		{"key": "prop/farmcrate_apple", "pos": Vector3(4.2, 0, -0.8)},
		{"key": "prop/stall_cart_empty", "pos": Vector3(7, 0, -6)},
		{"key": "prop/stall_empty", "pos": Vector3(9.5, 0, -6)},
		{"key": "prop/coin_pile", "pos": Vector3(8.3, 0, -5)},
		{"key": "tool/anvil", "pos": Vector3(6, 0, -2)},
		# -- 주민/용병 실루엣 --
		{"key": "human/male_base", "pos": Vector3(3, 0, 3)},
		{"key": "human/female_base", "pos": Vector3(4.2, 0, 3.6)},
		{"key": "outfit/male_ranger_full", "pos": Vector3(2, 0, 4.4)},
	]
	for item in layout:
		var node: Node3D = _catalog.instantiate_model(item["key"])
		if node == null:
			push_error("village model failed to instantiate: %s" % item["key"])
			continue
		node.position = WorldCoords3D.flatten(item["pos"])
		if item.has("yaw"):
			node.rotation.y = deg_to_rad(item["yaw"])
		if item.has("scale"):
			var s: float = item["scale"]
			node.scale = Vector3(s, s, s)
		_world.add_child(node)


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
		if _cam_ctl != null:
			_cam_ctl.day_zoom = _zoom
			_cam_ctl._zoom_target = _zoom
			# --script 실행은 zoom lerp가 실시간과 무관하므로 목표 size를 즉시
			# 적용한다(컨트롤러의 zoom 의미 계약은 그대로, 캡처 도구 관례).
			_cam_ctl.get_camera().size = _cam_ctl._ortho_size_for_zoom(_zoom)
			_cam_ctl.position = Vector3(0.0, 0.0, 0.0)
	if _frames == 50 and not _day_saved:
		_save(_day_output)
		_day_saved = true
		# NIGHT 기본 look으로 전환해 같은 구도를 다시 캡처한다.
		if _env != null:
			_env.apply_phase(_env_script.Phase.NIGHT)
	if _frames == 95:
		_save(_night_output)
		quit()
	return false
