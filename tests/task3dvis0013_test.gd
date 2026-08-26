extends SceneTree

## TASK-3D-VIS-001-3 Environment / Lighting Prototype 회귀 테스트.
## 기존 tests를 고치지 않는 신규 task3d* 계열 파일(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. STRUCTURE: environment_3d scene이 WorldEnvironment + DirectionalLight3D를
##      소유하고 ambient/background가 preset 기준으로 설정된다.
##   2. POSTFX_BUDGET: glow/fog/volumetric_fog/ssao/ssil/sdfgi/adjustment off,
##      LINEAR tonemap(과도한 bloom/fog/post-processing 금지의 코드화).
##   3. PHASE_SWITCH: DAY/NIGHT 프리셋 전환이 GameTime.phase_changed 구독으로
##      동작하고, DAY 복귀 시 원본 look이 정확히 복원된다.
##   4. READABILITY: preset 수치가 ground 반사휘도 밴드 안에 들어오는지 수치 검증
##      (DAY 과다 노출/역광 없음, NIGHT는 위험 분위기지만 유닛/길이 읽힘).
##   5. SHADOW_CONFIG: 그림자 상시 on + ortho 카메라 대응 단일 분할 + overview
##      커버 거리.
##   6. INTEGRATION: World Root + Camera3D + Environment3D 공존 smoke,
##      미등록 phase 무시, free 후 signal 잔여 연결 없음.

enum Phase {
	SETUP, STRUCTURE, POSTFX, SWITCH_DAY_BASE, SWITCH_NIGHT, SWITCH_RESTORE,
	READABILITY, SHADOW_CFG, INTEGRATION, CLEANUP, DONE,
}

const GODOT_EPS := 0.0001

## 가독성 수치 검증용 stylized 잔디 ground albedo(캡처 도구 임시 지면 머티리얼과
## 같은 톤). 실제 terrain visual은 VIS-001-5 소유이며, 이 상수는 lighting preset이
## "ground가 캐릭터/건물을 묻히는" 극단값이 아님을 고정하는 프록시다.
const GROUND_ALBEDO := Color(0.42, 0.62, 0.35)

