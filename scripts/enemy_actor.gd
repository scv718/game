extends CharacterBody2D
class_name EnemyActor

## TASK-014-3 첫 일반 근접 Enemy Actor.
## FirstEncounterSpawner가 NIGHT 시작 시 해당 방향 SpawnCandidate에 spawn하고,
## DAY 복귀 시 despawn한다. 이동은 Main Road/Approach Route waypoint를 따라
## 마을 쪽으로 접근하는 방식(road 접근 선호)이며, OPEN Gate면 Gate corridor를
## 통과해 Village Core 방향으로 진행할 수 있다.
## HP/move_speed/damage/attack_interval/death 속성을 prototype 값으로 보유한다.
## TASK-014-4 전투: 공격 range 안에 살아 있는 Mercenary가 있으면 정지해
## interval 단위로 공격한다(Enemy가 직접 Mercenary HP를 감소시킴). target이
## 죽거나 멀어지면 기존 접근(route)을 재개한다. Player는 절대 target이 되지
## 않는다(mercenaries 그룹만 탐색). 사망 기록/청소는 TASK-014-6에서 다룬다.
##
## TASK-014-5 Gate Breach: CLOSED 성문 앞에서 영구 정지하지 않도록, 가까운
## CLOSED 성문을 발견하면 GATE_ATTACK 상태로 정지해 interval 단위로 공격한다.
## 성문 HP가 0이 되어 BREACHED(또는 외부에서 OPEN)되면 기존 접근(route)을 재개해
## 마을 방향으로 진행한다. OPEN 성문은 공격하지 않고 통과한다. 성문 공격 중에도
## 살아 있는 대상이므로 Mercenary와 교전 가능하다. Wall 직접 공격은 하지 않는다.

enum EnemyState { MOVE, HOLD, ATTACK, GATE_ATTACK }

const REACH_DISTANCE := 12.0
const STUCK_TIMEOUT := 2.0
const ATTACK_RANGE := 26.0
## TASK-014-5: CLOSED 성문을 공격으로 전환하는 감지 거리.
const GATE_ATTACK_RANGE := 40.0

var enemy_id: String = ""
var display_name: String = ""
var direction := "north"
var max_hp: int = 60
var current_hp: int = 60
var move_speed: float = 90.0
var attack_damage: int = 8
var attack_interval: float = 1.0
var alive := true

var state: EnemyState = EnemyState.HOLD

var _waypoints: Array[Vector2] = []
var _final_target := Vector2.ZERO
var _has_final := false
var _stuck_timer := 0.0
var _last_move_pos := Vector2.ZERO
var _target: Node = null
var _gate_target: Node = null
var _attack_cd := 0.0

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D

## TASK-014-3: 사망 시 emit. (TASK-014-6 사망 처리에서 재사용)
signal died(enemy: Node)


func _ready() -> void:
	add_to_group("enemies")
	current_hp = max_hp


## Spawner가 식별 정보/방향을 설정한다.
func setup(p_id: String, p_name: String, p_direction: String) -> void:
	enemy_id = p_id
	display_name = p_name
	direction = p_direction


## Spawner가 road waypoint 경로와 최종 목표(Village Core)를 설정한다.
## 현재 위치에서 이미 지나친(도달 거리 내) waypoint는 건너뛴다.
func set_route(waypoints: Array, final_target: Vector2) -> void:
	_waypoints.clear()
	for p in waypoints:
		var v := Vector2(p)
		if global_position.distance_to(v) <= REACH_DISTANCE:
			continue
		_waypoints.append(v)
	_final_target = final_target
	_has_final = true
	state = EnemyState.MOVE


## TASK-014-3: HP 감소 처리. 0 이하가 되면 사망한다(실제 공격 호출은 TASK-014-4).
func take_damage(amount: int) -> void:
	if not alive or amount <= 0:
		return
	current_hp = maxi(0, current_hp - amount)
	if current_hp <= 0:
		die()


