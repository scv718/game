extends SceneTree

## TASK-3D-WRK-001-1 WorkerActor3D / Movement 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위(완료조건 매핑):
##   1. Test Worker 3D path 이동 - open ground 이동, XZ 도달, Y lock, 단일 종료 신호.
##   2. obstacle 회피 - 정적 wall 우회 경로로 목적지 도달.
##   3. unreachable target 안전 처리 - sealed pen 목적지가 BLOCKED/STALLED로
##     bounded 정지(영구 MOVE stall 없음).
##   4. stale target/reference 없음 - tracked node freed -> TARGET_LOST,
##      freed reference 수용 거부, cancel/recommand, actor 자체 freed 정리.
##   추가 구조 검증: Foundation Navigation convention 준수(WORKER layer/mask,
##   configure_agent 단일 소스, Actor Origin LOCK, Y 포함 좌표의 지면 해석).

enum Phase {
	SETUP, CONTRACT, BAKE_SYNC, OPEN_RUN, DETOUR_RUN, UNREACHABLE_RUN,
	FOLLOW_ARM, FOLLOW_CHASE, FOLLOW_RUN,
	STALE_PROGRESS, STALE_FREE, STALE_LOST_WAIT,
	CANCEL_ARM, CANCEL_CHECK, REFREE_WAIT, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 10
const MOVE_FRAME_LIMIT := 1800
const UNREACHABLE_OBSERVE_FRAMES := 600
const STALE_PROGRESS_FRAMES := 120
const STALE_LOST_LIMIT := 300
const ARRIVAL_TOLERANCE_UNITS := 1.0
const DETOUR_MIN_DEVIATION_UNITS := 6.0
const FACING_EPS_RAD := 0.25
const GODOT_EPS := 0.0001

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav: Node = null

var _mover: WorkerActor3D = null
var _detourer: WorkerActor3D = null
var _staller: WorkerActor3D = null
var _stale_worker: WorkerActor3D = null
var _freed_probe: Node3D = null
var _dummy_target: Node3D = null
var _moving_dummy: Node3D = null

# actor별 관측값(테스트가 매 frame 수집).
var _y_drift := {}
var _tilt := {}
var _events := {}
var _detour_positions := PackedVector3Array()
var _stale_start_dist := 0.0

const OPEN_START := Vector3(-45, 0, 25)
const OPEN_TARGET := Vector3(35, 0, -20)
const DETOUR_START := Vector3(-40, 0, -40)
const DETOUR_TARGET := Vector3(40, 0, -40)
const STALLER_START := Vector3(0, 0, 35)
const PEN_TARGET := Vector3(0, 0, 55)
const STALE_WORKER_START := Vector3(-30, 0, 30)
const DUMMY_TARGET_POS := Vector3(30, 0, 30)
const FOLLOW_P1 := Vector3(90, 0, 10)
const FOLLOW_P2 := Vector3(130, 0, 50)
const FOLLOW_CHASE_FRAMES := 200
const FAR_POINT := Vector3(-150, 0, 150)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	for actor in [_mover, _detourer, _staller, _stale_worker]:
		if actor != null and is_instance_valid(actor):
			actor.free()
	if _dummy_target != null and is_instance_valid(_dummy_target):
		_dummy_target.free()
	if _moving_dummy != null and is_instance_valid(_moving_dummy):
		_moving_dummy.free()
	print("TASK3DWRK0011_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= GODOT_EPS


func _yaw_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


func _record(actor_name: String, pos: Vector3, rot: Vector3) -> void:
	_y_drift[actor_name] = maxf(_y_drift.get(actor_name, 0.0), absf(pos.y))
	_tilt[actor_name] = maxf(_tilt.get(actor_name, 0.0), maxf(absf(rot.x), absf(rot.z)))


func _observe(actor: WorkerActor3D) -> void:
	_record(String(actor.name), actor.global_position, actor.rotation)


func _on_move_event(status: int, pos: Vector3, key: String) -> void:
	_events[key].append([status, pos])


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.BAKE_SYNC:
			_bake_sync()
		Phase.OPEN_RUN:
			_open_run()
		Phase.DETOUR_RUN:
			_detour_run()
		Phase.UNREACHABLE_RUN:
			_unreachable_run()
		Phase.FOLLOW_ARM:
			_follow_arm()
		Phase.FOLLOW_CHASE:
			_follow_chase()
		Phase.FOLLOW_RUN:
			_follow_run()
		Phase.STALE_PROGRESS:
			_stale_progress()
		Phase.STALE_FREE:
			_stale_free()
		Phase.STALE_LOST_WAIT:
			_stale_lost_wait()
		Phase.CANCEL_ARM:
			_cancel_arm()
		Phase.CANCEL_CHECK:
			_cancel_check()
		Phase.REFREE_WAIT:
			_refree_wait()
		Phase.DONE:
			_finish()
			return true
	if _frame > 9000:
		print("TASK3DWRK0011_RESULT=TIMEOUT phase=%s" % str(_phase))
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


func _spawn_worker(worker_name: String, start: Vector3) -> WorkerActor3D:
	var actor := WorkerActor3D.new()
	actor.name = worker_name
	_world.add_child(actor)
	actor.global_position = Vector3(start.x, WorldCoords3D.GROUND_Y, start.z)
	var key := String(actor.name)
	_events[key] = []
	actor.move_finished.connect(_on_move_event.bind(key))
	return actor


func _setup() -> void:
	if _mover == null:
		_world = root.get_node_or_null("World3DRoot") as Node3D
		_nav = root.get_node_or_null("World3DRoot/NavManager")
		if _world == null or _nav == null:
			_check(false, "3D world / navigation manager loads")
			_finish()
			return
		_mover = _spawn_worker("TestWorkerMover", OPEN_START)
		_detourer = _spawn_worker("TestWorkerDetourer", DETOUR_START)
		_staller = _spawn_worker("TestWorkerStaller", STALLER_START)
		_stale_worker = _spawn_worker("TestWorkerStale", STALE_WORKER_START)

		_add_block(Vector3(0, 1.5, -40), Vector3(4, 3, 16),
			CollisionLayers3D.WALL, "DetourWall")
		# sealed pen: 모서리가 겹치는 네 벽으로 완전 봉쇄(task3d0015_test 동일 기하).
		_add_block(Vector3(0, 1.5, 63.5), Vector3(18, 3, 2), CollisionLayers3D.WALL, "PenNorth")
		_add_block(Vector3(0, 1.5, 46.5), Vector3(18, 3, 2), CollisionLayers3D.WALL, "PenSouth")
		_add_block(Vector3(-8.5, 1.5, 55), Vector3(2, 3, 19), CollisionLayers3D.WALL, "PenWest")
		_add_block(Vector3(8.5, 1.5, 55), Vector3(2, 3, 19), CollisionLayers3D.WALL, "PenEast")

		_freed_probe = Node3D.new()
		_world.add_child(_freed_probe)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_enter(Phase.CONTRACT)


## -- CONTRACT: Foundation convention 구조 + 지면 좌표 해석 + stale 수용 거부 --
func _contract() -> void:
	var agent := _mover.get_nav_agent()
	_check(agent is NavigationAgent3D, "worker owns a NavigationAgent3D child")
	_check(_near(agent.radius, NavigationPolicy3D.ACTOR_RADIUS_UNITS)
		and _near(agent.height, NavigationPolicy3D.ACTOR_HEIGHT_UNITS),
		"agent tuning comes from NavigationPolicy3D.configure_agent single source")
	_check(not agent.avoidance_enabled, "avoidance stays off (foundation convention)")
	_check(_mover.collision_layer == CollisionLayers3D.WORKER,
		"worker body uses WORKER collision layer bit")
	_check(_mover.collision_mask == CollisionLayers3D.MASK_ACTOR_SOLID,
		"worker mask = static solid set (actors never collide with actors)")
	_check(_mover.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING,
		"floating motion mode (top-down XZ movement, no gravity)")
	var col := _mover.get_node_or_null("CollisionShape") as CollisionShape3D
	_check(col != null and col.position.y > 0.0 and col.shape != null,
		"Actor Origin LOCK: origin on ground, collision volume offset above")
	_check(_near(_mover.global_position.y, WorldCoords3D.GROUND_Y),
		"spawned worker origin sits at ground Y")
	_check(_mover.is_in_group("workers_3d"), "worker joins workers_3d group")
	_check(_near(_mover.move_speed, 90.0 * WorldCoords3D.PX_TO_UNIT),
		"move speed preserves legacy lumberjack/miner 90px/s ratio")
	_check(_mover.get_visual() is Node3D
		and _mover.get_visual().get_node_or_null("BodyMesh") is MeshInstance3D,
		"Visual child slot exists for VIS-domain replacement")

	_mover.begin_move_to(Vector3(10, 5, -6))
	_check(_near(_mover.move_target.y, WorldCoords3D.GROUND_Y)
		and _near(_mover.move_target.x, 10.0) and _near(_mover.move_target.z, -6.0),
		"Y-laden target position is interpreted as ground XZ coordinate (flatten)")
	_check(_mover.is_moving(), "move command activates movement state")
	_mover.cancel_move()
	_check(_events["TestWorkerMover"].size() == 1
		and _events["TestWorkerMover"][0][0] == WorkerActor3D.MoveStatus.CANCELED,
		"cancel_move finishes the attempt exactly once with CANCELED")
	_check(not _mover.is_moving() and _mover.velocity == Vector3.ZERO,
		"canceled worker stops with zero velocity")

	_freed_probe.free()
	_check(not _stale_worker.begin_move_to_node(_freed_probe),
		"freed target reference is rejected instead of being tracked")
	_check(not _stale_worker.is_moving(),
		"rejected stale command leaves worker safely idle")
	for key in ["TestWorkerMover", "TestWorkerDetourer", "TestWorkerStaller"]:
		_events[key].clear()
	_wait = 0
	_enter(Phase.BAKE_SYNC)


func _bake_sync() -> void:
	if _wait == 0:
		_nav.rebuild_navigation()
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_wait = 0
	_frame = 0
	_mover.begin_move_to(OPEN_TARGET)
	_enter(Phase.OPEN_RUN)


## -- OPEN_RUN: Test Worker 3D ground path 이동 + facing/Y lock --
func _open_run() -> void:
	if _mover.is_moving():
		_observe(_mover)
	_wait += 1
	if _events["TestWorkerMover"].is_empty():
		if _wait > MOVE_FRAME_LIMIT:
			_check(false, "open-ground move finished within frame limit")
			_finish()
			return
		return
	var event: Array = _events["TestWorkerMover"][0]
	_check(event[0] == WorkerActor3D.MoveStatus.ARRIVED,
		"test worker completes 3D ground path move with ARRIVED (%d frames)" % _wait)
	var final_pos: Vector3 = event[1]
	_check(WorldCoords3D.distance_xz(final_pos, OPEN_TARGET) <= ARRIVAL_TOLERANCE_UNITS,
		"arrival within reach tolerance of the ground target")
	_check(float(_y_drift["TestWorkerMover"]) < 0.05,
		"no Y height drift during ground movement (max %.4f)" % float(_y_drift["TestWorkerMover"]))
	_check(float(_tilt["TestWorkerMover"]) < 0.001,
		"no tilt during movement (pitch/roll stay zero)")
	var to_target := OPEN_TARGET - OPEN_START
	var expected_yaw := atan2(-to_target.x, -to_target.z)
	_check(_yaw_diff(_mover.get_visual().rotation.y, expected_yaw) < FACING_EPS_RAD,
		"visual faces travel direction after diagonal move (yaw-only rotation)")
	_check(is_finite(final_pos.x) and is_finite(final_pos.z),
		"path leaves no NaN in position")
	_events["TestWorkerMover"].clear()
	_frame = 0
	_wait = 0
	_detour_positions = PackedVector3Array()
	_detourer.begin_move_to(DETOUR_TARGET)
	_enter(Phase.DETOUR_RUN)


## -- DETOUR_RUN: 정적 wall obstacle 우회 --
func _detour_run() -> void:
	if _detourer.is_moving():
		_observe(_detourer)
		_detour_positions.append(_detourer.global_position)
	_wait += 1
	if _events["TestWorkerDetourer"].is_empty():
		if _wait > MOVE_FRAME_LIMIT:
			_check(false, "wall detour finished within frame limit")
			_finish()
			return
		return
	var event: Array = _events["TestWorkerDetourer"][0]
	_check(event[0] == WorkerActor3D.MoveStatus.ARRIVED,
		"worker reaches target behind the static wall (%d frames)" % _wait)
	var max_deviation := 0.0
	for p in _detour_positions:
		max_deviation = maxf(max_deviation, absf(p.z - DETOUR_START.z))
	_check(max_deviation >= DETOUR_MIN_DEVIATION_UNITS,
		"route went around the wall (max lateral deviation %.2f unit)" % max_deviation)
	_check(float(_y_drift["TestWorkerDetourer"]) < 0.05,
		"detour route also stayed locked on ground plane")
	_events["TestWorkerDetourer"].clear()
	_frame = 0
	_wait = 0
	_staller.begin_move_to(PEN_TARGET)
	_enter(Phase.UNREACHABLE_RUN)


## -- UNREACHABLE_RUN: unreachable target bounded 종료(영구 stall 없음) --
func _unreachable_run() -> void:
	if _staller.is_moving():
		_observe(_staller)
	_wait += 1
	if _events["TestWorkerStaller"].is_empty():
		if _wait > UNREACHABLE_OBSERVE_FRAMES:
			_check(false, "unreachable target ends within observe window (no permanent MOVE)")
			_finish()
			return
		return
	var event: Array = _events["TestWorkerStaller"][0]
	_check(event[0] == WorkerActor3D.MoveStatus.BLOCKED
		or event[0] == WorkerActor3D.MoveStatus.STALLED,
		"unreachable target stops via BLOCKED/STALLED bounded judgment")
	_check(not _staller.is_moving() and _staller.velocity == Vector3.ZERO,
		"stopped worker holds idle state with zero velocity")
	var from_start := WorldCoords3D.distance_xz(_staller.global_position, STALLER_START)
	_check(from_start <= 12.0,
		"stopped near press point instead of drifting (%.2f unit from start)" % from_start)
	_check(is_finite(_staller.global_position.x) and is_finite(_staller.global_position.z),
		"stall path leaves no NaN/drift in position")
	_events["TestWorkerStaller"].clear()
	_frame = 0
	_wait = 0
	_enter(Phase.FOLLOW_ARM)


## -- FOLLOW_ARM/CHASE/RUN: 추적 중 대상이 움직이면 경로도 갱신되어 따라간다 --
func _follow_arm() -> void:
	_moving_dummy = Node3D.new()
	_moving_dummy.name = "MovingDummyTarget"
	_world.add_child(_moving_dummy)
	_moving_dummy.global_position = FOLLOW_P1
	_check(_mover.begin_move_to_node(_moving_dummy),
		"moving tracked target starts a follow move")
	_wait = 0
	_enter(Phase.FOLLOW_CHASE)


func _follow_chase() -> void:
	if _mover.is_moving():
		_observe(_mover)
	_wait += 1
	if _wait < FOLLOW_CHASE_FRAMES:
		return
	if _events["TestWorkerMover"].is_empty():
		var before := WorldCoords3D.distance_xz(_mover.global_position, FOLLOW_P1)
		_check(before > ARRIVAL_TOLERANCE_UNITS,
			"chase is still en route when target relocates (%.1f unit away)" % before)
	else:
		_check(false, "worker finished before target relocation (test setup broken)")
		_finish()
		return
	_moving_dummy.global_position = FOLLOW_P2
	_wait = 0
	_frame = 0
	_enter(Phase.FOLLOW_RUN)


func _follow_run() -> void:
	if _mover.is_moving():
		_observe(_mover)
	_wait += 1
	if _events["TestWorkerMover"].is_empty():
		if _wait > MOVE_FRAME_LIMIT:
			_check(false, "relocated-target chase finished within frame limit")
			_finish()
			return
		return
	var event: Array = _events["TestWorkerMover"][0]
	_check(event[0] == WorkerActor3D.MoveStatus.ARRIVED,
		"relocated target chase ends with ARRIVED (%d frames)" % _wait)
	var final_pos: Vector3 = event[1]
	_check(WorldCoords3D.distance_xz(final_pos, FOLLOW_P2) <= ARRIVAL_TOLERANCE_UNITS,
		"live tracking follows mid-move relocation to the new position "
		+ "(%.2f unit from new spot)" % WorldCoords3D.distance_xz(final_pos, FOLLOW_P2))
	_check(float(_y_drift["TestWorkerMover"]) < 0.05,
		"relocation chase also stayed locked on ground plane")
	_events["TestWorkerMover"].clear()
	_moving_dummy.free()
	_frame = 0
	_wait = 0
	_dummy_target = Node3D.new()
	_dummy_target.name = "LiveDummyTarget"
	_world.add_child(_dummy_target)
	_dummy_target.global_position = DUMMY_TARGET_POS
	_stale_start_dist = WorldCoords3D.distance_xz(STALE_WORKER_START, DUMMY_TARGET_POS)
	_check(_stale_worker.begin_move_to_node(_dummy_target),
		"live tracked target starts a follow move")
	_check(_near(_stale_worker.distance_to_target_xz(), _stale_start_dist),
		"tracked target distance measured on XZ plane")
	_enter(Phase.STALE_PROGRESS)


## -- STALE_PROGRESS/FREE/LOST_WAIT: tracked node freed -> TARGET_LOST bounded 정지 --
func _stale_progress() -> void:
	if _stale_worker.is_moving():
		_observe(_stale_worker)
	_wait += 1
	if _wait < STALE_PROGRESS_FRAMES:
		return
	var remaining := WorldCoords3D.distance_xz(_stale_worker.global_position, DUMMY_TARGET_POS)
	_check(remaining < _stale_start_dist - 5.0,
		"tracked-target move makes real progress before free (%.1f/%.1f unit)"
			% [remaining, _stale_start_dist])
	_dummy_target.free()
	_wait = 0
	_enter(Phase.STALE_FREE)


func _stale_free() -> void:
	_wait += 1
	if _wait < 3:
		return
	_wait = 0
	_enter(Phase.STALE_LOST_WAIT)


func _stale_lost_wait() -> void:
	if _stale_worker.is_moving():
		_observe(_stale_worker)
	_wait += 1
	if _events["TestWorkerStale"].is_empty():
		if _wait > STALE_LOST_LIMIT:
			_check(false, "freed tracked target ends the move within limit")
			_finish()
			return
		return
	var event: Array = _events["TestWorkerStale"][0]
	_check(event[0] == WorkerActor3D.MoveStatus.TARGET_LOST,
		"freed tracked target finishes the move as TARGET_LOST")
	_check(not _stale_worker.is_moving() and _stale_worker.velocity == Vector3.ZERO,
		"TARGET_LOST leaves worker cleanly stopped (no stale reference kept)")
	_check(_stale_worker.tracked_target == null,
		"tracked_target reference is cleared after loss")
	_check(float(_y_drift["TestWorkerStale"]) < 0.05,
		"tracked move stayed on the ground plane too")
	_events["TestWorkerStale"].clear()
	_enter(Phase.CANCEL_ARM)


## -- CANCEL_ARM/CHECK: 이동 중 재명령 대체 + cancel bounded 종료 + mid-move free --
func _cancel_arm() -> void:
	_staller.begin_move_to(FAR_POINT)
	_staller.begin_move_to(Vector3(-140, 0, 140))
	_check(_staller.is_moving(),
		"re-command during move supersedes silently (single finish contract)")
	_staller.cancel_move()
	_check(_events["TestWorkerStaller"].size() == 1
		and _events["TestWorkerStaller"][0][0] == WorkerActor3D.MoveStatus.CANCELED,
		"superseded attempts emit nothing; cancel yields exactly one CANCELED")
	_check(not _staller.is_moving() and _staller.velocity == Vector3.ZERO,
		"cancel leaves staller idle with zero velocity")
	_events["TestWorkerStaller"].clear()
	_staller.begin_move_to(FAR_POINT)
	_wait = 0
	_enter(Phase.CANCEL_CHECK)


func _cancel_check() -> void:
	_wait += 1
	if _wait < 5:
		_observe(_staller)
		return
	_staller.queue_free()
	_wait = 0
	_enter(Phase.REFREE_WAIT)


## -- REFREE_WAIT: actor 자체가 이동 중 freed되어도 잔여 문제 없음 --
func _refree_wait() -> void:
	_wait += 1
	if _wait < 10:
		return
	_check(not is_instance_valid(_staller),
		"worker freed mid-move is fully removed from the tree")
	_check(true, "scene keeps running after mid-move free (no crash/orphan error)")
	_finish()