## ground 반사휘도 밴드(Rec.709 휘도, flat ground NdotL 가정).
## DAY: 밝고 생활감 있는 마을 feel(과다 노출로 하얗게 묻히지 않게 상한).
const DAY_GROUND_LUM_RANGE := Vector2(0.45, 0.95)
## NIGHT: 위험 분위기(어둠)지만 유닛/길 판독 하한을 유지.
const NIGHT_GROUND_LUM_RANGE := Vector2(0.06, 0.30)
const NIGHT_MIDGRAY_UNIT_LUM_MIN := 0.10
const NIGHT_TO_DAY_LUM_MAX_RATIO := 0.5

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _cam_ctl: Node = null
var _env: Node = null
var _catalog_script: GDScript = null
var _game_time: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	if _env != null and is_instance_valid(_env):
		_env.free()
	print("TASK3DVIS0013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= GODOT_EPS


func _c_near(a: Color, b: Color) -> bool:
	return _near(a.r, b.r) and _near(a.g, b.g) and _near(a.b, b.b) and _near(a.a, b.a)


func _v3_near(a: Vector3, b: Vector3) -> bool:
	return _near(a.x, b.x) and _near(a.y, b.y) and _near(a.z, b.z)


func _preset(phase_key: int) -> Dictionary:
	return _catalog_script.PRESETS[phase_key]


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.POSTFX:
			_postfx()
		Phase.SWITCH_DAY_BASE:
			_switch_day_base()
		Phase.SWITCH_NIGHT:
			_switch_night()
		Phase.SWITCH_RESTORE:
			_switch_restore()
		Phase.READABILITY:
			_readability()
		Phase.SHADOW_CFG:
			_shadow_cfg()
		Phase.INTEGRATION:
			_integration()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DVIS0013_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	cam_scene.name = "CamController"
	root.add_child(cam_scene)
	var env_scene: Node = (load("res://scenes/environment_3d.tscn") as PackedScene).instantiate()
	env_scene.name = "EnvRoot"
	root.add_child(env_scene)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_cam_ctl = root.get_node_or_null("CamController")
	_env = root.get_node_or_null("EnvRoot")
	_game_time = root.get_node_or_null("GameTime")
	_catalog_script = load("res://scripts/environment_lighting_3d.gd")
	_check(_world != null, "3D world root loads")
	_check(_cam_ctl != null, "camera controller loads")
	_check(_env != null, "environment/lighting scene loads")
	_check(_game_time != null, "GameTime autoload is present")
	_check(_catalog_script != null, "environment script loads")
	if _env == null or _game_time == null or _catalog_script == null:
		_finish()
		return
	_check(_env.is_in_group("environment_3d"),
		"environment joins dedicated environment_3d group")
	_enter(Phase.STRUCTURE)


## -- STRUCTURE --
func _structure() -> void:
	var world_env: WorldEnvironment = _env.get_world_environment()
	_check(world_env != null and world_env is WorldEnvironment,
		"environment owns a WorldEnvironment child")
	var env_res: Environment = _env.get_environment()
	_check(env_res != null, "WorldEnvironment carries an Environment resource")
	var sun: DirectionalLight3D = _env.get_sun_light()
	_check(sun != null and sun is DirectionalLight3D,
		"environment owns a DirectionalLight3D sun/moon light")
	_check(env_res.background_mode == Environment.BG_COLOR,
		"background uses cheap solid color (no sky/post pipeline cost)")
	_check(env_res.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR,
		"ambient is directly color-controlled for readability tuning")
	_check(env_res.ambient_light_energy > 0.0,
		"ambient contributes base readability energy")
	_check(env_res.ambient_light_color.is_equal_approx(
			_preset(_catalog_script.Phase.DAY)["ambient_color"]),
		"_ready applied the current phase look immediately (DAY default)")
	_enter(Phase.POSTFX)


## -- POSTFX_BUDGET --
func _postfx() -> void:
	var env_res: Environment = _env.get_environment()
	_check(not env_res.glow_enabled, "glow/bloom is disabled (post-processing budget)")
	_check(not env_res.fog_enabled, "depth fog is disabled")
	_check(not env_res.volumetric_fog_enabled, "volumetric fog is disabled")
	_check(not env_res.ssao_enabled, "SSAO is disabled")
	_check(not env_res.ssil_enabled, "SSIL is disabled")
	_check(not env_res.sdfgi_enabled, "SDFGI is disabled")
	_check(not env_res.adjustment_enabled, "color adjustment stage is disabled")
	_check(env_res.tonemap_mode == Environment.TONE_MAPPER_LINEAR,
		"LINEAR tonemap preserves the stylized low-poly palette")
	_enter(Phase.SWITCH_DAY_BASE)


## -- SWITCH_DAY_BASE: 새 GameTime은 DAY에서 시작한다 --
func _switch_day_base() -> void:
	var day: Dictionary = _preset(_catalog_script.Phase.DAY)
	var sun: DirectionalLight3D = _env.get_sun_light()
	var env_res: Environment = _env.get_environment()
	_check(_game_time.get_phase() == _game_time.Phase.DAY,
		"fresh run starts in DAY phase")
	_check(_near(sun.light_energy, day["sun_energy"]),
		"DAY sun energy matches the recorded default look")
	_check(_c_near(sun.light_color, day["sun_color"]), "DAY sun color matches")
	_check(_v3_near(sun.rotation_degrees, day["sun_rotation_degrees"]),
		"DAY sun direction matches the recorded oblique key-light angle")
	_check(_c_near(env_res.background_color, day["background_color"]),
		"DAY background matches the bright village backdrop")
	var connected := false
	for connection in _game_time.phase_changed.get_connections():
		if connection["callable"].get_object() == _env:
			connected = true
	_check(connected,
		"environment subscribes GameTime.phase_changed (same policy contract as camera)")
	_env._on_phase_changed(_catalog_script.Phase.DAY, _game_time.get_day_number())
	_check(_near(sun.light_energy, day["sun_energy"]),
		"re-applying current phase is idempotent")
	_enter(Phase.SWITCH_NIGHT)


## -- SWITCH_NIGHT --
func _switch_night() -> void:
	var night: Dictionary = _preset(_catalog_script.Phase.NIGHT)
	var day_energy: float = _preset(_catalog_script.Phase.DAY)["sun_energy"]
	var day_bg: Color = _preset(_catalog_script.Phase.DAY)["background_color"]
	var sun: DirectionalLight3D = _env.get_sun_light()
	var env_res: Environment = _env.get_environment()

	_env.apply_phase(_catalog_script.Phase.NIGHT)
	_check(sun.light_energy < day_energy * 0.5,
		"NIGHT drops the key light to moonlight level (%.2f < %.2f)"
			% [sun.light_energy, day_energy * 0.5])
	_check(sun.light_color.b > sun.light_color.r,
		"NIGHT key light shifts cool blue")
	var day_sun: Color = _preset(_catalog_script.Phase.DAY)["sun_color"]
	_check(day_sun.r >= day_sun.b, "DAY key light stays warm/neutral")
	_check(not _c_near(env_res.ambient_light_color, _preset(_catalog_script.Phase.DAY)["ambient_color"]),
		"NIGHT ambient tint changes with the phase")
	_check(not _c_near(env_res.background_color, day_bg),
		"NIGHT background darkens with the phase")
	_check(sun.shadow_enabled, "shadows stay enabled at NIGHT (silhouette readability)")

	# 알 수 없는 phase 값은 현재 look을 유지한다(기본 look 훼손 방지 계약).
	_env.apply_phase(-999)
	_check(_near(sun.light_energy, night["sun_energy"]),
		"unknown phase value is ignored without mutating the look")
	_enter(Phase.SWITCH_RESTORE)


## -- SWITCH_RESTORE --
func _switch_restore() -> void:
	var day: Dictionary = _preset(_catalog_script.Phase.DAY)
	_env.apply_phase(_catalog_script.Phase.DAY)
	var sun: DirectionalLight3D = _env.get_sun_light()
	var env_res: Environment = _env.get_environment()
	_check(_near(sun.light_energy, day["sun_energy"]), "DAY restore brings back sun energy")
	_check(_c_near(sun.light_color, day["sun_color"]), "DAY restore brings back sun color")
	_check(_v3_near(sun.rotation_degrees, day["sun_rotation_degrees"]),
		"DAY restore brings back sun direction")
	_check(_c_near(env_res.ambient_light_color, day["ambient_color"]),
		"DAY restore brings back ambient tint")
	_check(_near(env_res.ambient_light_energy, day["ambient_energy"]),
		"DAY restore brings back ambient energy")
	_check(_c_near(env_res.background_color, day["background_color"]),
		"DAY restore brings back background")
	_check(not _env.is_night(), "is_night reports false while GameTime is in DAY")
	_enter(Phase.READABILITY)


## -- READABILITY: preset 수치가 ground 반사휘도 밴드에 들어오는지 --
func _ground_luminance(albedo: Color, preset: Dictionary) -> float:
	var sun_rot: Vector3 = preset["sun_rotation_degrees"]
	var ndotl := cos(deg_to_rad(absf(sun_rot.x)))
	var r: float = albedo.r * (preset["ambient_color"].r * preset["ambient_energy"]
		+ preset["sun_color"].r * preset["sun_energy"] * ndotl)
	var g: float = albedo.g * (preset["ambient_color"].g * preset["ambient_energy"]
		+ preset["sun_color"].g * preset["sun_energy"] * ndotl)
	var b: float = albedo.b * (preset["ambient_color"].b * preset["ambient_energy"]
		+ preset["sun_color"].b * preset["sun_energy"] * ndotl)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


func _readability() -> void:
	var day_lum := _ground_luminance(GROUND_ALBEDO, _preset(_catalog_script.Phase.DAY))
	var night_lum := _ground_luminance(GROUND_ALBEDO, _preset(_catalog_script.Phase.NIGHT))
	_check(day_lum >= DAY_GROUND_LUM_RANGE.x and day_lum <= DAY_GROUND_LUM_RANGE.y,
		"DAY ground reflectance stays bright but not blown out (%.2f in [%.2f, %.2f])"
			% [day_lum, DAY_GROUND_LUM_RANGE.x, DAY_GROUND_LUM_RANGE.y])
	_check(night_lum >= NIGHT_GROUND_LUM_RANGE.x and night_lum <= NIGHT_GROUND_LUM_RANGE.y,
		"NIGHT ground keeps a readable floor under the danger mood (%.2f in [%.2f, %.2f])"
			% [night_lum, NIGHT_GROUND_LUM_RANGE.x, NIGHT_GROUND_LUM_RANGE.y])
	_check(night_lum < day_lum * NIGHT_TO_DAY_LUM_MAX_RATIO,
		"NIGHT reads clearly darker than DAY (mood shift, ratio %.2f)"
			% [night_lum / day_lum])

	# NIGHT 유닛 가독성 프록시: 중간톤 outfit이 ground와 구분되는 밝기를 가진다.
	var unit_lum := _ground_luminance(Color(0.5, 0.5, 0.5), _preset(_catalog_script.Phase.NIGHT))
	_check(unit_lum > NIGHT_MIDGRAY_UNIT_LUM_MIN,
		"NIGHT mid-tone units stay readable against the dark ground (%.2f > %.2f)"
			% [unit_lum, NIGHT_MIDGRAY_UNIT_LUM_MIN])
	_enter(Phase.SHADOW_CFG)


## -- SHADOW_CONFIG --
func _shadow_cfg() -> void:
	var sun: DirectionalLight3D = _env.get_sun_light()
	_check(sun.shadow_enabled, "directional shadow is always on (readability feature)")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,
		"single-split orthogonal shadow matches the orthographic top-down camera")
	_check(sun.directional_shadow_max_distance >= _catalog_script.SHADOW_MAX_DISTANCE - GODOT_EPS,
		"shadow distance covers zoomed-out overview (%.0f)" % sun.directional_shadow_max_distance)
	_enter(Phase.INTEGRATION)


