extends CharacterBody2D
class_name MercenaryActor

## TASK-014-4 Mercenary Auto Combat FSM.
## NIGHT spawn 위치(지정 방어 구역 Gate 안쪽 Rally Space / fallback RallyPoint)를
## defense_point로 삼아, 지정 구역 근처의 살아 있는 Enemy를 deterministic priority로
## 자동 탐색(ACQUIRE_TARGET) → 추격(MOVE_TO_TARGET) → 공격(ATTACK)한다.
## 과도하게 멀리 추격하면 defense_point로 복귀(RETURN_TO_DEFENSE_ZONE)하고,
## target이 죽거나 사라지면 새 target을 탐색한다. Enemy의 공격으로 HP가 0이 되면
## 사망(DEAD) 처리해 MercenaryData.alive=false, 그룹 제외, 월드에서 제거한다.
## Player는 절대 target/damage 대상이 되지 않는다(mercenaries 그룹만 탐색).
## 복잡한 Utility/BehaviorTree는 쓰지 않는 예측 가능한 상태 머신으로 구현한다.
##
## TASK-015-4 전술 명령: REGROUP은 현재 방어 구역 rally(anchor)로 복귀하고 이동 중
## 새 target 획득을 억제하며 도착 후 일반 방어 AI(재탐색)로 복귀한다. RETREAT은
## 중앙 Village/safe rally로 후퇴하고 이동 중·도착 후에도 공격/target 획득을 중지한 채
## 도착 후 HOLD한다. teleport는 없으며 무적도 아니다(후퇴 중에도 적 공격으로 사망 가능).
## 이후 새 DEFENSE_ZONE 명령으로 일반 방어 AI에 정상 복귀한다.

enum MercState {
	IDLE,
	ACQUIRE_TARGET,
	MOVE_TO_TARGET,
	ATTACK,
	RETURN_TO_DEFENSE_ZONE,
	REGROUP,
	RETREAT,
	DEAD,
}

const ATTACK_RANGE := 26.0
const CHASE_RETURN_DISTANCE := 180.0
const REACH_DISTANCE := 12.0
const STUCK_TIMEOUT := 2.0
## TASK-015-5: Focus Target 추격 중 목표에 도달하지 못하면(stuck) 영구 chase를
## 방지하기 위해 이 시간 동안 이동이 없으면 focus를 해제한다.
const FOCUS_STUCK_TIMEOUT := 2.0

var merc_data: MercenaryData = null
var current_hp: int = 0
var alive := true
var state: MercState = MercState.IDLE
var defense_point := Vector2.ZERO

var _target: Node = null
var _attack_cd := 0.0
var _stuck_timer := 0.0
var _last_move_pos := Vector2.ZERO
var _retreat_point := Vector2.ZERO
## TASK-015-5: 전술 Focus Target. 플레이어가 선택한 우선 target(살아 있는 Enemy).
## defense zone 자동 전투보다 우선하지만 RETREAT/REGROUP/DEAD보다는 낮은 우선순위다.
var _focus_target: Node = null
var _focus_stuck_timer := 0.0
var _last_focus_pos := Vector2.ZERO

## TASK-014-6 사망 처리에서 재사용.
signal died(mercenary: Node)

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	add_to_group("mercenaries")
	if merc_data != null:
		current_hp = merc_data.max_hp
	if defense_point == Vector2.ZERO:
		defense_point = global_position


func _physics_process(delta: float) -> void:
	if not alive or state == MercState.DEAD:
		velocity = Vector2.ZERO
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	match state:
		MercState.IDLE:
			velocity = Vector2.ZERO
			_acquire_target()
		MercState.ACQUIRE_TARGET:
			_acquire_target()
		MercState.MOVE_TO_TARGET:
			_tick_chase(delta)
		MercState.ATTACK:
			_tick_attack(delta)
		MercState.RETURN_TO_DEFENSE_ZONE:
			_tick_return(delta)
		MercState.REGROUP:
			_tick_regroup(delta)
		MercState.RETREAT:
			_tick_retreat(delta)
		MercState.DEAD:
			velocity = Vector2.ZERO


