extends WorkerActor3D
class_name Lumberjack3D

## TASK-3D-WRK-001-2 Lumberjack FSM 3D wiring.
## 기존 lumberjack.gd(CharacterBody2D + NavigationAgent2D)의 상태 전이 의미를
## 그대로 유지한 채 WorkerActor3D(TASK-3D-WRK-001-1) 이동 골격 위로 이전한 파일이다.
## 기존 2D lumberjack.gd / lumberjack.tscn은 LOCK 12에 따라 reference로 유지되며
## 수정하지 않는다(migration map 운영 규칙 5: 신규 파일만 추가).
##
## 상태 의미 보존(기존 lumberjack.gd와 1:1 대응):
##   IDLE -> FIND_TREE -> MOVE_TO_TREE -> GATHER -> RETURN_TO_LUMBERYARD -> DEPOSIT
##   - 생산량/쿨다운/운반량(carry_capacity/gather_interval) 불변.
##   - resource claim 규약(ResourceNode3D.claim/release/is_claimed_by_other) 불변.
##   - unassign 시 carrying 중이면 마지막 1회 deposit 후 해제(_final_deposit).
##   - despawn은 시설 복귀 후 callback(DESPAWN_TIMEOUT bounded guard 유지).
##
## 3D wiring 차이(이동 API만 교체, 의미 불변):
##   - 이동은 begin_move_to_node(target_tree)/begin_move_to(deposit) 단일 명령으로
##     시작하고 move_finished 신호(정확히 1회 종료)로 다음 상태를 결정한다.
##     2D의 매 tick target_position 재지정은 base의 tracked target 실시간 갱신
##     계약으로 대체된다(WRK-001-1에서 동등성 검증 완료).
##   - 나무 접근은 trunk 장애물 carve 경계에서 BLOCKED로 끝나는 것이 정상 경로다.
##     2D의 "navigation_failed + 근접 판정" 규약과 동일하게, 종료 위치가
##     GATHER_REACH(+SLACK) 이내면 채집 진입, 아니면 해당 나무를 skip하고
##     다음 후보를 찾는다(unreachable 자원 영구 stall 방지 규약 유지).
##   - 2D _find_nearest_tree의 NavigationServer2D 사전 경로 probe는 생략했다.
##     도달 불능 나무는 위 BLOCKED-skip 경로로 bounded 처리되며 보장은 동일하다
##     (claim 선점 후 즉시 release이므로 claim 충돌/누수 없음).
##
## workplace 연결(BLD 도메인 전환 전 duck-typed 계약):
##   - workplace는 Workplace 계약(assign_worker/unassign_worker/_on_assigned/
##     _on_unassigned/spawn·despawn_worker_actor)을 지원하는 Node면 충분하다.
##   - 반납 위치는 "DepositPoint" 이름의 Node3D 자식, 없으면 workplace origin
##     (지면 flatten). 작업 반경은 work_radius(px) 프로퍼티, 없으면 기본값.
##   - 자원 조회는 "resource_nodes_3d" 그룹(RES 도메인 계약)만 사용한다.
##
## Visual hook(기능 상태와 분리 - REQ):
##   - work_anim_started/stopped(&"chop"): GATHER 진입/이탈에서 발화.
##   - carry_prop_changed(attached, resource_id): 운반 prop attach/detach 시점.
##   - 실제 animation asset이 없어도 위 신호는 발화하며 기능 상태는 지연되지
##     않는다. 기본 표현은 Visual child 아래 placeholder CarryProp mesh
##     가시성 토글뿐이고, VIS 도메인이 자식 슬롯을 교체하는 방식으로 연결한다.

signal work_anim_started(action: StringName)
signal work_anim_stopped(action: StringName)
signal carry_prop_changed(attached: bool, resource_id: String)

enum State { IDLE, FIND_TREE, MOVE_TO_TREE, GATHER, RETURN_TO_LUMBERYARD, DEPOSIT }

const STATE_NAMES := {
	State.IDLE: "IDLE",
	State.FIND_TREE: "FIND",
	State.MOVE_TO_TREE: "MOVE",
	State.GATHER: "GATHER",
	State.RETURN_TO_LUMBERYARD: "RETURN",
	State.DEPOSIT: "DEPOSIT",
}

