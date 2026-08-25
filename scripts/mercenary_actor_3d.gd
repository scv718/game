extends CharacterBody3D
class_name MercenaryActor3D

## TASK-3D-CMB-001-1 Mercenary Actor3D.
## 기존 mercenary_actor.gd(CharacterBody2D)의 자동전투 FSM을 3D Runtime으로 이전한
## 신규 파일이다. 기존 2D mercenary_actor.gd / mercenary.tscn은 LOCK 12에 따라
## reference로 유지되며 이 파일이 대신하는 것은 3D World에서의 전투뿐이다.
##
## NIGHT spawn 위치(지정 방어 구역 Gate 안쪽 Rally Space / fallback RallyPoint)를
## defense_point로 삼아, 지정 구역 근처의 살아 있는 Enemy를 deterministic priority로
## 자동 탐색(ACQUIRE_TARGET) → 추격(MOVE_TO_TARGET) → 공격(ATTACK)한다. 과도하게
## 멀리 추격하면 defense_point로 복귀(RETURN_TO_DEFENSE_ZONE)하고, target이 죽거나
## 사라지면 새 target을 탐색한다. Enemy의 공격으로 HP가 0이 되면 사망(DEAD) 처리해
## MercenaryData.alive=false, 그룹 제외, Death Ledger 기록 후 월드에서 제거한다.
## Player는 절대 target/damage 대상이 되지 않는다(enemies_3d 그룹만 탐색).
##
## 3D 이동 계약(Foundation 001-5):
##   - NavigationAgent3D + NavigationPolicy3D.configure_agent만 사용(개별 튜닝 금지).
##   - gameplay 거리/사거리 판정은 전부 WorldCoords3D.distance_xz(XZ 평면).
##   - 상수는 2D px 값 * WorldCoords3D.PX_TO_UNIT 환산 그대로다(밸런스 불변).
##   - 이동 종료 규약은 judge_path_status(MOVING/ARRIVED/BLOCKED) 단일 경로.
##     BLOCKED(부분 경로 소진) 또는 stuck guard 발동 시 추격을 bounded하게 포기한다.
##     BLOCKED된 target은 CHASE_RETRY_COOLDOWN 동안 재탐색에서 제외해
##     "unreachable target 영구 chase lock"을 방지한다(cooldown 만료 후 1회 재시도).
##
## TASK-015-4/-5 전술 명령(REGROUP/RETREAT/set_defense_zone/focus target)과
## 우선순위(FOCUS > defense zone 자동 전투 > REGROUP/RETREAT/DEAD)는 2D와 동일하다.
## TASK-016-3 lethal death에만 DeathRecord를 정확히 1회 기록하며, record 생성은
## die() 내부 단일 경로에서만 수행한다. DAY cleanup/despawn은 die()를 거치지 않으므로
## record가 생성되지 않는다. death_position은 DeathRecord 스키마(Vector2)를 유지하기
## 위해 world XZ를 logical 좌표로 역변환해 저장한다(2D ledger와 동일 좌표 공간).
##
## visual hook: attack_performed / hit_taken / death_started signal과 placeholder
## 표현(hit flash, facing yaw)만 이 파일이 소유한다. 실제 mesh/animation 교체는
## VIS 도메인 소유이며 Visual child만 교체하면 된다.

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

const ATTACK_RANGE := 26.0 * WorldCoords3D.PX_TO_UNIT
const CHASE_RETURN_DISTANCE := 180.0 * WorldCoords3D.PX_TO_UNIT
const REACH_DISTANCE := 12.0 * WorldCoords3D.PX_TO_UNIT
const STUCK_TIMEOUT := 2.0
## focus 추격 중 목표에 도달하지 못하면(stuck) 영구 chase를 방지하기 위해
## 이 시간 동안 이동이 없으면 focus를 해제한다(2D와 동일 감각).
const FOCUS_STUCK_TIMEOUT := 2.0
## BLOCKED/unreachable target의 재탐색 제외 시간. cooldown 내에는 다른 target을
## 찾고, 없으면 IDLE로 유지한다(재추격 무한루프 금지).
const CHASE_RETRY_COOLDOWN := 2.5

