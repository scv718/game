extends SceneTree

## TASK-3D-INT-001-2 Existing Gameplay Vertical Slice 3D 회귀 테스트.
## 기존 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 큐 시나리오 22단계를 main_3d.tscn 실제 Runtime 위에서 재생한다:
##   게임 시작 -> 3D Main World content(Tree/Deposit/CoreBuilding/MapLayout) 확인 ->
##   DAY camera pan/zoom -> 건물 click(Tavern/Inn UI 개방) -> BuildingPlacement로
##   Lumberyard/Quarry/Wall/Gate 건설 -> 주점 고용(UI 버튼) -> 여관 배치(UI 버튼) ->
##   Lumberjack/Miner 자동 생산 -> 자원 고갈/regrowth -> NIGHT 진입 ->
##   전술 시간 명령(Pause/2x/1x) -> 성문 OPEN/CLOSE 명령 -> 용병 자동전투(focus 지정)
##   -> lethal death -> Death Ledger 기록 검증 -> DAY 복귀(despawn/orphan 없음)
##   -> 다음 cycle 반복(duplicate 없음, 사망자 재참전 없음).
##
## 핵심검증 대응: Player Avatar/combat 경로 없음, 카메라 회전 입력 경로 없음,
## 3D Actor만 사용, 모달 UI 열려 있을 때 월드 클릭 차단(UI click-through 방지),
## 반복 cycle에서 duplicate actor/freed reference/stale nav 없음.
##
## 주의: -s 기동 초기 autoload 미등록 컴파일 단계 규약(CMB-001-2 동일)에 따라
## autoload를 참조하는 스크립트는 정적으로 참조하지 않고 트리 노드/런타임 load +
## duck-typing으로만 접근한다.

enum Phase {
	SETUP, INSTANCE_WAIT, CONTENT_AUDIT, CAMERA_AUDIT, SELECT_BUILDINGS,
	MODAL_GUARD, BUILD_LUMBERYARD, BUILD_QUARRY, HIRE_WORKERS, ASSIGN_WORKERS,
	PRODUCTION_WAIT, STONE_WAIT, PRODUCTION_CHECK, DEPLETE_REGROW,
	DEPLETE_REGROW_CHECK, WALL_GATE_BUILD, HIRE_MERCENARY, TO_NIGHT, NIGHT_WAIT,
	NIGHT_CHECK, TIME_COMMANDS, GATE_COMMANDS, FOCUS_ENGAGE, COMBAT_WAIT,
	LEDGER_CHECK, TO_DAY, DAY_WAIT, DAY_CHECK, SECOND_NIGHT_WAIT, SECOND_NIGHT_CHECK,
	SECOND_DAY_WAIT, FINAL_CHECK, CLEANUP, DONE,
}

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const CONTENT_SCRIPT_PATH := "res://scripts/world_content_3d.gd"
const LAYOUT_SCRIPT_PATH := "res://scripts/world_map_layout_3d.gd"
const WORKPLACE_SCRIPT_PATH := "res://scripts/workplace_3d.gd"
const GAME_TIME_SCRIPT_PATH := "res://scripts/game_time.gd"
const MERC_DATA_SCRIPT_PATH := "res://scripts/mercenary_data.gd"
const TACTICAL_UI_SCRIPT_PATH := "res://scripts/tactical_command_ui.gd"

## 논리 px -> world unit 변환(테스트 배치 좌표 계산용 단일 소스).
const PX := WorldCoords3D.PX_TO_UNIT

## 테스트용 단축 phase 시간(sec).
const SHORT_DAY_DURATION := 1.0
const SHORT_NIGHT_DURATION := 2.0
const SETTLE_FRAMES := 8
const ENCOUNTER_ENEMY_COUNT := 3

## 조건 폴링 예산(physics tick). headless에서 idle frame rate와 physics tick rate가
## 1:1이 아니므로(INTEGRATION_NOTE_WRK 테스트 규약) 시간 의미 예산은 반드시
## physics frame 기준으로 잰다. 60 tick = 실제 1초 기준 환산값이다.
const POLL_BUDGET_PRODUCTION := 1500
const POLL_BUDGET_REGROW := 300
const POLL_BUDGET_COMBAT := 1200

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _start_msec := 0
## 진행 중인 폴링의 시작 physics frame 번호(-1 = 대기 중 아님).
var _poll_start_pf := -1