## 기존 lumberjack.gd 비율 보존값(px -> unit 환산은 WorldCoords3D.PX_TO_UNIT).
## GATHER 진입 14px, BLOCKED 종료 위치 판정 여유 4px(nav cell/path desired
## distance 경계 오차 흡수 - trunk carve 경계가 정확히 14px에 걸린다).
const GATHER_REACH_UNITS := 14.0 * WorldCoords3D.PX_TO_UNIT
const GATHER_REACH_SLACK_UNITS := 4.0 * WorldCoords3D.PX_TO_UNIT
## 기존 deposit 도달 판정 12px / navigation_failed 완화 판정 24px.
const DEPOSIT_REACH_UNITS := 12.0 * WorldCoords3D.PX_TO_UNIT
const DESPAWN_REACH_UNITS := 24.0 * WorldCoords3D.PX_TO_UNIT
const DESPAWN_TIMEOUT := 6.0
## workplace에 work_radius 프로퍼티가 없을 때의 기본값(기존 Lumberyard 기본값).
const DEFAULT_WORK_RADIUS_PX := 192.0

const WORK_ANIM_ID := &"chop"
const CARRY_PROP_OFFSET := Vector3(0.0, 1.55, 0.0)
const CARRY_PROP_SIZE := Vector3(0.85, 0.22, 0.22)
const CARRY_PROP_COLOR := Color(0.42, 0.3, 0.18)

@export var carry_capacity: int = 5
@export var gather_interval: float = 0.6
@export var search_interval: float = 1.0

var state: State = State.IDLE
## Workplace 계약을 지원하는 Node(3D 건물 전환 전까지 duck-typed).
var workplace: Node = null
var worker_data: WorkerData = null
var target_tree: ResourceNode3D = null
var carried_resource_id: String = ""
var carried_amount: int = 0

var _final_deposit := false
var _search_timer := 0.0
var _gather_timer := 0.0
var _skip_tree: ResourceNode3D = null
var _despawn_pending := false
var _despawn_callback: Callable = Callable()
var _despawn_timeout := 0.0

var _carry_prop: MeshInstance3D = null
var _work_anim_active := false


func _ready() -> void:
	super()
	add_to_group("lumberjacks_3d")
	move_finished.connect(_on_move_finished)
	_create_carry_prop()


func _physics_process(delta: float) -> void:
	super(delta)
	_search_timer = maxf(_search_timer - delta, 0.0)
	_gather_timer = maxf(_gather_timer - delta, 0.0)
	if _despawn_pending:
		_despawn_timeout -= delta
		if _despawn_timeout <= 0.0:
			_try_despawn()
			return
	match state:
		State.IDLE:
			_tick_idle()
		State.FIND_TREE:
			_tick_find_tree()
		State.MOVE_TO_TREE:
			_tick_move_to_tree()
		State.GATHER:
			_tick_gather()
		State.RETURN_TO_LUMBERYARD:
			_tick_return()
		State.DEPOSIT:
			_tick_deposit()


## -- 상태 전이 단일 진입점. 이동 상태 진입 시 여기서 이동 명령 1건을 시작하고,
## 이동 외 상태 진입 시에는 잔여 이동 시도를 bounded하게 정리한다(명령 1건 =
## 완료 신호 최대 1건 계약 유지). --
func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.MOVE_TO_TREE:
			if not begin_move_to_node(target_tree):
				# 직전 tick과의 경계에서 대상이 사라졌으면 즉시 bounded 복귀.
				_abandon_target_tree()
				_resume_after_target_loss()
				return
		State.RETURN_TO_LUMBERYARD:
			begin_move_to(_deposit_position())
		State.GATHER:
			_gather_timer = 0.0
			_set_work_anim(true)
			cancel_move()
		_:
			_set_work_anim(false)
			cancel_move()


func _tick_idle() -> void:
	if _final_deposit and carried_amount > 0:
		if is_instance_valid(workplace):
			_set_state(State.RETURN_TO_LUMBERYARD)
		else:
			_deposit_last_carry()
		return
	if not is_instance_valid(workplace):
		workplace = null
		return
	if _search_timer > 0.0:
		return
	_skip_tree = null
	_set_state(State.FIND_TREE)


func _tick_find_tree() -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_search_timer = 0.0
		_set_state(State.IDLE)
		return
	var best := _find_nearest_tree()
	if best == null:
		_search_timer = search_interval
		_set_state(State.IDLE)
		return
	if not best.claim(self):
		# 같은 tick 내 선점 경합 방어(claim 충돌 없음 완료조건). 이번 사이클은
		# 건너뛰고 다음 검색 주기에 재시도한다.
		_search_timer = search_interval
		_set_state(State.IDLE)
		return
	_skip_tree = null
	target_tree = best
	_set_state(State.MOVE_TO_TREE)