var merc_data: MercenaryData = null
var current_hp: int = 0
var alive := true
var state: MercState = MercState.IDLE
var defense_point := Vector3.ZERO

signal attack_performed(target: Node)
signal hit_taken(amount: int)
signal death_started(mercenary: Node)

var _target: Node = null
var _attack_cd := 0.0
var _stuck_timer := 0.0
var _last_move_pos := Vector3.ZERO
var _retreat_point := Vector3.ZERO
## 전술 Focus Target. 플레이어가 선택한 우선 target(살아 있는 Enemy).
var _focus_target: Node = null
var _focus_stuck_timer := 0.0
var _last_focus_pos := Vector3.ZERO
## 최근 도달 불가(BLOCKED/stuck)로 포기한 target과 cooldown. cooldown 중에는
## _resolve_priority_target이 이 target을 건너뛴다(focus는 예외 없이 해제).
var _unreachable_target: Node = null
var _unreachable_cooldown := 0.0
var _hit_flash_left := 0.0
## nav agent에 마지막으로 설정한 목적지. 바뀔 때만 대입 + 즉시 path 갱신한다.
var _nav_dest := Vector3.ZERO

## TASK-014-6 사망 처리에서 재사용(2D 계약 동일).
signal died(mercenary: Node)

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/BodyVisual


func _ready() -> void:
	add_to_group("mercenaries_3d")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if merc_data != null:
		current_hp = merc_data.max_hp
	if defense_point == Vector3.ZERO:
		defense_point = global_position
	NavigationPolicy3D.configure_agent(_nav_agent)
	# hit flash가 인스턴스 단위로 동작하려면 scene 공유 material을 복제해 쓴다.
	_body_mesh.set_surface_override_material(
		0, _body_mesh.mesh.surface_get_material(0).duplicate())


func _physics_process(delta: float) -> void:
	if not alive or state == MercState.DEAD:
		velocity = Vector3.ZERO
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_unreachable_cooldown = maxf(0.0, _unreachable_cooldown - delta)
	_tick_hit_flash(delta)
	match state:
		MercState.IDLE:
			velocity = Vector3.ZERO
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
			velocity = Vector3.ZERO


## target을 획득한다. 우선순위는 FOCUS TARGET > defense zone 자동 전투다.
## 유효한 focus target이 있으면 그것을 우선 target으로 삼고, 없거나 invalid
## (사망/freed/unreachable cooldown)면 기존 defense zone 자동 전투로 되돌아간다.
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


## 우선 순위에 따른 target 후보 결정. focus target이 살아 있고 유효하면 우선하고,
## 아니면 defense zone 자동 전투(CHASE_RETURN_DISTANCE 이내에서 defense_point에
## 가장 가까운 Enemy)를 선택한다. unreachable cooldown 중인 target은 건너뛴다.
func _resolve_priority_target() -> Node:
	if _focus_target != null and is_instance_valid(_focus_target) \
			and _focus_target.get("alive") != false \
			and not _focus_unreachable():
		return _focus_target
	var best: Node = null
	var best_score := INF
	for e in get_tree().get_nodes_in_group("enemies_3d"):
		if not is_instance_valid(e):
			continue
		if e.get("alive") == false:
			continue
		if e == _unreachable_target and _unreachable_cooldown > 0.0:
			continue
		var dist_from_zone: float = WorldCoords3D.distance_xz(e.global_position, defense_point)
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
	# focus target을 추격 중이면 defense zone 거리 제한을 우선 대상에서 제외하고,
	# 도달 불가능(BLOCKED/stuck)이면 영구 chase 없이 focus를 해제하고 기본 AI로
	# 복귀한다. 일반 target은 defense_point 기반 복귀 한계를 유지한다.
	if _target == _focus_target:
		if _focus_chase_stuck(delta):
			_focus_target = null
			_focus_stuck_timer = 0.0
			_acquire_target()
			return
	elif WorldCoords3D.distance_xz(global_position, defense_point) > CHASE_RETURN_DISTANCE:
		_state_to(MercState.RETURN_TO_DEFENSE_ZONE)
		return
	if not _move_towards(_target.global_position, delta):
		_mark_target_unreachable()
		_acquire_target()


