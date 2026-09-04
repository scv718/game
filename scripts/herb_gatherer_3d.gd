extends WorkerActor3D
class_name HerbGatherer3D

## TASK-021-1 HerbGatherer FSM 3D wiring.
## TASK-021 요구 "Worker 채집이 필요하면 기존 Worker pattern 최소 확장"을 따르는
## 최소 확장 worker다. 기존 lumberjack_3d.gd(WorkerActor3D 상속 FSM)의 상태 전이
## 의미와 resource claim/interact/deposit 규약을 그대로 유지한 채, 대상 자원만
## wood에서 herb(야생 약초)로 바꾼 신규 파일이다.
##
## - 상태 의미: IDLE -> FIND_HERB -> MOVE_TO_HERB -> GATHER -> RETURN_TO_WORKPLACE
##   -> DEPOSIT. lumberjack_3d의 1:1 대응이며 생산량/운반량/carry 규약 불변.
## - resource claim 규약(ResourceNode3D.claim/release/is_claimed_by_other) 불변.
## - 반납은 VillageResources.add("herb", carried) (acquire stock - 기존 deposit
##   계약 그대로). herb 워크플레이스 건물은 TASK-021-2/038(자동화)에서 연결되며,
##   여기서는 기존 duck-typed Workplace 계약(assign/unassign + DepositPoint)만
##   소비한다.
## - 대상 탐색은 "resource_nodes_3d" 그룹에서 resource_id == "herb"인 노드만
##   선택한다(lumberjack의 wood 필터와 동일 패턴).
## - Player Avatar 직접 채집 없음: herb 노드의 is_selectable() == false 정책이
##   마우스 직접 채집을 차단하므로 이 worker가 유일한 획득 경로다.
## - unassign 시 carrying 중이면 마지막 1회 deposit 후 해제(_final_deposit),
##   despawn은 시설 복귀 후 callback(DESPAWN_TIMEOUT bounded guard) - 모두 기존
##   lumberjack 규약과 동일.

signal work_anim_started(action: StringName)
signal work_anim_stopped(action: StringName)
signal carry_prop_changed(attached: bool, resource_id: String)

enum State { IDLE, FIND_HERB, MOVE_TO_HERB, GATHER, RETURN_TO_WORKPLACE, DEPOSIT }

const STATE_NAMES := {
	State.IDLE: "IDLE",
	State.FIND_HERB: "FIND",
	State.MOVE_TO_HERB: "MOVE",
	State.GATHER: "GATHER",
	State.RETURN_TO_WORKPLACE: "RETURN",
	State.DEPOSIT: "DEPOSIT",
}

## lumberjack_3d.gd GATHER_REACH(14px)+SLACK(4px) 비율 보존값(herb는 trunk carve
## 경계가 없어 접근은 도달로 끝난다. 여유는 BLOCKED 종점 오차 흡수용).
const GATHER_REACH_UNITS := 14.0 * WorldCoords3D.PX_TO_UNIT
const GATHER_REACH_SLACK_UNITS := 4.0 * WorldCoords3D.PX_TO_UNIT
const DEPOSIT_REACH_UNITS := 12.0 * WorldCoords3D.PX_TO_UNIT
const DESPAWN_REACH_UNITS := 24.0 * WorldCoords3D.PX_TO_UNIT
const DESPAWN_TIMEOUT := 6.0
const DEFAULT_WORK_RADIUS_PX := 192.0

const WORK_ANIM_ID := &"gather"
const CARRY_PROP_OFFSET := Vector3(0.0, 1.4, 0.0)
const CARRY_PROP_SIZE := Vector3(0.5, 0.5, 0.5)
const CARRY_PROP_COLOR := Color(0.32, 0.62, 0.28)

@export var carry_capacity: int = 5
@export var gather_interval: float = 0.6
@export var search_interval: float = 1.0

var state: State = State.IDLE
## Workplace 계약을 지원하는 Node(3D 건물 전환 전까지 duck-typed).
var workplace: Node = null
var worker_data: WorkerData = null
var target_herb: ResourceNode3D = null
var carried_resource_id: String = ""
var carried_amount: int = 0

var _final_deposit := false
var _search_timer := 0.0
var _gather_timer := 0.0
var _skip_herb: ResourceNode3D = null
var _despawn_pending := false
var _despawn_callback: Callable = Callable()
var _despawn_timeout := 0.0

var _carry_prop: MeshInstance3D = null
var _work_anim_active := false


func _ready() -> void:
	super()
	add_to_group("herb_gatherers_3d")
	add_to_group("workers_3d")
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
		State.FIND_HERB:
			_tick_find_herb()
		State.MOVE_TO_HERB:
			_tick_move_to_herb()
		State.GATHER:
			_tick_gather()
		State.RETURN_TO_WORKPLACE:
			_tick_return()
		State.DEPOSIT:
			_tick_deposit()


## -- 상태 전이 단일 진입점. 이동 상태 진입 시 이동 명령 1건을 시작하고, 이동 외
## 상태 진입 시 잔여 이동 시도를 bounded하게 정리한다(명령 1건 = 완료 신호 최대
## 1건 계약 유지). --
func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.MOVE_TO_HERB:
			if not begin_move_to_node(target_herb):
				_abandon_target_herb()
				_resume_after_target_loss()
				return
		State.RETURN_TO_WORKPLACE:
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
			_set_state(State.RETURN_TO_WORKPLACE)
		else:
			_deposit_last_carry()
		return
	if not is_instance_valid(workplace):
		workplace = null
		return
	if _search_timer > 0.0:
		return
	_skip_herb = null
	_set_state(State.FIND_HERB)


