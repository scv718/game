extends SceneTree

## TASK-3D-CMB-001-1 Mercenary / Enemy Actor3D 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위(큐 요구사항/완료조건 대응):
##   1. scene 구조: 3D Runtime node만 사용, collision layer/mask = CollisionLayers3D
##     정책(MERCENARY 64 / ENEMY 128 / MASK_ACTOR_SOLID), NavigationAgent3D 보유.
##   2. 상수 스케일: 사거리/추격 한계/reach/gate 감지 거리가 2D px * PX_TO_UNIT 환산
##     그대로다(전투 밸런스 불변).
##   3. Mercenary vs Enemy 자동전투: 상호 target 획득 → 접근(XZ 이동, Y 고정) →
##     attack range 진입 → interval 단위 상호 데미지. facing yaw 적용 확인.
##   4. Player attack 경로 없음: 어느 그룹에도 속하지 않은 Player mock은
##     전투 내내 take_damage되지 않는다.
##   5. lethal death cleanup: died signal 1회, 그룹 제외, freed, Death Ledger에
##     ENEMY/MERCENARY record 각 1회(중복 없음). DAY식 직접 queue_free despawn은
##     record를 만들지 않는다.
##   6. unreachable chase lock 방지: 벽으로 봉쇄된 pen 안의 Enemy를 영구 추격하지
##     않고 BLOCKED 판정으로 bounded 포기(unreachable cooldown) 후 IDLE 복귀.
##   7. Gate 계약: gates_3d 그룹 + is_closed()/take_damage duck-typing. CLOSED 성문
##     공격(GATE_ATTACK) 후 개방 시 route 재개.

enum Phase {
	SETUP, STRUCTURE, COMBAT_SETUP, AUTO_COMBAT, DEATH_WAIT, DEATH_CHECK,
	MERC_DEATH_ARM, MERC_DEATH_CHECK, UNREACH_SETUP, UNREACH_BAKE,
	UNREACH_OBSERVE, GATE_ARM, GATE_OBSERVE, GATE_OPEN_RESUME, CLEANUP, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 12
const COMBAT_FRAME_LIMIT := 1800
const DEATH_FRAME_LIMIT := 1500
const UNREACH_OBSERVE_FRAMES := 300
const GATE_OBSERVE_FRAMES := 260
const GATE_RESUME_FRAME_LIMIT := 700

const MERC_START := Vector3(-14, 0, 0)
const ENEMY_START := Vector3(26, 0, 0)
const ENEMY_ROUTE_FINAL := Vector3(-4, 0, 0)
const PEN_CENTER := Vector3(30, 0, 40)
const PEN_MERC_START := Vector3(30, 0, 20)
const GATE_POS := Vector3(0, 0, 74)
const RAIDER_START := Vector3(0, 0, 71)
const RAIDER_FINAL := Vector3(0, 0, 92)

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav_manager: Node = null
var _game_time: Node = null
var _ledger: Node = null

var _merc: Node = null
var _enemy: Node = null
var _player_mock: Node3D = null
var _merc_attacks := 0
var _merc_hits_taken := 0
var _enemy_attacks := 0
var _enemy_hits_taken := 0
var _enemy_died_count := 0
var _merc_died_count := 0
var _saw_merc_attack_state := false
var _saw_unreach_release := false
var _saw_gate_attack := false
var _ledger_count_before_cleanup := -1

var _pen_enemy: Node = null
var _pen_merc: Node = null
var _gate_mock: Node = null
var _gate_damage_at_open := -1
var _raider: Node = null
var _cleanup_enemy: Node = null


class PlayerMock extends Node3D:
	var damage_received := 0

	func take_damage(amount: int) -> void:
		damage_received += amount


## 2D gate.gd의 최소 계약(is_closed/take_damage)을 따르는 BLD Gate3D 모의 객체.
class MockGate3D extends Node3D:
	var closed := true
	var damage_taken := 0

	func is_closed() -> bool:
		return closed

