extends WorkerActor3D
class_name Farmer3D

## TASK-019-2 Farmer FSM 3D.
## 기존 Worker Assignment framework(WorkerActor3D + Workplace3D + WorkerRoster) 위에
## 얹은 Farmer 직업용 FSM이다. Farmer는 별도 범용 AI framework를 만들지 않으며,
## 기존 lumberjack_3d.gd(miner_3d.gd)의 상태 전이 의미를 그대로 따른다.
##
## 상태 의미 보존(기존 Worker convention 1:1 대응):
##   IDLE -> MOVE_TO_WORK -> WORK(HARVEST) -> RETURN_TO_FARM -> DEPOSIT
##   - 이동은 begin_move_to(work point / deposit point) 단일 명령 + move_finished
##     신호(정확히 1회)로 다음 상태를 결정한다(WorkerActor3D 단일 종료 규약).
##   - WORK 상태는 harvest cycle(harvest_interval)마다 carry를 채운다. carry가
##     차면 RETURN_TO_FARM -> DEPOSIT로 crop 자원을 VillageResources에 반납한다
##     (lumberjack의 GATHER -> RETURN -> DEPOSIT carry 규약과 동일).
##   - 작업 위치는 miner 계약과 동일하게 workplace.get_work_point_for(self) ->
##     "WorkPoint"/"WorkPoint2" Marker3D -> workplace origin 순으로 해석한다.
##   - 반납 위치는 lumberjack 계약과 동일하게 "DepositPoint" Node3D 자식 ->
##     workplace origin(지면 flatten) 순으로 해석한다.
##   - unassign 시 carrying 중이면 마지막 1회 deposit 후 해제(_final_deposit),
##     아니면 즉시 IDLE. despawn은 시설 복귀 후 callback(DESPAWN_TIMEOUT
##     bounded guard 유지 - TASK-011-5 규약).
##   - BLOCKED/STALLED 종료는 2D navigation 미도달 -> IDLE 폴백과 동등한
##     bounded 처리다(영구 MOVE stall 금지).
##
## workplace 연결(BLD duck-typed 계약):
##   - workplace는 Workplace 계약(assign_worker/unassign_worker/_on_assigned/
##     _on_unassigned/spawn·despawn_worker_actor)을 지원하는 Node면 충분하다.
##
## crop 생산(TASK-019-3 선행 범위):
##   - 실제 crop node(growth/harvest)는 TASK-019-3에서 연결된다. 여기서는
##     정적 work point에서의 반복 harvest cycle로 캡슐화하고 생산 자원은
##     crop_resource_id("crop")로 VillageResources에 직접 반납한다.
##     수치(carry_capacity/harvest_interval)는 DESIGN_TUNING.
##
## Visual hook(기능 상태와 분리 - REQ):
##   - work_anim_started/stopped(&"work"): WORK 진입/이탈에서 발화한다.
##     Animation Library의 farming/work 동작(Farm_Harvest 등)은 VIS 도메인이
##     "work" action으로 연결한다. 실제 animation asset이 없어도 신호는 발화하며
##     기능 상태는 지연되지 않는다.
##   - carry_prop_changed(attached, resource_id): 운반 prop attach/detach 시점.
##     기본 표현은 Visual child 아래 placeholder CarryProp mesh 가시성 토글뿐이다.

signal work_anim_started(action: StringName)
signal work_anim_stopped(action: StringName)
signal carry_prop_changed(attached: bool, resource_id: String)

enum State { IDLE, MOVE_TO_WORK, WORK, RETURN_TO_FARM, DEPOSIT }

const STATE_NAMES := {
	State.IDLE: "IDLE",
	State.MOVE_TO_WORK: "MOVE",
	State.WORK: "WORK",
	State.RETURN_TO_FARM: "RETURN",
	State.DEPOSIT: "DEPOSIT",
}

## 기존 miner WORK_APPROACH_DISTANCE(12px) 비율 보존값.
const WORK_REACH_UNITS := 12.0 * WorldCoords3D.PX_TO_UNIT
## 기존 lumberjack deposit 도달 판정 12px / navigation_failed 완화 판정 24px.
const DEPOSIT_REACH_UNITS := 12.0 * WorldCoords3D.PX_TO_UNIT
const DESPAWN_REACH_UNITS := 24.0 * WorldCoords3D.PX_TO_UNIT
const DESPAWN_TIMEOUT := 6.0