func _tick_attack(delta: float) -> void:
	if _target_invalid():
		_acquire_target()
		return
	if not _in_attack_range():
		_state_to(MercState.MOVE_TO_TARGET)
		return
	velocity = Vector3.ZERO
	_face_towards(_target.global_position, delta)
	if _attack_cd <= 0.0:
		if _target.has_method("take_damage"):
			_target.take_damage(_get_attack_damage())
		attack_performed.emit(_target)
		_attack_cd = _get_attack_interval()


func _tick_return(delta: float) -> void:
	if NavigationPolicy3D.reached_xz(global_position, defense_point, REACH_DISTANCE):
		_acquire_target()
		return
	if not _move_towards(defense_point, delta):
		velocity = Vector3.ZERO


## REGROUP 상태. 현재 방어 구역 rally(anchor)로 복귀한다. 이동 중에는 새 target을
## 획득하지 않고(잠시 억제), 도착하면 일반 방어 AI(재탐색)로 복귀한다.
func _tick_regroup(delta: float) -> void:
	if NavigationPolicy3D.reached_xz(global_position, defense_point, REACH_DISTANCE):
		_acquire_target()
		return
	if not _move_towards(defense_point, delta):
		_acquire_target()


## RETREAT 상태. 중앙 Village/safe rally로 후퇴한다. 이동 중/도착 후에도 공격하지
## 않고 target도 획득하지 않는다(공격 중지). 도착 후 HOLD. 무적이 아니므로 도중
## 적의 공격으로 사망할 수 있다.
func _tick_retreat(delta: float) -> void:
	if NavigationPolicy3D.reached_xz(global_position, _retreat_point, REACH_DISTANCE):
		velocity = Vector3.ZERO
		return
	if not _move_towards(_retreat_point, delta):
		velocity = Vector3.ZERO


## 공통 지면 이동 step. dest에 도달(reach tolerance)하면 true, 경로 소진(BLOCKED)
## 또는 stuck guard로 진행 포기 시 false를 반환한다. 호출부는 false를 받으면
## 재시도 루프를 만들지 않고 bounded하게 상태를 전환해야 한다(001-5 규약).
func _move_towards(dest: Vector3, delta: float) -> bool:
	if not _nav_dest_is(dest):
		_begin_move(dest)
	if NavigationPolicy3D.reached_xz(global_position, dest, REACH_DISTANCE):
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
	velocity = NavigationPolicy3D.path_follow_velocity_xz(
		global_position, _nav_agent, _get_move_speed())
	_face_velocity(delta)
	move_and_slide()
	return true


## 새 목적지 시작. target_position 설정 직후 get_next_path_position으로 path를
## 즉시 갱신해 첫 frame의 stale finished 상태로 BLOCKED 오판하는 것을 막는다.
func _begin_move(dest: Vector3) -> bool:
	_nav_dest = dest
	_stuck_timer = 0.0
	_last_move_pos = global_position
	_nav_agent.target_position = dest
	_nav_agent.get_next_path_position()
	return true


func _nav_dest_is(dest: Vector3) -> bool:
	return _nav_dest == dest


## Enemy 공격 등으로부터 HP를 감소시킨다. 0 이하가 되면 사망 처리한다.
## Player는 공격 대상이 아니므로 이 경로로 피격되지 않는다.
func take_damage(amount: int) -> void:
	if not alive or amount <= 0:
		return
	current_hp = maxi(0, current_hp - amount)
	_apply_hit_visual()
	hit_taken.emit(amount)
	if current_hp <= 0:
		die()