## TASK-014-3: 사망 처리. alive=false, 그룹 제외, Death Ledger 기록, died signal 후
## 월드에서 제거한다. (DAY cleanup/despawn은 queue_free를 직접 사용해 die()를 거치지
## 않으므로 record가 생성되지 않는다)
## TASK-016-3: 실제 combat damage로 HP 0 이하가 된 lethal 사망에만 ENEMY DeathRecord를
## 정확히 1회 기록한다. record 생성은 die() 내부 단일 경로에서만 수행하므로(died signal
## 핸들러는 생성하지 않음) 동일 실제 죽음 = record 1개가 보장된다.
func die() -> void:
	if not alive:
		return
	alive = false
	remove_from_group("enemies")
	_record_death()
	died.emit(self)
	queue_free()


## TASK-016-3: 사망 시점의 Enemy 정체성/전투 stat snapshot으로 DeathRecord를 생성한다.
## Actor/Node reference가 아닌 순수 snapshot만 DeathLedger에 저장한다. 동일 Enemy type
## (같은 display_name)이라도 각 Actor의 독립 source_uid(enemy_id)를 사용하므로 서로 다른
## 죽음으로 기록된다. temporary combat state(target/FSM/gate target)는 저장하지 않는다.
## GameTime/DeathLedger autoload는 NodePath로 런타임 조회해 compile-time autoload global
## 참조를 피한다(--script 테스트 초기 compile 시 미등록 문제 회피).
func _record_death() -> void:
	var record := DeathRecord.new("")
	record.source_uid = enemy_id
	record.source_kind = DeathRecord.SourceKind.ENEMY
	record.display_name = display_name
	record.class_or_type = display_name
	record.level = 1
	record.max_hp = max_hp
	record.attack_damage = attack_damage
	record.attack_interval = attack_interval
	record.move_speed = move_speed
	record.death_day = _current_death_day()
	record.death_phase = _current_death_phase()
	record.death_position = global_position
	var ledger: Node = get_node_or_null("/root/DeathLedger")
	if ledger != null:
		ledger.record_death(record.to_snapshot())


## TASK-016-3: 사망 시점 day. GameTime autoload를 NodePath로 런타임 조회한다.
func _current_death_day() -> int:
	var gt: Node = get_node_or_null("/root/GameTime")
	return gt.get_day_number() if gt != null else 1


## TASK-016-3: 사망 시점 phase. GameTime.Phase와 DeathRecord.DeathPhase는 DAY=0/NIGHT=1로
## 값이 동일하므로 GameTime enum 참조 없이 DeathRecord enum 값으로 비교한다.
func _current_death_phase() -> int:
	var gt: Node = get_node_or_null("/root/GameTime")
	if gt != null and gt.get_phase() == DeathRecord.DeathPhase.NIGHT:
		return DeathRecord.DeathPhase.NIGHT
	return DeathRecord.DeathPhase.DAY


func _physics_process(delta: float) -> void:
	if not alive:
		return
	match state:
		EnemyState.MOVE:
			_tick_move(delta)
		EnemyState.HOLD:
			velocity = Vector2.ZERO
		EnemyState.ATTACK:
			_tick_attack(delta)
		EnemyState.GATE_ATTACK:
			_tick_gate_attack(delta)


func _tick_move(delta: float) -> void:
	# TASK-014-4: 공격 range 안에 살아 있는 Mercenary가 있으면 교전을 우선한다.
	var merc := _find_nearby_mercenary()
	if merc != null:
		_target = merc
		state = EnemyState.ATTACK
		return
	# TASK-014-5: 가까운 CLOSED 성문이 있으면 정지해 공격한다(OPEN 성문은 통과).
	var gate := _find_closed_gate()
	if gate != null:
		_gate_target = gate
		state = EnemyState.GATE_ATTACK
		return
	var dest := _current_dest()
	_nav_agent.target_position = dest
	var reached := global_position.distance_to(dest) <= REACH_DISTANCE
	if reached or (_nav_agent.is_target_reachable() and _nav_agent.is_target_reached()):
		if _waypoints.size() > 0:
			_waypoints.pop_front()
			return
		velocity = Vector2.ZERO
		state = EnemyState.HOLD
		return
	if _check_stuck(delta):
		# nav로 목표 도달이 불가능하면 영구 MOVE stall 없이 안전하게 정지한다.
		velocity = Vector2.ZERO
		return
	var next_pos := _nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_pos) * move_speed
	move_and_slide()