var _game_time: Node = null
var _phase_enum: Dictionary = {}
var _resources: Node = null
var _worker_roster: Node = null
var _roster_autoload: Node = null
var _ledger: Node = null

var _main: Node = null
var _world: Node = null
var _content: Node = null
var _layout: Node = null
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

var _wood_baseline := 0
## 모든 건설 비용 차감이 끝난 직후의 Wood 잔액. 생산 입금 판정 기준선이다.
var _wood_after_build := 0
var _ledger_baseline := -1
var _ledger_after_combat := -1


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


## 폴링 예산 소진 판정(physics tick 기준). 첫 호출에 시작 frame을 기록한다.
func _poll_budget_exhausted(budget_ticks: int) -> bool:
	var now := Engine.get_physics_frames()
	if _poll_start_pf < 0:
		_poll_start_pf = now
	if int(now - _poll_start_pf) >= budget_ticks:
		return true
	return false


func _wood() -> int:
	return _resources.get_amount("wood")


func _stone() -> int:
	return _resources.get_amount("stone")


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DINT0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.INSTANCE_WAIT:
			_instance_wait()
		Phase.CONTENT_AUDIT:
			_content_audit()
		Phase.CAMERA_AUDIT:
			_camera_audit()
		Phase.SELECT_BUILDINGS:
			_select_buildings()
		Phase.MODAL_GUARD:
			_modal_guard()
		Phase.BUILD_LUMBERYARD:
			_build_lumberyard()
		Phase.BUILD_QUARRY:
			_build_quarry()
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
		Phase.DEPLETE_REGROW:
			_deplete_regrow()
		Phase.DEPLETE_REGROW_CHECK:
			_deplete_regrow_check()
		Phase.WALL_GATE_BUILD:
			_wall_gate_build()
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
		Phase.FINAL_CHECK:
			_final_check()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if Time.get_ticks_msec() - _start_msec > 420000:
		print("TASK3DINT0012_RESULT=TIMEOUT phase=%s" % str(_phase))
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
		"shared autoloads are available to the vertical slice runtime")
	if _game_time == null:
		_enter(Phase.DONE)
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(SHORT_DAY_DURATION, SHORT_NIGHT_DURATION)
	# headless 기본 window(64x64)에서는 UI Control이 화면 대부분을 덮어
	# push_input 마우스 이벤트가 GUI 단계에서 흡수된다. 프로젝트 표시 해상도로
	# 올려 실제 런타임과 동일한 screen 좌표 계산(unproject/GUI hit)을 보장한다.
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
		"game boots into the 3D Main World (scenario 1-2)")
	if _world == null:
		_enter(Phase.DONE)
		return
	_content = _world.get_node_or_null("WorldContent3D")
	_layout = _world.get_node_or_null("MapLayout")
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
	_enter(Phase.CONTENT_AUDIT)


## -- 시나리오 2/5: 3D world gameplay content 구성 확인 --
func _content_audit() -> void:
	var content_script: Script = load(CONTENT_SCRIPT_PATH)
	var layout_script: Script = load(LAYOUT_SCRIPT_PATH)
	var workplace_script: Script = load(WORKPLACE_SCRIPT_PATH)
	_check(_content != null and _content.get_script() == content_script,
		"WorldContent3D composes the 3D world gameplay content")
	_check(_content.get_tree_count() == 60,
		"3D world holds the same 60 trees as the 2D reference layout")
	_check(_group_count("resource_nodes_3d") == 60,
		"every composed tree registers as a 3D resource node")
	var deposit: Node3D = _content.get_stone_deposit()
	_check(deposit != null \
			and deposit.global_position.is_equal_approx(
				Vector3(600 * PX, 0, 300 * PX)),
		"StoneDeposit3D sits at the WorldMap stone zone position")
	_check(_layout != null and _layout.get_script() == layout_script,
		"MapLayout3D is wired under the world root")
	_check(_layout.has_method("get_rally_space") \
			and _layout.has_method("get_clearing_rect") \
			and _layout.has_method("get_spawn_candidate") \
			and _layout.has_method("get_main_road"),
		"MapLayout3D satisfies the roster/spawner lookup contract")
	_check(_layout.get_clearing_rect().get_center() == Vector2.ZERO,
		"MapLayout3D clearing center matches the shared settlement center")
	_check(workplace_script != null \
			and get_first_node_in_group("lumberyards") == null,
		"no workplace exists before the player builds one")
	var expected_types := {"keep": 0, "tavern": 0, "inn": 0, "grocery": 0, "equipment": 0}
	for building in get_nodes_in_group("core_buildings_3d"):
		expected_types[building.get_core_type()] += 1
	var all_once := true
	for t in expected_types:
		if expected_types[t] != 1:
			all_once = false
	_check(all_once,
		"all five core buildings exist exactly once (keep/tavern/inn/grocery/equipment)")
	_check(_keep != null and _keep.get_parent() == _world,
		"Keep is a direct world-root child so spawner/retreat resolve the village core")
	var spawn_point: Vector3 = _spawner_3d.get_spawn_world_point("west", _world)
	_check(spawn_point.is_equal_approx(Vector3(-180, 0, 25)),
		"encounter spawner resolves the west spawn candidate through MapLayout3D")
	var defense_zone_west: int = (load(MERC_DATA_SCRIPT_PATH) as Script).DefenseZone.WEST
	var rally_west: Vector3 = _roster_3d.get_rally_point_for_zone(defense_zone_west, _world)
	_check(rally_west.is_equal_approx(Vector3(-38.125, 0, 0)),
		"west defense rally resolves to the rally space center")
	_check(_nav_manager.nav_rebuild_count >= 1,
		"initial navigation bake covers the composed world (no stale startup nav)")
	_enter(Phase.CAMERA_AUDIT)


