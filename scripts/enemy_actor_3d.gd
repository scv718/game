extends CharacterBody3D
class_name EnemyActor3D

## TASK-3D-CMB-001-1 첫 일반 근접 Enemy Actor3D.
## 기존 enemy_actor.gd(CharacterBody2D)의 이동/교전/Gate Breach FSM을 3D Runtime으로
## 이전한 신규 파일이다. 기존 2D enemy_actor.gd / enemy.tscn은 LOCK 12에 따라
## reference로 유지되며 이 파일이 대신하는 것은 3D World에서의 전투뿐이다.
##
## Spawner가 NIGHT 시작에 SpawnCandidate에서 spawn하고 DAY 복귀 시 despawn한다.
## 이동은 road/approach waypoint를 따라 마을 쪽으로 접근하며, 공격 range 안의
## 살아 있는 Mercenary가 있으면 교전을 우선하고(Enemy가 직접 Mercenary HP를 감소),
## 가까운 CLOSED 성문은 GATE_ATTACK으로 파괴한다(BREACHED/OPEN 성문은 통과).
## Player는 절대 target이 되지 않는다(mercenaries_3d 그룹만 탐색).
##
## 3D 이동 계약(Foundation 001-5):
##   - NavigationAgent3D + NavigationPolicy3D.configure_agent만 사용.
##   - gameplay 거리/사거리 판정은 전부 WorldCoords3D.distance_xz.
##   - 상수는 2D px 값 * PX_TO_UNIT 환산 그대로다(밸런스 불변).
##   - 이동 종료 규약 judge_path_status. BLOCKED/stuck 시 waypoint route는 다음
##     waypoint로 bounded skip, 최종 목표면 HOLD로 종료한다(영구 MOVE stall 금지).
##
## 사망 기록/청소: 실제 combat damage로 HP 0 이하가 된 lethal 사망에만 ENEMY
## DeathRecord를 정확히 1회 기록한다(die() 단일 경로). DAY cleanup/despawn은
## queue_free를 직접 사용해 die()를 거치지 않으므로 record가 생성되지 않는다.
## death_position은 world XZ를 logical 좌표로 역변환해 저장한다(Vector2 스키마 유지).
##
## Gate 계약: BLD 도메인의 3D 성문은 "gates_3d" 그룹 + is_closed()/take_damage()
## duck-typing 계약으로 연결된다(2D gate.gd 계약과 동일, INTEGRATION_NOTE_CMB 참고).

enum EnemyState { MOVE, HOLD, ATTACK, GATE_ATTACK }

const REACH_DISTANCE := 12.0 * WorldCoords3D.PX_TO_UNIT
const STUCK_TIMEOUT := 2.0
const ATTACK_RANGE := 26.0 * WorldCoords3D.PX_TO_UNIT
## CLOSED 성문을 공격으로 전환하는 감지 거리(2D 40px 환산).
const GATE_ATTACK_RANGE := 40.0 * WorldCoords3D.PX_TO_UNIT

var enemy_id: String = ""
var display_name: String = ""
var direction := "north"
var max_hp: int = 60
var current_hp: int = 60
var move_speed: float = 90.0 * WorldCoords3D.PX_TO_UNIT
var attack_damage: int = 8
var attack_interval: float = 1.0
var alive := true

var state: EnemyState = EnemyState.HOLD

signal attack_performed(target: Node)
signal hit_taken(amount: int)
signal death_started(enemy: Node)

var _waypoints: Array[Vector3] = []
var _final_target := Vector3.ZERO
var _has_final := false
var _stuck_timer := 0.0
var _last_move_pos := Vector3.ZERO
var _target: Node = null
var _gate_target: Node = null
var _attack_cd := 0.0
var _nav_dest := Vector3.ZERO
var _hit_flash_left := 0.0

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/BodyVisual

## TASK-014-3: 사망 시 emit(2D 계약 동일).
signal died(enemy: Node)


func _ready() -> void:
	add_to_group("enemies_3d")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	current_hp = max_hp
	NavigationPolicy3D.configure_agent(_nav_agent)
	_body_mesh.set_surface_override_material(
		0, _body_mesh.mesh.surface_get_material(0).duplicate())


## Spawner가 식별 정보/방향을 설정한다.
func setup(p_id: String, p_name: String, p_direction: String) -> void:
	enemy_id = p_id
	display_name = p_name
	direction = p_direction


## Spawner가 road waypoint 경로와 최종 목표(Village Core)를 설정한다.
## 현재 위치에서 이미 지나친(도달 거리 내) waypoint는 건너뛴다.
func set_route(waypoints: Array, final_target: Vector3) -> void:
	_waypoints.clear()
	for p in waypoints:
		var v := Vector3(p)
		if WorldCoords3D.distance_xz(global_position, v) <= REACH_DISTANCE:
			continue
		_waypoints.append(v)
	_final_target = final_target
	_has_final = true
	state = EnemyState.MOVE


