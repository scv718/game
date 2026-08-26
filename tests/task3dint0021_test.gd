extends SceneTree

## TASK-3D-INT-002-1 Automated Regression.
## 기존 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 3D Migration 전체의 최종 자동검증이다. 프로젝트 main scene(main_3d.tscn)을
## 실제 Runtime으로 부팅하고 큐 검증 목록 21항목을 하나의 vertical slice로 재생한다:
##
##   1. main scene smoke      - project main scene 경로 + 부팅 + content/world 구성
##   2. Camera pan/zoom       - XZ pan/clamp, wheel zoom clamp, 고정 basis
##   3. mouse ray/selection   - 건물 선택/해제, 빈 ground 클릭 안전
##   4. Building interaction  - Tavern/Inn click -> 기존 UI 개방, 모달 차단
##   5. BuildingPlacement     - Lumberyard/Quarry 입력 경로 배치 + 비용 1회 차감
##   6. Wall/Gate             - Wall 연속 배치 + Gate corridor 배치/상태
##   7. Tree claim/regrowth   - claim 계약 + stump/regrow + nav rebake
##   8. Wood/Stone production - Lumberjack/Miner 자동 생산 입금
##   9. Worker 2명 이상       - Lumberyard slot 2 + lumberjacks_3d 2
##  10. Miner 2명 이상        - Quarry slot 2 + miners_3d 2 동시 MINE
##  11. Navigation obstacle   - Keep 본체 우회 도달(BLOCKED 없이 ARRIVED)
##  12. unreachable target    - sealed pen 목적지 BLOCKED/STALLED bounded 정지
##  13. DAY/NIGHT             - phase 전환 + tactical UI 표시/숨김
##  14. Tactical combat       - NIGHT encounter vs 용병 자동전투 lethal death
##  15. Tactical commands     - Pause/1x/2x 시간 명령
##  16. Gate command          - GATE_OPEN/GATE_CLOSE 명령이 gate 상태를 바꿈
##  17. Death Ledger          - unique source_uid 기록, cleanup 무기록
##  18. repeated cycle        - 2번째 NIGHT/DAY 반복, 사망자 재참전 없음
##  19. no duplicate actor    - 주요 group instance_id 전수 유일성
##  20. no freed reference    - roster/workplace/actor 참조 is_instance_valid
##  21. no stale navigation   - manager 생존 + rebake counter 증가 + 상태 일관
##
## 검증 11/12는 wrk0011 선례와 동일하게 WorkerActor3D probe를 실제 world에
## spawn해 결정적으로 수행하고, 종료 후 probe/pen을 제거해 뒤 단계 오염을 막는다.
##
## 주의: -s 기동 초기 autoload 미등록 컴파일 단계 규약(CMB-001-2/INT-001-2 동일)에
## 따라 autoload는 트리 노드로만 접근하고, enum이 필요한 스크립트는 runtime load로
## 해석한다.

enum Phase {
	SETUP, INSTANCE_WAIT, SMOKE_AUDIT, CAMERA_AUDIT, SELECTION_AUDIT,
	INTERACTION_AUDIT, BUILD_LUMBERYARD, BUILD_QUARRY, WALL_GATE_BUILD,
	TREE_CLAIM_REGROW, REGROW_WAIT, HIRE_WORKERS, ASSIGN_WORKERS,
	PRODUCTION_WAIT, STONE_WAIT, PRODUCTION_CHECK, NAV_PROBE_SPAWN,
	NAV_BAKE_SYNC, OBSTACLE_ARM, OBSTACLE_RUN, UNREACHABLE_RUN, NAV_RESTORE,
	HIRE_MERCENARY, TO_NIGHT, NIGHT_WAIT, NIGHT_CHECK, TIME_COMMANDS, GATE_COMMANDS,
	FOCUS_ENGAGE, COMBAT_WAIT, LEDGER_CHECK, TO_DAY, DAY_WAIT, DAY_CHECK,
	SECOND_NIGHT_WAIT, SECOND_NIGHT_CHECK, SECOND_DAY_WAIT, FINAL_AUDIT,
	CLEANUP, DONE,
}

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const CONTENT_SCRIPT_PATH := "res://scripts/world_content_3d.gd"
const GAME_TIME_SCRIPT_PATH := "res://scripts/game_time.gd"
const MERC_DATA_SCRIPT_PATH := "res://scripts/mercenary_data.gd"
const TACTICAL_UI_SCRIPT_PATH := "res://scripts/tactical_command_ui.gd"

## 논리 px -> world unit 변환(테스트 배치 좌표 계산용 단일 소스).
const PX := WorldCoords3D.PX_TO_UNIT

const SHORT_DAY_DURATION := 1.0
const SHORT_NIGHT_DURATION := 2.0
const SETTLE_FRAMES := 8
const ENCOUNTER_ENEMY_COUNT := 3

## 조건 폴링 예산(physics tick 기준 - headless frame rate 규약은 WRK 노트 참조).
const POLL_BUDGET_PRODUCTION := 1500
const POLL_BUDGET_REGROW := 300
const POLL_BUDGET_COMBAT := 1200
const NAV_SYNC_FRAMES := 10
const PROBE_SETTLE_FRAMES := 30
const OBSTACLE_FRAME_LIMIT := 1800
const UNREACHABLE_OBSERVE_FRAMES := 600