## -- 시나리오 3/4 + 핵심검증(camera rotation 없음): pan/zoom --
func _camera_audit() -> void:
	var before: Vector3 = _cam_ctl.position
	_cam_ctl.pan_camera(Vector3(30, 0, -20))
	var panned: Vector3 = _cam_ctl.position
	_check(panned.x > before.x and panned.z < before.z and panned.y == 0.0,
		"WASD-equivalent pan moves the camera pivot on the ground plane only")
	_cam_ctl.pan_camera(Vector3(4000, 0, 4000))
	_check(_cam_ctl.position.x <= WorldCoords3D.WORLD_HALF_UNITS \
			and _cam_ctl.position.z <= WorldCoords3D.WORLD_HALF_UNITS,
		"pan clamps against the shared world bounds")
	_cam_ctl.pan_camera(-_cam_ctl.position)
	_check(_cam_ctl.position.length_squared() < 0.0001,
		"camera pivots back to the village center")
	var zoom_before: float = _cam_ctl.get_zoom_target()
	_push_wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(_cam_ctl.get_zoom_target() > zoom_before,
		"mouse wheel zooms in (scenario 4)")
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
		"camera keeps a fixed oblique basis while panning (rotation path 없음)")
	_cam_ctl.pan_camera(Vector3(-10, 0, 0))
	_enter(Phase.SELECT_BUILDINGS)


## -- 시나리오 5/6: 건물 click -> Tavern/Inn UI 개방 --
func _select_buildings() -> void:
	var tavern: Node3D = _world.get_node_or_null("Tavern")
	var inn: Node3D = _world.get_node_or_null("Inn")
	var tavern_screen := _screen_pos_of(tavern.global_position + Vector3(0, 2, 0))
	var selected: Interactable3D = _selection.select_at_screen_position(tavern_screen)
	_check(selected != null and selected.get_core_building() == tavern,
		"clicking the Tavern selects its interactable (scenario 5)")
	_check(_tavern_ui.visible,
		"Tavern interaction opens the existing TavernRecruitmentUI (scenario 6)")
	_tavern_ui.close()
	var inn_screen := _screen_pos_of(inn.global_position + Vector3(0, 2, 0))
	selected = _selection.select_at_screen_position(inn_screen)
	_check(selected != null and selected.get_core_building() == inn,
		"clicking the Inn selects its interactable")
	_check(_inn_ui.visible, "Inn interaction opens the existing InnRosterUI")
	_inn_ui.close()
	_enter(Phase.MODAL_GUARD)


## -- 핵심검증(UI click-through 없음): 모달 개방 중 월드 클릭 차단 --
func _modal_guard() -> void:
	_inn_ui.open()
	_check(not _selection.can_handle_world_click(),
		"open modal UI blocks world clicks (no UI click-through)")
	_inn_ui.close()
	_check(_selection.can_handle_world_click(),
		"closing the modal restores world click handling")
	_enter(Phase.BUILD_LUMBERYARD)


