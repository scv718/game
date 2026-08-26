extends WorkerActor3D
class_name Miner3D

## TASK-3D-WRK-001-2 Miner FSM 3D wiring.
## 기존 miner.gd(CharacterBody2D + NavigationAgent2D)의 상태 전이 의미를
## 그대로 유지한 채 WorkerActor3D(TASK-3D-WRK-001-1) 이동 골격 위로 이전한 파일이다.
## 기존 2D miner.gd / miner.tscn은 LOCK 12에 따라 reference로 유지되며
## 수정하지 않는다(migration map 운영 규칙 5: 신규 파일만 추가).
##
## 상태 의미 보존(기존 miner.gd와 1:1 대응):
##   IDLE -> MOVE_TO_WORK -> MINE (+ RETURN_TO_FACILITY는 despawn 전용)
##   - 생산량/쿨다운(production_interval/stone_per_cycle) 불변.
##   - 생산은 VillageResources.add("stone", ...) 직접 반납(carry 없음 - 기존 규약).
##   - _on_assigned 즉시 MOVE_TO_WORK, unassign 시 즉시 IDLE(기존 동작).
##   - despawn은 시설 SpawnPoint 복귀 후 callback(DESPAWN_TIMEOUT bounded guard).
##
## 3D wiring 차이(이동 API만 교체, 의미 불변):
##   - 이동은 begin_move_to(work point/spawn point) 단일 명령으로 시작하고
##     move_finished 신호(정확히 1회 종료)로 다음 상태를 결정한다. work point는
##     정적 지점이므로 tracked node 이동 대신 좌표 명령을 쓴다.
##   - BLOCKED/STALLED 종료는 2D navigation_finished 미도달 -> IDLE 폴백과
##     동등한 bounded 처리다(영구 MOVE stall 금지). 복귀 실패 시에도 despawn으로
##     bounded 종료한다(unassigned actor의 영구 잔류 방지).
##
## workplace 연결(BLD 도메인 전환 전 duck-typed 계약):
##   - 작업 위치는 workplace.get_work_point_for(self)(Node3D 반환 시 사용,
##     배치 index 기반 분산 - TASK-011-6 계약) -> "WorkPoint"/"WorkPoint2"
##     Node3D 자식 -> workplace origin 순으로 해석한다.
##   - 복귀 위치는 "SpawnPoint" Node3D 자식, 없으면 workplace origin(지면).
##
## Visual hook(기능 상태와 분리 - REQ):
##   - work_anim_started/stopped(&"mine"): MINE 진입/이탈에서 발화.
##   - 실제 animation asset이 없어도 신호는 발화하며 기능 상태는 지연되지 않는다.

signal work_anim_started(action: StringName)
signal work_anim_stopped(action: StringName)

enum State { IDLE, MOVE_TO_WORK, MINE, RETURN_TO_FACILITY }

const STATE_NAMES := {
	State.IDLE: "IDLE",
	State.MOVE_TO_WORK: "MOVE",
	State.MINE: "MINE",
	State.RETURN_TO_FACILITY: "RETURN",
}

## 기존 miner.gd WORK_APPROACH_DISTANCE(12px) 비율 보존값.
const WORK_REACH_UNITS := 12.0 * WorldCoords3D.PX_TO_UNIT
const DESPAWN_TIMEOUT := 6.0

const WORK_ANIM_ID := &"mine"

@export var production_interval: float = 1.0
@export var stone_per_cycle: int = 1

var state: State = State.IDLE
## Workplace 계약을 지원하는 Node(3D 건물 전환 전까지 duck-typed).
var workplace: Node = null
var worker_data: WorkerData = null

var _produce_timer := 0.0
var _despawn_pending := false
var _despawn_callback: Callable = Callable()
var _despawn_timeout := 0.0

var _work_anim_active := false


func _ready() -> void:
	super()
	add_to_group("miners_3d")
	move_finished.connect(_on_move_finished)


func _physics_process(delta: float) -> void:
	super(delta)
	if _despawn_pending:
		_despawn_timeout -= delta
		if _despawn_timeout <= 0.0:
			_try_despawn()
			return
	match state:
		State.MOVE_TO_WORK:
			_tick_move_to_work()
		State.MINE:
			_tick_mine(delta)
		State.RETURN_TO_FACILITY:
			_tick_return_to_facility()