## HP 감소 처리. 0 이하가 되면 사망한다.
func take_damage(amount: int) -> void:
	if not alive or amount <= 0:
		return
	current_hp = maxi(0, current_hp - amount)
	_apply_hit_visual()
	hit_taken.emit(amount)
	if current_hp <= 0:
		die()


## 사망 처리. alive=false, 그룹 제외, Death Ledger 기록, died signal 후 월드에서
## 제거한다. DAY cleanup/despawn은 queue_free를 직접 사용해 die()를 거치지 않으므로
## record가 생성되지 않는다(cleanup record 없음 보장).
func die() -> void:
	if not alive:
		return
	alive = false
	remove_from_group("enemies_3d")
	death_started.emit(self)
	_apply_death_visual()
	_record_death()
	died.emit(self)
	queue_free()


## 사망 시점의 Enemy 정체성/전투 stat snapshot으로 DeathRecord를 생성한다.
## 각 Actor의 독립 source_uid(enemy_id)를 쓰므로 같은 type의 개체도 서로 다른
## 죽음으로 기록된다. temporary combat state(target/FSM/gate target)는 저장하지 않는다.
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
	record.death_position = WorldCoords3D.to_logical(global_position)
	var ledger: Node = get_node_or_null("/root/DeathLedger")
	if ledger != null:
		ledger.record_death(record.to_snapshot())


func _current_death_day() -> int:
	var gt: Node = get_node_or_null("/root/GameTime")
	return gt.get_day_number() if gt != null else 1


func _current_death_phase() -> int:
	var gt: Node = get_node_or_null("/root/GameTime")
	if gt != null and gt.get_phase() == DeathRecord.DeathPhase.NIGHT:
		return DeathRecord.DeathPhase.NIGHT
	return DeathRecord.DeathPhase.DAY


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_tick_hit_flash(delta)
	match state:
		EnemyState.MOVE:
			_tick_move(delta)
		EnemyState.HOLD:
			velocity = Vector3.ZERO
		EnemyState.ATTACK:
			_tick_attack(delta)
		EnemyState.GATE_ATTACK:
			_tick_gate_attack(delta)


func _tick_move(delta: float) -> void:
	# 공격 range 안에 살아 있는 Mercenary가 있으면 교전을 우선한다.
	var merc := _find_nearby_mercenary()
	if merc != null:
		_target = merc
		state = EnemyState.ATTACK
		return
	# 가까운 CLOSED 성문이 있으면 정지해 공격한다(OPEN/BREACHED 성문은 통과).
	var gate := _find_closed_gate()
	if gate != null:
		_gate_target = gate
		state = EnemyState.GATE_ATTACK
		return
	var dest := _current_dest()
	if not _move_towards(dest, delta):
		# BLOCKED/stuck: 남은 waypoint가 있으면 다음 목표로 bounded skip하고,
		# 최종 목표에 막힌 것이면 영구 재시도 없이 HOLD로 종료한다.
		if _waypoints.size() > 0 and _nav_dest == _waypoints[0]:
			_waypoints.pop_front()
			return
		velocity = Vector3.ZERO
		state = EnemyState.HOLD


## 공통 지면 이동 step. 도달 시 true, 경로 소진(BLOCKED)/stuck 포기 시 false.
func _move_towards(dest: Vector3, delta: float) -> bool:
	if _nav_dest != dest:
		_nav_dest = dest
		_stuck_timer = 0.0
		_last_move_pos = global_position
		_nav_agent.target_position = dest
		_nav_agent.get_next_path_position()
	if WorldCoords3D.distance_xz(global_position, dest) <= REACH_DISTANCE:
		velocity = Vector3.ZERO
		return true
	var status := NavigationPolicy3D.judge_path_status(_nav_agent, global_position, dest)
	if status == NavigationPolicy3D.PathStatus.ARRIVED:
		velocity = Vector3.ZERO
		return true
	if status == NavigationPolicy3D.PathStatus.BLOCKED:
		velocity = Vector3.ZERO
		return false
	if _check_stuck(delta):
		velocity = Vector3.ZERO
		return false
	velocity = NavigationPolicy3D.path_follow_velocity_xz(global_position, _nav_agent, move_speed)
	_face_velocity(delta)
	move_and_slide()
	return true


func _current_dest() -> Vector3:
	if _waypoints.size() > 0:
		return _waypoints[0]
	return _final_target


func _check_stuck(delta: float) -> bool:
	if WorldCoords3D.distance_xz(global_position, _last_move_pos) \
			< NavigationPolicy3D.STUCK_MOVE_EPSILON_UNITS:
		_stuck_timer += delta
		return _stuck_timer >= STUCK_TIMEOUT
	_last_move_pos = global_position
	_stuck_timer = 0.0
	return false