## TASK-015-5: target을 획득한다. 우선순위는 FOCUS TARGET(4) > defense zone
## 자동 전투(5)다. 유효한 focus target이 있으면 그것을 우선 target으로 삼고,
## 없거나 invalid(사망/freed)면 기존 defense zone 자동 전투로 되돌아간다.
func _acquire_target() -> void:
	_state_to(MercState.ACQUIRE_TARGET)
	if _focus_target_invalid():
		_focus_target = null
		_focus_stuck_timer = 0.0
	_target = _resolve_priority_target()
	if _target != null:
		_state_to(MercState.MOVE_TO_TARGET)
	else:
		_state_to(MercState.IDLE)


## TASK-015-5: 우선 순위에 따른 target 후보 결정.
## focus target이 살아 있고 유효하면 우선하고, 아니면 defense zone 자동 전투
## (CHASE_RETURN_DISTANCE 이내에서 defense_point에 가장 가까운 Enemy)를 선택한다.
func _resolve_priority_target() -> Node:
	if _focus_target != null and is_instance_valid(_focus_target) \
			and _focus_target.get("alive") != false:
		return _focus_target
	var best: Node = null
	var best_score := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.get("alive") == false:
			continue
		var dist_from_zone: float = e.global_position.distance_to(defense_point)
		if dist_from_zone > CHASE_RETURN_DISTANCE:
			continue
		if dist_from_zone < best_score:
			best_score = dist_from_zone
			best = e
	return best


func _tick_chase(delta: float) -> void:
	if _target_invalid():
		_acquire_target()
		return
	if _in_attack_range():
		_state_to(MercState.ATTACK)
		return
	# TASK-015-5: focus target을 추격 중이면 defense zone 거리 제한을 우선 대상에서
	# 제외하되, 도달 불가능(stuck)이면 영구 chase 없이 focus를 해제하고 기본 AI로 복귀한다.
	if _target == _focus_target:
		if _focus_chase_stuck(delta):
			_focus_target = null
			_focus_stuck_timer = 0.0
			_acquire_target()
			return
	elif global_position.distance_to(defense_point) > CHASE_RETURN_DISTANCE:
		_state_to(MercState.RETURN_TO_DEFENSE_ZONE)
		return
	_move_towards(_target.global_position, delta)


func _tick_attack(delta: float) -> void:
	if _target_invalid():
		_acquire_target()
		return
	if not _in_attack_range():
		_state_to(MercState.MOVE_TO_TARGET)
		return
	velocity = Vector2.ZERO
	if _attack_cd <= 0.0:
		if _target.has_method("take_damage"):
			_target.take_damage(_get_attack_damage())
		_attack_cd = _get_attack_interval()


func _tick_return(delta: float) -> void:
	if _reached_defense_point():
		_acquire_target()
		return
	_move_towards(defense_point, delta)


## TASK-015-4: REGROUP 상태. 현재 방어 구역 rally(anchor)로 복귀한다.
## 이동 중에는 새 target을 획득하지 않고(잠시 억제), 도착하면 일반 방어 AI(재탐색)로
## 복귀해 자동 전투를 재개한다.
func _tick_regroup(delta: float) -> void:
	if _reached_defense_point():
		_acquire_target()
		return
	_move_towards(defense_point, delta)


## TASK-015-4: RETREAT 상태. 중앙 Village/safe rally로 후퇴한다.
## 이동 중/도착 후에도 공격하지 않고 target도 획득하지 않는다(공격 중지).
## 도착 후에는 HOLD한다. 무적이 아니므로 도중 적의 공격으로 사망할 수 있다.
func _tick_retreat(delta: float) -> void:
	if _reached_retreat_point():
		velocity = Vector2.ZERO
		return
	_move_towards(_retreat_point, delta)