## 사망 처리. MercenaryData.alive=false 반영, 그룹 제외, Death Ledger 기록,
## died signal 후 월드에서 제거. DAY cleanup/despawn은 queue_free를 직접 사용해
## die()를 거치지 않으므로 record가 생성되지 않는다(cleanup record 없음 보장).
func die() -> void:
	if not alive or state == MercState.DEAD:
		return
	alive = false
	state = MercState.DEAD
	if merc_data != null:
		merc_data.alive = false
	remove_from_group("mercenaries_3d")
	death_started.emit(self)
	_apply_death_visual()
	_record_death()
	died.emit(self)
	queue_free()


## 사망 시점의 MercenaryData 정체성/전투 stat snapshot으로 DeathRecord를 생성한다.
## Actor/Node reference가 아닌 순수 snapshot만 DeathLedger에 저장하며, source_uid는
## display_name과 독립(용병 고유 id)이므로 이름이 같은 다른 용병도 서로 다른 죽음으로
## 기록된다. GameTime/DeathLedger autoload는 NodePath로 런타임 조회해 --script 테스트
## 초기 compile 시 미등록 문제를 회피한다(2D와 동일 패턴).
func _record_death() -> void:
	if merc_data == null:
		return
	var record := DeathRecord.new("")
	record.source_uid = merc_data.id
	record.source_kind = DeathRecord.SourceKind.MERCENARY
	record.display_name = merc_data.display_name
	record.class_or_type = merc_data.get_class_name()
	record.level = merc_data.level
	record.max_hp = merc_data.max_hp
	record.attack_damage = merc_data.attack_damage
	record.attack_interval = merc_data.attack_interval
	record.move_speed = merc_data.move_speed
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


func _in_attack_range() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	return WorldCoords3D.distance_xz(global_position, _target.global_position) \
		<= ATTACK_RANGE


func _target_invalid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	if _target.get("alive") == false:
		return true
	return false


func _focus_target_invalid() -> bool:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return true
	if _focus_target.get("alive") == false:
		return true
	return false


## focus target이 unreachable cooldown 중인지.
func _focus_unreachable() -> bool:
	return _focus_target == _unreachable_target and _unreachable_cooldown > 0.0


func _focus_chase_stuck(delta: float) -> bool:
	if WorldCoords3D.distance_xz(global_position, _last_focus_pos) \
			< NavigationPolicy3D.STUCK_MOVE_EPSILON_UNITS:
		_focus_stuck_timer += delta
		return _focus_stuck_timer >= FOCUS_STUCK_TIMEOUT
	_last_focus_pos = global_position
	_focus_stuck_timer = 0.0
	return false


func _mark_target_unreachable() -> void:
	_unreachable_target = _target
	_unreachable_cooldown = CHASE_RETRY_COOLDOWN
	if _target == _focus_target:
		_focus_target = null
		_focus_stuck_timer = 0.0


func _check_stuck(delta: float) -> bool:
	if WorldCoords3D.distance_xz(global_position, _last_move_pos) \
			< NavigationPolicy3D.STUCK_MOVE_EPSILON_UNITS:
		_stuck_timer += delta
		return _stuck_timer >= STUCK_TIMEOUT
	_last_move_pos = global_position
	_stuck_timer = 0.0
	return false


## 이동 방향(-Z forward 관례)으로 Visual child의 yaw를 부드럽게 맞춘다.
## root를 회전시키지 않으므로 nav/collision 볼륨은 영향받지 않는다.
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


func _state_to(new_state: MercState) -> void:
	if state != new_state:
		state = new_state


func _get_attack_damage() -> int:
	return merc_data.attack_damage if merc_data != null else 0


func _get_attack_interval() -> float:
	return merc_data.attack_interval if merc_data != null else 1.0


func _get_move_speed() -> float:
	# MercenaryData.move_speed는 logical px/s(2D 데이터 계약). 3D world에서는
	# PX_TO_UNIT 환산값만 사용한다(비율 불변 = 밸런스 불변).
	return (merc_data.move_speed if merc_data != null else 0.0) * WorldCoords3D.PX_TO_UNIT