func _tick_move_to_tree() -> void:
	if carried_amount >= carry_capacity:
		_abandon_target_tree()
		_set_state(State.RETURN_TO_LUMBERYARD)
		return
	if not is_instance_valid(target_tree) or not target_tree.can_interact():
		_abandon_target_tree()
		_resume_after_target_loss()
		return
	# 도착 판정은 move_finished 핸들러가 담당한다(base 단일 종료 규약).


func _tick_gather() -> void:
	if not is_instance_valid(target_tree) or not target_tree.can_interact():
		_abandon_target_tree()
		_resume_after_target_loss()
		return
	if _gather_timer > 0.0:
		return
	var result: Variant = target_tree.interact(self)
	if result is Dictionary:
		var gained: int = int(result.get("amount", 0))
		if gained > 0:
			carried_resource_id = String(result.get("resource_id", ""))
			carried_amount += gained
			_gather_timer = gather_interval
			_notify_carry_changed()
			if carried_amount >= carry_capacity:
				_abandon_target_tree()
				_set_state(State.RETURN_TO_LUMBERYARD)
			return
	_abandon_target_tree()
	_resume_after_target_loss()


func _tick_return() -> void:
	# 도착 판정은 move_finished 핸들러가 담당한다. workplace 소실만 감시한다.
	if not is_instance_valid(workplace):
		if _final_deposit and carried_amount > 0:
			_deposit_last_carry()
		else:
			workplace = null
			_set_state(State.IDLE)


func _tick_deposit() -> void:
	if carried_amount > 0 and carried_resource_id != "":
		VillageResources.add(carried_resource_id, carried_amount)
		carried_amount = 0
		carried_resource_id = ""
		_notify_carry_changed()
	if _despawn_pending:
		_try_despawn()
		return
	if _final_deposit:
		_final_deposit = false
		workplace = null
		_set_state(State.IDLE)
		return
	_set_state(State.FIND_TREE)


## -- 이동 종료(정확히 1회) dispatch. 2D의 tick 판정/navigation_failed 규약을
## 신호 기반으로 옮긴 것이다. --
func _on_move_finished(status: int, _final_position: Vector3) -> void:
	match state:
		State.MOVE_TO_TREE:
			match status:
				MoveStatus.ARRIVED, MoveStatus.BLOCKED, MoveStatus.STALLED:
					# BLOCKED는 trunk carve 경계의 정상 종료다. 실제 근접 거리로
					# 채집 진입 여부를 판정한다(2D navigation_failed 규약 동등).
					if is_instance_valid(target_tree) \
							and WorldCoords3D.distance_xz(global_position,
								target_tree.global_position) \
								<= GATHER_REACH_UNITS + GATHER_REACH_SLACK_UNITS:
						_set_state(State.GATHER)
						return
					_skip_tree = target_tree
					_abandon_target_tree()
					_resume_after_target_loss()
				MoveStatus.TARGET_LOST, MoveStatus.CANCELED:
					_abandon_target_tree()
					_resume_after_target_loss()
		State.RETURN_TO_LUMBERYARD:
			match status:
				MoveStatus.ARRIVED:
					if _despawn_pending and carried_amount == 0:
						_try_despawn()
						return
					_set_state(State.DEPOSIT)
				MoveStatus.BLOCKED, MoveStatus.STALLED:
					# 2D 완화 판정(24px) 동등: 반납지 인근이면 DEPOSIT,
					# 아니면 IDLE 복귀(영구 RETURN stall 금지).
					if is_instance_valid(workplace) \
							and WorldCoords3D.distance_xz(global_position,
								_deposit_position()) <= DESPAWN_REACH_UNITS:
						_set_state(State.DEPOSIT)
					else:
						_set_state(State.IDLE)
				MoveStatus.TARGET_LOST, MoveStatus.CANCELED:
					_set_state(State.IDLE)


## -- 대상 정리 헬퍼. 2D _release_tree_claim + target 해제 조합과 동일하다. --
func _abandon_target_tree() -> void:
	_release_tree_claim()
	target_tree = null


func _resume_after_target_loss() -> void:
	if carried_amount > 0:
		_set_state(State.RETURN_TO_LUMBERYARD)
	else:
		_set_state(State.FIND_TREE)


func _release_tree_claim() -> void:
	if is_instance_valid(target_tree) and target_tree.has_method("release"):
		target_tree.release(self)