const WORK_ANIM_ID := &"work"
const CARRY_PROP_OFFSET := Vector3(0.0, 1.55, 0.0)
const CARRY_PROP_SIZE := Vector3(0.55, 0.55, 0.35)
const CARRY_PROP_COLOR := Color(0.82, 0.7, 0.25)

@export var carry_capacity: int = 5
@export var harvest_interval: float = 0.8
@export var crop_resource_id: String = "crop"

var state: State = State.IDLE
## Workplace 계약을 지원하는 Node(duck-typed).
var workplace: Node = null
var worker_data: WorkerData = null
var carried_amount: int = 0
## TASK-019-3: 현재 운반 중인 raw ingredient id(수확한 crop에서 비롯).
var carried_resource_id: String = ""

## TASK-019-3: 수확 대상 crop node(현재 claim 중).
var target_crop: Node = null

var _final_deposit := false
var _harvest_timer := 0.0
var _despawn_pending := false
var _despawn_callback: Callable = Callable()
var _despawn_timeout := 0.0

var _carry_prop: MeshInstance3D = null
var _work_anim_active := false


func _ready() -> void:
	super()
	add_to_group("farmers_3d")
	move_finished.connect(_on_move_finished)
	_create_carry_prop()


func _physics_process(delta: float) -> void:
	super(delta)
	_harvest_timer = maxf(_harvest_timer - delta, 0.0)
	if _despawn_pending:
		_despawn_timeout -= delta
		if _despawn_timeout <= 0.0:
			_try_despawn()
			return
	match state:
		State.IDLE:
			_tick_idle()
		State.MOVE_TO_WORK:
			_tick_move_to_work()
		State.WORK:
			_tick_work()
		State.RETURN_TO_FARM:
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
		State.MOVE_TO_WORK:
			begin_move_to(_get_work_point_position())
		State.RETURN_TO_FARM:
			begin_move_to(_get_deposit_position())
		State.WORK:
			_harvest_timer = harvest_interval
			_set_work_anim(true)
			cancel_move()
		_:
			_set_work_anim(false)
			cancel_move()


func _tick_idle() -> void:
	if _final_deposit and carried_amount > 0:
		if is_instance_valid(workplace):
			_set_state(State.RETURN_TO_FARM)
		else:
			_deposit_last_carry()
		return
	if not is_instance_valid(workplace):
		workplace = null
		return


func _tick_move_to_work() -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_set_state(State.IDLE)
		return
	# 도착 판정은 move_finished 핸들러가 담당한다(base 단일 종료 규약).


func _tick_work() -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_release_crop()
		_harvest_timer = 0.0
		_set_state(State.IDLE)
		return
	if _harvest_timer > 0.0:
		return
	if not _acquire_harvest_target():
		# 수확 가능한 crop이 아직 없음(성장 중). harvest_interval만큼 대기 후 재시도.
		_harvest_timer = harvest_interval
		return
	var result: Variant = target_crop.interact(self)
	_release_crop()
	if result is Dictionary:
		var gained: int = int(result.get("amount", 0))
		if gained > 0:
			carried_resource_id = String(result.get("resource_id", crop_resource_id))
			carried_amount += gained
			_harvest_timer = harvest_interval
			_notify_carry_changed()
			if carried_amount >= carry_capacity:
				_set_state(State.RETURN_TO_FARM)


## TASK-019-3: workplace(Farm3D)의 READY crop 1개를 claim한다. workplace가 crop
## 관리 계약(get_crops/find_harvestable_crop)을 지원하지 않으면 기존 static harvest
## fallback(crop_resource_id 직접)을 사용한다.
func _acquire_harvest_target() -> bool:
	_release_crop()
	if is_instance_valid(workplace) and workplace.has_method("find_harvestable_crop"):
		var crop: Variant = workplace.find_harvestable_crop(self)
		if crop is CropNode3D and is_instance_valid(crop) and crop.claim(self):
			target_crop = crop
			return true
		return false
	# static fallback: 실제 crop node 없이 바로 1단위 생산(lumberjack 없는 시설 대비).
	return true


func _release_crop() -> void:
	if is_instance_valid(target_crop) and target_crop.has_method("release"):
		target_crop.release(self)
	target_crop = null


func _tick_return() -> void:
	# 도착 판정은 move_finished 핸들러가 담당한다. workplace 소실만 감시한다.
	if not is_instance_valid(workplace):
		if _final_deposit and carried_amount > 0:
			_deposit_last_carry()
		else:
			workplace = null
			_set_state(State.IDLE)


