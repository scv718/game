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

enum MercState {
	IDLE,
	ACQUIRE_TARGET,
	MOVE_TO_TARGET,
	ATTACK,
	RETURN_TO_DEFENSE_ZONE,
	DEAD,
}

const ATTACK_RANGE := 26.0
const CHASE_RETURN_DISTANCE := 180.0
const REACH_DISTANCE := 12.0
const STUCK_TIMEOUT := 2.0

var merc_data: MercenaryData = null
var current_hp: int = 0
var alive := true
var state: MercState = MercState.IDLE
var defense_point := Vector2.ZERO

var _target: Node = null
var _attack_cd := 0.0
var _stuck_timer := 0.0
var _last_move_pos := Vector2.ZERO

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
		MercState.DEAD:
			velocity = Vector2.ZERO


## 지정 defense zone 주변(CHASE_RETURN_DISTANCE 이내) 살아 있는 Enemy 중
## defense_point에서 가장 가까운 것을 target으로 획득한다. 구역 밖 Enemy는
## 획득하지 않아 과도한 추격/영구 chase를 방지한다.
func _acquire_target() -> void:
	_state_to(MercState.ACQUIRE_TARGET)
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
	_target = best
	if best != null:
		_state_to(MercState.MOVE_TO_TARGET)
	else:
		_state_to(MercState.IDLE)


func _tick_chase(delta: float) -> void:
	if _target_invalid():
		_acquire_target()
		return
	if _in_attack_range():
		_state_to(MercState.ATTACK)
		return
	if global_position.distance_to(defense_point) > CHASE_RETURN_DISTANCE:
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


func _target_invalid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	if _target.get("alive") == false:
		return true
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


## TASK-014-4: 테스트/디버그용 현재 FSM 상태 조회.
func get_state() -> int:
	return state


## TASK-014-4: 테스트/디버그용 현재 target 조회.
func get_target() -> Node:
	return _target