## Lumberyard 배치지: starter tree 3그루가 모두 work_radius(24 unit) 안에 들어오는
## cell로 골라 Worker 2명이 동시 벌목할 수 있게 한다(검증 9의 전제).
const YARD_SPOT := Vector3(32, 0, 30)
## Quarry는 StoneDeposit(600,300 px logical)에 스냅된다.
const DEPOSIT_SPOT := Vector3(75, 0, 37.5)
## Tree claim/regrowth 검증 대상: sparse forest 가장자리(생산 동선과 무관한 원거리).
const REGROW_TREE_SPOT := Vector3(103.75, 0, -75)
## Navigation obstacle probe: 직선 경로가 Keep footprint(중심 (0,-18.5), 반폭 2)를
## 관통하므로 ARRIVED면 우회 성공이다.
const KEEP_CENTER := Vector3(0, 0, -18.5)
const OBSTACLE_START := Vector3(0, 0, 30)
const OBSTACLE_TARGET := Vector3(0, 0, -40)
const MIN_KEEP_CLEARANCE_UNITS := 2.9
## unreachable pen: wrk0011 sealed pen 기하(모서리 겹침 4벽)를 외곽 빈 땅에 재현.
const PEN_CENTER := Vector3(112.5, 0, 112.5)
const PEN_START := Vector3(90, 0, 90)
## pen 벽 중심 반경 8.5 - 벽 두께/반(half 1 + agent radius 1)을 고려한 내부 침입 금지선.
const PEN_INTERIOR_LIMIT_UNITS := 7.6
const ARRIVAL_TOLERANCE_UNITS := 1.5

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _start_msec := 0
## 진행 중인 폴링의 시작 physics frame 번호(-1 = 대기 중 아님).
var _poll_start_pf := -1
var _probe_frame := 0

var _game_time: Node = null
var _phase_enum: Dictionary = {}
var _resources: Node = null
var _worker_roster: Node = null
var _roster_autoload: Node = null
var _ledger: Node = null

var _main: Node = null
var _world: Node = null
var _content: Node = null
var _keep: Node = null
var _cam_ctl: Node = null
var _camera: Camera3D = null
var _selection: Node = null
var _placement: Node = null
var _roster_3d: Node = null
var _spawner_3d: Node = null
var _tac_ui: Node = null
var _tavern_ui: Node = null
var _inn_ui: Node = null
var _nav_manager: Node = null
var _lumberyard: Node = null
var _quarry: Node = null
var _gate: Node = null
var _obstacle_probe: WorkerActor3D = null
var _pen_probe: WorkerActor3D = null
var _pen_bodies: Array[StaticBody3D] = []

var _wood_baseline := 0
var _wood_after_build := 0
var _ledger_baseline := -1
var _nav_baseline := -1
var _nav_before_regrow := -1
var _min_keep_distance := INF
var _min_pen_distance := INF
var _obstacle_events: Array = []
var _pen_events: Array = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0
	_poll_start_pf = -1


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _poll_budget_exhausted(budget_ticks: int) -> bool:
	var now := Engine.get_physics_frames()
	if _poll_start_pf < 0:
		_poll_start_pf = now
	return int(now - _poll_start_pf) >= budget_ticks


func _wood() -> int:
	return _resources.get_amount("wood")


func _stone() -> int:
	return _resources.get_amount("stone")


