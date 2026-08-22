extends Node2D
class_name CameraController

## TASK-CTRL-001-1 World Camera Controller.
## 기존 Player node가 소유하던 Camera2D 이동/Zoom 책임을 Player와 분리된 이 컨트롤러로
## 이전한다. DAY/NIGHT 모두 단일 Camera2D(자식 노드)를 관리하며 Player에 종속되지 않는다.
##
## - DAY WASD = camera pan(day_pan_speed).
## - NIGHT WASD = 기존 Tactical camera pan 유지(night_pan_speed).
## - Mouse Wheel = camera zoom(_zoom_target 조정, min/max clamp).
## - phase 전환 시 zoom target을 day_zoom/night_zoom으로 복귀(TASK-010 정책 유지).
## - 카메라 위치는 World boundary(WORLD_BOUNDS) 밖으로 벗어나지 않는다.

## TASK-010-3 밤 tactical view 카메라 배율. DAY에서는 day_zoom으로 복귀한다.
## 프로토타입 값이며 추후 실제 플레이에서 조정 가능하다(export).
@export var day_zoom: float = 1.0
@export var night_zoom: float = 0.5
@export var zoom_transition_speed: float = 3.0

## DAY 일반 camera pan 속도(px/s). WASD로 카메라를 자유 이동한다.
@export var day_pan_speed: float = 480.0

## TASK-015-1 NIGHT tactical camera 독립 pan 속도(px/s).
@export var night_pan_speed: float = 480.0

## Mouse wheel zoom 스텝(zoom target에 가/감).
@export var wheel_zoom_step: float = 0.1

## Mouse wheel zoom 허용 범위.
@export var min_zoom: float = 0.4
@export var max_zoom: float = 2.0

## TASK-015-1 월드 경계. world.gd의 FALLBACK_BOUNDS_RECT와 동일한 2048x2048 맵.
const WORLD_BOUNDS := Rect2(-1024, -1024, 2048, 2048)

var _night_mode := false
var _zoom_target := 1.0
var _camera: Camera2D = null


func _ready() -> void:
	add_to_group("camera_controller")
	_camera = $Camera2D
	GameTime.phase_changed.connect(_on_phase_changed)
	_apply_phase(GameTime.get_phase())


## zoom target(phase 또는 mouse wheel로 결정)으로 부드럽게 수렴한다.
func _process(delta: float) -> void:
	if _camera == null:
		return
	var target := _zoom_target
	_camera.zoom = _camera.zoom.lerp(
		Vector2(target, target),
		clampf(zoom_transition_speed * delta, 0.0, 1.0)
	)


## WASD로 camera pan. DAY는 일반 pan, NIGHT는 tactical pan(속도만 다름).
## 카메라가 Player에 종속되지 않으므로 컨트롤러 자체 위치를 이동한다.
func _physics_process(delta: float) -> void:
	var pan_speed := night_pan_speed if _night_mode else day_pan_speed
	var pan_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if pan_dir == Vector2.ZERO:
		return
	pan_camera(pan_dir * pan_speed * delta)


## 지정 offset만큼 camera를 이동하고 월드 경계로 clamp한다.
func pan_camera(offset: Vector2) -> void:
	if _camera == null:
		return
	var desired := global_position + offset
	global_position = Vector2(
		clampf(desired.x, WORLD_BOUNDS.position.x, WORLD_BOUNDS.end.x),
		clampf(desired.y, WORLD_BOUNDS.position.y, WORLD_BOUNDS.end.y),
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target + wheel_zoom_step, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target - wheel_zoom_step, min_zoom, max_zoom)


func _on_phase_changed(phase: int, _day_number: int) -> void:
	_apply_phase(phase)


func _apply_phase(phase: int) -> void:
	_night_mode = (phase == GameTime.Phase.NIGHT)
	_zoom_target = night_zoom if _night_mode else day_zoom


## 아래는 테스트/후속 태스크용 접근자.
func is_night_mode() -> bool:
	return _night_mode


func get_camera() -> Camera2D:
	return _camera


func get_zoom_target() -> float:
	return _zoom_target


func get_world_bounds() -> Rect2:
	return WORLD_BOUNDS