## -- 시나리오 11: BuildingPlacement(B 입력)로 Lumberyard 배치 --
func _build_lumberyard() -> void:
	_resources.add("wood", 40)
	_wood_baseline = _wood()
	_pan_for(Vector3(51, 0, 45))
	_push_key(KEY_1)
	_push_key(KEY_B)
	_check(_placement.is_active(), "B enters build mode (scenario 11)")
	_push_left_click(_screen_pos_of(Vector3(51, 0, 45)))
	_check(_placement.is_active() == false,
		"single-unit buildings exit build mode after placement")
	_wait = 0
	_enter(Phase.BUILD_QUARRY)


## -- 시나리오 7: Quarry를 deposit에 스냅 배치 --
func _build_quarry() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	var yards := get_nodes_in_group("lumberyards")
	_check(yards.size() == 1, "one Lumberyard3D placed via the input path (scenario 7)")
	if yards.size() == 1:
		_lumberyard = yards[0]
	_check(_lumberyard != null and _lumberyard.is_in_group("lumberyards"),
		"3D workplace serves the legacy inn-UI lookup group (dual registration)")
	_check(_wood() == _wood_baseline - 10,
		"lumberyard cost deducts Wood exactly once (%d -> %d)" % [_wood_baseline, _wood()])
	var deposits := get_nodes_in_group("stone_deposits_3d")
	var deposit: Node3D = deposits[0] if not deposits.is_empty() else null
	_pan_for(Vector3(75, 0, 37.5))
	_push_key(KEY_2)
	_push_key(KEY_B)
	_push_left_click(_screen_pos_of(Vector3(75, 0, 37.5)))
	var quarries := get_nodes_in_group("quarries")
	_check(quarries.size() == 1, "Quarry3D placed onto the Stone Deposit")
	if quarries.size() == 1:
		_quarry = quarries[0]
		_check(_quarry.is_in_group("quarries"),
			"quarry serves the legacy inn-UI lookup group (dual registration)")
		_check(deposit != null and deposit.get_quarry() == _quarry,
			"quarry binds the deposit anchor on placement")
	_check(_placement.is_active() == false, "quarry placement exits build mode")
	# 생산 판정 기준선은 quarry 비용 차감까지 끝난 지점에서 캡처한다.
	_wood_after_build = _wood()
	_wait = 0
	_enter(Phase.HIRE_WORKERS)


## -- 시나리오 8(고용): 주점 UI 버튼으로 Worker/Mercenary 고용 --
func _hire_workers() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_tavern_ui.open()
	_tavern_ui._hire_buttons["lumberjack_A"].pressed.emit()
	_tavern_ui._hire_buttons["miner_A"].pressed.emit()
	_check(_worker_roster.get_count() == 2,
		"Tavern UI hiring registers both workers in the shared WorkerRoster")
	_check(_worker_roster.get_unassigned().size() == 2,
		"hired workers stay roster data only (no world actor yet)")
	_check(_group_count("workers_3d") == 0,
		"unassigned residents never become world actors (design rule)")
	_tavern_ui.close()
	_wait = 0
	_enter(Phase.ASSIGN_WORKERS)


## -- 시나리오 8(배치): 여관 UI 버튼으로 시설 배치 -> Worker Actor spawn --
func _assign_workers() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_inn_ui.open()
	_inn_ui._assign_buttons["lumberjack_A"].pressed.emit()
	_inn_ui._assign_buttons["miner_A"].pressed.emit()
	_check(_worker_roster.get_assigned_count() == 2,
		"Inn UI assigns each worker to its matching facility")
	_check(_group_count("workers_3d") == 2,
		"assignment spawns exactly one Worker Actor per assigned resident")
	_check(_group_count("lumberjacks_3d") == 1 and _group_count("miners_3d") == 1,
		"spawned actors are the 3D lumberjack/miner pair")
	_check(_group_count("lumberjacks") == 0 and _group_count("miners") == 0,
		"no legacy 2D worker actors leak into the 3D runtime")
	_inn_ui.close()
	_wait = 0
	_enter(Phase.PRODUCTION_WAIT)


## -- 시나리오 9: Lumberjack 자동 벌목 생산 대기 --
func _production_wait() -> void:
	if _wood() >= _wood_after_build + 5 \
			or _poll_budget_exhausted(POLL_BUDGET_PRODUCTION):
		_enter(Phase.STONE_WAIT)


## -- 시나리오 10: Miner 자동 채굴 생산 대기 --
func _stone_wait() -> void:
	if _stone() >= 2 or _poll_budget_exhausted(POLL_BUDGET_PRODUCTION):
		_enter(Phase.PRODUCTION_CHECK)


