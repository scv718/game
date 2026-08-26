extends CharacterBody3D
class_name WorkerActor3D

## TASK-3D-WRK-001-1 Worker Actor 3D 공통 base / Movement.
## 기존 lumberjack.gd / miner.gd(CharacterBody2D + NavigationAgent2D)가 공유하던
## 이동 골격을 Foundation Navigation convention(NavigationPolicy3D) 위로 이전한
## 신규 파일이다. 기존 2D worker 스크립트/scene은 LOCK 12에 따라 유지되며,
## Lumberjack/Miner 개별 FSM wiring(TASK-3D-WRK-001-2)이 이 base를 상속해
## 기존 상태 의미(IDLE/FIND/MOVE/GATHER/RETURN/DEPOSIT 계열)를 그대로 얹는다.
##
## 이동 규약(요구사항 매핑):
##   - 3D Actor root: CharacterBody3D. collision_layer/mask는 CollisionLayers3D
##     단일 소스(WORKER / MASK_ACTOR_SOLID). actor끼리 물리 충돌 없음(2D 동일).
##   - NavigationAgent3D: NavigationPolicy3D.configure_agent()만 적용한다.
##     도메인별 개별 agent 튜닝 금지(Foundation 001-5 LOCK).
##   - XZ ground movement: velocity는 NavigationPolicy3D.path_follow_velocity_xz로만
##     계산(Y 성분 상수 0). move_and_slide 후에도 origin Y를 GROUND_Y로 강제해
##     Y height drift를 구조적으로 차단한다. pitch/roll도 항상 0으로 고정한다.
##   - facing: 이동 방향으로 Visual child의 yaw만 갱신한다(Godot forward -Z 관례,
##     target_yaw = atan2(-v.x, -v.z)). body 자체는 회전하지 않는다.
##   - target 해석: workplace/resource node는 Actor Origin LOCK에 따라 지면 접지점을
##     origin으로 가지므로, global_position을 WorldCoords3D.flatten으로 지면 좌표로
##     해석해 목적지로 쓴다. begin_move_to에 Y가 섞인 좌표가 와도 flatten된다.
##
## 단일 종료 규약(영구 stall 방지 원칙 유지):
##   - 모든 이동 시도는 move_finished 신호 정확히 1회로 끝난다.
##     ARRIVED(도달) / BLOCKED(부분 경로 소진, NavigationPolicy3D.judge_path_status
##     판정) / STALLED(stuck guard 2차 안전망 발동) / TARGET_LOST(tracked node
##     freed) / CANCELED(cancel_move 또는 agent 무효).
##   - 이동 중 새 명령이 오면 이전 시도는 신호 없이 조용히 대체된다.
##     즉 "명령 1건 = 완료 신호 최대 1건"이다.
##
## cleanup 경계(요구사항: agent freed/unassigned cleanup 안정):
##   - tracked_target이 freed되면 다음 physics frame에 TARGET_LOST로 bounded
##     정지한다. freed reference를 재해석하거나 보유하지 않는다.
##   - 이미 freed된 node를 begin_move_to_node로 받으면 false를 반환하고
##     stale reference를 수용하지 않는다(호출자 FSM이 분기한다).
##   - NavigationAgent3D가 외부에서 free되어도 CANCELED로 bounded 종료한다.
##   - _exit_tree에서는 이동 상태만 조용히 폐기한다(tree 이탈 중 signal emit 금지 -
##     구독자 참조 자체가 무효화되는 순서일 수 있다). claim/release 등
##     자원 규약은 WRK-001-2 서브클래스 소유다.
##
## Visual child는 VIS 도메인 교체 슬롯이다(placeholder capsule mesh).
## tree_3d.gd의 Visual child 계약과 동일하게 game logic과 visual 표현을 분리한다.

signal move_finished(status: int, final_position: Vector3)

## 이동 시도의 종료 사유. ARRIVED/BLOCKED는 NavigationPolicy3D.PathStatus 판정에서,
## STALLED는 stuck guard(NavigationPolicy3D.STUCK_TIMEOUT) 발동에서 온다.
enum MoveStatus { ARRIVED, BLOCKED, STALLED, TARGET_LOST, CANCELED }

## 기존 lumberjack/miner move_speed(90 px/s)의 비율 보존값(PX_TO_UNIT 환산 = 11.25).
const MOVE_SPEED_PX := 90.0

