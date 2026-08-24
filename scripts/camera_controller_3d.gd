extends Node3D
class_name CameraController3D

## TASK-3D-001-3 Orthographic Camera3D Pan / Zoom / Screen-to-World.
## 기존 camera_controller(Node2D + Camera2D)의 관리 조작을 고정 사선 Top-down
## Orthographic Camera3D로 이전한다. 기존 2D 컨트롤러는 reference로 유지한다(LOCK 12).
##
## - 고정 Pitch/Yaw 사선 시점. 회전 입력 경로는 존재하지 않는다(Top-down Direction LOCK 5/7).
## - WASD = XZ camera pan. 속도는 logical px/s로 export하고 WorldCoords3D.PX_TO_UNIT으로
##   변환해 적용한다(기존 2D pan 감각 비율 보존, 파편적 하드코딩 금지 규칙 준수).
## - Mouse Wheel = orthographic size 기반 zoom. zoom 값은 기존 2D 배율 의미를 유지한다
##   (값이 클수록 확대). size = 화면 높이(unit 환산) / zoom 이므로 zoom=1에서 세로 가시
##   범위가 기존 2D zoom 1.0과 동일하다.
## - 최소/최대 zoom clamp + World boundary clamp. bounds는 WorldCoords3D 단일 소스를 사용.
## - Screen mouse position -> 3D ground/world ray 변환을 제공한다(Interaction3D 001-4 소비).
## - Mouse 입력은 _unhandled_input에서만 처리하므로 Control UI가 소비한 클릭/wheel이
##   world 조작으로 누수되지 않고, 모달 overlay(world_map_overlay 그룹)가 열려 있으면
##   pan/wheel 입력을 게이트한다(기존 2D 컨트롤러 게이트 규약 동일).
## - DAY/NIGHT zoom policy(phase_changed 구독)를 유지해 Tactical Migration(CMB-001-2)에서
##   재사용 가능하다.

const GROUND_Y := WorldCoords3D.GROUND_Y

## 카메라 pivot과 Camera3D의 거리(unit). orthographic 투영에서 거리는 화면 크기에
## 영향 없이 near/far 클리핑 여유만 결정한다.
const CAMERA_DISTANCE := 160.0

## 고정 Top-down 사선 각도(deg). 북(-Z)이 화면 위쪽으로 읽히는 기본값이며
## HUMAN_CHECK 결과에 따라 export 튜닝으로만 조정한다. 런타임 회전 입력 없음.
@export var pitch_degrees: float = -55.0
@export var yaw_degrees: float = 0.0

## 기존 2D 정책과 동일한 zoom 배율 값(클수록 확대). NIGHT는 마을 overview 지휘 시점.
@export var day_zoom: float = 1.0
@export var night_zoom: float = 0.5
@export var zoom_transition_speed: float = 3.0

## DAY 일반 camera pan 속도(logical px/s). PX_TO_UNIT으로 unit 변환해 적용한다.
@export var day_pan_speed: float = 480.0

## NIGHT tactical pan 속도(logical px/s).
@export var night_pan_speed: float = 480.0

## Mouse wheel zoom 스텝(zoom target 가/감).
@export var wheel_zoom_step: float = 0.1

## Mouse wheel zoom 허용 범위.
@export var min_zoom: float = 0.4
@export var max_zoom: float = 2.0

var _night_mode := false
var _zoom_target := 1.0
var _camera: Camera3D = null


func _ready() -> void:
	add_to_group("camera_controller_3d")
	_camera = $Camera3D
	_apply_fixed_orientation()
	_camera.make_current()
	GameTime.phase_changed.connect(_on_phase_changed)
	_apply_phase(GameTime.get_phase())


## 고정 사선 Pitch/Yaw를 적용한다. pivot(이 노드)이 항상 화면 중심에 오도록
## Camera3D를 시선 반대 방향으로 CAMERA_DISTANCE만큼 띄운다. 이후 회전 입력 없음.
func _apply_fixed_orientation() -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees)) \
		* Basis(Vector3.RIGHT, deg_to_rad(pitch_degrees))
	_camera.basis = basis
	_camera.position = basis * Vector3(0.0, 0.0, CAMERA_DISTANCE)


## zoom 배율 -> orthographic size(unit). viewport 세로 px를 unit 환산한 값이 기준이라
## zoom=1일 때 세로 가시 범위가 기존 2D zoom 1.0의 px 높이와 일치한다.
func _ortho_size_for_zoom(zoom_value: float) -> float:
	var viewport_height_px := get_viewport().get_visible_rect().size.y
	var base_height_units := viewport_height_px * WorldCoords3D.PX_TO_UNIT
	return base_height_units / maxf(zoom_value, 0.0001)


## zoom target(phase 또는 mouse wheel로 결정)에 부드럽게 수렴한다.
func _process(delta: float) -> void:
	if _camera == null:
		return
	var target_size := _ortho_size_for_zoom(_zoom_target)
	_camera.size = lerpf(_camera.size, target_size,
		clampf(zoom_transition_speed * delta, 0.0, 1.0))