## -- 시나리오 9/10 생산 결과 확인 --
func _production_check() -> void:
	_check(_wood() >= _wood_after_build + 5,
		"Lumberjack deposits gathered Wood into the stockpile (auto production)")
	_check(_stone() >= 2,
		"Miner produces Stone at the bound deposit (auto production)")
	_enter(Phase.DEPLETE_REGROW)


func _find_tree_near(world_pos: Vector3) -> WorldTree3D:
	var target: WorldTree3D = null
	var best_dist := INF
	for tree in get_nodes_in_group("resource_nodes_3d"):
		var d: float = WorldCoords3D.distance_xz(tree.global_position, world_pos)
		if d < best_dist:
			best_dist = d
			target = tree
	return target


## -- 시나리오 13: 자원 고갈(stump) -> regrowth --
func _deplete_regrow() -> void:
	var target := _find_tree_near(Vector3(103.75, 0, -75))
	_check(target != null and target.current_amount == 5,
		"a far sparse-forest tree is picked for the depletion check")
	target.regrow_time = 0.4
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
	_enter(Phase.DEPLETE_REGROW_CHECK)


func _deplete_regrow_check() -> void:
	if not _poll_budget_exhausted(POLL_BUDGET_REGROW):
		return
	var target := _find_tree_near(Vector3(103.75, 0, -75))
	_check(target.state == WorldTree3D.State.MATURE and target.current_amount == 5,
		"stump regrows into a mature tree after regrow_time")
	_check(_nav_manager.nav_rebuild_count >= 2,
		"depletion/regrowth keep navigation rebaked (no stale nav)")
	_enter(Phase.WALL_GATE_BUILD)


## -- 시나리오 12: Wall 연속 배치 + Gate(corridor snap) 배치 --
func _wall_gate_build() -> void:
	_resources.add("wood", 40)
	_pan_for(Vector3(0, 0, -57))
	_push_key(KEY_3)
	_push_key(KEY_B)
	_check(_placement.is_active(), "build mode re-enters for walls")
	# 클릭/차감 확인은 같은 tick 안에서 수행한다(생산 입금과의 경합 제거).
	var wood_before_walls := _wood()
	_push_left_click(_screen_pos_of(Vector3(0, 0, -57)))
	_push_left_click(_screen_pos_of(Vector3(0, 0, -53)))
	_check(get_nodes_in_group("walls_3d").size() == 2,
		"two wall segments placed in continuous build mode (scenario 12)")
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
			"gate direction resolves from the corridor (centerline snap)")
		_check(_gate.is_closed(), "newly placed gate starts CLOSED")
	_check(_placement.is_active(),
		"wall/gate keep continuous build mode (TASK-013-1 policy)")
	_check(_wood() == wood_before_gate - 5,
		"gate placement deducts its Wood cost once")
	_push_key(KEY_ESCAPE)
	_check(_placement.is_active() == false,
		"ESC exits the continuous build mode after the gate")
	_wait = 0
	_enter(Phase.HIRE_MERCENARY)


## -- 시나리오 6/16 준비: 용병 고용 + 여관에서 방어 구역 지정 --
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
		"hire sync bridges the recruit into MercenaryRoster3D (same data object)")
	_tavern_ui.close()
	_inn_ui.open()
	var merc = _roster_3d.get_mercenary("mercenary_A")
	_inn_ui._on_defense_zone_pressed(merc, defense_zone_west)
	_check(merc.defense_zone == defense_zone_west,
		"Inn UI assigns the mercenary to the west defense zone")
	_inn_ui.close()
	_wait = 0
	_enter(Phase.TO_NIGHT)


## -- 시나리오 14: NIGHT 진입 --
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
		"phase advanced to NIGHT (scenario 14)")
	_check(_tac_ui.visible, "tactical command UI shows at NIGHT (scenario 15)")
	_check(get_nodes_in_group("enemies_3d").size() == ENCOUNTER_ENEMY_COUNT,
		"NIGHT encounter spawns raiders from the west")
	_check(_group_count("mercenaries_3d") == 1,
		"zone-assigned mercenary deploys as a single 3D actor")
	_check(_ledger.get_all_records().size() == _ledger_baseline,
		"deployment itself records nothing in the Death Ledger")
	_enter(Phase.TIME_COMMANDS)


## -- 시나리오 17 일부: 전술 시간 명령(Pause/2x/1x) --
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


