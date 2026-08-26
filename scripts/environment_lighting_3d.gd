extends Node3D
class_name EnvironmentLighting3D

## TASK-3D-VIS-001-3 Environment / Lighting Prototype.
## Top-down stylized low-poly look의 최소 environment/lighting 레이어.
## world3d.tscn(world_root_3d.gd)은 Foundation 소유라 수정하지 않고, 이 신규
## scene을 World Root 위에 add_child로 얹는다(camera_controller_3d와 동일 방식).
## Main World wiring은 TASK-3D-INT-001이 수행한다(INTEGRATION_NOTE_VIS.md 참조).
##
## - WorldEnvironment + DirectionalLight3D(sun/moon 1등)만 사용한다.
##   과도한 bloom/fog/post-processing 금지(태스크 요구)를 코드로 고정한다:
##   glow/fog/volumetric_fog/ssao/ssil/sdfgi/adjustment는 항상 off,
##   tonemap은 LINEAR(stylized 저채도 억제 없음)다.
## - DAY/NIGHT 기본 look은 PRESETS 단일 소스다. GameTime.phase_changed를
##   구독해 전환하며(camera_controller_3d의 phase policy와 같은 구독 계약),
##   _ready에서 현재 phase를 즉시 적용한다.
## - Shadow: DirectionalLight3D.shadow_enabled 상시 on. orthographic top-down
##   카메라에 맞게 SHADOW_ORTHOGONAL 단일 분할 + max distance로 overview까지
##   커버한다. 그림자가 지형/건물 가독성을 개선하는지는 HUMAN_CHECK 항목이다.
## - Ambient: AMBIENT_SOURCE_COLOR로 직접 제어한다. NIGHT는 어둡지만
##   유닛/길이 읽히도록 ambient energy를 유지한다(top-down 가독성 우선).
## - terrain/ground가 캐릭터/건물을 묻히지 않도록 preset 수치는
##   "ground 반사휘도 밴드" 검증(task3dvis0013_test)을 통과하는 값으로 고정했다.
##   placeholder GroundVisual 교체/실제 terrain visual은 VIS-001-5 소유다.

## GameTime.Phase(DAY=0, NIGHT=1)와 순서를 맞춘 로컬 미러. autoload 식별자는
## const 초기화에 쓸 수 없으므로 프리셋 키는 이 enum으로 고정한다.
enum Phase { DAY, NIGHT }

## 그림자 커버 거리(unit). min_zoom 0.4에서 세로 가시 범위 약 202 unit까지
## 덮이도록 설정한다(카메라 controller의 zoom clamp 기준).
const SHADOW_MAX_DISTANCE := 220.0

## DAY/NIGHT 기본 look 단일 소스.
## sun_rotation_degrees: (pitch, yaw, roll). pitch = 태양 고도(음수 = 하늘 방향),
## yaw는 화면상 그림자 방향을 결정한다(기존 캡처 도구 관례 -50/-35를 DAY 기본으로 승계).
const PRESETS := {
	Phase.DAY: {
		"sun_rotation_degrees": Vector3(-50.0, -35.0, 0.0),
		"sun_energy": 1.15,
		"sun_color": Color(1.0, 0.97, 0.9),
		"ambient_color": Color(0.72, 0.78, 0.85),
		"ambient_energy": 0.75,
		"background_color": Color(0.58, 0.72, 0.84),
	},
	Phase.NIGHT: {
		"sun_rotation_degrees": Vector3(-55.0, 25.0, 0.0),
		"sun_energy": 0.35,
		"sun_color": Color(0.6, 0.7, 1.0),
		"ambient_color": Color(0.16, 0.2, 0.32),
		"ambient_energy": 0.85,
		"background_color": Color(0.05, 0.07, 0.12),
	},
}

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $SunLight


func _ready() -> void:
	add_to_group("environment_3d")
	GameTime.phase_changed.connect(_on_phase_changed)
	_apply_postfx_budget()
	_apply_shadow_config()
	apply_phase(GameTime.get_phase())


## 그림자 설정. orthographic top-down 카메라에는 단일 분할 SHADOW_ORTHOGONAL이
## 대응하며, phase와 무관하게 상시 유지된다(NIGHT에서도 실루엣 가독성 제공).
func _apply_shadow_config() -> void:
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE


## post-processing 예산 고정(태스크 금지 항목의 코드화).
## LINEAR tonemap 외의 색감 재해석을 하지 않아 stylized low-poly 원색을 유지한다.
func _apply_postfx_budget() -> void:
	var env := get_environment()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.adjustment_enabled = false


func _on_phase_changed(phase: int, _day_number: int) -> void:
	apply_phase(phase)


## phase(GameTime.Phase 값)에 대응하는 기본 look을 적용한다.
## 알 수 없는 값은 현재 상태를 유지한다(기본 look 훼손 방지).
func apply_phase(phase: int) -> void:
	if not PRESETS.has(phase):
		return
	var preset: Dictionary = PRESETS[phase]
	_sun.rotation_degrees = preset["sun_rotation_degrees"]
	_sun.light_energy = preset["sun_energy"]
	_sun.light_color = preset["sun_color"]
	var env := get_environment()
	env.background_color = preset["background_color"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = preset["ambient_color"]
	env.ambient_light_energy = preset["ambient_energy"]


func is_night() -> bool:
	return GameTime.get_phase() == GameTime.Phase.NIGHT


func get_sun_light() -> DirectionalLight3D:
	return _sun


func get_world_environment() -> WorldEnvironment:
	return _world_environment


func get_environment() -> Environment:
	return _world_environment.environment
