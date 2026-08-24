extends SceneTree

## TASK-3D-001-5 Navigation3D Convention / Foundation Lock 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. NavigationManager3D 기본 구조(NavigationRegion3D 보유, 그룹 계약, 초기 bake).
##   2. NavigationPolicy3D 단일 소스 상수(radius/height/desired/stuck guard/bake mask).
##   3. Test Agent의 3D ground path 이동(XZ 이동 기준, Y lock, 도달 판정).
##   4. Static Wall obstacle 우회(navmesh carve + 실제 우회 경로 이동).
##   5. Gate OPEN/CLOSED passage shape 존재 = nav 장애물 계약 + 그룹 rebuild 요청.
##   6. unreachable target이 부분 경로 소진(BLOCKED) 판정으로 bounded 정지
##     (stuck guard는 2차 안전망. 영구 stall 없음).
##   7. Runtime 변경 후 debounced rebake coalesce(world.gd 동등 API).

enum Phase {
	SETUP, POLICY, AGENT_CONFIG, PROBE_SETUP, PRE_BAKE, BAKE_SYNC, REACHABILITY,
	RUN_MOVER, RUN_DETOUR, RUN_STALLER, GATE_TOGGLE, GATE_SYNC,
	DEBOUNCE_ARM, DEBOUNCE_CHECK, DONE,
}

const GODOT_EPS := 0.0001
const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 10
const MOVE_FRAME_LIMIT := 1500
const STALL_OBSERVE_FRAMES := 240

## PolicyProbe가 공통 policy만으로 세 카테고리(Worker/Mercenary/Enemy)를 모두
## 수행함을 보이기 위한 test agent. 이동 루프는 enemy_actor/lumberjack의
## get_next_path_position + stuck guard 패턴과 동일하다.
class PolicyProbe extends CharacterBody3D:
	var nav_agent: NavigationAgent3D
	var move_speed := 30.0
	var active := false
	var reached := false
	var stalled_out := false
	var path_positions := PackedVector3Array()
	var _stuck_timer := 0.0
	var _last_pos := Vector3.ZERO

	func _init(category_bit: int) -> void:
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		collision_layer = category_bit
		collision_mask = CollisionLayers3D.MASK_ACTOR_SOLID
		var col := CollisionShape3D.new()
		# Actor Origin LOCK: node origin은 지면 접지점, 볼륨은 위로 오프셋.
		col.position = Vector3(0, NavigationPolicy3D.ACTOR_RADIUS_UNITS, 0)
		var sphere := SphereShape3D.new()
		sphere.radius = NavigationPolicy3D.ACTOR_RADIUS_UNITS
		col.shape = sphere
		add_child(col)
		nav_agent = NavigationAgent3D.new()
		add_child(nav_agent)

	func _ready() -> void:
		NavigationPolicy3D.configure_agent(nav_agent)

	func command_to(target: Vector3) -> void:
		_last_pos = global_position
		_stuck_timer = 0.0
		active = true
		nav_agent.target_position = target
		# target 변경 직후 stale한 finished 상태로 ARRIVED/BLOCKED 오판하지 않도록
		# path를 즉시 갱신한다(get_next_path_position이 repath를 트리거한다).
		nav_agent.get_next_path_position()

	func _physics_process(delta: float) -> void:
		if not active or reached or stalled_out:
			return
		path_positions.append(global_position)
		var status := NavigationPolicy3D.judge_path_status(
			nav_agent, global_position, nav_agent.target_position)
		if status == NavigationPolicy3D.PathStatus.ARRIVED:
			reached = true
			velocity = Vector3.ZERO
			return
		if status == NavigationPolicy3D.PathStatus.BLOCKED:
			stalled_out = true
			velocity = Vector3.ZERO
			return
		if _check_stuck(delta):
			stalled_out = true
			velocity = Vector3.ZERO
			return
		velocity = NavigationPolicy3D.path_follow_velocity_xz(
			global_position, nav_agent, move_speed)
		move_and_slide()

	func _check_stuck(delta: float) -> bool:
		if global_position.distance_to(_last_pos) < NavigationPolicy3D.STUCK_MOVE_EPSILON_UNITS:
			_stuck_timer += delta
			return _stuck_timer >= NavigationPolicy3D.STUCK_TIMEOUT
		_last_pos = global_position
		_stuck_timer = 0.0
		return false