## -- INTEGRATION: World Root + Camera3D + Environment3D 공존 smoke --
func _integration() -> void:
	var camera: Camera3D = _cam_ctl.get_camera()
	_check(camera.current, "camera stays current after environment enters the tree")
	_check(_world.get_node_or_null("Ground") is StaticBody3D,
		"foundation ground body is untouched by the environment layer")
	_check(root.get_world_3d().environment == _env.get_environment(),
		"environment resource is the one serving the shared World3D")

	# DAY/NIGHT 반복 전환 smoke(렌더 파라미터 경계 값 스왑 내성).
	_env.apply_phase(_catalog_script.Phase.NIGHT)
	_env.apply_phase(_catalog_script.Phase.DAY)
	_env._on_phase_changed(_game_time.Phase.NIGHT, 1)
	_env._on_phase_changed(_game_time.Phase.DAY, 1)
	_check(_near(_env.get_sun_light().light_energy,
			_preset(_catalog_script.Phase.DAY)["sun_energy"]),
		"repeated DAY/NIGHT flips settle back on the DAY look")

	# viewport에 WorldEnvironment가 1개뿐임을 보장(중복 환경 충돌 방지).
	var count := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is WorldEnvironment:
			count += 1
		stack.append_array(node.get_children())
	_check(count == 1, "exactly one WorldEnvironment serves this viewport (%d)" % count)
	_enter(Phase.CLEANUP)


## -- CLEANUP: free 후 GameTime 구독 잔여 연결 없음(freed reference 금지) --
func _cleanup() -> void:
	var env_callable: Callable = _env._on_phase_changed
	_env.free()
	_env = null
	_check(not _game_time.phase_changed.is_connected(env_callable),
		"freeing the environment leaves no dangling subscription")
	_finish()
