extends SceneTree

## TASK-3D-WRK-001-3 Worker Navigation Stress Regression 테스트.
## WRK-001-1(WorkerActor3D 이동 골격) + WRK-001-2(Lumberjack/Miner FSM) 위에서
## 장애물/게이트/assign-unassign/DAY-NIGHT 스트레스를 가하고 회귀 조건을 검증한다.
## 기존 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 시나리오(완료조건 매핑):
##   - Lumberyard 2명(lumberjack) + Quarry 2명(miner), 남측 작업대 / 북측 산림.
##   - 여러 Tree target 6그루 + Quarry WorkPoint 2개 + StoneDeposit anchor.
##   - Static Building obstacle(산림 내 건물) + Wall obstacle(남북 완전 분리 wall row).
##   - Gate OPEN/CLOSED 전환: passage shape 노드 add/remove = nav 장애물 토글
##     (NavigationPolicy3D gate 표현 규약, BLD 도메인 전환 전 테스트 환경 구성).
##     wall row가 지폭 전체를 덮으므로 gate가 유일한 남북 통로다.
##   - unreachable Resource: 북동 봉쇄 pen 안 Tree(도달 불가 -> BLOCKED-skip bounded).
##   - assign/unassign 반복 3라운드 + 최종 해제.
##   - DAY/NIGHT 반복: GameTime set_auto_advance(false) + advance() 직접 호출
##     (game_time.gd 자동 테스트 규약)로 스트레스 전 구간 반복 전환.
##
## 검증:
##   - obstacle 통과 금지: 매 frame 모든 actor XZ가 wall/building/gate(CLOSED)/
##     trunk/deposit 볼륨 침입 금지(BLOCKED 접점은 center가 볼륨 밖이므로 허용).
##   - permanent MOVE stall 없음: 연속 이동 4초 동안 displacement 0.5unit 미만 금지
##     (STUCK_TIMEOUT 1.5s의 2차 안전망 상회 여유).
##   - duplicate actor 없음: workers_3d/lumberjacks_3d/miners_3d 그룹 수와 월드
##     subtree WorkerActor3D 실제 인스턴스 수가 전 구간 4/2/2로 일치, 이름 unique.
##   - freed reference 없음: target_tree/workplace/tracked_target이 freed instance를
##     계속 쥐고 있으면 위반. 채집 대상 tree를 운행 중 강제 free해도 bounded 전이.
##   - 생산 중복 없음: wood는 "나무에서 소비된 양 == 반납 + 운반중" 항등식,
##     stone은 MINE 누적 tick 대비 상한 검사(이중 집계/이중 deposit 탐지).
##   - claim leak 없음: claim된 tree의 claimer는 항상 live actor이고 그 actor의
##     target_tree여야 함. unassign settle 시점마다 전체 claim 해제 확인.