var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav: Node = null
var _bake_signals := 0
var _mover: PolicyProbe = null
var _detourer: PolicyProbe = null
var _staller: PolicyProbe = null
var _gate: StaticBody3D = null
var _gate_shape: CollisionShape3D = null
var _gate_count_before := 0
var _gate_signals_before := 0
var _debounce_count_before := 0
var _debounce_signals_before := 0

const MOVER_START := Vector3(-50, 0, 15)
const MOVER_TARGET := Vector3(50, 0, -15)
const DETOUR_START := Vector3(-40, 0, -70)
const DETOUR_TARGET := Vector3(40, 0, -70)
const STALLER_START := Vector3(0, 0, 35)
const PEN_TARGET := Vector3(0, 0, 55)
const GATE_FROM := Vector3(-20, 0, 78)
const GATE_TO := Vector3(20, 0, 102)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	for probe in [_mover, _detourer, _staller]:
		if probe != null and is_instance_valid(probe):
			probe.free()
	print("TASK3D0015_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= GODOT_EPS


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.POLICY:
			_policy()
		Phase.AGENT_CONFIG:
			_agent_config()
		Phase.PROBE_SETUP:
			_probe_setup()
		Phase.PRE_BAKE:
			_pre_bake()
		Phase.BAKE_SYNC:
			_bake_sync()
		Phase.REACHABILITY:
			_reachability()
		Phase.RUN_MOVER:
			_run_mover()
		Phase.RUN_DETOUR:
			_run_detour()
		Phase.RUN_STALLER:
			_run_staller()
		Phase.GATE_TOGGLE:
			_gate_toggle()
		Phase.GATE_SYNC:
			_gate_sync()
		Phase.DEBOUNCE_ARM:
			_debounce_arm()
		Phase.DEBOUNCE_CHECK:
			_debounce_check()
		Phase.DONE:
			_finish()
			return true
	if _frame > 6000:
		print("TASK3D0015_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	var manager: Node = NavigationManager3D.new()
	manager.name = "NavManager"
	world_scene.add_child(manager)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_nav = root.get_node_or_null("World3DRoot/NavManager")
	_check(_world != null, "empty 3D world loads")
	_check(_nav != null, "navigation manager loads under world root")
	if _world == null or _nav == null:
		_finish()
		return
	_check(_nav.is_in_group(NavigationPolicy3D.SERVICE_GROUP),
		"manager joins navigation_3d group (domain request contract)")
	_check(_nav.get_nav_region() is NavigationRegion3D,
		"manager owns a NavigationRegion3D child")
	_check(_nav.nav_rebuild_count >= 1, "initial bake ran on ready (world.gd parity)")
	_check(_nav.get_navigation_map().is_valid(), "navigation map RID is valid")
	_nav.navigation_baked.connect(func(): _bake_signals += 1)
	_enter(Phase.POLICY)


## -- POLICY: convention 상수 단일 소스 --
func _policy() -> void:
	_check(_near(NavigationPolicy3D.ACTOR_RADIUS_UNITS,
		NavigationPolicy3D.ACTOR_RADIUS_PX * WorldCoords3D.PX_TO_UNIT),
		"actor radius convention = legacy PARSE_AGENT_RADIUS scaled by PX_TO_UNIT")
	_check(_near(NavigationPolicy3D.ACTOR_RADIUS_UNITS, 1.0), "actor radius = 1.0 unit")
	_check(_near(NavigationPolicy3D.ACTOR_HEIGHT_UNITS, WorldCoords3D.TILE_SIZE_UNITS),
		"actor height convention = one logical grid cell (2 units)")
	_check(_near(NavigationPolicy3D.PATH_DESIRED_DISTANCE_UNITS, 0.5)
		and _near(NavigationPolicy3D.TARGET_DESIRED_DISTANCE_UNITS, 0.5),
		"agent desired distances preserve legacy 4px tuning ratio")
	_check(_near(NavigationPolicy3D.STUCK_TIMEOUT, 1.5)
		and _near(NavigationPolicy3D.STUCK_MOVE_EPSILON_UNITS, 0.25),
		"stuck guard constants preserve lumberjack/enemy stall-prevention feel")
	_check(NavigationPolicy3D.BAKE_MASK == CollisionLayers3D.MASK_ACTOR_SOLID,
		"bake mask single source = actor solid set")
	_check((NavigationPolicy3D.BAKE_MASK & CollisionLayers3D.GROUND) != 0,
		"ground plane is parsed as walkable surface")
	_check((NavigationPolicy3D.BAKE_MASK & CollisionLayers3D.MASK_ACTORS) == 0,
		"actors are never parsed as nav obstacles")

	var flat := NavigationPolicy3D.velocity_towards_xz(
		Vector3(0, 5, 0), Vector3(3, 9, 4), 10.0)
	_check(_near(flat.y, 0.0) and _near(flat.length(), 10.0),
		"velocity_towards_xz strips Y and preserves XZ speed (ground XZ basis)")
	_check(NavigationPolicy3D.velocity_towards_xz(Vector3.ONE, Vector3.ONE, 5.0) \
			== Vector3.ZERO,
		"zero-length XZ direction is a safe zero velocity")
	_check(NavigationPolicy3D.reached_xz(Vector3(1, 99, 1), Vector3(1, 0, 1), 0.5),
		"reached_xz ignores height per ground-plane basis")
	_check(not NavigationPolicy3D.reached_xz(Vector3(2, 0, 1), Vector3(1, 0, 1), 0.5),
		"reached_xz still enforces XZ tolerance")
	_check(not NavigationPolicy3D.request_rebuild_debounced(null),
		"rebuild request without tree is a safe no-op")
	_enter(Phase.AGENT_CONFIG)


## -- AGENT_CONFIG: configure_agent 공통 적용 --
func _agent_config() -> void:
	var agent := NavigationAgent3D.new()
	NavigationPolicy3D.configure_agent(agent)
	_check(_near(agent.radius, NavigationPolicy3D.ACTOR_RADIUS_UNITS)
		and _near(agent.height, NavigationPolicy3D.ACTOR_HEIGHT_UNITS),
		"configure_agent applies common radius/height to any domain agent")
	_check(_near(agent.path_desired_distance, NavigationPolicy3D.PATH_DESIRED_DISTANCE_UNITS)
		and _near(agent.target_desired_distance,
			NavigationPolicy3D.TARGET_DESIRED_DISTANCE_UNITS),
		"configure_agent applies shared desired-distance tuning")
	_check(not agent.avoidance_enabled,
		"avoidance stays off (matches legacy actors pushing-free policy)")
	agent.free()
	_enter(Phase.PROBE_SETUP)


func _add_block(pos: Vector3, size: Vector3, layer_bit: int, body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer_bit
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	body.position = pos
	_world.add_child(body)
	return body


## -- PROBE_SETUP: 장애물/게이트/pen/probe 배치 후 physics 등록 대기 --
func _probe_setup() -> void:
	if _mover == null:
		_mover = PolicyProbe.new(CollisionLayers3D.WORKER)
		_mover.name = "ProbeWorkerMover"
		_world.add_child(_mover)
		_detourer = PolicyProbe.new(CollisionLayers3D.MERCENARY)
		_detourer.name = "ProbeMercenaryDetour"
		_world.add_child(_detourer)
		_staller = PolicyProbe.new(CollisionLayers3D.ENEMY)
		_staller.name = "ProbeEnemyStaller"
		_world.add_child(_staller)
		_mover.position = Vector3(MOVER_START.x, WorldCoords3D.GROUND_Y, MOVER_START.z)
		_detourer.position = Vector3(DETOUR_START.x, WorldCoords3D.GROUND_Y, DETOUR_START.z)
		_staller.position = Vector3(STALLER_START.x, WorldCoords3D.GROUND_Y, STALLER_START.z)

		_add_block(Vector3(0, 1.5, -70), Vector3(4, 3, 14),
			CollisionLayers3D.WALL, "DetourWall")
		_gate = _add_block(Vector3(0, 1.5, 90), Vector3(8, 3, 2),
			CollisionLayers3D.GATE, "ProbeGate")
		_gate_shape = _gate.get_child(0) as CollisionShape3D
		# gate 통행선 봉쇄: 회랑 벽이 gate 양끝(x=±4)을 월드 경계 벽까지 잇는다.
		# 이래야 CLOSED gate가 z=90 남북 통과를 유일하게 통제한다(2D defense belt
		# corridor와 동일 기하). 없으면 열린 들판에서 gate 블록 하나만으로는 우회된다.
		_add_block(Vector3(-100, 1.5, 90), Vector3(192, 3, 2), CollisionLayers3D.WALL, "SealWest")
		_add_block(Vector3(100, 1.5, 90), Vector3(192, 3, 2), CollisionLayers3D.WALL, "SealEast")

		# sealed pen: 네 벽이 모서리를 겹치게 배치해 내부가 완전히 봉쇄된다.
		_add_block(Vector3(0, 1.5, 63.5), Vector3(18, 3, 2), CollisionLayers3D.WALL, "PenNorth")
		_add_block(Vector3(0, 1.5, 46.5), Vector3(18, 3, 2), CollisionLayers3D.WALL, "PenSouth")
		_add_block(Vector3(-8.5, 1.5, 55), Vector3(2, 3, 19), CollisionLayers3D.WALL, "PenWest")
		_add_block(Vector3(8.5, 1.5, 55), Vector3(2, 3, 19), CollisionLayers3D.WALL, "PenEast")
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.PRE_BAKE)


## -- PRE_BAKE: runtime 배치 완료 상태로 재bake + map sync 대기 --
func _pre_bake() -> void:
	_nav.rebuild_navigation()
	_wait = 0
	_enter(Phase.BAKE_SYNC)


func _bake_sync() -> void:
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_wait = 0
	_enter(Phase.REACHABILITY)


## -- REACHABILITY: bake 결과 질의(도달/차단 판정은 이동 시작 전 가능) --
func _reachability() -> void:
	_check(_nav.is_target_reachable(MOVER_START, MOVER_TARGET),
		"test agent gets a 3D ground path across open ground")
	_check(_nav.is_target_reachable(DETOUR_START, DETOUR_TARGET),
		"path exists around static wall (obstacle carves but does not seal)")
	_check(not _nav.is_target_reachable(STALLER_START, PEN_TARGET),
		"sealed pen target reported unreachable before any movement starts")
	_check(not _nav.is_target_reachable(GATE_FROM, GATE_TO),
		"CLOSED gate passage blocks the cross-gate path")

	_mover.command_to(MOVER_TARGET)
	_detourer.command_to(DETOUR_TARGET)
	_staller.command_to(PEN_TARGET)
	_wait = 0
	_enter(Phase.RUN_MOVER)


## -- RUN_MOVER: 지면 XZ path 이동 --
func _run_mover() -> void:
	_wait += 1
	if not _mover.reached:
		if _wait > MOVE_FRAME_LIMIT:
			_check(false, "mover reached target within frame limit")
			_finish()
			return
		return
	_check(true, "test agent completed 3D ground path move (%d frames)" % _wait)
	var pos := _mover.global_position
	_check(WorldCoords3D.distance_xz(pos, MOVER_TARGET) <= 1.0,
		"mover arrival within reach tolerance of ground target")
	_check(absf(pos.y - WorldCoords3D.GROUND_Y) < 0.05,
		"movement stayed height-locked on ground plane (no vertical drift)")
	_check(is_finite(pos.x) and is_finite(pos.z), "mover position stays finite")
	_enter(Phase.RUN_DETOUR)


## -- RUN_DETOUR: 정적 obstacle 우회 --
func _run_detour() -> void:
	_wait += 1
	if not _detourer.reached:
		if _wait > MOVE_FRAME_LIMIT:
			_check(false, "detour probe bypassed wall within frame limit")
			_finish()
			return
		return
	_check(true, "detour probe reached target behind the static wall (%d frames)" % _wait)
	var max_deviation := 0.0
	for p in _detourer.path_positions:
		max_deviation = maxf(max_deviation, absf(p.z + 70.0))
	_check(max_deviation >= 5.5,
		"actual route went around the wall (max lateral deviation %.2f unit)" % max_deviation)
	_check(absf(_detourer.global_position.y - WorldCoords3D.GROUND_Y) < 0.05,
		"detour route stayed on ground plane as well")
	_enter(Phase.RUN_STALLER)


## -- RUN_STALLER: unreachable target이 bounded guard로 정지 --
func _run_staller() -> void:
	_wait += 1
	if _wait < STALL_OBSERVE_FRAMES:
		return
	var start_dist := WorldCoords3D.distance_xz(_staller.global_position, STALLER_START)
	_check(_staller.stalled_out,
		"unreachable target stops via BLOCKED path-exhaustion judgment (no permanent MOVE)")
	_check(start_dist <= 12.0,
		"stopped near press point instead of drifting (%.2f unit from start)" % start_dist)
	_check(_staller.velocity == Vector3.ZERO, "stopped probe holds zero velocity")
	_check(is_finite(_staller.global_position.x)
		and is_finite(_staller.global_position.z),
		"stall path leaves no NaN/drift in position")
	_enter(Phase.GATE_TOGGLE)


## -- GATE_TOGGLE: passage shape 제거(OPEN/BREACHED) = 통과 가능 --
func _gate_toggle() -> void:
	var count_before: int = _nav.nav_rebuild_count
	var signals_before := _bake_signals
	_gate_shape.free()
	var routed := NavigationPolicy3D.request_rebuild_debounced(_nav.get_tree())
	_check(routed, "domain rebuild request routes through navigation_3d group contract")
	_check(is_instance_valid(_gate) and _gate.collision_layer == CollisionLayers3D.GATE,
		"gate body itself remains; only passage shape presence encodes state")
	_gate_count_before = count_before
	_gate_signals_before = signals_before
	_wait = 0
	_enter(Phase.GATE_SYNC)


func _gate_sync() -> void:
	_wait += 1
	if _wait <= 30:
		return
	var count_after: int = _nav.nav_rebuild_count
	_check(count_after == _gate_count_before + 1,
		"passage removal triggered exactly one debounced rebake")
	_check(_bake_signals == _gate_signals_before + 1,
		"navigation_baked emitted once for the gate-driven rebake")
	_check(_nav.is_target_reachable(GATE_FROM, GATE_TO),
		"OPEN/BREACHED passage becomes traversable after rebake")
	_enter(Phase.DEBOUNCE_ARM)


## -- DEBOUNCE: 연속 요청 coalesce --
func _debounce_arm() -> void:
	_debounce_count_before = _nav.nav_rebuild_count
	_debounce_signals_before = _bake_signals
	for i in 4:
		_nav.rebuild_navigation_debounced()
	_wait = 0
	_enter(Phase.DEBOUNCE_CHECK)


func _debounce_check() -> void:
	_wait += 1
	if _wait <= 30:
		return
	_check(_nav.nav_rebuild_count == _debounce_count_before + 1,
		"rapid placement requests coalesce into a single debounced rebake")
	_check(_bake_signals == _debounce_signals_before + 1,
		"coalesced rebake emits navigation_baked exactly once")
	_finish()