func _current_dest() -> Vector2:
	if _waypoints.size() > 0:
		return _waypoints[0]
	return _final_target


func _check_stuck(delta: float) -> bool:
	if global_position.distance_to(_last_move_pos) < 2.0:
		_stuck_timer += delta
		return _stuck_timer >= STUCK_TIMEOUT
	_last_move_pos = global_position
	_stuck_timer = 0.0
	return false


func get_enemy_id() -> String:
	return enemy_id


func get_direction() -> String:
	return direction


## TASK-014-4: 공격 range 안의 살아 있는 Mercenary를 target으로 선택한다.
## Player는 절대 target이 되지 않는다(mercenaries 그룹만 탐색).
func _find_nearby_mercenary() -> Node:
	var best: Node = null
	var best_dist := ATTACK_RANGE
	for m in get_tree().get_nodes_in_group("mercenaries"):
		if not is_instance_valid(m):
			continue
		if m.get("alive") == false:
			continue
		var d := global_position.distance_to(m.global_position)
		if d <= best_dist:
			best_dist = d
			best = m
	return best


## TASK-014-4: 정지 상태에서 interval 단위로 target(Mercenary)을 공격한다.
## target이 죽거나 attack range 밖으로 멀어지면 기존 접근(route)으로 복귀한다.
func _tick_attack(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _target_invalid():
		_target = null
		state = EnemyState.MOVE
		return
	if global_position.distance_to(_target.global_position) > ATTACK_RANGE * 1.5:
		_target = null
		state = EnemyState.MOVE
		return
	velocity = Vector2.ZERO
	if _attack_cd <= 0.0:
		if _target.has_method("take_damage"):
			_target.take_damage(attack_damage)
		_attack_cd = attack_interval


func _target_invalid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	if _target.get("alive") == false:
		return true
	return false


## TASK-014-5: GATE_ATTACK_RANGE 안에 있는 살아 있는 CLOSED 성문 중 가장 가까운 것을
## 반환한다. OPEN/BREACHED 성문은 통과하므로 제외하고, Wall은 직접 공격하지 않는다.
func _find_closed_gate() -> Node:
	var best: Node = null
	var best_dist := GATE_ATTACK_RANGE
	for g in get_tree().get_nodes_in_group("gates"):
		if not is_instance_valid(g):
			continue
		if not g.has_method("is_closed") or not g.is_closed():
			continue
		var d := global_position.distance_to(g.global_position)
		if d <= best_dist:
			best_dist = d
			best = g
	return best


## TASK-014-5: CLOSED 성문을 정지해 interval 단위로 공격한다. 성문이 파괴(BREACHED)되거나
## OPEN되면(통로 개방) 기존 접근(route)으로 복귀해 마을 방향으로 진행한다. 공격 중에도
## 살아 있는 대상이므로 Mercenary가 교전할 수 있다.
func _tick_gate_attack(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _gate_invalid():
		_gate_target = null
		state = EnemyState.MOVE
		return
	if global_position.distance_to(_gate_target.global_position) > GATE_ATTACK_RANGE * 1.5:
		_gate_target = null
		state = EnemyState.MOVE
		return
	velocity = Vector2.ZERO
	if _attack_cd <= 0.0:
		if _gate_target.has_method("take_damage"):
			_gate_target.take_damage(attack_damage)
		_attack_cd = attack_interval


func _gate_invalid() -> bool:
	if _gate_target == null or not is_instance_valid(_gate_target):
		return true
	if _gate_target.has_method("is_closed") and not _gate_target.is_closed():
		return true
	return false


## TASK-014-5: 테스트/디버그용 현재 공격 중인 성문 조회.
func get_gate_target() -> Node:
	return _gate_target