func _tick_deposit() -> void:
	if carried_amount > 0:
		VillageResources.add(carried_resource_id if carried_resource_id != "" else crop_resource_id, carried_amount)
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
	_set_state(State.MOVE_TO_WORK)


## -- 이동 종료(정확히 1회) dispatch. 2D의 tick 판정/navigation_failed 규약을
## 신호 기반으로 옮긴 것이다. --
func _on_move_finished(status: int, _final_position: Vector3) -> void:
	match state:
		State.MOVE_TO_WORK:
			match status:
				MoveStatus.ARRIVED, MoveStatus.BLOCKED, MoveStatus.STALLED:
					# BLOCKED/STALLED는 부분 경로 소진의 정상 종료다. 실제 근접
					# 거리로 작업 진입 여부를 판정한다(2D navigation_failed 규약
					# 동등). 도달 불가 work point는 IDLE로 bounded 복귀한다.
					if is_instance_valid(workplace) \
							and WorldCoords3D.distance_xz(global_position,
								_get_work_point_position()) <= WORK_REACH_UNITS:
						_set_state(State.WORK)
					else:
						_set_state(State.IDLE)
				MoveStatus.TARGET_LOST, MoveStatus.CANCELED:
					_set_state(State.IDLE)
		State.RETURN_TO_FARM:
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
								_get_deposit_position()) <= DESPAWN_REACH_UNITS:
						_set_state(State.DEPOSIT)
					else:
						_set_state(State.IDLE)
				MoveStatus.TARGET_LOST, MoveStatus.CANCELED:
					_set_state(State.IDLE)


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


## 반납 위치: "DepositPoint" Node3D 자식 우선, 없으면 workplace origin(지면).
func _get_deposit_position() -> Vector3:
	if is_instance_valid(workplace) and workplace is Node3D:
		var marker := workplace.get_node_or_null("DepositPoint")
		if marker is Node3D:
			return WorldCoords3D.flatten(marker.global_position)
		return WorldCoords3D.flatten((workplace as Node3D).global_position)
	return global_position


## -- TASK-011-5 규약 유지: 배치 해제 시 마지막 자원 반납 후 IDLE. --
func _on_unassigned() -> void:
	_release_crop()
	if carried_amount > 0:
		_final_deposit = true
		if is_instance_valid(workplace):
			_set_state(State.RETURN_TO_FARM)
		else:
			_deposit_last_carry()
		return
	_final_deposit = false
	workplace = null
	_set_state(State.IDLE)


func _on_assigned(building: Node) -> void:
	workplace = building
	_final_deposit = false
	_harvest_timer = 0.0
	_set_state(State.MOVE_TO_WORK)


## TASK-011-5 규약 유지: carrying 중이면 마지막 1회 deposit 후 복귀, 아니면
## 즉시 시설 복귀 후 despawn. Navigation 문제로 영구 정지하지 않도록 bounded
## timeout을 둔다.
func begin_despawn(callback: Callable) -> void:
	_despawn_pending = true
	_despawn_callback = callback
	_despawn_timeout = DESPAWN_TIMEOUT
	_release_crop()
	if carried_amount > 0:
		_final_deposit = true
		if is_instance_valid(workplace):
			_set_state(State.RETURN_TO_FARM)
		else:
			_deposit_last_carry()
			_try_despawn()
		return
	_final_deposit = false
	if is_instance_valid(workplace):
		_set_state(State.RETURN_TO_FARM)
	else:
		_try_despawn()


func _try_despawn() -> void:
	_despawn_pending = false
	if _despawn_callback.is_valid():
		var cb := _despawn_callback
		_despawn_callback = Callable()
		cb.call()


func _deposit_last_carry() -> void:
	if carried_amount > 0:
		VillageResources.add(carried_resource_id if carried_resource_id != "" else crop_resource_id, carried_amount)
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
	carry_prop_changed.emit(attached, crop_resource_id)


func _set_work_anim(active: bool) -> void:
	if _work_anim_active == active:
		return
	_work_anim_active = active
	if active:
		work_anim_started.emit(WORK_ANIM_ID)
	else:
		work_anim_stopped.emit(WORK_ANIM_ID)


## -- 조회 API(기존 worker 계약 유지). --
func is_gathering() -> bool:
	return state == State.WORK


func get_state_name() -> String:
	return STATE_NAMES.get(state, "?")


func get_workplace() -> Node:
	return workplace


func is_assigned() -> bool:
	return is_instance_valid(workplace)