@export var move_speed: float = MOVE_SPEED_PX * WorldCoords3D.PX_TO_UNIT
@export var facing_turn_rate: float = 12.0

## 현재 지면 목적지(Y = GROUND_Y 보장). tracked_target이 있으면 매 frame 갱신된다.
var move_target := Vector3.ZERO
## 추적 대상(workplace/resource 등 Node3D). freed 시 TARGET_LOST로 종료한다.
var tracked_target: Node3D = null

var _moving := false
## 추적 의도 플래그. Godot 4에서 freed된 Object는 `== null` 참이 되므로
## tracked_target의 null 비교만으로는 "추적 중인 대상이 freed되었는지"를
## 감지할 수 없다. 이 플래그가 의도를 보존하고 is_instance_valid 판정을
## 반드시 통과시킨다.
var _tracking_node := false
var _stuck_timer := 0.0
var _last_move_pos := Vector3.ZERO

var _nav_agent: NavigationAgent3D = null
var _visual: Node3D = null


func _init() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = CollisionLayers3D.WORKER
	collision_mask = CollisionLayers3D.MASK_ACTOR_SOLID
	var col := CollisionShape3D.new()
	col.name = "CollisionShape"
	# Actor Origin LOCK: node origin은 지면 접지점, 볼륨은 위로 오프셋한다
	# (task3d0015_test PolicyProbe와 동일 구성).
	col.position = Vector3(0.0, NavigationPolicy3D.ACTOR_RADIUS_UNITS, 0.0)
	var sphere := SphereShape3D.new()
	sphere.radius = NavigationPolicy3D.ACTOR_RADIUS_UNITS
	col.shape = sphere
	add_child(col)
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.name = "NavigationAgent"
	add_child(_nav_agent)
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	var capsule := CapsuleMesh.new()
	capsule.radius = NavigationPolicy3D.ACTOR_RADIUS_UNITS * 0.5
	capsule.height = NavigationPolicy3D.ACTOR_HEIGHT_UNITS
	body_mesh.mesh = capsule
	body_mesh.position = Vector3(0.0, NavigationPolicy3D.ACTOR_HEIGHT_UNITS * 0.5, 0.0)
	_visual.add_child(body_mesh)


func _ready() -> void:
	add_to_group("workers_3d")
	if _nav_agent != null:
		NavigationPolicy3D.configure_agent(_nav_agent)
	rotation.x = 0.0
	rotation.z = 0.0
	global_position.y = WorldCoords3D.GROUND_Y


func _physics_process(delta: float) -> void:
	if not _moving:
		return
	if not is_instance_valid(_nav_agent):
		_stop_body()
		_finish_move(MoveStatus.CANCELED)
		return
	if _tracking_node:
		if not is_instance_valid(tracked_target):
			_tracking_node = false
			tracked_target = null
			_stop_body()
			_finish_move(MoveStatus.TARGET_LOST)
			return
		var next := WorldCoords3D.flatten(tracked_target.global_position)
		if not next.is_equal_approx(move_target):
			# 추적 중 대상이 움직였으면 경로도 함께 갱신한다. 기존 2D worker가
			# 매 frame target_position을 재지정하던 계약(lumberjack/miner 이동
			# tick)과 동일하며, 갱신 즉시 get_next_path_position()로 repath를
			# 확정해 stale한 finished 상태 오판을 막는다(command_to 계약).
			move_target = next
			_nav_agent.target_position = move_target
			_nav_agent.get_next_path_position()
	match NavigationPolicy3D.judge_path_status(_nav_agent, global_position, move_target):
		NavigationPolicy3D.PathStatus.ARRIVED:
			_stop_body()
			_finish_move(MoveStatus.ARRIVED)
			return
		NavigationPolicy3D.PathStatus.BLOCKED:
			_stop_body()
			_finish_move(MoveStatus.BLOCKED)
			return
	if _check_stuck(delta):
		_stop_body()
		_finish_move(MoveStatus.STALLED)
		return
	velocity = NavigationPolicy3D.path_follow_velocity_xz(
		global_position, _nav_agent, move_speed)
	move_and_slide()
	# Y height drift / tilt 금지(LOCK): 지면 이동이 origin Y/yaw 이외를 바꾸지 않게 강제.
	global_position.y = WorldCoords3D.GROUND_Y
	rotation.x = 0.0
	rotation.z = 0.0
	_update_facing(delta)