func _tick_find_herb() -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_search_timer = 0.0
		_set_state(State.IDLE)
		return
	var best := _find_nearest_herb()
	if best == null:
		_search_timer = search_interval
		_set_state(State.IDLE)
		return
	if not best.claim(self):
		_search_timer = search_interval
		_set_state(State.IDLE)
		return
	_skip_herb = null
	target_herb = best
	_set_state(State.MOVE_TO_HERB)


func _tick_move_to_herb() -> void:
	if carried_amount >= carry_capacity:
		_abandon_target_herb()
		_set_state(State.RETURN_TO_WORKPLACE)
		return
	if not is_instance_valid(target_herb) or not target_herb.can_interact():
		_abandon_target_herb()
		_resume_after_target_loss()
		return


func _tick_gather() -> void:
	if not is_instance_valid(target_herb) or not target_herb.can_interact():
		_abandon_target_herb()
		_resume_after_target_loss()
		return
	if _gather_timer > 0.0:
		return
	var result: Variant = target_herb.interact(self)
	if result is Dictionary:
		var gained: int = int(result.get("amount", 0))
		if gained > 0:
			carried_resource_id = String(result.get("resource_id", ""))
			carried_amount += gained
			_gather_timer = gather_interval
			_notify_carry_changed()
			if carried_amount >= carry_capacity:
				_abandon_target_herb()
				_set_state(State.RETURN_TO_WORKPLACE)
			return
	_abandon_target_herb()
	_resume_after_target_loss()


func _tick_return() -> void:
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
	_set_state(State.FIND_HERB)


func _on_move_finished(status: int, _final_position: Vector3) -> void:
	match state:
		State.MOVE_TO_HERB:
			match status:
				MoveStatus.ARRIVED, MoveStatus.BLOCKED, MoveStatus.STALLED:
					if is_instance_valid(target_herb) \
							and WorldCoords3D.distance_xz(global_position,
								target_herb.global_position) \
								<= GATHER_REACH_UNITS + GATHER_REACH_SLACK_UNITS:
						_set_state(State.GATHER)
						return
					_skip_herb = target_herb
					_abandon_target_herb()
					_resume_after_target_loss()
				MoveStatus.TARGET_LOST, MoveStatus.CANCELED:
					_abandon_target_herb()
					_resume_after_target_loss()
		State.RETURN_TO_WORKPLACE:
			match status:
				MoveStatus.ARRIVED:
					if _despawn_pending and carried_amount == 0:
						_try_despawn()
						return
					_set_state(State.DEPOSIT)
				MoveStatus.BLOCKED, MoveStatus.STALLED:
					if is_instance_valid(workplace) \
							and WorldCoords3D.distance_xz(global_position,
								_deposit_position()) <= DESPAWN_REACH_UNITS:
						_set_state(State.DEPOSIT)
					else:
						_set_state(State.IDLE)
				MoveStatus.TARGET_LOST, MoveStatus.CANCELED:
					_set_state(State.IDLE)


func _abandon_target_herb() -> void:
	_release_herb_claim()
	target_herb = null


func _resume_after_target_loss() -> void:
	if carried_amount > 0:
		_set_state(State.RETURN_TO_WORKPLACE)
	else:
		_set_state(State.FIND_HERB)


func _release_herb_claim() -> void:
	if is_instance_valid(target_herb) and target_herb.has_method("release"):
		target_herb.release(self)


func _find_nearest_herb() -> ResourceNode3D:
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
		if resource_node == _skip_herb:
			continue
		if resource_node.is_claimed_by_other(self):
			continue
		if resource_node.resource_id != "herb" or not resource_node.can_interact():
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


func _deposit_position() -> Vector3:
	if is_instance_valid(workplace) and workplace is Node3D:
		var marker := workplace.get_node_or_null("DepositPoint")
		if marker is Node3D:
			return WorldCoords3D.flatten((marker as Node3D).global_position)
		return WorldCoords3D.flatten((workplace as Node3D).global_position)
	return global_position


## TASK-011-5 규약 유지: 배치 해제 시 마지막 자원 반납 후 IDLE.
func _on_unassigned() -> void:
	_release_herb_claim()
	target_herb = null
	if carried_amount > 0:
		_final_deposit = true
		_set_state(State.RETURN_TO_WORKPLACE)
		return
	_final_deposit = false
	workplace = null
	_set_state(State.IDLE)


func _on_assigned(building: Node) -> void:
	workplace = building
	_final_deposit = false
	_search_timer = 0.0


func begin_despawn(callback: Callable) -> void:
	_despawn_pending = true
	_despawn_callback = callback
	_despawn_timeout = DESPAWN_TIMEOUT
	_release_herb_claim()
	target_herb = null
	_skip_herb = null
	if carried_amount > 0:
		_final_deposit = true
		if is_instance_valid(workplace):
			_set_state(State.RETURN_TO_WORKPLACE)
		else:
			_deposit_last_carry()
			_try_despawn()
		return
	_final_deposit = false
	if is_instance_valid(workplace):
		_set_state(State.RETURN_TO_WORKPLACE)
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


func _create_carry_prop() -> void:
	_carry_prop = MeshInstance3D.new()
	_carry_prop.name = "CarryProp"
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CARRY_PROP_COLOR
	sphere.material = mat
	_carry_prop.mesh = sphere
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