## WASD로 XZ camera pan. DAY/NIGHT는 속도만 다르고 방향 축 의미는 동일하다
## (screen up = north(-Z) 등 WorldCoords3D.DIRECTION_XZ 해석 보존).
func _physics_process(delta: float) -> void:
	if _is_map_overlay_open():
		return
	var pan_speed := night_pan_speed if _night_mode else day_pan_speed
	var pan_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if pan_dir == Vector2.ZERO:
		return
	pan_camera(Vector3(pan_dir.x, 0.0, pan_dir.y) \
		* pan_speed * WorldCoords3D.PX_TO_UNIT * delta)


## 지정 offset(XZ)만큼 camera pivot을 이동하고 월드 경계로 clamp한다.
## Y는 GROUND_Y 고정(자유 높이 이동 금지). 기존 2D pan_camera의 center-point clamp
## 규약과 동일하게 pivot 위치 기준으로 제한한다.
func pan_camera(offset: Vector3) -> void:
	var bounds := get_world_bounds_aabb()
	var desired := position + offset
	position = Vector3(
		clampf(desired.x, bounds.position.x, bounds.end.x),
		GROUND_Y,
		clampf(desired.z, bounds.position.z, bounds.end.z),
	)


func _unhandled_input(event: InputEvent) -> void:
	if _is_map_overlay_open():
		return
	if event is InputEventMouseButton and event.pressed:
		# Left/Right click류는 STOP Control이 GUI 단계에서 소비하지만,
		# 휠 이벤트는 Godot 4에서 Control 위에서도 unhandled로 통과하므로
		# 포인터가 UI 위에 있으면 명시적으로 게이트한다(UI click-through 방지).
		if _is_pointer_over_ui():
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom_target(wheel_zoom_step)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom_target(-wheel_zoom_step)
			get_viewport().set_input_as_handled()


## 포인터가 입력을 받는 Control 위에 있으면 world 조작 입력을 게이트한다.
## 기존 world_selection의 모달 그룹 게이트와 동일한 명시 차단 철학을 따른다.
func _is_pointer_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null


func _adjust_zoom_target(amount: float) -> void:
	_zoom_target = clampf(_zoom_target + amount, min_zoom, max_zoom)


func _on_phase_changed(phase: int, _day_number: int) -> void:
	_apply_phase(phase)


## DAY/NIGHT zoom policy 매핑. Tactical Migration(CMB-001-2)이 재사용하는 지점.
func _apply_phase(phase: int) -> void:
	_night_mode = (phase == GameTime.Phase.NIGHT)
	_zoom_target = night_zoom if _night_mode else day_zoom


## 아래는 테스트/후속 태스크(Interaction3D, Tactical Migration)용 접근자.
func is_night_mode() -> bool:
	return _night_mode


func get_camera() -> Camera3D:
	return _camera


func get_zoom_target() -> float:
	return _zoom_target


func get_world_bounds_aabb() -> AABB:
	return WorldCoords3D.world_bounds_aabb()


## 모달 overlay(world_map_overlay 그룹)가 열려 있으면 world 조작 입력을 게이트한다.
## 기존 2D camera_controller._is_map_overlay_open과 동일 규약.
func _is_map_overlay_open() -> bool:
	var overlay := get_tree().get_first_node_in_group("world_map_overlay")
	return overlay != null and overlay.has_method("is_open") and overlay.is_open()


## Screen 좌표 -> 3D world ray(Camera3D project_ray 기반).
## Interaction3D(001-4) 선택 광선 소비 전용. 카메라 미준비 시 빈 Dictionary.
func screen_to_world_ray(screen_pos: Vector2) -> Dictionary:
	if _camera == null:
		return {}
	return {
		"origin": _camera.project_ray_origin(screen_pos),
		"direction": _camera.project_ray_normal(screen_pos),
	}


## Screen 좌표 -> 지면(Y=GROUND_Y 평면) 교차점. 빈 ground 클릭/placement 좌표 등에 사용.
## 광선이 지면과 평행하거나 위쪽 향이면 교차하지 않으므로 Vector3.INF를 반환한다.
func ground_point_from_screen(screen_pos: Vector2) -> Vector3:
	var ray := screen_to_world_ray(screen_pos)
	if ray.is_empty():
		return Vector3.INF
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]
	if absf(direction.y) < 0.0001 or direction.y >= 0.0:
		return Vector3.INF
	var t := (GROUND_Y - origin.y) / direction.y
	if t < 0.0:
		return Vector3.INF
	return origin + direction * t


## Screen 좌표 -> physics world raycast. 지정 mask의 최근접 hit을 반환하고
## 미스 시 빈 Dictionary. UI 차단 여부는 호출자가 unhandled input 계약으로 보장한다.
func raycast_from_screen(screen_pos: Vector2, collision_mask: int) -> Dictionary:
	var ray := screen_to_world_ray(screen_pos)
	if ray.is_empty():
		return {}
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray["origin"], ray["origin"] + ray["direction"] * 2000.0, collision_mask)
	return space.intersect_ray(query)