func _move_towards(dest: Vector2, delta: float) -> void:
	_nav_agent.target_position = dest
	var reached := global_position.distance_to(dest) <= REACH_DISTANCE \
		or (_nav_agent.is_target_reachable() and _nav_agent.is_target_reached())
	if reached:
		velocity = Vector2.ZERO
		return
	if _check_stuck(delta):
		velocity = Vector2.ZERO
		return
	var next_pos := _nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_pos) * _get_move_speed()
	move_and_slide()


## Enemy 공격 등으로부터 HP를 감소시킨다. 0 이하가 되면 사망 처리한다.
## Player는 공격 대상이 아니므로 이 경로로 피격되지 않는다.
func take_damage(amount: int) -> void:
	if not alive or amount <= 0:
		return
	current_hp = maxi(0, current_hp - amount)
	if current_hp <= 0:
		die()


## 사망 처리. MercenaryData.alive=false 반영, 그룹 제외, died signal 후 월드에서 제거.
## (다음 DAY/NIGHT 자동 부활 금지는 roster의 get_alive() 기반 spawn이 처리)
func die() -> void:
	if not alive or state == MercState.DEAD:
		return
	alive = false
	state = MercState.DEAD
	if merc_data != null:
		merc_data.alive = false
	remove_from_group("mercenaries")
	died.emit(self)
	queue_free()


func _in_attack_range() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	return global_position.distance_to(_target.global_position) <= ATTACK_RANGE


func _reached_defense_point() -> bool:
	return global_position.distance_to(defense_point) <= REACH_DISTANCE


## TASK-015-4: RETREAT 목표(중앙 safe rally)에 도착했는지 판정.
func _reached_retreat_point() -> bool:
	return global_position.distance_to(_retreat_point) <= REACH_DISTANCE


func _target_invalid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	if _target.get("alive") == false:
		return true
	return false


## TASK-015-5: focus target이 invalid(사망/freed)인지 판정.
func _focus_target_invalid() -> bool:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return true
	if _focus_target.get("alive") == false:
		return true
	return false


## TASK-015-5: focus target 추격 중 도달 불가능(이동 없음)을 감지한다.
## 일정 시간 이동이 없으면 unreachable로 판정해 영구 chase를 방지한다.
func _focus_chase_stuck(delta: float) -> bool:
	if global_position.distance_to(_last_focus_pos) < 2.0:
		_focus_stuck_timer += delta
		return _focus_stuck_timer >= FOCUS_STUCK_TIMEOUT
	_last_focus_pos = global_position
	_focus_stuck_timer = 0.0
	return false


func _check_stuck(delta: float) -> bool:
	if global_position.distance_to(_last_move_pos) < 2.0:
		_stuck_timer += delta
		return _stuck_timer >= STUCK_TIMEOUT
	_last_move_pos = global_position
	_stuck_timer = 0.0
	return false


func _state_to(new_state: MercState) -> void:
	if state != new_state:
		state = new_state


func _get_attack_damage() -> int:
	return merc_data.attack_damage if merc_data != null else 0


func _get_attack_interval() -> float:
	return merc_data.attack_interval if merc_data != null else 1.0


func _get_move_speed() -> float:
	return merc_data.move_speed if merc_data != null else 0.0


func get_mercenary_id() -> String:
	return merc_data.id if merc_data != null else ""


func get_defense_zone() -> int:
	return merc_data.defense_zone if merc_data != null else MercenaryData.DefenseZone.NONE


## TASK-015-4: REGROUP 명령. 현재 지정 방어 구역 rally(anchor)로 복귀한다.
## 전투 중(target 추격/공격)이면 현재 target을 놓고 복귀를 우선한다. 이동 중 target
## 획득은 REGROUP 상태가 억제하므로, 도착 후 일반 방어 AI(재탐색)로 정상 복귀한다.
func regroup() -> void:
	if not alive or state == MercState.DEAD:
		return
	_target = null
	_state_to(MercState.REGROUP)