func _find_nearest_tree() -> ResourceNode3D:
	if not is_instance_valid(workplace):
		return null
	var origin: Vector3 = WorldCoords3D.flatten(workplace.global_position)
	var radius_sq: float = _work_radius_units() * _work_radius_units()
	var best: ResourceNode3D = null
	var best_dist_sq := INF
	for node in get_tree().get_nodes_in_group("resource_nodes_3d"):
		var resource_node := node as ResourceNode3D
		if resource_node == null or not is_instance_valid(resource_node):
			continue
		if resource_node == _skip_tree:
			continue
		if resource_node.is_claimed_by_other(self):
			continue
		if resource_node.resource_id != "wood" or not resource_node.can_interact():
			continue
		var d := origin.distance_squared_to(
			WorldCoords3D.flatten(resource_node.global_position))
		if d > radius_sq:
			continue
		if d < best_dist_sq:
			best = resource_node
			best_dist_sq = d
	return best


func _work_radius_units() -> float:
	if is_instance_valid(workplace):
		var radius_px: Variant = workplace.get("work_radius")
		if radius_px != null and (radius_px is float or radius_px is int):
			return float(radius_px) * WorldCoords3D.PX_TO_UNIT
	return DEFAULT_WORK_RADIUS_PX * WorldCoords3D.PX_TO_UNIT


## 반납 위치: "DepositPoint" Node3D 자식 우선, 없으면 workplace origin(지면).
func _deposit_position() -> Vector3:
	if is_instance_valid(workplace) and workplace is Node3D:
		var marker := workplace.get_node_or_null("DepositPoint")
		if marker is Node3D:
			return WorldCoords3D.flatten(marker.global_position)
		return WorldCoords3D.flatten((workplace as Node3D).global_position)
	return global_position


## -- TASK-011-5 규약 유지: 배치 해제 시 마지막 자원 반납 후 IDLE. --
func _on_unassigned() -> void:
	_release_tree_claim()
	target_tree = null
	if carried_amount > 0:
		_final_deposit = true
		_set_state(State.RETURN_TO_LUMBERYARD)
		return
	_final_deposit = false
	workplace = null
	_set_state(State.IDLE)


func _on_assigned(building: Node) -> void:
	workplace = building
	_final_deposit = false
	_search_timer = 0.0


## TASK-011-5 규약 유지: carrying 중이면 마지막 1회 deposit 후 복귀, 아니면
## 즉시 시설 복귀 후 despawn. Navigation 문제로 영구 정지하지 않도록 bounded
## timeout을 둔다.
func begin_despawn(callback: Callable) -> void:
	_despawn_pending = true
	_despawn_callback = callback
	_despawn_timeout = DESPAWN_TIMEOUT
	_release_tree_claim()
	target_tree = null
	_skip_tree = null
	if carried_amount > 0:
		_final_deposit = true
		if is_instance_valid(workplace):
			_set_state(State.RETURN_TO_LUMBERYARD)
		else:
			_deposit_last_carry()
			_try_despawn()
		return
	_final_deposit = false
	if is_instance_valid(workplace):
		_set_state(State.RETURN_TO_LUMBERYARD)
	else:
		_try_despawn()


func _try_despawn() -> void:
	_despawn_pending = false
	if _despawn_callback.is_valid():
		var cb := _despawn_callback
		_despawn_callback = Callable()
		cb.call()


func _deposit_last_carry() -> void:
	if carried_amount > 0 and carried_resource_id != "":
		VillageResources.add(carried_resource_id, carried_amount)
		carried_amount = 0
		carried_resource_id = ""
		_notify_carry_changed()
	_final_deposit = false
	workplace = null
	_set_state(State.IDLE)


## -- Visual hooks(VIS 교체 슬롯). asset 부재와 무관하게 항상 발화한다. --
func _create_carry_prop() -> void:
	_carry_prop = MeshInstance3D.new()
	_carry_prop.name = "CarryProp"
	var box := BoxMesh.new()
	box.size = CARRY_PROP_SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CARRY_PROP_COLOR
	box.material = mat
	_carry_prop.mesh = box
	_carry_prop.position = CARRY_PROP_OFFSET
	_carry_prop.visible = false
	get_visual().add_child(_carry_prop)


func _notify_carry_changed() -> void:
	var attached := carried_amount > 0
	if _carry_prop != null:
		_carry_prop.visible = attached
	carry_prop_changed.emit(attached, carried_resource_id)


func _set_work_anim(active: bool) -> void:
	if _work_anim_active == active:
		return
	_work_anim_active = active
	if active:
		work_anim_started.emit(WORK_ANIM_ID)
	else:
		work_anim_stopped.emit(WORK_ANIM_ID)


## -- 조회 API(기존 lumberjack.gd 계약 유지). --
func is_gathering() -> bool:
	return state == State.GATHER


func get_state_name() -> String:
	return STATE_NAMES.get(state, "?")


func get_workplace() -> Node:
	return workplace


func is_assigned() -> bool:
	return is_instance_valid(workplace)