enum Phase {
	SETUP, CONTRACT, NAV_SYNC, STRESS_ARM,
	RUN_OPEN, GATE_CLOSE, GATE_REOPEN,
	FREE_TARGET_WAIT, POST_FREE,
	CYCLE_UNASSIGN, CYCLE_SETTLE, CYCLE_ASSIGN, CYCLE_RUN,
	FINAL_RELEASE, AUDIT, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 10
const DT := 1.0 / 60.0
## 스트레스 구간 예산은 physics tick 기준이다. headless에서 idle(_process) frame
## rate와 physics tick rate가 1:1이 아니므로(측정 결과 idle 1회당 다수 physics
## step), 시간 의미가 있는 모든 판정은 physics tick으로 잰다.
const LOOP_FRAME_LIMIT := 1800
const FREE_WAIT_LIMIT := 1800

const RUN_OPEN_FRAMES := 900
const GATE_CLOSE_FRAMES := 360
const GATE_REOPEN_FRAMES := 240
const POST_FREE_FRAMES := 300
const CYCLE_RUN_FRAMES := 300
const CYCLE_ROUNDS := 3

## stall 판정: 연속 이동 window(4초 = 240 tick) 동안 displacement 미만이면
## 영구 MOVE stall 위반(STUCK_TIMEOUT 1.5s의 2차 안전망 상회 여유).
const STALL_WINDOW_FRAMES := 240
const STALL_MIN_DISP_UNITS := 0.5
## obstacle 볼륨 침입 판정 여유(center 기준이라 physics/nav 보장치보다 넉넉히 안쪽).
const PENETRATION_SHRINK := 0.05

const LY_POS := Vector3(-50, 0, 16)
const QUARRY_POS := Vector3(50, 0, 16)
## stress 환경 전체 산림을 커버하는 work_radius(px). 기본 192px는 프로토타입
## 배치 기준값이라 이 광역 시나리오에서는 의도적으로 넓힌다(duck workplace).
const STRESS_WORK_RADIUS_PX := 1600.0

const TREE_POSITIONS := [
	Vector3(-40, 0, -20), Vector3(-28, 0, -38), Vector3(-8, 0, -46),
	Vector3(12, 0, -30), Vector3(30, 0, -44), Vector3(42, 0, -22),
]
const PEN_CENTER := Vector3(82, 0, -70)
const BUILDING_POS := Vector3(-18, 1.5, -30)
const BUILDING_SIZE := Vector3(10, 3, 10)
const GATE_POS := Vector3(0, 1.5, 0)
const GATE_SIZE := Vector3(14, 3, 2)
const DEPOSIT_ANCHOR_POS := Vector3(58, 0, 44)

var _frame := 0
var _wait := 0
## 현재 phase의 physics tick 카운트(예산 판정용).
var _phase_ticks := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav: Node = null
var _resources: Node = null
var _game_time: Node = null

## -s 스탠드얼론 모드에서는 autoload 전역 식별자 의존 스크립트를 직접 참조하지
## 않고 load()로 지연 로드한다(기존 2D/task3dwrk0012 테스트 관례).
var _lj_script: GDScript = null
var _mn_script: GDScript = null

var _ly: Node3D = null
var _quarry: Node3D = null
var _lj1 = null
var _lj2 = null
var _mn1 = null
var _mn2 = null
var _workers: Array = []

var _trees: Array = []
var _tree_init := {}
## 강제 free된 tree가 free 시점까지 소비한 양(init - remaining). freed tree의
## 소비분을 live tree와 동일한 "init - 최종 잔량" 의미로 합산하기 위한 값이다.
var _freed_tree_consumed: Array[int] = []

var _gate: StaticBody3D = null
var _gate_open := true
var _obstacles: Array = []
var _gate_box := {}
var _obstacle_bodies: Array = []

var _wood_before := 0
var _stone_before := 0
var _mine_frames := {}
var _histories := {}
var _nav_baseline := 0
var _nav_count_at_close := 0

var _dn_transitions := 0
var _cycle_round := 0
## identity watchdog 직전 상태(최초 이탈 프레임만 덤프하기 위한 엣지 트리거).
var _identity_prev_ok := true
## FINAL_RELEASE의 1회 unassign 실행 가드.
var _final_unassigned := false

var _stall_violations: Array[String] = []
var _penetration_violations: Array[String] = []
var _freed_ref_violations: Array[String] = []
var _claim_violations: Array[String] = []


## workplace 계약 duck-typing용 최소 workplace(lumberyard.gd처럼 work_radius
## 스크립트 프로퍼티를 직접 소유한다. bare Node3D.set()은 no-op라 무효).
class DuckWorkplace extends Node3D:
	var work_radius: float = 192.0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


## phase 전환 시점의 clock 리셋 단일 진입점.
func _reset_clocks() -> void:
	_wait = 0
	_frame = 0
	_phase_ticks = 0


func _finish() -> void:
	for w in _workers:
		if w != null and is_instance_valid(w):
			w.free()
	for t in _trees:
		if is_instance_valid(t):
			t.free()
	for wp in [_ly, _quarry]:
		if is_instance_valid(wp):
			wp.free()
	for body in _obstacle_bodies:
		if is_instance_valid(body):
			body.free()
	print("TASK3DWRK0013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.NAV_SYNC:
			_nav_sync()
		Phase.STRESS_ARM:
			_stress_arm()
		Phase.RUN_OPEN:
			_run_open()
		Phase.GATE_CLOSE:
			_gate_close()
		Phase.GATE_REOPEN:
			_gate_reopen()
		Phase.FREE_TARGET_WAIT:
			_free_target_wait()
		Phase.POST_FREE:
			_post_free()
		Phase.CYCLE_UNASSIGN:
			_cycle_unassign()
		Phase.CYCLE_SETTLE:
			_cycle_settle()
		Phase.CYCLE_ASSIGN:
			_cycle_assign()
		Phase.CYCLE_RUN:
			_cycle_run()
		Phase.FINAL_RELEASE:
			_final_release()
		Phase.AUDIT:
			_audit()
		Phase.DONE:
			_finish()
			return true
	if _frame > 45000:
		print("TASK3DWRK0013_RESULT=TIMEOUT phase=%s" % str(_phase))
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


## -- 환경 구성 helpers -------------------------------------------------------

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
	_obstacle_bodies.append(body)
	_obstacles.append({"c": pos, "h": size * 0.5})
	return body


## NavigationPolicy3D gate 표현 규약(passage shape 노드 존재 = CLOSED)에 따른
## 테스트 환경용 toggle gate. BLD 도메인의 3D gate가 나오면 그 API로 교체된다.
func _make_gate() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "StressGate"
	body.collision_layer = CollisionLayers3D.GATE
	body.collision_mask = 0
	body.position = GATE_POS
	_world.add_child(body)
	_obstacle_bodies.append(body)
	_gate_box = {"c": GATE_POS, "h": GATE_SIZE * 0.5}
	_gate_open = true
	_gate = body
	_apply_gate_shape()
	return body


func _apply_gate_shape() -> void:
	var col := _gate.get_node_or_null("PassageShape") as CollisionShape3D
	if not _gate_open:
		if col == null:
			col = CollisionShape3D.new()
			col.name = "PassageShape"
			var box := BoxShape3D.new()
			box.size = GATE_SIZE
			col.shape = box
			_gate.add_child(col)
	elif col != null:
		col.free()


func _set_gate_open(open: bool) -> void:
	if _gate_open == open:
		return
	_gate_open = open
	_apply_gate_shape()
	# 이 테스트는 SceneTree 그 자체이므로 tree 조회 없이 self를 넘긴다.
	NavigationPolicy3D.request_rebuild_debounced(self)


func _make_workplace(wp_name: String, pos: Vector3) -> Node3D:
	var wp: DuckWorkplace = DuckWorkplace.new()
	wp.name = wp_name
	wp.work_radius = STRESS_WORK_RADIUS_PX
	_world.add_child(wp)
	wp.global_position = Vector3(pos.x, WorldCoords3D.GROUND_Y, pos.z)
	_add_marker(wp, "DepositPoint", Vector3(0, 0, 4))
	_add_marker(wp, "SpawnPoint", Vector3(0, 0, -4))
	_add_marker(wp, "WorkPoint", Vector3(3, 0, 0))
	_add_marker(wp, "WorkPoint2", Vector3(-3, 0, 0))
	return wp


func _add_marker(wp: Node3D, marker_name: String, offset: Vector3) -> void:
	var marker := Node3D.new()
	marker.name = marker_name
	wp.add_child(marker)
	marker.position = offset


## ResourceNode3D + trunk 물리 블록(Tree3D TrunkBlock 계약과 동일: r=0.75 unit,
## RESOURCE layer). nav bake 장애물 + obstacle 통과 금지 판정 대상이 된다.
func _make_tree(tree_name: String, pos: Vector3) -> ResourceNode3D:
	var t := ResourceNode3D.new()
	t.name = tree_name
	t.resource_id = "wood"
	t.max_amount = 25
	t.current_amount = 25
	t.gather_amount = 1
	_world.add_child(t)
	t.global_position = Vector3(pos.x, WorldCoords3D.GROUND_Y, pos.z)
	var trunk := StaticBody3D.new()
	trunk.name = "TrunkBlock"
	trunk.collision_layer = CollisionLayers3D.RESOURCE
	trunk.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.75
	shape.height = 2.0
	col.shape = shape
	col.position = Vector3(0, 1, 0)
	trunk.add_child(col)
	t.add_child(trunk)
	_obstacles.append({"c": t.global_position, "h": Vector3(0.75, 1, 0.75)})
	_tree_init[t.name] = t.current_amount
	return t


func _spawn_worker(worker_name: String, start: Vector3) -> WorkerActor3D:
	var actor: WorkerActor3D = null
	if worker_name.begins_with("LJ"):
		actor = _lj_script.new()
	else:
		actor = _mn_script.new()
	actor.name = worker_name
	_world.add_child(actor)
	actor.global_position = Vector3(start.x, WorldCoords3D.GROUND_Y, start.z)
	return actor


## -- SETUP ------------------------------------------------------------------

func _setup() -> void:
	if _world == null:
		_world = root.get_node_or_null("World3DRoot") as Node3D
		_nav = root.get_node_or_null("World3DRoot/NavManager")
		_resources = root.get_node_or_null("VillageResources")
		_game_time = root.get_node_or_null("GameTime")
		_lj_script = load("res://scripts/lumberjack_3d.gd") as GDScript
		_mn_script = load("res://scripts/miner_3d.gd") as GDScript
		if _world == null or _nav == null or _resources == null or _game_time == null \
				or _lj_script == null or _mn_script == null:
			_check(false, "3D world / nav / VillageResources / GameTime / worker scripts load")
			_finish()
			return
		# 남측 작업대: workplaces.
		_ly = _make_workplace("Lumberyard", LY_POS)
		_quarry = _make_workplace("Quarry", QUARRY_POS)
		# 북측 산림: 여러 Tree target.
		for i in TREE_POSITIONS.size():
			_trees.append(_make_tree("StressTree%d" % i, TREE_POSITIONS[i]))
		# unreachable Resource: 봉쇄 pen 안 tree(task3dwrk0011 pen과 동일 기하 감각).
		_add_block(PEN_CENTER + Vector3(0, 1.5, -10), Vector3(22, 3, 2),
			CollisionLayers3D.WALL, "PenNorth")
		_add_block(PEN_CENTER + Vector3(0, 1.5, 10), Vector3(22, 3, 2),
			CollisionLayers3D.WALL, "PenSouth")
		_add_block(PEN_CENTER + Vector3(-11, 1.5, 0), Vector3(2, 3, 22),
			CollisionLayers3D.WALL, "PenWest")
		_add_block(PEN_CENTER + Vector3(11, 1.5, 0), Vector3(2, 3, 22),
			CollisionLayers3D.WALL, "PenEast")
		_trees.append(_make_tree("PenTree", PEN_CENTER))
		# Static Building obstacle(산림 내).
		_add_block(BUILDING_POS, BUILDING_SIZE, CollisionLayers3D.BUILDING, "StressBuilding")
		# Wall obstacle: 남북을 완전 분리하는 wall row(gate 폭 제외 전체).
		_add_block(Vector3(-99, 1.5, 0), Vector3(184, 3, 2), CollisionLayers3D.WALL, "WallRowWest")
		_add_block(Vector3(99, 1.5, 0), Vector3(184, 3, 2), CollisionLayers3D.WALL, "WallRowEast")
		# Gate OPEN/CLOSED 전환 가능 통로(초기 OPEN).
		_gate = _make_gate()
		# Quarry stone anchor(RES 도메인 occupancy 계약 소비 확인용).
		var deposit := StoneDeposit3D.new()
		deposit.name = "StressDeposit"
		_world.add_child(deposit)
		deposit.global_position = Vector3(DEPOSIT_ANCHOR_POS.x, WorldCoords3D.GROUND_Y,
			DEPOSIT_ANCHOR_POS.z)
		var block := StaticBody3D.new()
		block.name = "Block"
		block.collision_layer = CollisionLayers3D.RESOURCE
		block.collision_mask = 0
		var bcol := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.25
		bcol.shape = sphere
		bcol.position = Vector3(0, 1.5, 0)
		block.add_child(bcol)
		deposit.add_child(block)
		_obstacles.append({"c": deposit.global_position, "h": Vector3(2.25, 1, 2.25)})
		_obstacle_bodies.append(block)
		_check(deposit.occupy(_quarry), "stone deposit anchor accepts the quarry occupancy")
		# Worker 2명 Lumberyard + Worker 2명 Quarry.
		_lj1 = _spawn_worker("LJ1", Vector3(-56, 0, 4))
		_lj2 = _spawn_worker("LJ2", Vector3(-44, 0, 8))
		_mn1 = _spawn_worker("MN1", Vector3(44, 0, 4))
		_mn2 = _spawn_worker("MN2", Vector3(56, 0, 8))
		_workers = [_lj1, _lj2, _mn1, _mn2]
		for w in _workers:
			_histories[w] = []
			_mine_frames[w] = 0
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_enter(Phase.CONTRACT)


## -- CONTRACT: 환경/배선 기본 구조 확인 -------------------------------------

func _contract() -> void:
	_check(_lj1.get_script() == _lj_script and _mn1.get_script() == _mn_script,
		"worker actors resolve the 3D FSM scripts")
	_check(_gate_open and _gate.get_node_or_null("PassageShape") == null,
		"stress gate starts OPEN (no passage shape)")
	_check(_trees.back().can_interact() and not _trees.back().is_claimed(),
		"pen resource starts mature and unclaimed")
	# DAY/NIGHT 반복 준비: 자동 진행 off, 짧은 duration으로 수동 advance 반복
	# (game_time.gd 자동 테스트 규약).
	_game_time.set_auto_advance(false)
	_game_time.set_durations(4.0, 2.0)
	_game_time.set_time_scale(1.0)
	_dn_transitions = 0
	_game_time.phase_changed.connect(_on_phase_changed)
	_check(_game_time.get_phase_name() == "DAY" and _game_time.get_day_number() == 1,
		"GameTime starts at day 1 for deterministic cycling")
	_wait = 0
	_enter(Phase.NAV_SYNC)


func _on_phase_changed(_phase: int, _day_number: int) -> void:
	_dn_transitions += 1


func _nav_sync() -> void:
	if _wait == 0:
		_nav.rebuild_navigation()
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_nav_baseline = _nav.nav_rebuild_count
	_reset_clocks()
	_enter(Phase.STRESS_ARM)


## -- STRESS_ARM: 4명 전원 배치 + 관측 초기화 ---------------------------------

func _stress_arm() -> void:
	_wood_before = _resources.get_amount("wood")
	_stone_before = _resources.get_amount("stone")
	_lj1._on_assigned(_ly)
	_lj2._on_assigned(_ly)
	_mn1._on_assigned(_quarry)
	_mn2._on_assigned(_quarry)
	_check(_lj1.is_assigned() and _lj2.is_assigned()
		and _mn1.is_assigned() and _mn2.is_assigned(),
		"2 lumberjacks + 2 miners all assigned to start the stress run")
	# MINE 누적은 physics tick 기준으로 잰다(idle frame rate와 무관하게 정확).
	physics_frame.connect(_on_physics_frame)
	_census()
	_reset_clocks()
	_enter(Phase.RUN_OPEN)


## -- 공통 관측(스트레스 구간 매 frame) ---------------------------------------

func _stress_tick() -> void:
	_daynight_tick()
	_guard_freed_refs()
	_guard_claims()
	_penetration_watch()
	_identity_watchdog()
	if _frame % 60 == 0:
		_census()


## 생산 중복 없음(stone) 판정의 시간 기준 + phase 예산 카운트. physics tick마다
## MINE 상태를 샘플링해 실제 채굴 exposure와 stall window를 정확히 누적한다.
func _on_physics_frame() -> void:
	_phase_ticks += 1
	for w in _workers:
		_stall_watch(w)
	for w in [_mn1, _mn2]:
		if is_instance_valid(w) and w.is_gathering():
			_mine_frames[w] += 1


func _daynight_tick() -> void:
	_game_time.advance(0.06)


func _stall_watch(actor: Node3D) -> void:
	var hist: Array = _histories[actor]
	if not actor.is_moving():
		hist.clear()
		return
	hist.append(actor.global_position)
	if hist.size() > STALL_WINDOW_FRAMES:
		hist.pop_front()
	if hist.size() == STALL_WINDOW_FRAMES \
			and WorldCoords3D.distance_xz(hist[0], hist[hist.size() - 1]) < STALL_MIN_DISP_UNITS:
		_stall_violations.append("%s moved < %.1f unit over %d consecutive moving frames"
			% [String(actor.name), STALL_MIN_DISP_UNITS, STALL_WINDOW_FRAMES])
		hist.clear()


func _inside_xz(pos: Vector3, box: Dictionary) -> bool:
	var h: Vector3 = box.h
	return absf(pos.x - box.c.x) <= h.x - PENETRATION_SHRINK \
		and absf(pos.z - box.c.z) <= h.z - PENETRATION_SHRINK


func _penetration_watch() -> void:
	for w in _workers:
		var p: Vector3 = w.global_position
		for o in _obstacles:
			if _inside_xz(p, o):
				_penetration_violations.append("%s inside obstacle volume at %s"
					% [String(w.name), str(p)])
				return
		if not _gate_open and _inside_xz(p, _gate_box):
			_penetration_violations.append("%s passed through CLOSED gate at %s"
				% [String(w.name), str(p)])
			return


func _guard_freed_refs() -> void:
	for w in _workers:
		# Miner3D에는 target_tree 슬롯이 없으므로 프로퍼티 존재로 구분한다.
		if "target_tree" in w and w.target_tree != null \
				and not is_instance_valid(w.target_tree):
			_freed_ref_violations.append("%s keeps a freed target_tree reference"
				% String(w.name))
		if w.is_assigned() and not is_instance_valid(w.workplace):
			_freed_ref_violations.append("%s keeps a freed workplace reference"
				% String(w.name))


func _guard_claims() -> void:
	for t in _trees:
		if not is_instance_valid(t) or not t.is_claimed():
			continue
		var claimer: Node = t._claimed_by
		if not is_instance_valid(claimer):
			_claim_violations.append("%s claimed by a freed worker (leak)" % String(t.name))
		elif claimer.get("target_tree") != t:
			_claim_violations.append("%s claimed by a worker not targeting it (leak)"
				% String(t.name))


func _census() -> void:
	var found := {}
	var names := {}
	for node in _world.find_children("*", "", true, false):
		if node is WorkerActor3D:
			found[node] = true
			names[String(node.name)] = true
	if found.size() != 4 or names.size() != 4:
		_freed_ref_violations.append("actor census drifted: instances=%d names=%d"
			% [found.size(), names.size()])
	var lj_count := _group_worker_count("lumberjacks_3d")
	var mn_count := _group_worker_count("miners_3d")
	var w_count := _group_worker_count("workers_3d")
	if lj_count != 2 or mn_count != 2 or w_count != 4:
		_freed_ref_violations.append(
			"group census drifted: lj=%d mn=%d workers=%d (duplicate/orphan actor)"
				% [lj_count, mn_count, w_count])


func _group_worker_count(group: String) -> int:
	var count := 0
	for node in get_nodes_in_group(group):
		if node is WorkerActor3D:
			count += 1
	return count


func _wood_consumed() -> int:
	var consumed := 0
	for t in _trees:
		if is_instance_valid(t):
			consumed += int(_tree_init[t.name]) - t.current_amount
	for consumed_freed in _freed_tree_consumed:
		consumed += consumed_freed
	return consumed


func _carried_wood() -> int:
	var carried := 0
	for lj in [_lj1, _lj2]:
		carried += lj.carried_amount
	return carried


## 생산 중복 없음(wood): 소비 == 반납 + 운반중. 어떤 순간에도 항등식이 깨지면
## 이중 집계/이중 deposit이다. 매 frame 감시하고 최초 이탈 시점에 상세 덤프를
## 남겨 원인 규명을 돕는다.
func _check_wood_identity(label: String) -> void:
	var deposited: int = _resources.get_amount("wood") - _wood_before
	var consumed := _wood_consumed()
	var carried := _carried_wood()
	_check(deposited + carried == consumed,
		"%s: wood identity holds deposited(%d)+carried(%d)==consumed(%d)"
			% [label, deposited, carried, consumed])


func _identity_watchdog() -> void:
	var deposited: int = _resources.get_amount("wood") - _wood_before
	var consumed := _wood_consumed()
	var carried := _carried_wood()
	if deposited + carried == consumed:
		_identity_prev_ok = true
		return
	if not _identity_prev_ok:
		return
	_identity_prev_ok = false
	print("WOOD_IDENTITY_BREAK frame=%d phase=%s deposited=%d carried=%d consumed=%d"
		% [_frame, str(_phase), deposited, carried, consumed])
	for lj in [_lj1, _lj2]:
		var target_name := "-"
		if "target_tree" in lj and is_instance_valid(lj.target_tree):
			target_name = String(lj.target_tree.name)
		print("  %s state=%s carry=%d res='%s' target=%s moving=%s pos=%s"
			% [String(lj.name), lj.get_state_name(), lj.carried_amount,
			lj.carried_resource_id, target_name, lj.is_moving(),
			str(lj.global_position)])
	for t in _trees:
		if is_instance_valid(t):
			print("  %s amount=%d/%d claimed=%s"
				% [String(t.name), t.current_amount, int(_tree_init[t.name]),
				str(t.is_claimed())])
	print("  freed_consumed=" + str(_freed_tree_consumed))


## 전원 해제 후 정착 검사. settle이 완료되면 true를 반환한다(bounded 대기).
## 대기 예산은 phase 진입부터의 physics tick 기준이다.
func _settle_all_released(label: String) -> bool:
	var released := true
	for w in _workers:
		if w.is_assigned() or w.is_moving():
			released = false
	if not released and _phase_ticks < LOOP_FRAME_LIMIT:
		return false
	_check(released, "%s: all workers reach unassigned idle within limit" % label)
	for w in _workers:
		_check(not w.is_moving() and w.velocity == Vector3.ZERO,
			"%s: %s stops cleanly with zero velocity" % [label, String(w.name)])
		if w.get_script() == _lj_script:
			_check(w.target_tree == null,
				"%s: %s holds no tree target after release" % [label, String(w.name)])
	var leaked := 0
	for t in _trees:
		if is_instance_valid(t) and t.is_claimed():
			leaked += 1
	_check(leaked == 0, "%s: no claim leak after full release (%d leaked)" % [label, leaked])
	_check_wood_identity(label)
	return true


## -- RUN_OPEN: 게이트 OPEN 상태 정상 가동 구간 -------------------------------

func _run_open() -> void:
	_stress_tick()
	if _phase_ticks < RUN_OPEN_FRAMES:
		return
	_check(true, "open-gate production run completed (%d ticks)" % RUN_OPEN_FRAMES)
	_check(_wood_consumed() > 0,
		"lumberjacks extract wood through the gate corridor (%d consumed)"
			% _wood_consumed())
	_check(_resources.get_amount("stone") > _stone_before, "miners produced stone")
	_check_wood_identity("RUN_OPEN")
	_nav_count_at_close = _nav.nav_rebuild_count
	_set_gate_open(false)
	_check(_gate.get_node_or_null("PassageShape") != null,
		"CLOSED recreates the passage shape (nav obstacle)")
	_reset_clocks()
	_enter(Phase.GATE_CLOSE)


## -- GATE_CLOSE: 유일 통로 봉쇄 -> bounded 동작만 허용 -----------------------

func _gate_close() -> void:
	_stress_tick()
	if _phase_ticks < GATE_CLOSE_FRAMES:
		return
	_check(_nav.nav_rebuild_count > _nav_count_at_close,
		"gate close triggered a debounced nav rebake")
	_check_wood_identity("GATE_CLOSE")
	_check(_penetration_violations.is_empty(),
		"no worker crossed the closed gate or walls while sealed")
	_set_gate_open(true)
	_check(_gate.get_node_or_null("PassageShape") == null,
		"OPEN removes the passage shape again (repeat toggle safe)")
	_reset_clocks()
	_enter(Phase.GATE_REOPEN)


## -- GATE_REOPEN: 재개방 후 생산 회복 ----------------------------------------

func _gate_reopen() -> void:
	_stress_tick()
	if _phase_ticks < GATE_REOPEN_FRAMES:
		return
	_check_wood_identity("GATE_REOPEN")
	_check(_dn_transitions >= 2,
		"DAY/NIGHT kept cycling during obstacle stress (%d transitions)" % _dn_transitions)
	_reset_clocks()
	_enter(Phase.FREE_TARGET_WAIT)


## -- FREE_TARGET: 채집 대상 tree를 운행 중 강제 free -------------------------

func _free_target_wait() -> void:
	_stress_tick()
	for lj in [_lj1, _lj2]:
		if is_instance_valid(lj.target_tree) and lj.target_tree in _trees:
			var victim: ResourceNode3D = lj.target_tree
			_freed_tree_consumed.append(
				int(_tree_init[victim.name]) - victim.current_amount)
			_trees.erase(victim)
			victim.free()
			_check(true, "freed in-flight target tree while claimed (consumed %d)"
				% _freed_tree_consumed.back())
			_reset_clocks()
			_enter(Phase.POST_FREE)
			return
	if _phase_ticks >= FREE_WAIT_LIMIT:
		_check(false, "a lumberjack held a live tree target within the wait window")
		_finish()


## -- POST_FREE: freed target 이후 bounded 전이/freed reference 없음 ----------

func _post_free() -> void:
	_stress_tick()
	if _phase_ticks < POST_FREE_FRAMES:
		return
	_check(_freed_ref_violations.is_empty(),
		"no worker kept a freed reference after in-flight target free")
	for lj in [_lj1, _lj2]:
		_check(lj.target_tree == null or is_instance_valid(lj.target_tree),
			"%s target reference is null or live (never stale)" % String(lj.name))
		var state_name: String = lj.get_state_name()
		_check(state_name in ["IDLE", "FIND", "MOVE", "GATHER", "RETURN", "DEPOSIT"],
			"%s stayed in a valid FSM state after target loss (%s)"
				% [String(lj.name), state_name])
	_check_wood_identity("POST_FREE")
	_cycle_round = 0
	_reset_clocks()
	_enter(Phase.CYCLE_UNASSIGN)


## -- CYCLE: assign/unassign 반복 ---------------------------------------------

func _cycle_unassign() -> void:
	_stress_tick()
	for w in _workers:
		w._on_unassigned()
	# carrying 중인 lumberjack은 마지막 1회 deposit 후 해제되는 기존 규약이므로
	# 즉시 판정하지 않고 CYCLE_SETTLE의 bounded 대기로 검증한다.
	_reset_clocks()
	_enter(Phase.CYCLE_SETTLE)


func _cycle_settle() -> void:
	_stress_tick()
	if _settle_all_released("round %d settle" % (_cycle_round + 1)):
		_enter(Phase.CYCLE_ASSIGN)


func _cycle_assign() -> void:
	_stress_tick()
	_lj1._on_assigned(_ly)
	_lj2._on_assigned(_ly)
	_mn1._on_assigned(_quarry)
	_mn2._on_assigned(_quarry)
	_check(_workers.all(func(w) -> bool: return w.is_assigned()),
		"round %d: re-assigned all workers" % (_cycle_round + 1))
	_census()
	_cycle_round += 1
	_reset_clocks()
	_enter(Phase.CYCLE_RUN)


func _cycle_run() -> void:
	_stress_tick()
	if _phase_ticks < CYCLE_RUN_FRAMES:
		return
	_reset_clocks()
	if _cycle_round < CYCLE_ROUNDS:
		_enter(Phase.CYCLE_UNASSIGN)
	else:
		_enter(Phase.FINAL_RELEASE)


## -- FINAL_RELEASE: 전원 해제 후 완전 정착 -----------------------------------

func _final_release() -> void:
	_stress_tick()
	if not _final_unassigned:
		for w in _workers:
			w._on_unassigned()
		_final_unassigned = true
	var released := true
	for w in _workers:
		if w.is_assigned() or w.is_moving():
			released = false
	if not released and _phase_ticks < LOOP_FRAME_LIMIT:
		return
	_check(released, "final release settles every worker within limit")
	_final_unassigned = false
	_enter(Phase.AUDIT)


## -- AUDIT: 스트레스 종료 판정 -----------------------------------------------

func _audit() -> void:
	_census()
	_census_check()
	_freed_and_target_sweep()
	_claim_leak_sweep()
	_production_audit()
	_daynight_audit()
	_violation_audit()
	_enter(Phase.DONE)


func _census_check() -> void:
	_check(_group_worker_count("workers_3d") == 4
		and _group_worker_count("lumberjacks_3d") == 2
		and _group_worker_count("miners_3d") == 2,
		"final group census holds 4 workers / 2 lumberjacks / 2 miners (no duplicates)")
	var instances := 0
	var seen_names := {}
	for node in _world.find_children("*", "", true, false):
		if node is WorkerActor3D:
			instances += 1
			seen_names[String(node.name)] = true
	_check(instances == 4 and seen_names.size() == 4,
		"world subtree holds exactly 4 uniquely named worker actors")


func _freed_and_target_sweep() -> void:
	for w in _workers:
		_check(w.tracked_target == null,
			"%s tracked_target fully cleared" % String(w.name))
		_check(w.workplace == null, "%s workplace reference cleared" % String(w.name))
		if w.get_script() == _lj_script:
			_check(w.carried_amount == 0 and w.carried_resource_id == "",
				"%s carry emptied by final-deposit rule" % String(w.name))
	_check(_freed_ref_violations.is_empty(),
		"no freed reference violations across the whole run (%d)"
			% _freed_ref_violations.size())
	_check(is_instance_valid(_ly) and is_instance_valid(_quarry),
		"workplaces survive the whole stress run")


func _claim_leak_sweep() -> void:
	var leaked: Array[String] = []
	for t in _trees:
		if is_instance_valid(t) and t.is_claimed():
			leaked.append(String(t.name))
	_check(leaked.is_empty(), "no claim leak on any surviving tree (%d)" % leaked.size())
	_check(_claim_violations.is_empty(),
		"no mid-run claim-consistency violations (%d)" % _claim_violations.size())


func _production_audit() -> void:
	var wood_gained: int = _resources.get_amount("wood") - _wood_before
	var stone_gained: int = _resources.get_amount("stone") - _stone_before
	_check(wood_gained > 0, "stress run produced wood overall (%d)" % wood_gained)
	_check(stone_gained > 0, "stress run produced stone overall (%d)" % stone_gained)
	_check_wood_identity("AUDIT")
	# stone 상한: MINE 누적 시간 대비 생산량 초과는 이중 집계다(생산 interval 1s).
	var total_mine_frames := 0
	for w in _workers:
		total_mine_frames += _mine_frames[w]
	var expected_max: int = int(total_mine_frames * DT / 1.0) + _workers.size() * 2 + 2
	_check(stone_gained <= expected_max,
		"stone gain %d stays within mining-time bound %d (no duplication)"
			% [stone_gained, expected_max])
	# freed tree 포함 총 소비량은 나무 용량 합계를 넘을 수 없다.
	var capacity := 0
	for key in _tree_init:
		capacity += int(_tree_init[key])
	_check(_wood_consumed() <= capacity,
		"consumed wood never exceeds total tree capacity (no double-gather)")


func _daynight_audit() -> void:
	_check(_dn_transitions >= 5,
		"DAY/NIGHT cycled repeatedly during stress (%d transitions)" % _dn_transitions)
	_check(_game_time.get_day_number() >= 2,
		"day number advanced across night cycles (day %d)" % _game_time.get_day_number())


func _violation_audit() -> void:
	_check(_stall_violations.is_empty(),
		"no permanent MOVE stall detected (%d violations)" % _stall_violations.size())
	_check(_penetration_violations.is_empty(),
		"no obstacle penetration detected (%d violations)" % _penetration_violations.size())
	_check(_nav.nav_rebuild_count >= _nav_baseline + 3,
		"dynamic obstacles triggered repeated nav rebuilds (%d >= %d+3)"
			% [_nav.nav_rebuild_count, _nav_baseline])