## TASK-015-4: RETREAT 명령. 중앙 Village/safe rally로 후퇴한다.
## 공격을 중지하고 target을 놓으며 도착 후 HOLD한다. 무적이 아니므로 후퇴 중에도
## 적의 공격으로 사망할 수 있다.
func retreat(safe_point: Vector2) -> void:
	if not alive or state == MercState.DEAD:
		return
	_retreat_point = safe_point
	_target = null
	_state_to(MercState.RETREAT)


## TASK-015-3: 전술 명령으로 방어 구역/앵커(rally)를 실시간 변경한다.
## 새 defense_point로 nav 이동한다(teleport 금지). 현재 target이 새 구역과 무관하거나
## 너무 멀면 disengage(_target 클리어)하고 새 구역으로 복귀한다.
## 아직 새 구역에 도착하지 않았으면 RETURN_TO_DEFENSE_ZONE, 도착했으면 재탐색한다.
## 이를 통해 stale target/permanent chase 없이 새 구역 기준 target 탐색으로 전환한다.
## TASK-015-4: REGROUP/RETREAT 중이면 새 방어 명령으로 일반 방어 AI로 복귀한다.
func set_defense_zone(zone: int, new_rally: Vector2) -> void:
	if merc_data != null:
		merc_data.set_defense_zone(zone)
	defense_point = new_rally
	if not alive or state == MercState.DEAD:
		return
	if state == MercState.REGROUP or state == MercState.RETREAT:
		_target = null
		if _reached_defense_point():
			_state_to(MercState.ACQUIRE_TARGET)
		else:
			_state_to(MercState.RETURN_TO_DEFENSE_ZONE)
		return
	if _target_invalid() or _target_far_from_zone():
		_target = null
		if not _reached_defense_point():
			_state_to(MercState.RETURN_TO_DEFENSE_ZONE)
		else:
			_state_to(MercState.ACQUIRE_TARGET)
	else:
		_state_to(MercState.ACQUIRE_TARGET)


## TASK-015-3: 현재 target이 새 defense_point(구역)로부터 CHASE_RETURN_DISTANCE보다
## 멀면 "새 구역과 무관/너무 멀다"로 판정한다.
func _target_far_from_zone() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	return _target.global_position.distance_to(defense_point) > CHASE_RETURN_DISTANCE


## TASK-014-4: 테스트/디버그용 현재 FSM 상태 조회.
func get_state() -> int:
	return state


## TASK-014-4: 테스트/디버그용 현재 target 조회.
func get_target() -> Node:
	return _target


## TASK-015-5: 전술 Focus Target 지정. 유효한 살아 있는 Enemy를 우선 target으로
## 삼는다. RETREAT/REGROUP/DEAD 상태에서는 즉시 전환하지 않고(그 상태가 우선),
## 해당 상태가 끝난 뒤 재탐색 시 focus를 우선 target으로 선택한다.
func set_focus_target(enemy: Node) -> void:
	if not alive or state == MercState.DEAD:
		return
	if enemy == null or not is_instance_valid(enemy) or enemy.get("alive") == false:
		clear_focus_target()
		return
	_focus_target = enemy
	_focus_stuck_timer = 0.0
	_last_focus_pos = global_position
	if state == MercState.RETREAT or state == MercState.REGROUP:
		return
	_acquire_target()


## TASK-015-5: focus target 해제. 현재 target이 focus였다면 놓고 기본 AI로 복귀한다.
func clear_focus_target() -> void:
	_focus_target = null
	_focus_stuck_timer = 0.0
	if state == MercState.MOVE_TO_TARGET or state == MercState.ATTACK \
			or state == MercState.ACQUIRE_TARGET:
		_acquire_target()


## TASK-015-5: 테스트/디버그용 현재 focus target 조회.
func get_focus_target() -> Node:
	return _focus_target


## TASK-015-5: 현재 focus target을 우선 target으로 추격/공격 중인지 판정.
func is_focusing() -> bool:
	return _focus_target != null and is_instance_valid(_focus_target) \
		and _target == _focus_target


## TASK-015-4: RETREAT 목표(중앙 safe rally) 좌표 조회.
func get_retreat_point() -> Vector2:
	return _retreat_point