## -- 상태 전이 단일 진입점. 이동 상태 진입 시 여기서 이동 명령 1건을 시작하고,
## 이동 외 상태 진입 시에는 잔여 이동 시도를 bounded하게 정리한다(명령 1건 =
## 완료 신호 최대 1건 계약 유지). --
func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.MOVE_TO_WORK:
			begin_move_to(_get_work_point_position())
		State.RETURN_TO_FACILITY:
			begin_move_to(_get_return_position())
		State.MINE:
			# produce timer는 진입 호출부가 기존 규약대로 preset한다.
			_set_work_anim(true)
			cancel_move()
		_:
			_set_work_anim(false)
			cancel_move()


func _tick_move_to_work() -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_set_state(State.IDLE)
		return
	# 도착 판정은 move_finished 핸들러가 담당한다(base 단일 종료 규약).


func _tick_mine(delta: float) -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_produce_timer = 0.0
		_set_state(State.IDLE)
		return
	_produce_timer -= delta
	if _produce_timer > 0.0:
		return
	_produce_timer = production_interval
	VillageResources.add("stone", stone_per_cycle)


## TASK-011-5 규약 유지: 배치 해제 시 Miner가 시설 Spawn/Return point로
## 복귀한 뒤 despawn한다.
func _tick_return_to_facility() -> void:
	if not is_instance_valid(workplace):
		_try_despawn()
		return
	# 도착 판정은 move_finished 핸들러가 담당한다.


func _on_move_finished(status: int, _final_position: Vector3) -> void:
	match state:
		State.MOVE_TO_WORK:
			if status == MoveStatus.ARRIVED:
				_produce_timer = production_interval
				_set_state(State.MINE)
				return
			# BLOCKED/STALLED/TARGET_LOST/CANCELED: bounded 폴백(2D navigation
			# 미도달 -> IDLE과 동등). 재시도 무한루프를 만들지 않는다.
			_set_state(State.IDLE)
		State.RETURN_TO_FACILITY:
			if status == MoveStatus.ARRIVED:
				_try_despawn()
				return
			# 복귀 실패도 bounded: 무한 RETURN 잔류 대신 despawn을 확정한다.
			_try_despawn()


func _get_work_point_position() -> Vector3:
	if is_instance_valid(workplace) and workplace.has_method("get_work_point_for"):
		var point: Variant = workplace.get_work_point_for(self)
		if point is Node3D:
			return WorldCoords3D.flatten(point.global_position)
	if is_instance_valid(workplace):
		for point_name in ["WorkPoint", "WorkPoint2"]:
			var marker: Node = workplace.get_node_or_null(point_name)
			if marker is Node3D:
				return WorldCoords3D.flatten((marker as Node3D).global_position)
		if workplace is Node3D:
			return WorldCoords3D.flatten((workplace as Node3D).global_position)
	return global_position


func _get_return_position() -> Vector3:
	if is_instance_valid(workplace) and workplace is Node3D:
		var marker: Node = workplace.get_node_or_null("SpawnPoint")
		if marker is Node3D:
			return WorldCoords3D.flatten((marker as Node3D).global_position)
		return WorldCoords3D.flatten((workplace as Node3D).global_position)
	return global_position


## TASK-011-5 규약 유지: 새 생산 cycle을 즉시 중단하고 시설 복귀 -> despawn
## 흐름을 시작한다. Navigation 문제로 영구 정지하지 않도록 bounded timeout을 둔다.
func begin_despawn(callback: Callable) -> void:
	_despawn_pending = true
	_despawn_callback = callback
	_despawn_timeout = DESPAWN_TIMEOUT
	_produce_timer = 0.0
	if is_instance_valid(workplace):
		_set_state(State.RETURN_TO_FACILITY)
	else:
		_try_despawn()


func _try_despawn() -> void:
	_despawn_pending = false
	if _despawn_callback.is_valid():
		var cb := _despawn_callback
		_despawn_callback = Callable()
		cb.call()


func _on_unassigned() -> void:
	workplace = null
	_produce_timer = 0.0
	_set_state(State.IDLE)


func _on_assigned(building: Node) -> void:
	workplace = building
	_produce_timer = production_interval
	_set_state(State.MOVE_TO_WORK)


func _set_work_anim(active: bool) -> void:
	if _work_anim_active == active:
		return
	_work_anim_active = active
	if active:
		work_anim_started.emit(WORK_ANIM_ID)
	else:
		work_anim_stopped.emit(WORK_ANIM_ID)


## -- 조회 API(기존 miner.gd 계약 유지). --
func is_gathering() -> bool:
	return state == State.MINE


func get_state_name() -> String:
	return STATE_NAMES.get(state, "?")


func get_workplace() -> Node:
	return workplace


func is_assigned() -> bool:
	return is_instance_valid(workplace)