func _on_probe_move_finished(status: int, final_position: Vector3, sink: Array) -> void:
	sink.append([status, final_position])


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DINT0021_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.INSTANCE_WAIT:
			_instance_wait()
		Phase.SMOKE_AUDIT:
			_smoke_audit()
		Phase.CAMERA_AUDIT:
			_camera_audit()
		Phase.SELECTION_AUDIT:
			_selection_audit()
		Phase.INTERACTION_AUDIT:
			_interaction_audit()
		Phase.BUILD_LUMBERYARD:
			_build_lumberyard()
		Phase.BUILD_QUARRY:
			_build_quarry()
		Phase.WALL_GATE_BUILD:
			_wall_gate_build()
		Phase.TREE_CLAIM_REGROW:
			_tree_claim_regrow()
		Phase.REGROW_WAIT:
			_regrow_wait()
		Phase.HIRE_WORKERS:
			_hire_workers()
		Phase.ASSIGN_WORKERS:
			_assign_workers()
		Phase.PRODUCTION_WAIT:
			_production_wait()
		Phase.STONE_WAIT:
			_stone_wait()
		Phase.PRODUCTION_CHECK:
			_production_check()
		Phase.NAV_PROBE_SPAWN:
			_nav_probe_spawn()
		Phase.NAV_BAKE_SYNC:
			_nav_bake_sync()
		Phase.OBSTACLE_ARM:
			_obstacle_arm()
		Phase.OBSTACLE_RUN:
			_obstacle_run()
		Phase.UNREACHABLE_RUN:
			_unreachable_run()
		Phase.NAV_RESTORE:
			_nav_restore()
		Phase.HIRE_MERCENARY:
			_hire_mercenary()
		Phase.TO_NIGHT:
			_to_night()
		Phase.NIGHT_WAIT:
			_night_wait()
		Phase.NIGHT_CHECK:
			_night_check()
		Phase.TIME_COMMANDS:
			_time_commands()
		Phase.GATE_COMMANDS:
			_gate_commands()
		Phase.FOCUS_ENGAGE:
			_focus_engage()
		Phase.COMBAT_WAIT:
			_combat_wait()
		Phase.LEDGER_CHECK:
			_ledger_check()
		Phase.TO_DAY:
			_to_day()
		Phase.DAY_WAIT:
			_day_wait()
		Phase.DAY_CHECK:
			_day_check()
		Phase.SECOND_NIGHT_WAIT:
			_second_night_wait()
		Phase.SECOND_NIGHT_CHECK:
			_second_night_check()
		Phase.SECOND_DAY_WAIT:
			_second_day_wait()
		Phase.FINAL_AUDIT:
			_final_audit()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if Time.get_ticks_msec() - _start_msec > 420000:
		print("TASK3DINT0021_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < SETTLE_FRAMES:
		return
	_start_msec = Time.get_ticks_msec()
	_game_time = root.get_node_or_null("GameTime")
	_resources = root.get_node_or_null("VillageResources")
	_worker_roster = root.get_node_or_null("WorkerRoster")
	_roster_autoload = root.get_node_or_null("MercenaryRoster")
	_ledger = root.get_node_or_null("DeathLedger")
	_check(_game_time != null and _resources != null and _worker_roster != null \
			and _roster_autoload != null and _ledger != null,
		"shared autoloads are available to the final regression runtime")
	if _game_time == null or _resources == null:
		_enter(Phase.DONE)
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(SHORT_DAY_DURATION, SHORT_NIGHT_DURATION)
	# headless 기본 window(64x64)는 GUI hit-test를 왜곡하므로 프로젝트 해상도로 올린다
	# (INT-001-2 입력 경로 규약 동일).
	root.size = Vector2i(1152, 648)
	_phase_enum = (load(GAME_TIME_SCRIPT_PATH) as Script).get("Phase")
	_check(_phase_enum != null and _phase_enum.has("NIGHT"),
		"GameTime Phase enum resolves through runtime load")
	_enter(Phase.INSTANCE_WAIT)


func _instance_wait() -> void:
	if _wait == 0:
		var packed: PackedScene = load(MAIN_SCENE_PATH)
		_main = packed.instantiate()
		_main.name = "Main3D"
		root.add_child(_main)
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_world = root.get_node_or_null("Main3D/World3D")
	_check(_main != null and _world != null,
		"project main scene boots into the live 3D Main World")
	if _world == null:
		_enter(Phase.DONE)
		return
	_content = _world.get_node_or_null("WorldContent3D")
	_keep = _world.get_node_or_null("Keep")
	_cam_ctl = get_first_node_in_group("camera_controller_3d")
	_camera = _cam_ctl.get_camera() if _cam_ctl != null else null
	_selection = get_first_node_in_group("world_selection_3d")
	_placement = get_first_node_in_group("building_placement_3d")
	_roster_3d = _main.get_node_or_null("MercenaryRoster3D")
	_spawner_3d = _main.get_node_or_null("FirstEncounterSpawner3D")
	_tac_ui = get_first_node_in_group("tactical_command_ui_3d")
	_tavern_ui = get_first_node_in_group("recruitment_ui")
	_inn_ui = get_first_node_in_group("inn_roster_ui")
	_nav_manager = _world.get_node_or_null("NavigationManager3D")
	_ledger_baseline = _ledger.get_all_records().size()
	_nav_baseline = _nav_manager.nav_rebuild_count
	_enter(Phase.SMOKE_AUDIT)


## -- 검증 1: main scene smoke --
func _smoke_audit() -> void:
	_check(String(ProjectSettings.get_setting(
				"application/run/main_scene")) == MAIN_SCENE_PATH,
		"project entry stays on the 3D main scene path (main scene smoke)")
	var camera_count := 0
	var legacy_2d_nodes := 0
	for node in iterate_tree(root):
		if node is Camera3D:
			camera_count += 1
		if node is Node2D or node is CharacterBody2D or node is Area2D \
				or node is NavigationAgent2D:
			legacy_2d_nodes += 1
	_check(camera_count == 1, "exactly one Camera3D drives the runtime view")
	_check(legacy_2d_nodes == 0,
		"live runtime holds no 2D Actor/Camera/Collision/Nav nodes (%d)" % legacy_2d_nodes)
	_check(_content != null and _content.get_script() == load(CONTENT_SCRIPT_PATH),
		"WorldContent3D composes the gameplay content deterministically")
	_check(_content.get_tree_count() == 60 \
			and _group_count("resource_nodes_3d") == 60,
		"composed world holds exactly 60 registered tree resource nodes")
	var deposit: Node3D = _content.get_stone_deposit()
	_check(deposit != null \
			and deposit.global_position.is_equal_approx(Vector3(600 * PX, 0, 300 * PX)),
		"StoneDeposit sits at the shared stone zone position")
	var expected_types := {"keep": 0, "tavern": 0, "inn": 0, "grocery": 0, "equipment": 0}
	for building in get_nodes_in_group("core_buildings_3d"):
		expected_types[building.get_core_type()] += 1
	var all_once := true
	for t in expected_types:
		if expected_types[t] != 1:
			all_once = false
	_check(all_once, "all five core buildings exist exactly once")
	_check(_keep != null and _keep.get_parent() == _world,
		"Keep stays a direct world-root child for spawner/rally resolution")
	_check(_cam_ctl != null and _camera != null and _selection != null \
			and _placement != null and _tac_ui != null and _tavern_ui != null \
			and _inn_ui != null and _nav_manager != null,
		"camera/selection/placement/UI/navigation services are all wired")
	_check(_nav_manager.nav_rebuild_count >= 1,
		"initial navigation bake covers the composed world")
	_enter(Phase.CAMERA_AUDIT)


func iterate_tree(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(iterate_tree(child))
	return out


## -- 검증 2: Camera pan/zoom --
func _camera_audit() -> void:
	var before: Vector3 = _cam_ctl.position
	_cam_ctl.pan_camera(Vector3(30, 0, -20))
	var panned: Vector3 = _cam_ctl.position
	_check(panned.x > before.x and panned.z < before.z and panned.y == 0.0,
		"WASD-equivalent pan moves the pivot on the ground plane only")
	_cam_ctl.pan_camera(Vector3(4000, 0, 4000))
	_check(_cam_ctl.position.x <= WorldCoords3D.WORLD_HALF_UNITS \
			and _cam_ctl.position.z <= WorldCoords3D.WORLD_HALF_UNITS,
		"pan clamps against the shared world bounds")
	_cam_ctl.pan_camera(-_cam_ctl.position)
	_check(_cam_ctl.position.length_squared() < 0.0001,
		"camera pivots back to the village center")
	var zoom_before: float = _cam_ctl.get_zoom_target()
	_push_wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(_cam_ctl.get_zoom_target() > zoom_before, "mouse wheel zooms in")
	for i in 20:
		_push_wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(is_equal_approx(_cam_ctl.get_zoom_target(), _cam_ctl.max_zoom),
		"zoom clamps at the configured maximum")
	for i in 30:
		_push_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check(is_equal_approx(_cam_ctl.get_zoom_target(), _cam_ctl.min_zoom),
		"zoom clamps at the configured minimum")
	var basis_snapshot: Basis = _camera.global_transform.basis
	_cam_ctl.pan_camera(Vector3(10, 0, 0))
	_check(_camera.global_transform.basis == basis_snapshot,
		"camera keeps a fixed oblique basis while panning (no rotation path)")
	_cam_ctl.pan_camera(Vector3(-10, 0, 0))
	_enter(Phase.SELECTION_AUDIT)


## -- 검증 3: mouse ray/selection --
func _selection_audit() -> void:
	var tavern: Node3D = _world.get_node_or_null("Tavern")
	var screen := _screen_pos_of(tavern.global_position + Vector3(0, 2, 0))
	var selected: Interactable3D = _selection.select_at_screen_position(screen)
	_check(selected != null and selected.get_core_building() == tavern,
		"mouse ray selects the Tavern interactable through the live camera")
	_check(_selection.get_selected() == selected, "selection state tracks the pick")
	# 선택 interact가 주점 UI를 개방하므로, 입력 경로 검증 전에 모달을 닫는다
	# (열린 모달은 화면 중앙 클릭을 GUI 단계에서 흡수한다).
	if _tavern_ui.visible:
		_tavern_ui.close()
	_push_right_click(screen)
	_check(_selection.get_selected() == null,
		"right click clears the selection (contextual cancel)")
	var ground_pick: Interactable3D = _selection.select_at_screen_position(
		_screen_pos_of(Vector3(0, 0, 100)))
	_check(ground_pick == null and _selection.get_selected() == null,
		"empty ground/decoration clicks stay a safe no-op")
	_enter(Phase.INTERACTION_AUDIT)


## -- 검증 4: Building interaction --
func _interaction_audit() -> void:
	var tavern: Node3D = _world.get_node_or_null("Tavern")
	var inn: Node3D = _world.get_node_or_null("Inn")
	_selection.select_at_screen_position(
		_screen_pos_of(tavern.global_position + Vector3(0, 2, 0)))
	_check(_tavern_ui.visible,
		"Tavern interaction opens the existing recruitment UI")
	_tavern_ui.close()
	_selection.select_at_screen_position(
		_screen_pos_of(inn.global_position + Vector3(0, 2, 0)))
	_check(_inn_ui.visible, "Inn interaction opens the existing InnRosterUI")
	_check(not _selection.can_handle_world_click(),
		"open modal UI blocks world clicks (no UI click-through)")
	_inn_ui.close()
	_check(_selection.can_handle_world_click(),
		"closing the modal restores world click handling")
	_enter(Phase.BUILD_LUMBERYARD)


## -- 검증 5: BuildingPlacement(입력 경로) --
func _build_lumberyard() -> void:
	_resources.add("wood", 60)
	_wood_baseline = _wood()
	_pan_for(YARD_SPOT)
	_push_key(KEY_1)
	_push_key(KEY_B)
	_check(_placement.is_active(), "B enters build mode with KEY_1 selected type")
	_push_left_click(_screen_pos_of(YARD_SPOT))
	_check(_placement.is_active() == false,
		"single-unit buildings exit build mode after placement")
	_wait = 0
	_enter(Phase.BUILD_QUARRY)


func _build_quarry() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	var yards := get_nodes_in_group("lumberyards")
	_check(yards.size() == 1, "one Lumberyard placed via the input path")
	if yards.size() == 1:
		_lumberyard = yards[0]
		_check(WorldCoords3D.distance_xz(_lumberyard.global_position,
				Vector3(33, 0, 31)) < 0.01,
			"placement snaps the building to the logical grid cell center")
	_check(_wood() == _wood_baseline - 10,
		"lumberyard cost deducts Wood exactly once (%d -> %d)" % [_wood_baseline, _wood()])
	_pan_for(DEPOSIT_SPOT)
	_push_key(KEY_2)
	_push_key(KEY_B)
	_check(_placement.is_active(), "KEY_2 + B re-enters build mode for the quarry")
	_push_left_click(_screen_pos_of(DEPOSIT_SPOT))
	var quarries := get_nodes_in_group("quarries")
	_check(quarries.size() == 1, "Quarry placed onto the Stone Deposit snap")
	if quarries.size() == 1:
		_quarry = quarries[0]
		var deposit: Node = get_nodes_in_group("stone_deposits_3d")[0]
		_check(deposit.get_quarry() == _quarry,
			"quarry binds the deposit anchor on placement")
	_check(_placement.is_active() == false, "quarry placement exits build mode")
	# 생산 판정 기준선은 quarry 비용 차감까지 끝난 지점에서 캡처한다.
	_wood_after_build = _wood()
	_wait = 0
	_enter(Phase.WALL_GATE_BUILD)


## -- 검증 6: Wall/Gate --
func _wall_gate_build() -> void:
	_resources.add("wood", 40)
	_pan_for(Vector3(0, 0, -57))
	_push_key(KEY_3)
	_push_key(KEY_B)
	_check(_placement.is_active(), "build mode re-enters for walls")
	var wood_before_walls := _wood()
	_push_left_click(_screen_pos_of(Vector3(0, 0, -57)))
	_push_left_click(_screen_pos_of(Vector3(0, 0, -53)))
	_check(get_nodes_in_group("walls_3d").size() == 2,
		"two wall segments place in continuous build mode")
	_check(_wood() == wood_before_walls - 2 * 2,
		"each wall segment deducts its Wood cost once")
	_pan_for(Vector3(0, 0, -62.5))
	_push_key(KEY_4)
	var wood_before_gate := _wood()
	_push_left_click(_screen_pos_of(Vector3(0, 0, -62.5)))
	var gates := get_nodes_in_group("gates_3d")
	_check(gates.size() == 1, "gate placed inside the north gate corridor")
	if gates.size() == 1:
		_gate = gates[0]
		_check(_gate.get_direction() == "north",
			"gate direction resolves from the corridor centerline snap")
		_check(_gate.is_closed(), "newly placed gate starts CLOSED")
	_check(_wood() == wood_before_gate - 5,
		"gate placement deducts its Wood cost once")
	_push_key(KEY_ESCAPE)
	_check(_placement.is_active() == false, "ESC exits the continuous build mode")
	_wait = 0
	_enter(Phase.TREE_CLAIM_REGROW)


## -- 검증 7: Tree claim/regrowth --
func _find_tree_near(world_pos: Vector3) -> WorldTree3D:
	var target: WorldTree3D = null
	var best_dist := INF
	for tree in get_nodes_in_group("resource_nodes_3d"):
		var d: float = WorldCoords3D.distance_xz(tree.global_position, world_pos)
		if d < best_dist:
			best_dist = d
			target = tree
	return target


func _tree_claim_regrow() -> void:
	var claimant_a := Node3D.new()
	var claimant_b := Node3D.new()
	_world.add_child(claimant_a)
	_world.add_child(claimant_b)
	var target := _find_tree_near(REGROW_TREE_SPOT)
	_check(target != null and WorldCoords3D.distance_xz(target.global_position,
				REGROW_TREE_SPOT) < 0.01,
		"a deterministic far forest tree is picked for the claim check")
	_check(target.claim(claimant_a), "first claimant acquires an unclaimed tree")
	_check(target.is_claimed_by_other(claimant_b),
		"a second worker sees the tree as claimed by someone else")
	_check(target.claim(claimant_b) == false,
		"duplicate claim on a claimed tree is rejected")
	target.release(claimant_a)
	_check(not target.is_claimed(),
		"release clears the claim without leaving stale ownership")
	claimant_a.free()
	claimant_b.free()
	target.regrow_time = 0.4
	_nav_before_regrow = _nav_manager.nav_rebuild_count
	var gained := 0
	for i in 5:
		gained += int(target.interact(null).get("amount", 0))
	_check(gained == 5, "gathering drains the tree's full yield")
	_check(target.state == WorldTree3D.State.STUMP and target.current_amount == 0,
		"depleted tree switches to the stump state")
	_check(not target.get_node("Visual/CanopyVisual").visible \
			and target.get_node("Visual/StumpVisual").visible,
		"stump state swaps canopy/trunk visuals for the stump visual")
	_wait = 0
	_enter(Phase.REGROW_WAIT)


func _regrow_wait() -> void:
	if not _poll_budget_exhausted(POLL_BUDGET_REGROW):
		return
	var target := _find_tree_near(REGROW_TREE_SPOT)
	if not is_instance_valid(target):
		_check(false, "regrowth target tree survives until regrow_time")
		_enter(Phase.HIRE_WORKERS)
		return
	_check(target.state == WorldTree3D.State.MATURE and target.current_amount == 5,
		"stump regrows into a mature tree after regrow_time")
	_check(_nav_manager.nav_rebuild_count > _nav_before_regrow,
		"depletion/regrowth keep navigation rebaked (no stale obstacle state)")
	_enter(Phase.HIRE_WORKERS)


## -- 검증 9 전반: Worker 2명 / Miner 2명 고용 --
func _hire_workers() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_tavern_ui.open()
	_tavern_ui._hire_buttons["lumberjack_A"].pressed.emit()
	_tavern_ui._hire_buttons["lumberjack_B"].pressed.emit()
	_tavern_ui._hire_buttons["miner_A"].pressed.emit()
	_tavern_ui._hire_buttons["miner_B"].pressed.emit()
	_check(_worker_roster.get_count() == 4,
		"Tavern UI hires two lumberjacks and two miners into the shared roster")
	_check(_worker_roster.get_unassigned().size() == 4,
		"hired workers stay roster data only before assignment")
	_check(_group_count("workers_3d") == 0,
		"unassigned residents never become world actors (design rule)")
	_tavern_ui.close()
	_wait = 0
	_enter(Phase.ASSIGN_WORKERS)


func _assign_workers() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_inn_ui.open()
	_inn_ui._assign_buttons["lumberjack_A"].pressed.emit()
	_inn_ui._assign_buttons["lumberjack_B"].pressed.emit()
	_inn_ui._assign_buttons["miner_A"].pressed.emit()
	_inn_ui._assign_buttons["miner_B"].pressed.emit()
	_check(_worker_roster.get_assigned_count() == 4,
		"Inn UI assigns both workers of each job to its matching facility")
	_check(_group_count("workers_3d") == 4,
		"assignment spawns exactly one Worker Actor per assigned resident")
	_check(_group_count("lumberjacks_3d") == 2 and _group_count("miners_3d") == 2,
		"two 3D lumberjacks and two 3D miners are live (Worker/Miner 2+)")
	_check(_group_count("lumberjacks") == 0 and _group_count("miners") == 0,
		"no legacy 2D worker actors leak into the 3D runtime")
	_inn_ui.close()
	_wait = 0
	_enter(Phase.PRODUCTION_WAIT)


## -- 검증 8: Wood/Stone production --
func _production_wait() -> void:
	if _wood() >= _wood_after_build + 10 \
			or _poll_budget_exhausted(POLL_BUDGET_PRODUCTION):
		_enter(Phase.STONE_WAIT)


func _stone_wait() -> void:
	if _stone() >= 6 or _poll_budget_exhausted(POLL_BUDGET_PRODUCTION):
		_enter(Phase.PRODUCTION_CHECK)


func _production_check() -> void:
	# 배치 실패 등으로 시설 참조가 없으면 여기서 한 번만 실패를 기록하고
	# 진행한다(SCRIPT ERROR 재진입 loop 방지 - fail-fast guard).
	if not is_instance_valid(_lumberyard) or not is_instance_valid(_quarry):
		_check(false, "workplace references exist for the production audit")
		_enter(Phase.NAV_PROBE_SPAWN)
		return
	_check(_wood() >= _wood_after_build + 10,
		"both lumberjacks deposit gathered Wood into the stockpile (+10)")
	_check(_stone() >= 6, "both miners produce Stone at the bound deposit")
	_check(_lumberyard.get_filled_slots() == 2 and _quarry.get_filled_slots() == 2,
		"each workplace fills both of its slots (capacity 2)")
	for miner in get_nodes_in_group("miners_3d"):
		_check(miner.is_gathering(),
			"%s reached the steady MINE state" % String(miner.name))
	for jack in get_nodes_in_group("lumberjacks_3d"):
		_check(jack.is_assigned() and jack.get_workplace() == _lumberyard,
			"%s works at the lumberyard workplace" % String(jack.name))
	_enter(Phase.NAV_PROBE_SPAWN)


## -- 검증 11/12 준비: navigation probe + sealed pen --
func _add_pen_wall(offset: Vector3, size: Vector3, wall_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = CollisionLayers3D.WALL
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	body.position = PEN_CENTER + offset
	_world.add_child(body)
	_pen_bodies.append(body)


func _spawn_probe(probe_name: String, start: Vector3, sink: Array) -> WorkerActor3D:
	var probe := WorkerActor3D.new()
	probe.name = probe_name
	_world.add_child(probe)
	probe.global_position = Vector3(start.x, WorldCoords3D.GROUND_Y, start.z)
	probe.move_finished.connect(
		_on_probe_move_finished.bind(sink), CONNECT_ONE_SHOT)
	return probe


func _nav_probe_spawn() -> void:
	_obstacle_probe = _spawn_probe(
		"Int0021ObstacleProbe", OBSTACLE_START, _obstacle_events)
	_pen_probe = _spawn_probe("Int0021PenProbe", PEN_START, _pen_events)
	# wrk0011 sealed pen 기하: 모서리가 겹치는 네 벽으로 완전 봉쇄.
	_add_pen_wall(Vector3(0, 1.5, 8.5), Vector3(18, 3, 2), "Int0021PenNorth")
	_add_pen_wall(Vector3(0, 1.5, -8.5), Vector3(18, 3, 2), "Int0021PenSouth")
	_add_pen_wall(Vector3(-8.5, 1.5, 0), Vector3(2, 3, 19), "Int0021PenWest")
	_add_pen_wall(Vector3(8.5, 1.5, 0), Vector3(2, 3, 19), "Int0021PenEast")
	# wrk0011 순서 준수: physics 정착 이후 bake -> map sync frame 확보.
	_wait = 0
	_enter(Phase.NAV_BAKE_SYNC)


func _nav_bake_sync() -> void:
	_wait += 1
	if _wait < PROBE_SETTLE_FRAMES:
		return
	if _wait == PROBE_SETTLE_FRAMES:
		_nav_manager.rebuild_navigation()
	_wait += 1
	if _wait < PROBE_SETTLE_FRAMES + NAV_SYNC_FRAMES:
		return
	_enter(Phase.OBSTACLE_ARM)


## -- 검증 11: Navigation obstacle --
func _obstacle_arm() -> void:
	_probe_frame = 0
	_min_keep_distance = INF
	_obstacle_probe.begin_move_to(OBSTACLE_TARGET)
	_enter(Phase.OBSTACLE_RUN)


func _obstacle_run() -> void:
	_probe_frame += 1
	if _obstacle_probe.is_moving():
		_min_keep_distance = minf(_min_keep_distance,
			WorldCoords3D.distance_xz(_obstacle_probe.global_position, KEEP_CENTER))
	if _obstacle_events.is_empty():
		if _probe_frame > OBSTACLE_FRAME_LIMIT:
			_check(false, "obstacle detour finished within the frame limit")
			_arm_pen_probe()
		return
	var event: Array = _obstacle_events[0]
	_check(event[0] == WorkerActor3D.MoveStatus.ARRIVED,
		"probe crosses the village behind the static Keep building (ARRIVED)")
	_check(WorldCoords3D.distance_xz(event[1], OBSTACLE_TARGET) \
			<= ARRIVAL_TOLERANCE_UNITS,
		"detour route reaches the target behind the obstacle")
	_check(_min_keep_distance >= MIN_KEEP_CLEARANCE_UNITS,
		"route keeps clearance around the building footprint (min %.2f)"
			% _min_keep_distance)
	_arm_pen_probe()


func _arm_pen_probe() -> void:
	_probe_frame = 0
	_min_pen_distance = INF
	_pen_probe.begin_move_to(PEN_CENTER)
	_enter(Phase.UNREACHABLE_RUN)


## -- 검증 12: unreachable target --
func _unreachable_run() -> void:
	_probe_frame += 1
	if _pen_probe.is_moving():
		_min_pen_distance = minf(_min_pen_distance,
			WorldCoords3D.distance_xz(_pen_probe.global_position, PEN_CENTER))
	if _pen_events.is_empty():
		if _probe_frame > UNREACHABLE_OBSERVE_FRAMES:
			_check(false, "unreachable target ends within the observe window "
				+ "(no permanent MOVE stall)")
			_enter(Phase.NAV_RESTORE)
		return
	var event: Array = _pen_events[0]
	_check(event[0] == WorkerActor3D.MoveStatus.BLOCKED
		or event[0] == WorkerActor3D.MoveStatus.STALLED,
		"sealed-pen target stops via BLOCKED/STALLED bounded judgment (status %d)"
			% event[0])
	_check(not _pen_probe.is_moving() and _pen_probe.velocity == Vector3.ZERO,
		"stopped probe holds idle state with zero velocity")
	_check(_min_pen_distance >= PEN_INTERIOR_LIMIT_UNITS,
		"probe never entered the sealed pen interior (min %.2f)"
			% _min_pen_distance)
	_check(is_finite(event[1].x) and is_finite(event[1].z),
		"unreachable attempt leaves no NaN/drift in position")
	_enter(Phase.NAV_RESTORE)


func _nav_restore() -> void:
	if _wait == 0:
		for body in _pen_bodies:
			if is_instance_valid(body):
				body.free()
		_pen_bodies.clear()
		if _obstacle_probe != null and is_instance_valid(_obstacle_probe):
			_obstacle_probe.free()
		if _pen_probe != null and is_instance_valid(_pen_probe):
			_pen_probe.free()
		_nav_manager.rebuild_navigation()
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_check(_nav_manager.nav_rebuild_count > _nav_baseline,
		"navigation manager survived the probe bakes and restored open nav")
	_enter(Phase.HIRE_MERCENARY)


## -- 검증 13/14 준비: 용병 고용 + 방어 구역 지정 --
func _hire_mercenary() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	var defense_zone_west: int = (load(MERC_DATA_SCRIPT_PATH) as Script).DefenseZone.WEST
	_tavern_ui.open()
	_tavern_ui._mercenary_hire_buttons["mercenary_A"].pressed.emit()
	_check(_roster_autoload.get_mercenary("mercenary_A") != null,
		"Tavern UI hires the mercenary into the shared roster")
	_check(_roster_3d.get_mercenary("mercenary_A") != null,
		"hire sync bridges the recruit into MercenaryRoster3D")
	_tavern_ui.close()
	_inn_ui.open()
	var merc = _roster_3d.get_mercenary("mercenary_A")
	_inn_ui._on_defense_zone_pressed(merc, defense_zone_west)
	_check(merc.defense_zone == defense_zone_west,
		"Inn UI assigns the mercenary to the west defense zone")
	_inn_ui.close()
	_wait = 0
	_enter(Phase.TO_NIGHT)


## -- 검증 13: DAY/NIGHT 전환 --
func _to_night() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_advance_to_next_phase()
	_enter(Phase.NIGHT_WAIT)


func _night_wait() -> void:
	_wait += 1
	if _wait >= SETTLE_FRAMES:
		_enter(Phase.NIGHT_CHECK)


func _night_check() -> void:
	_check(_game_time.get_phase_name() == "NIGHT",
		"phase advances DAY -> NIGHT")
	_check(_tac_ui.visible, "tactical command UI shows at NIGHT")
	_check(get_nodes_in_group("enemies_3d").size() == ENCOUNTER_ENEMY_COUNT,
		"NIGHT encounter spawns raiders from the west")
	_check(_group_count("mercenaries_3d") == 1,
		"zone-assigned mercenary deploys as a single 3D actor")
	_check(_ledger.get_all_records().size() == _ledger_baseline,
		"deployment itself records nothing in the Death Ledger")
	_enter(Phase.TIME_COMMANDS)


## -- 검증 15: Tactical commands --
func _time_commands() -> void:
	_tac_ui.get_time_pause_button().pressed.emit()
	_check(is_equal_approx(_game_time.get_time_scale(), 0.0),
		"Pause command freezes tactical time scale")
	_tac_ui.get_time_2x_button().pressed.emit()
	_check(is_equal_approx(_game_time.get_time_scale(), 2.0),
		"2x command doubles tactical time scale")
	_tac_ui.get_time_1x_button().pressed.emit()
	_check(is_equal_approx(_game_time.get_time_scale(), 1.0),
		"1x command restores tactical time scale")
	_enter(Phase.GATE_COMMANDS)


## -- 검증 16: Gate command --
func _gate_commands() -> void:
	var commands: Dictionary = (load(TACTICAL_UI_SCRIPT_PATH) as Script).get("Command")
	_check(_gate.is_closed(), "gate starts the night CLOSED")
	_roster_3d._on_tactical_command(commands.GATE_OPEN, _gate)
	_check(_gate.is_open() and not _gate.is_breached(),
		"GATE_OPEN command opens the passage")
	_roster_3d._on_tactical_command(commands.GATE_CLOSE, _gate)
	_check(_gate.is_closed(), "GATE_CLOSE command closes the passage again")
	_enter(Phase.FOCUS_ENGAGE)


## -- 검증 14: Tactical combat --
func _focus_engage() -> void:
	var enemies := get_nodes_in_group("enemies_3d")
	_check(enemies.size() == ENCOUNTER_ENEMY_COUNT, "enemies hold before engagement")
	var target: Node = null
	var best_dist := INF
	for enemy in enemies:
		var d: float = WorldCoords3D.distance_xz(enemy.global_position,
			Vector3(-38.125, 0, 0))
		if d < best_dist:
			best_dist = d
			target = enemy
	_roster_3d.set_focus_target(target)
	_check(_roster_3d.has_focus_target(),
		"focus target command designates the priority enemy")
	var merc_actor: Node = _roster_3d.get_actor("mercenary_A")
	_check(merc_actor != null and merc_actor.is_inside_tree(),
		"mercenary actor is live when engagement starts")
	_wait = 0
	_enter(Phase.COMBAT_WAIT)


func _combat_wait() -> void:
	var deaths: int = _ledger.get_all_records().size() - _ledger_baseline
	if deaths >= 1 or _poll_budget_exhausted(POLL_BUDGET_COMBAT):
		_enter(Phase.LEDGER_CHECK)


## -- 검증 17: Death Ledger --
func _ledger_check() -> void:
	var records: Array = _ledger.get_all_records()
	var deaths := records.size() - _ledger_baseline
	_check(deaths >= 1, "auto combat produces at least one lethal death")
	var source_ids := {}
	var unique := true
	for record in records:
		var uid: Variant = record.source_uid
		if source_ids.has(uid):
			unique = false
		source_ids[uid] = true
	_check(unique, "Death Ledger holds no duplicate records")
	_enter(Phase.TO_DAY)


func _to_day() -> void:
	_advance_to_next_phase()
	_enter(Phase.DAY_WAIT)


func _day_wait() -> void:
	_wait += 1
	if _wait >= SETTLE_FRAMES:
		_enter(Phase.DAY_CHECK)


func _day_check() -> void:
	_check(_game_time.get_phase_name() == "DAY", "phase returns to DAY")
	_check(not _tac_ui.visible, "tactical UI hides at DAY")
	_check(_group_count("enemies_3d") == 0 and _group_count("mercenaries_3d") == 0,
		"DAY cleanup despawns every combat actor")
	var orphans := 0
	for child in _world.get_children():
		if child is EnemyActor3D or child is MercenaryActor3D:
			orphans += 1
	_check(orphans == 0, "despawned combat actors leave no orphan under the world")
	_check(_ledger.get_all_records().size() == _ledger_records_after_combat(),
		"DAY despawn writes no extra death records")
	_check(is_equal_approx(_game_time.get_time_scale(), 1.0),
		"time scale restored to 1x at DAY")
	_check(_roster_3d.focus_target == null and _roster_3d.focus_mode == false,
		"focus transient state clears at DAY")
	_wait = 0
	_enter(Phase.SECOND_NIGHT_WAIT)


func _ledger_records_after_combat() -> int:
	return _ledger.get_all_records().size()


## -- 검증 18: repeated cycle --
func _second_night_wait() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_advance_to_next_phase()
	_wait = 0
	_enter(Phase.SECOND_NIGHT_CHECK)


func _second_night_check() -> void:
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	_check(_game_time.get_phase_name() == "NIGHT",
		"second cycle reaches NIGHT (repeated cycle)")
	_check(get_nodes_in_group("enemies_3d").size() == ENCOUNTER_ENEMY_COUNT,
		"second encounter spawns exactly %d fresh raiders (no duplicates)"
			% ENCOUNTER_ENEMY_COUNT)
	var alive_hires: int = _roster_3d.get_alive_count()
	_check(_group_count("mercenaries_3d") == alive_hires,
		"only living mercenaries redeploy (dead hires stay dead)")
	var merc_actor: Node = _roster_3d.get_actor("mercenary_A")
	if alive_hires == 0:
		_check(merc_actor == null,
			"killed mercenary leaves no actor and no freed reference behind")
	else:
		_check(merc_actor != null and merc_actor.alive,
			"surviving mercenary redeploys as a fresh actor")
	# 같은 NIGHT 내 재진입 advance가 duplicate spawn을 만들지 않는다.
	_game_time.advance(0.2)
	_check(get_nodes_in_group("enemies_3d").size() == ENCOUNTER_ENEMY_COUNT,
		"idle re-entry does not duplicate the encounter")
	_wait = 0
	_enter(Phase.SECOND_DAY_WAIT)


func _second_day_wait() -> void:
	if _wait == 0:
		_advance_to_next_phase()
	_wait += 1
	if _wait >= SETTLE_FRAMES:
		_enter(Phase.FINAL_AUDIT)


## -- 검증 19/20/21: duplicate actor / freed reference / stale navigation --
func _assert_group_unique(group_name: String, expected_size: int) -> void:
	var ids := {}
	var unique := true
	for node in get_nodes_in_group(group_name):
		if ids.has(node.get_instance_id()):
			unique = false
		ids[node.get_instance_id()] = true
	var sized := get_nodes_in_group(group_name).size() == expected_size
	_check(unique and sized,
		"group '%s' holds %d unique actors (no duplicates)" % [group_name, expected_size])


func _final_audit() -> void:
	_check(_game_time.get_phase_name() == "DAY"
			and _game_time.get_day_number() >= 3,
		"repeated cycle returns to DAY on day %d" % _game_time.get_day_number())
	_check(_group_count("enemies_3d") == 0,
		"second cleanup leaves no enemies behind")
	_assert_group_unique("workers_3d", 4)
	_assert_group_unique("lumberjacks_3d", 2)
	_assert_group_unique("miners_3d", 2)
	_assert_group_unique("resource_nodes_3d", 60)
	_assert_group_unique("walls_3d", 2)
	_assert_group_unique("gates_3d", 1)
	_assert_group_unique("core_buildings_3d", 5)
	var valid_refs := true
	for worker_data in _worker_roster.get_workers():
		var actor: Node = _worker_roster.get_actor(worker_data)
		if actor == null or not is_instance_valid(actor):
			valid_refs = false
		var workplace: Object = worker_data.get_workplace()
		if not is_instance_valid(workplace):
			valid_refs = false
	_check(valid_refs and _worker_roster.get_actor_count() == 4,
		"every rostered worker keeps a live actor and workplace reference")
	if is_instance_valid(_lumberyard) and is_instance_valid(_quarry):
		_check(_lumberyard.get_assigned_workers().all(
				func(w): return is_instance_valid(w)) \
				and _quarry.get_assigned_workers().all(
					func(w): return is_instance_valid(w)),
			"workplace slot references stay valid after repeated cycles")
	else:
		_check(false, "workplaces survive repeated cycles for the slot audit")
	_check(_roster_3d.get_actor("mercenary_A") == null,
		"despawns leave no stale combat actor reference in the night roster")
	_check(_nav_manager.is_inside_tree()
			and _nav_manager.nav_rebuild_count > _nav_baseline,
		"navigation manager stays live with a growing rebuild ledger "
			+ "(no stale navigation)")
	_check(is_instance_valid(_gate) and _gate.is_closed() and _gate.is_inside_tree(),
		"gate survives cycles in a consistent CLOSED state")
	_enter(Phase.CLEANUP)


func _cleanup() -> void:
	_main.queue_free()
	_enter(Phase.DONE)


## -- 입력 헬퍼(bld/cmb/int 회귀와 동일한 push_input 규약) --

## 현재 phase 경계까지 정확히 진행한다. advance의 남은 시간 carry가 다음
## transition을 건너뛰지 않도록 duration - elapsed(+epsilon)만큼만 진행한다.
func _advance_to_next_phase() -> void:
	var need: float = _game_time.get_phase_duration() \
			- _game_time.get_phase_elapsed()
	_game_time.advance(need + 0.05)


func _screen_pos_of(world_pos: Vector3) -> Vector2:
	return _camera.unproject_position(world_pos)


## 카메라 pivot을 world_pos가 화면 중앙에 오도록 이동한다. CameraController3D.pan_camera는
## 상대 offset 계약이므로 현재 pivot과의 delta를 전달해야 절대 목적지 이동이 된다.
func _pan_for(world_pos: Vector3) -> void:
	_cam_ctl.pan_camera(WorldCoords3D.flatten(world_pos) - _cam_ctl.position)


func _push_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event)


func _push_wheel(button_index: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = _screen_pos_of(Vector3.ZERO)
	root.push_input(event)


func _push_left_click(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_pos
	root.push_input(event)


func _push_right_click(screen_pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = screen_pos
	root.push_input(event)