## -- 시나리오 18: 성문 개폐 명령 --
func _gate_commands() -> void:
	var commands: Dictionary = (load(TACTICAL_UI_SCRIPT_PATH) as Script).get("Command")
	_check(_gate.is_closed(), "gate starts the night CLOSED")
	_roster_3d._on_tactical_command(commands.GATE_OPEN, _gate)
	_check(_gate.is_open() and not _gate.is_breached(),
		"GATE_OPEN command opens the passage (scenario 18)")
	_roster_3d._on_tactical_command(commands.GATE_CLOSE, _gate)
	_check(_gate.is_closed(), "GATE_CLOSE command closes the passage again")
	_enter(Phase.FOCUS_ENGAGE)


## -- 시나리오 16/17: 용병 자동전투(focus 지정 포함) --
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
		"focus target command designates the priority enemy (scenario 17)")
	var merc_actor: Node = _roster_3d.get_actor("mercenary_A")
	_check(merc_actor != null and merc_actor.is_inside_tree(),
		"mercenary actor is live when engagement starts (freed reference 없음)")
	_wait = 0
	_enter(Phase.COMBAT_WAIT)


## -- 시나리오 19: lethal death 대기 --
func _combat_wait() -> void:
	var deaths: int = _ledger.get_all_records().size() - _ledger_baseline
	if deaths >= 1 or _poll_budget_exhausted(POLL_BUDGET_COMBAT):
		_enter(Phase.LEDGER_CHECK)


## -- 시나리오 19/20: Death Ledger 기록 검증 --
func _ledger_check() -> void:
	var records: Array = _ledger.get_all_records()
	var deaths := records.size() - _ledger_baseline
	_check(deaths >= 1,
		"auto combat produces at least one lethal death (scenario 19)")
	var source_ids := {}
	var unique := true
	for record in records:
		var uid: Variant = record.source_uid
		if source_ids.has(uid):
			unique = false
		source_ids[uid] = true
	_check(unique, "Death Ledger holds no duplicate records (scenario 20)")
	_ledger_after_combat = records.size()
	_enter(Phase.TO_DAY)


## -- 시나리오 21: DAY 복귀 --
func _to_day() -> void:
	_advance_to_next_phase()
	_enter(Phase.DAY_WAIT)


func _day_wait() -> void:
	_wait += 1
	if _wait >= SETTLE_FRAMES:
		_enter(Phase.DAY_CHECK)


func _day_check() -> void:
	_check(_game_time.get_phase_name() == "DAY",
		"phase returned to DAY (scenario 21)")
	_check(not _tac_ui.visible, "tactical UI hides at DAY")
	_check(_group_count("enemies_3d") == 0 and _group_count("mercenaries_3d") == 0,
		"DAY cleanup despawns every combat actor")
	var orphans := 0
	for child in _world.get_children():
		if child is EnemyActor3D or child is MercenaryActor3D:
			orphans += 1
	_check(orphans == 0, "despawned combat actors leave no orphan under the world")
	_check(_ledger.get_all_records().size() == _ledger_after_combat,
		"DAY despawn writes no extra death records")
	_check(is_equal_approx(_game_time.get_time_scale(), 1.0),
		"time scale restored to 1x at DAY")
	_check(_roster_3d.focus_target == null and _roster_3d.focus_mode == false,
		"focus transient state clears at DAY")
	_wait = 0
	_enter(Phase.SECOND_NIGHT_WAIT)


## -- 시나리오 22: 다음 cycle 반복 --
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
		"second cycle reaches NIGHT (scenario 22)")
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
		_enter(Phase.FINAL_CHECK)


func _final_check() -> void:
	_check(_game_time.get_phase_name() == "DAY", "second cycle returns to DAY")
	_check(_group_count("enemies_3d") == 0,
		"second cleanup leaves no enemies behind")
	_check(_worker_roster.get_actor_count() == 2,
		"civilian worker actors persist across cycles (no respawn churn)")
	_check(_ledger.get_all_records().size() == _ledger_after_combat,
		"second cycle cleanup adds no death records")
	_check(_nav_manager.nav_rebuild_count >= 1,
		"navigation manager survived repeated cycles (service intact)")
	_enter(Phase.CLEANUP)


func _cleanup() -> void:
	_main.queue_free()
	_enter(Phase.DONE)


## -- 입력 헬퍼(bld/cmb 회귀와 동일한 push_input 규약) --

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