## 지면 목적지로 이동을 시작한다. Y가 포함된 좌표도 지면 좌표로 해석한다(flatten).
## 배치 위치 확정 후(add_child 이후) 호출해야 한다.
func begin_move_to(target: Vector3) -> void:
	move_target = WorldCoords3D.flatten(target)
	tracked_target = null
	_tracking_node = false
	_start_move()


## workplace/resource node 추적 이동. node origin(지면 접지점)을 실시간 목적지로
## 쓰므로 이동 중 node가 움직여도 따라간다.
##
## 파라미터는 일부러 untyped다. 이미 freed된 참조를 typed 파라미터로 넘기면
## 엔진이 즉시 타입 오류를 내므로, caller가 보유한 workplace/resource 참조가
## freed된 상태로 들어와도 stale probe로 안전하게 거부되려면 Variant로 받아
## is_instance_valid로 검증해야 한다(cleanup 안정 요구사항). 유효하지 않은
## 입력(null/freed/Node3D 아님)은 false 반환으로 거부되고 상태는 변하지 않는다.
func begin_move_to_node(target_node) -> bool:
	if not is_instance_valid(target_node):
		return false
	if not (target_node is Node3D):
		return false
	tracked_target = target_node
	_tracking_node = true
	move_target = WorldCoords3D.flatten(tracked_target.global_position)
	_start_move()
	return true


## 현재 이동을 bounded하게 중단하고 CANCELED로 종료한다. 이동 중이 아니면 no-op.
func cancel_move() -> void:
	if not _moving:
		return
	_clear_tracking()
	_stop_body()
	_finish_move(MoveStatus.CANCELED)


func is_moving() -> bool:
	return _moving


## 현재 목적지까지의 gameplay 거리(XZ 평면, 2D distance 의미 보존).
## approach distance 판정 등 WRK-001-2 FSM이 사용한다.
func distance_to_target_xz() -> float:
	return WorldCoords3D.distance_xz(global_position, move_target)


func get_nav_agent() -> NavigationAgent3D:
	return _nav_agent


func get_visual() -> Node3D:
	return _visual


func _start_move() -> void:
	_moving = true
	_stuck_timer = 0.0
	_last_move_pos = global_position
	if is_instance_valid(_nav_agent):
		_nav_agent.target_position = move_target
		# target 변경 직후 stale한 finished 상태로 ARRIVED/BLOCKED 오판하지 않도록
		# path를 즉시 갱신한다(task3d0015_test PolicyProbe.command_to 동일 계약).
		_nav_agent.get_next_path_position()


func _finish_move(status: int) -> void:
	_moving = false
	_clear_tracking()
	move_finished.emit(status, global_position)


func _clear_tracking() -> void:
	tracked_target = null
	_tracking_node = false


func _stop_body() -> void:
	velocity = Vector3.ZERO


## 기존 lumberjack/enemy _check_stuck과 동일 감각(NavigationPolicy3D 비율 보존값).
## BLOCKED가 못 잡는 예외 케이스의 2차 안전망이다.
func _check_stuck(delta: float) -> bool:
	if global_position.distance_to(_last_move_pos) \
			< NavigationPolicy3D.STUCK_MOVE_EPSILON_UNITS:
		_stuck_timer += delta
		return _stuck_timer >= NavigationPolicy3D.STUCK_TIMEOUT
	_last_move_pos = global_position
	_stuck_timer = 0.0
	return false


## 이동 방향으로 Visual yaw만 갱신한다(pitch/roll 고정 - tilt 금지).
## Godot forward(-Z) 관례: Visual의 -Z 축이 이동 방향을 향한다.
func _update_facing(delta: float) -> void:
	var v := velocity
	v.y = 0.0
	if v.length_squared() <= 0.0001:
		return
	var target_yaw := atan2(-v.x, -v.z)
	var weight := clampf(facing_turn_rate * delta, 0.0, 1.0)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, weight)


func _exit_tree() -> void:
	# freed/unassigned 경계: 이동 상태를 조용히 폐기한다(signal emit 없음).
	_moving = false
	_clear_tracking()
	velocity = Vector3.ZERO