func get_enemy_id() -> String:
	return enemy_id


func get_direction() -> String:
	return direction


## 공격 range 안의 살아 있는 Mercenary를 target으로 선택한다.
## Player는 절대 target이 되지 않는다(mercenaries_3d 그룹만 탐색).
func _find_nearby_mercenary() -> Node:
	var best: Node = null
	var best_dist := ATTACK_RANGE
	for m in get_tree().get_nodes_in_group("mercenaries_3d"):
		if not is_instance_valid(m):
			continue
		if m.get("alive") == false:
			continue
		var d := WorldCoords3D.distance_xz(global_position, m.global_position)
		if d <= best_dist:
			best_dist = d
			best = m
	return best


## 정지 상태에서 interval 단위로 target(Mercenary)을 공격한다. target이 죽거나
## attack range 밖으로 멀어지면 기존 접근(route)으로 복귀한다.
func _tick_attack(delta: float) -> void:
	if _target_invalid():
		_target = null
		state = EnemyState.MOVE
		return
	if WorldCoords3D.distance_xz(global_position, _target.global_position) \
			> ATTACK_RANGE * 1.5:
		_target = null
		state = EnemyState.MOVE
		return
	velocity = Vector3.ZERO
	_face_towards(_target.global_position, delta)
	if _attack_cd <= 0.0:
		if _target.has_method("take_damage"):
			_target.take_damage(attack_damage)
		attack_performed.emit(_target)
		_attack_cd = attack_interval


func _target_invalid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	if _target.get("alive") == false:
		return true
	return false


## GATE_ATTACK_RANGE 안에 있는 살아 있는 CLOSED 성문 중 가장 가까운 것을 반환한다.
## OPEN/BREACHED 성문은 통과하므로 제외하고, Wall은 직접 공격하지 않는다.
func _find_closed_gate() -> Node:
	var best: Node = null
	var best_dist := GATE_ATTACK_RANGE
	for g in get_tree().get_nodes_in_group("gates_3d"):
		if not is_instance_valid(g):
			continue
		if not g.has_method("is_closed") or not g.is_closed():
			continue
		var d := WorldCoords3D.distance_xz(global_position, g.global_position)
		if d <= best_dist:
			best_dist = d
			best = g
	return best


## CLOSED 성문을 정지해 interval 단위로 공격한다. 성문이 파괴(BREACHED)되거나
## OPEN되면(통로 개방) 기존 접근(route)으로 복귀해 마을 방향으로 진행한다.
## 공격 중에도 살아 있는 대상이므로 Mercenary가 교전할 수 있다.
func _tick_gate_attack(delta: float) -> void:
	if _gate_invalid():
		_gate_target = null
		state = EnemyState.MOVE
		return
	if WorldCoords3D.distance_xz(global_position, _gate_target.global_position) \
			> GATE_ATTACK_RANGE * 1.5:
		_gate_target = null
		state = EnemyState.MOVE
		return
	velocity = Vector3.ZERO
	_face_towards(_gate_target.global_position, delta)
	if _attack_cd <= 0.0:
		if _gate_target.has_method("take_damage"):
			_gate_target.take_damage(attack_damage)
		attack_performed.emit(_gate_target)
		_attack_cd = attack_interval


func _gate_invalid() -> bool:
	if _gate_target == null or not is_instance_valid(_gate_target):
		return true
	if _gate_target.has_method("is_closed") and not _gate_target.is_closed():
		return true
	return false


## 이동 방향(-Z forward 관례)으로 Visual child의 yaw를 부드럽게 맞춘다.
func _face_velocity(delta: float) -> void:
	if velocity.length_squared() < 0.0001:
		return
	_face_yaw(atan2(-velocity.x, -velocity.z), delta)


func _face_towards(dest: Vector3, delta: float) -> void:
	var offset := dest - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return
	_face_yaw(atan2(-offset.x, -offset.z), delta)


func _face_yaw(desired: float, delta: float) -> void:
	_visual.rotation.y = lerp_angle(_visual.rotation.y, desired, minf(1.0, 10.0 * delta))


## hit flash placeholder. VIS가 실제 피격 표현으로 교체할 지점이다.
func _apply_hit_visual() -> void:
	var mat := _body_mesh.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).emission_enabled = true
		(mat as StandardMaterial3D).emission = Color(0.9, 0.15, 0.1)
	_hit_flash_left = 0.15


func _tick_hit_flash(delta: float) -> void:
	if _hit_flash_left <= 0.0:
		return
	_hit_flash_left -= delta
	if _hit_flash_left <= 0.0:
		var mat := _body_mesh.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).emission_enabled = false


## death visual placeholder(월드 제거 직전 1회). VIS 교체 지점.
func _apply_death_visual() -> void:
	_visual.visible = false


## 테스트/디버그용 현재 공격 중인 성문 조회.
func get_gate_target() -> Node:
	return _gate_target