func get_mercenary_id() -> String:
	return merc_data.id if merc_data != null else ""


func get_defense_zone() -> int:
	return merc_data.defense_zone if merc_data != null else MercenaryData.DefenseZone.NONE


## REGROUP 명령. 현재 지정 방어 구역 rally(anchor)로 복귀한다. 이동 중 target
## 획득은 REGROUP 상태가 억제하므로, 도착 후 일반 방어 AI(재탐색)로 복귀한다.
func regroup() -> void:
	if not alive or state == MercState.DEAD:
		return
	_target = null
	_state_to(MercState.REGROUP)


## RETREAT 명령. 중앙 Village/safe rally로 후퇴한다. 공격을 중지하고 target을
## 놓으며 도착 후 HOLD한다. 무적이 아니므로 후퇴 중에도 적의 공격으로 사망할 수 있다.
func retreat(safe_point: Vector3) -> void:
	if not alive or state == MercState.DEAD:
		return
	_retreat_point = safe_point
	_target = null
	_state_to(MercState.RETREAT)


## 전술 명령으로 방어 구역/앵커(rally)를 실시간 변경한다. 새 defense_point로 nav
## 이동한다(teleport 금지). 현재 target이 새 구역과 무관하거나 너무 멀면 disengage
## (_target 클리어)하고 새 구역으로 복귀한다. REGROUP/RETREAT 중이면 새 방어 명령으로
## 일반 방어 AI로 복귀한다. stale target/permanent chase 없이 전환한다.
func set_defense_zone(zone: int, new_rally: Vector3) -> void:
	if merc_data != null:
		merc_data.set_defense_zone(zone)
	defense_point = new_rally
	if not alive or state == MercState.DEAD:
		return
	if state == MercState.REGROUP or state == MercState.RETREAT:
		_target = null
		if NavigationPolicy3D.reached_xz(global_position, defense_point, REACH_DISTANCE):
			_state_to(MercState.ACQUIRE_TARGET)
		else:
			_state_to(MercState.RETURN_TO_DEFENSE_ZONE)
		return
	if _target_invalid() or _target_far_from_zone():
		_target = null
		if not NavigationPolicy3D.reached_xz(global_position, defense_point, REACH_DISTANCE):
			_state_to(MercState.RETURN_TO_DEFENSE_ZONE)
		else:
			_state_to(MercState.ACQUIRE_TARGET)
	else:
		_state_to(MercState.ACQUIRE_TARGET)


## 현재 target이 새 defense_point(구역)로부터 CHASE_RETURN_DISTANCE보다 멀면
## "새 구역과 무관/너무 멀다"로 판정한다.
func _target_far_from_zone() -> bool:
	if _target == null or not is_instance_valid(_target):
		return true
	return WorldCoords3D.distance_xz(_target.global_position, defense_point) \
		> CHASE_RETURN_DISTANCE


func get_state() -> int:
	return state


func get_target() -> Node:
	return _target


## 전술 Focus Target 지정. 유효한 살아 있는 Enemy를 우선 target으로 삼는다.
## RETREAT/REGROUP/DEAD 상태에서는 즉시 전환하지 않고 해당 상태가 끝난 뒤
## 재탐색 시 focus를 우선 target으로 선택한다.
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


## focus target 해제. 현재 target이 focus였다면 놓고 기본 AI로 복귀한다.
func clear_focus_target() -> void:
	_focus_target = null
	_focus_stuck_timer = 0.0
	if state == MercState.MOVE_TO_TARGET or state == MercState.ATTACK \
			or state == MercState.ACQUIRE_TARGET:
		_acquire_target()


func get_focus_target() -> Node:
	return _focus_target


func is_focusing() -> bool:
	return _focus_target != null and is_instance_valid(_focus_target) \
		and _target == _focus_target


func get_retreat_point() -> Vector3:
	return _retreat_point