	func take_damage(amount: int) -> void:
		damage_taken += amount


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DCMB0011_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.COMBAT_SETUP:
			_combat_setup()
		Phase.AUTO_COMBAT:
			_auto_combat()
		Phase.DEATH_WAIT:
			_death_wait()
		Phase.DEATH_CHECK:
			_death_check()
		Phase.MERC_DEATH_ARM:
			_merc_death_arm()
		Phase.MERC_DEATH_CHECK:
			_merc_death_check()
		Phase.UNREACH_SETUP:
			_unreach_setup()
		Phase.UNREACH_BAKE:
			_unreach_bake()
		Phase.UNREACH_OBSERVE:
			_unreach_observe()
		Phase.GATE_ARM:
			_gate_arm()
		Phase.GATE_OBSERVE:
			_gate_observe()
		Phase.GATE_OPEN_RESUME:
			_gate_open_resume()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if _frame > 12000:
		print("TASK3DCMB0011_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_game_time = root.get_node_or_null("GameTime")
	_ledger = root.get_node_or_null("DeathLedger")
	_check(_world != null, "3D world loads")
	_check(_game_time != null and _ledger != null,
		"GameTime/DeathLedger autoloads available to the 3D combat runtime")
	if _world == null or _game_time == null or _ledger == null:
		_finish()
		return
	_game_time.set_auto_advance(false)
	_nav_manager = load("res://scripts/navigation_manager_3d.gd").new()
	_nav_manager.name = "NavManager"
	_world.add_child(_nav_manager)
	_enter(Phase.STRUCTURE)


## -- STRUCTURE: scene 구조 / collision 정책 / 상수 스케일 --
func _structure() -> void:
	var allowed := {
		"CharacterBody3D": true, "CollisionShape3D": true, "Node3D": true,
		"MeshInstance3D": true, "NavigationAgent3D": true,
	}
	for setup in [
		["res://scenes/mercenary_3d.tscn", "Mercenary3D", 64],
		["res://scenes/enemy_3d.tscn", "Enemy3D", 128],
	]:
		var instance: Node = (load(setup[0]) as PackedScene).instantiate()
		_check(instance.get_class() == "CharacterBody3D",
			"%s root is a CharacterBody3D (no 2D actor)" % setup[1])
		_check(instance.name == String(setup[1]), "%s keeps its scene name" % setup[1])
		_check(instance.collision_layer == setup[2],
			"%s sits on its own actor layer (%d)" % [setup[1], setup[2]])
		_check(instance.collision_mask == CollisionLayers3D.MASK_ACTOR_SOLID,
			"%s mask = MASK_ACTOR_SOLID (actors never collide with actors)" % setup[1])
		_check(instance.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING,
			"%s uses floating motion (ground XZ, no gravity)" % setup[1])
		var clean := true
		var has_nav_agent := false
		var has_visual := false
		var stack: Array[Node] = [instance]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if not allowed.has(node.get_class()):
				clean = false
				print("  offending node in %s: %s (%s)"
					% [setup[1], node.name, node.get_class()])
			if node is NavigationAgent3D:
				has_nav_agent = true
			if node.name == "Visual":
				has_visual = true
			stack.append_array(node.get_children())
		_check(clean, "%s scene contains only 3D runtime nodes" % setup[1])
		_check(has_nav_agent, "%s owns a NavigationAgent3D child" % setup[1])
		_check(has_visual, "%s separates the visual into a Visual child" % setup[1])
		instance.free()

	_check(_near(MercenaryActor3D.ATTACK_RANGE, 26.0 * WorldCoords3D.PX_TO_UNIT),
		"mercenary attack range preserves legacy 26px scaled by PX_TO_UNIT")
	_check(_near(MercenaryActor3D.CHASE_RETURN_DISTANCE,
		180.0 * WorldCoords3D.PX_TO_UNIT),
		"chase return limit preserves legacy 180px ratio")
	_check(_near(MercenaryActor3D.REACH_DISTANCE, 12.0 * WorldCoords3D.PX_TO_UNIT),
		"reach distance preserves legacy 12px ratio")
	var enemy := EnemyActor3D.new()
	_check(_near(EnemyActor3D.GATE_ATTACK_RANGE, 40.0 * WorldCoords3D.PX_TO_UNIT),
		"gate attack trigger preserves legacy 40px ratio")
	_check(_near(enemy.move_speed, 90.0 * WorldCoords3D.PX_TO_UNIT),
		"enemy prototype move speed stays in world units (90px scaled)")
	enemy.free()
	_enter(Phase.COMBAT_SETUP)


## -- COMBAT_SETUP: 전투 참여자 배치 + physics/nav sync 대기 --
func _combat_setup() -> void:
	if _merc == null:
		var data := MercenaryData.new("m1", "Garrick")
		data.max_hp = 100
		data.attack_damage = 10
		data.attack_interval = 1.0
		data.move_speed = 120.0
		_merc = (load("res://scenes/mercenary_3d.tscn") as PackedScene).instantiate()
		_merc.merc_data = data
		_merc.position = MERC_START
		_merc.defense_point = MERC_START
		_world.add_child(_merc)
		_merc.attack_performed.connect(func(_t): _merc_attacks += 1)
		_merc.hit_taken.connect(func(_a): _merc_hits_taken += 1)
		_merc.died.connect(func(_m): _merc_died_count += 1)

		_enemy = (load("res://scenes/enemy_3d.tscn") as PackedScene).instantiate()
		_enemy.setup("enemy_west_t1", "Raider", "west")
		_enemy.position = ENEMY_START
		_world.add_child(_enemy)
		_enemy.set_route([], ENEMY_ROUTE_FINAL)
		_enemy.attack_performed.connect(func(_t): _enemy_attacks += 1)
		_enemy.hit_taken.connect(func(_a): _enemy_hits_taken += 1)
		_enemy.died.connect(func(_e): _enemy_died_count += 1)

		_player_mock = PlayerMock.new()
		_player_mock.name = "PlayerMock"
		_player_mock.position = Vector3(8, 0, 4)
		_world.add_child(_player_mock)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES + NAV_SYNC_FRAMES:
		return
	_wait = 0
	_check(_merc.is_in_group("mercenaries_3d"), "mercenary joins mercenaries_3d group")
	_check(_enemy.is_in_group("enemies_3d"), "enemy joins enemies_3d group")
	_check(_merc.current_hp == 100, "mercenary initializes hp from merc_data")
	_check(_enemy.current_hp == 60, "enemy initializes hp from prototype stats")
	var agent: NavigationAgent3D = _merc._nav_agent
	_check(_near(agent.radius, NavigationPolicy3D.ACTOR_RADIUS_UNITS)
		and _near(agent.height, NavigationPolicy3D.ACTOR_HEIGHT_UNITS),
		"actor nav agent is tuned by the shared NavigationPolicy3D convention")
	_enter(Phase.AUTO_COMBAT)


## -- AUTO_COMBAT: 자동전투 수렴(Mercenary vs Enemy 상호 교전) --
func _auto_combat() -> void:
	_wait += 1
	if _merc.state == MercenaryActor3D.MercState.ATTACK:
		_saw_merc_attack_state = true
	if not (_enemy.current_hp < 60 and _merc.current_hp < 100):
		if _wait > COMBAT_FRAME_LIMIT:
			_check(false, "mutual engagement within frame limit")
			_finish()
		return
	_wait = 0
	_check(true, "mercenaries and enemies exchange damage through auto combat")
	_check(_merc_attacks >= 1 and _enemy_attacks >= 1,
		"attack visual hooks fire on both sides")
	_check(_merc_hits_taken >= 1 and _enemy_hits_taken >= 1,
		"hit hooks fire on both sides")
	_check(_merc.alive and _enemy.alive, "both fighters stay alive mid-engagement")
	var gap := WorldCoords3D.distance_xz(_merc.global_position, _enemy.global_position)
	_check(gap <= MercenaryActor3D.ATTACK_RANGE + 0.5,
		"fighters close to legacy attack range before swinging (%.2f unit)" % gap)
	_check(absf(_merc.global_position.y - WorldCoords3D.GROUND_Y) < 0.05
		and absf(_enemy.global_position.y - WorldCoords3D.GROUND_Y) < 0.05,
		"combat movement stays height-locked on the ground plane")
	_check(is_finite(_merc.global_position.x) and is_finite(_enemy.global_position.z),
		"combat positions stay finite")
	_check(absf(_merc._visual.rotation.y) > 0.01,
		"mercenary visual faces the fight (facing yaw applied)")
	_check(_player_mock.damage_received == 0,
		"groupless player mock never takes damage (no player attack path)")
	_enter(Phase.DEATH_WAIT)


## -- DEATH_WAIT: lethal death(Enemy 사망)까지 자동전투 지속 --
func _death_wait() -> void:
	_wait += 1
	if _enemy_died_count == 0 and _wait <= DEATH_FRAME_LIMIT:
		return
	_check(_enemy_died_count == 1, "enemy lethal death emits died exactly once")
	_wait = 0
	_enter(Phase.DEATH_CHECK)


func _count_records_for(uid: String) -> int:
	var n := 0
	for record in _ledger.get_all_records():
		if record.source_uid == uid:
			n += 1
	return n


func _record_for(uid: String) -> DeathRecord:
	for record in _ledger.get_all_records():
		if record.source_uid == uid:
			return record
	return null


## -- DEATH_CHECK: 사망 cleanup / ledger 기록 / cleanup-despawn 무기록 --
func _death_check() -> void:
	if is_instance_valid(_enemy):
		if _wait < PHYSICS_WAIT_FRAMES:
			_wait += 1
			return
	_check(not is_instance_valid(_enemy), "dead enemy is freed from the world")
	_check(_group_count("enemies_3d") == 0,
		"dead enemy leaves the enemies_3d group (stale target source removed)")
	_check(_merc.alive and _merc.current_hp > 0,
		"surviving mercenary keeps fighting state")
	var record := _record_for("enemy_west_t1")
	_check(record != null, "lethal enemy death is recorded in the Death Ledger")
	_check(_count_records_for("enemy_west_t1") == 1,
		"same real death produces exactly one ledger record (no duplicates)")
	if record != null:
		_check(record.source_kind == DeathRecord.SourceKind.ENEMY,
			"ledger record kind is ENEMY")
		_check(record.death_position is Vector2,
			"3D death position is stored in the Vector2 logical schema")
		_check(record.death_position != Vector2.ZERO,
			"death position carries the logical map coordinate of the fall")

	# DAY cleanup/despawn 경로(직접 queue_free)는 record를 만들면 안 된다.
	_ledger_count_before_cleanup = _ledger.get_all_records().size()
	_cleanup_enemy = (load("res://scenes/enemy_3d.tscn") as PackedScene).instantiate()
	_cleanup_enemy.setup("enemy_despawn_only", "Raider", "north")
	_cleanup_enemy.position = Vector3(-60, 0, 60)
	_world.add_child(_cleanup_enemy)
	_wait = 0
	_enter(Phase.MERC_DEATH_ARM)


## -- MERC_DEATH_ARM/MERC_DEATH_CHECK: 용병 lethal death cleanup --
func _merc_death_arm() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	# DAY로 돌아갈 때 roster가 쓰는 despawn 경로와 동일한 queue_free 정리.
	_cleanup_enemy.queue_free()
	_merc.take_damage(999999)
	_check(not _merc.alive, "lethal damage kills the mercenary through take_damage")
	_check(_merc_died_count == 1, "mercenary lethal death emits died exactly once")
	_check(not _merc.is_in_group("mercenaries_3d"),
		"dead mercenary leaves the mercenaries_3d group")
	_check(_merc.merc_data.alive == false,
		"roster data reflects the death (alive=false, no respawn)")
	_enter(Phase.MERC_DEATH_CHECK)


func _merc_death_check() -> void:
	if is_instance_valid(_merc) and _wait < PHYSICS_WAIT_FRAMES:
		_wait += 1
		return
	_wait = 0
	_check(not is_instance_valid(_merc), "dead mercenary is freed from the world")
	var record := _record_for("m1")
	_check(record != null, "lethal mercenary death is recorded in the Death Ledger")
	_check(_count_records_for("m1") == 1,
		"mercenary death produces exactly one ledger record")
	if record != null:
		_check(record.source_kind == DeathRecord.SourceKind.MERCENARY,
			"ledger record kind is MERCENARY")
		_check(record.display_name == "Garrick",
			"ledger snapshot keeps the fallen identity")
	_check(_count_records_for("enemy_despawn_only") == 0,
		"despawn-only cleanup created no death records")
	_check(_ledger.get_all_records().size() == _ledger_count_before_cleanup + 1,
		"only the real lethal mercenary death grew the ledger")
	_enter(Phase.UNREACH_SETUP)


## -- UNREACH_SETUP/BAKE/OBSERVE: unreachable target chase lock 방지 --
func _add_wall(pos: Vector3, size: Vector3, wall_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = CollisionLayers3D.WALL
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	body.position = pos
	_world.add_child(body)


func _unreach_setup() -> void:
	if _pen_enemy == null:
		# sealed pen: 네 벽이 모서리를 겹치게 배치해 내부가 완전히 봉쇄된다.
		_add_wall(PEN_CENTER + Vector3(0, 1.5, -6.5), Vector3(18, 3, 2), "PenNorth")
		_add_wall(PEN_CENTER + Vector3(0, 1.5, 6.5), Vector3(18, 3, 2), "PenSouth")
		_add_wall(PEN_CENTER + Vector3(-8.5, 1.5, 0), Vector3(2, 3, 15), "PenWest")
		_add_wall(PEN_CENTER + Vector3(8.5, 1.5, 0), Vector3(2, 3, 15), "PenEast")
		_pen_enemy = (load("res://scenes/enemy_3d.tscn") as PackedScene).instantiate()
		_pen_enemy.setup("enemy_penned", "Raider", "south")
		_pen_enemy.position = PEN_CENTER
		_world.add_child(_pen_enemy)
		var data := MercenaryData.new("m2", "Bram")
		data.max_hp = 100
		data.attack_damage = 10
		data.attack_interval = 1.0
		data.move_speed = 120.0
		_pen_merc = (load("res://scenes/mercenary_3d.tscn") as PackedScene).instantiate()
		_pen_merc.merc_data = data
		_pen_merc.position = PEN_MERC_START
		_pen_merc.defense_point = PEN_MERC_START
		_world.add_child(_pen_merc)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.UNREACH_BAKE)


func _unreach_bake() -> void:
	_nav_manager.rebuild_navigation()
	_wait = 0
	_enter(Phase.UNREACH_OBSERVE)


func _unreach_observe() -> void:
	_wait += 1
	var pos: Vector3 = _pen_merc.global_position
	var inside_pen: bool = absf(pos.x - PEN_CENTER.x) < 7.0 \
		and absf(pos.z - PEN_CENTER.z) < 5.0
	if inside_pen:
		_check(false, "mercenary never penetrates the sealed pen while chasing")
		_finish()
		return
	if _pen_merc.state == MercenaryActor3D.MercState.IDLE:
		_saw_unreach_release = true
	if _wait < UNREACH_OBSERVE_FRAMES:
		return
	_check(true, "sealed-pen chase ends without penetrating the pen")
	_check(_saw_unreach_release,
		"unreachable target releases the chase into IDLE (bounded, no permanent lock)")
	_check(_pen_enemy.alive and _pen_enemy.current_hp == 60,
		"penned enemy stays untouched behind the wall")
	var start_dist := WorldCoords3D.distance_xz(pos, PEN_MERC_START)
	_check(start_dist < 20.0,
		"blocked chase stops near the press point instead of drifting (%.2f unit)" % start_dist)
	_check(_pen_merc.get_focus_target() == null, "focus-free chase leaves focus cleared")
	_check(is_finite(pos.x) and is_finite(pos.z), "blocked chase leaves no NaN/drift")
	_enter(Phase.GATE_ARM)


## -- GATE_ARM/OBSERVE/OPEN_RESUME: gates_3d 계약(CLOSED 공격 → OPEN 통과) --
func _gate_arm() -> void:
	if _raider == null:
		_gate_mock = MockGate3D.new()
		_gate_mock.name = "GateMock"
		_gate_mock.position = GATE_POS
		_world.add_child(_gate_mock)
		_gate_mock.add_to_group("gates_3d")
		_raider = (load("res://scenes/enemy_3d.tscn") as PackedScene).instantiate()
		_raider.setup("enemy_gate_raider", "Breacher", "north")
		_raider.position = RAIDER_START
		_world.add_child(_raider)
		_raider.set_route([], RAIDER_FINAL)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.GATE_OBSERVE)


func _gate_observe() -> void:
	_wait += 1
	if _raider.state == EnemyActor3D.EnemyState.GATE_ATTACK:
		_saw_gate_attack = true
	if not _saw_gate_attack or (_gate_mock as MockGate3D).damage_taken < 2:
		if _wait > GATE_OBSERVE_FRAMES:
			_check(false, "closed gate draws raider into GATE_ATTACK and takes hits")
			_finish()
		return
	_check(_raider.get_gate_target() == _gate_mock,
		"raider targets the nearest closed gate through the gates_3d contract")
	_check((_gate_mock as MockGate3D).damage_taken >= 2,
		"raider chips the closed gate on its attack interval (%d damage)"
		% (_gate_mock as MockGate3D).damage_taken)
	_gate_damage_at_open = (_gate_mock as MockGate3D).damage_taken
	(_gate_mock as MockGate3D).closed = false
	_wait = 0
	_enter(Phase.GATE_OPEN_RESUME)


func _gate_open_resume() -> void:
	_wait += 1
	var passed: bool = _raider.state == EnemyActor3D.EnemyState.HOLD \
		or WorldCoords3D.distance_xz(_raider.global_position, RAIDER_FINAL) <= 2.0
	if not passed and _wait <= GATE_RESUME_FRAME_LIMIT:
		return
	_check(passed, "opened gate lets the raider resume its route (no re-assault)")
	_check(_raider.state != EnemyActor3D.EnemyState.GATE_ATTACK,
		"OPEN gate is never a valid assault target")
	_check(_raider.get_gate_target() == null, "gate target clears when passage opens")
	_check((_gate_mock as MockGate3D).damage_taken == _gate_damage_at_open,
		"no further gate damage lands after opening")
	_enter(Phase.CLEANUP)


## -- CLEANUP: 잔여 reference/orphan 정리 검증 --
func _cleanup() -> void:
	if is_instance_valid(_pen_merc):
		_pen_merc.free()
	if is_instance_valid(_pen_enemy):
		_pen_enemy.free()
	if is_instance_valid(_gate_mock):
		_gate_mock.free()
	if is_instance_valid(_raider):
		_raider.free()
	_wait += 1
	if _wait < 4:
		return
	_check(_group_count("mercenaries_3d") == 0,
		"no orphan mercenaries remain after cleanup")
	_check(_group_count("enemies_3d") == 0,
		"no orphan enemies remain after cleanup")
	_check(_group_count("gates_3d") == 0,
		"mock gate leaves no residue in gates_3d")
	var sources := {}
	var duplicated := false
	for record in _ledger.get_all_records():
		if sources.has(record.source_uid):
			duplicated = true
		sources[record.source_uid] = true
	_check(not duplicated, "ledger holds no duplicate source_uid across the battle")
	_finish()
