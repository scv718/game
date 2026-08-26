extends SceneTree

## TASK-3D-INT-002-3 Visual Acceptance.
## 기존 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## Visual Acceptance 완료조건 4항(필수 screenshot 존재 / 기능 regression PASS /
## 치명적 visual blocker 없음 / HUMAN_CHECK 항목 명확히 기록)을 자동검증 가능한
## 두 계층으로 검증한다:
##
## A. Acceptance artifact audit
##    - 캡처 도구(tools/capture_visual_acceptance_3d.gd)의 SHOTS 계약 = 태스크
##      필수 7컷(day overview / worker zoom / forest / lumberyard+quarry /
##      placement / night tactical / night combat)과 정확히 일치.
##    - 7개 PNG 실제 존재 + PNG 시그니처 + 최소 해상도(IHDR 파싱).
##    - 캡처 실행 로그: CAPTURED 7건 + COMPLETE 마커 + ERROR/WARNING 0건
##      (visual blocker 게이트).
##    - acceptance report(auto_dev/INT_VISUAL_ACCEPTANCE_REPORT.md): HUMAN_CHECK
##      9항목 전부 기록 + 전부 "사용자 판단 대기"(AI 임의 PASS 금지 요구) +
##      스크린샷 인덱스 포함.
##    - 기능 regression 로그: task3dint0021(컨테이너 자동검증 21항목) + smoke의
##      실제 실행 PASS 마커.
##
## B. Live functional slice (headless, 실제 main_3d 런타임)
##    - 스크린샷이 대표하는 Runtime이 실제로 동작함을 재확인한다:
##      부팅 wiring → build mode 입력 경로 배치(비용 1회) → 주점 고용/여관 배치 →
##      Worker Actor spawn → 자동 생산 입금 → NIGHT encounter + tactical UI →
##      DAY cleanup → duplicate/orphan/freed 없음.
##
## 주의: -s 기동 초기 autoload 미등록 컴파일 단계 규약(INT-001-2/CMB-001-2 동일)에
## 따라 autoload는 트리 노드로만 접근하고, enum이 필요한 스크립트는 runtime load로
## 해석한다. 캡처 도구 스크립트도 runtime load로만 조회한다.

enum Phase {
	SETUP, INSTANCE_WAIT, BOOT_AUDIT, BUILD_YARD, BUILD_QUARRY,
	HIRE_ASSIGN, PRODUCE_WAIT, TO_NIGHT, NIGHT_CHECK, TO_DAY, DAY_CHECK,
	ARTIFACT_AUDIT, DONE,
}

const TOOL_SCRIPT_PATH := "res://tools/capture_visual_acceptance_3d.gd"
const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const GAME_TIME_SCRIPT_PATH := "res://scripts/game_time.gd"
const MERC_DATA_SCRIPT_PATH := "res://scripts/mercenary_data.gd"
const CAPTURE_LOG_PATH := "res://test_results/visual_acceptance_capture_run.txt"
const REPORT_PATH := "res://auto_dev/INTEGRATION_NOTE_INT_VISUAL_ACCEPTANCE.md"
const REGRESSION_INT0021_LOG := "res://test_results/task3dint0023_regression_int0021_run.txt"
const REGRESSION_SMOKE_LOG := "res://test_results/task3dint0023_regression_smoke_run.txt"

## 논리 px -> world unit 변환(테스트 배치 좌표 계산용 단일 소스).
const PX := WorldCoords3D.PX_TO_UNIT

## task3dint0021 회귀와 동일한 검증된 배치 cell.
const YARD_SPOT := Vector3(32, 0, 30)
const DEPOSIT_SPOT := Vector3(75, 0, 37.5)
const SETTLE_FRAMES := 8
const ENCOUNTER_ENEMY_COUNT := 3
const POLL_BUDGET_PRODUCTION := 1800
const MIN_SHOT_WIDTH := 1024
const MIN_SHOT_HEIGHT := 576
const PNG_SIGNATURE := "89504e470d0a1a0a"

## HUMAN_CHECK 9항목(report에 기록되어야 하는 판단 문장 키워드).
const HUMAN_CHECK_ITEMS := [
	"2D 버전보다 비주얼이 확실히 마음에 드는가",
	"실제 게임 방향처럼 보이는가",
	"마을/자원/방어 공간이 읽히는가",
	"Worker 행동을 보는 재미가 있는가",
	"하나의 아트 스타일로 보이는가",
	"좀보이드 계열의 탑다운 시야감",
	"낮/밤 분위기 차이가 의미 있는가",
	"selection/navigation 가독성을 방해하지 않는가",
	"기능 개발할 동기가 생길 정도의 화면",
]

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _start_msec := 0
var _poll_start_pf := -1

var _game_time: Node = null
var _resources: Node = null
var _worker_roster: Node = null
var _main: Node = null
var _world: Node = null
var _cam_ctl: Node = null
var _camera: Camera3D = null
var _placement: Node = null
var _tac_ui: Node = null
var _tavern_ui: Node = null
var _inn_ui: Node = null
var _wood_before_yard := 0
var _wood_after_build := 0


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


func _poll_budget_exhausted(budget_ticks: int) -> bool:
	var now := Engine.get_physics_frames()
	if _poll_start_pf < 0:
		_poll_start_pf = now
	return int(now - _poll_start_pf) >= budget_ticks


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DINT0023_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.INSTANCE_WAIT:
			_instance_wait()
		Phase.BOOT_AUDIT:
			_boot_audit()
		Phase.BUILD_YARD:
			_build_yard()
		Phase.BUILD_QUARRY:
			_build_quarry()
		Phase.HIRE_ASSIGN:
			_hire_assign()
		Phase.PRODUCE_WAIT:
			_produce_wait()
		Phase.TO_NIGHT:
			_to_night()
		Phase.NIGHT_CHECK:
			_night_check()
		Phase.TO_DAY:
			_to_day()
		Phase.DAY_CHECK:
			_day_check()
		Phase.ARTIFACT_AUDIT:
			_artifact_audit()
		Phase.DONE:
			_finish()
			return true
	if Time.get_ticks_msec() - _start_msec > 300000:
		print("TASK3DINT0023_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	_check(_game_time != null and _resources != null and _worker_roster != null,
		"shared autoloads are available to the acceptance runtime")
	if _game_time == null or _resources == null:
		_enter(Phase.DONE)
		return
	_game_time.set_auto_advance(false)
	root.size = Vector2i(1152, 648)
	_check((load(TOOL_SCRIPT_PATH) as Script).get("SHOTS") != null,
		"capture tool exposes its SHOTS screenshot contract")
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
	_cam_ctl = get_first_node_in_group("camera_controller_3d")
	_camera = _cam_ctl.get_camera() if _cam_ctl != null else null
	_placement = get_first_node_in_group("building_placement_3d")
	_tac_ui = get_first_node_in_group("tactical_command_ui_3d")
	_tavern_ui = get_first_node_in_group("recruitment_ui")
	_inn_ui = get_first_node_in_group("inn_roster_ui")
	_check(_world != null and _cam_ctl != null and _camera != null \
			and _placement != null and _tac_ui != null and _tavern_ui != null \
			and _inn_ui != null,
		"the accepted runtime boots with camera/selection/placement/UI wired")
	if _world == null:
		_enter(Phase.DONE)
		return
	_enter(Phase.BOOT_AUDIT)


func _boot_audit() -> void:
	var camera_count := 0
	var legacy_2d_nodes := 0
	for node in _iterate(root):
		if node is Camera3D:
			camera_count += 1
		if node is Node2D or node is CharacterBody2D or node is Area2D \
				or node is NavigationAgent2D:
			legacy_2d_nodes += 1
	_check(camera_count == 1, "exactly one Camera3D drives the accepted view")
	_check(legacy_2d_nodes == 0,
		"accepted runtime holds no 2D Actor/Camera/Collision/Nav nodes")
	_check(_group_count("resource_nodes_3d") == 60,
		"composed world holds the deterministic 60 tree resources")
	var core_types := {"keep": 0, "tavern": 0, "inn": 0, "grocery": 0, "equipment": 0}
	for building in get_nodes_in_group("core_buildings_3d"):
		core_types[building.get_core_type()] += 1
	var all_once := true
	for t in core_types:
		if core_types[t] != 1:
			all_once = false
	_check(all_once, "all five core buildings exist exactly once")
	_enter(Phase.BUILD_YARD)


func _iterate(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_iterate(child))
	return out


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _wood() -> int:
	return _resources.get_amount("wood")


func _stone() -> int:
	return _resources.get_amount("stone")


func _pan_for(world_pos: Vector3) -> void:
	_cam_ctl.pan_camera(WorldCoords3D.flatten(world_pos) - _cam_ctl.position)


func _screen_pos_of(world_pos: Vector3) -> Vector2:
	return _camera.unproject_position(world_pos)


func _push_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
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


func _advance_to_next_phase() -> void:
	var need: float = _game_time.get_phase_duration() \
			- _game_time.get_phase_elapsed()
	_game_time.advance(need + 0.05)


func _build_yard() -> void:
	if _wait == 0:
		_resources.add("wood", 60)
		_wood_before_yard = _wood()
		_pan_for(YARD_SPOT)
		_push_key(KEY_1)
		_push_key(KEY_B)
		_push_left_click(_screen_pos_of(YARD_SPOT))
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	var yards := get_nodes_in_group("lumberyards")
	_check(yards.size() == 1, "lumberyard places through the live input path")
	if yards.size() == 1:
		_check(WorldCoords3D.distance_xz(yards[0].global_position,
				Vector3(33, 0, 31)) < 0.01,
			"placement snaps to the logical grid cell center")
	_check(_wood() == _wood_before_yard - 10,
		"lumberyard cost deducts Wood exactly once (%d -> %d)"
			% [_wood_before_yard, _wood()])
	_wait = 0
	_enter(Phase.BUILD_QUARRY)


func _build_quarry() -> void:
	if _wait == 0:
		_wood_after_build = _wood()
		_pan_for(DEPOSIT_SPOT)
		_push_key(KEY_2)
		_push_key(KEY_B)
		_push_left_click(_screen_pos_of(DEPOSIT_SPOT))
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	_check(_group_count("quarries") == 1, "quarry places onto the stone deposit")
	_check(_wood() == _wood_after_build - 10,
		"quarry cost deducts Wood exactly once (%d -> %d)"
			% [_wood_after_build, _wood()])
	_wait = 0
	_enter(Phase.HIRE_ASSIGN)


func _hire_assign() -> void:
	if _wait == 0:
		_tavern_ui.open()
		_tavern_ui._hire_buttons["lumberjack_A"].pressed.emit()
		_tavern_ui._hire_buttons["miner_A"].pressed.emit()
		_tavern_ui.close()
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	if _wait == SETTLE_FRAMES:
		_inn_ui.open()
		_inn_ui._assign_buttons["lumberjack_A"].pressed.emit()
		_inn_ui._assign_buttons["miner_A"].pressed.emit()
		_inn_ui.close()
	_wait += 1
	if _wait < SETTLE_FRAMES * 2:
		return
	_check(_group_count("workers_3d") == 2,
		"assignment spawns one Worker Actor per assigned resident")
	_check(_group_count("lumberjacks_3d") == 1 and _group_count("miners_3d") == 1,
		"lumberjack and miner actors are live for the accepted economy loop")
	_wait = 0
	_enter(Phase.PRODUCE_WAIT)


func _produce_wait() -> void:
	if _wood() >= _wood_after_build + 2 and _stone() >= 2 \
			or _poll_budget_exhausted(POLL_BUDGET_PRODUCTION):
		_check(_wood() >= _wood_after_build + 2,
			"lumberjack deposits gathered Wood into the stockpile")
		_check(_stone() >= 2, "miner produces Stone at the bound deposit")
		_enter(Phase.TO_NIGHT)


func _to_night() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_advance_to_next_phase()
	_enter(Phase.NIGHT_CHECK)


func _night_check() -> void:
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	_check(_game_time.get_phase_name() == "NIGHT", "phase advances to NIGHT")
	_check(_tac_ui.visible, "tactical command UI shows at NIGHT")
	_check(_group_count("enemies_3d") == ENCOUNTER_ENEMY_COUNT,
		"NIGHT encounter spawns raiders in the accepted runtime")
	_enter(Phase.TO_DAY)


func _to_day() -> void:
	_advance_to_next_phase()
	_enter(Phase.DAY_CHECK)


func _day_check() -> void:
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	_check(_game_time.get_phase_name() == "DAY", "phase returns to DAY")
	_check(not _tac_ui.visible, "tactical UI hides at DAY")
	_check(_group_count("enemies_3d") == 0,
		"DAY cleanup despawns every combat actor")
	var orphans := 0
	for child in _world.get_children():
		if child is EnemyActor3D or child is MercenaryActor3D:
			orphans += 1
	_check(orphans == 0, "despawned combat actors leave no orphan")
	_check(is_equal_approx(_game_time.get_time_scale(), 1.0),
		"time scale restored to 1x at DAY")
	var ids := {}
	var unique := true
	for node in get_nodes_in_group("workers_3d"):
		if ids.has(node.get_instance_id()):
			unique = false
		ids[node.get_instance_id()] = true
	_check(unique and _group_count("workers_3d") == 2,
		"worker actors stay unique (no duplicates)")
	var valid_refs := true
	for worker_data in _worker_roster.get_workers():
		var actor: Node = _worker_roster.get_actor(worker_data)
		if actor == null or not is_instance_valid(actor):
			valid_refs = false
	_check(valid_refs, "roster keeps live actor references (no freed)")
	_enter(Phase.ARTIFACT_AUDIT)


## 감사 대상 텍스트 파일도 게이트 실행 시점 윈도우 파일 잠금/인코딩 경합의 영향을
## 받는다(PNG_OPEN_RETRY 주석의 재발 사례와 동일 계열). open 실패나 빈 읽기로
## 회귀 PASS 마커를 놓치면 정상 로그가 있어도 FAIL 오탐이 나므로, 같은 재시도
## 규약을 적용한다. 판정 기준은 불변이며 최종 관측값만 사용한다.
const TEXT_OPEN_RETRY := 8
const TEXT_OPEN_RETRY_DELAY_MSEC := 400


func _read_text(path: String) -> String:
	for attempt in range(TEXT_OPEN_RETRY):
		var text := _read_text_once(path)
		if attempt == TEXT_OPEN_RETRY - 1 or not text.is_empty():
			return text
		OS.delay_msec(TEXT_OPEN_RETRY_DELAY_MSEC)
	return ""


func _read_text_once(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## PNG 바이너리 검증: 시그니처 + IHDR 치수 파싱.
## 구현 세션 종료 직후 게이트 실행 시점에 윈도우 파일 잠금 경합으로 open이
## 일시 실패해 정상 PNG를 (-1,-1)로 오판한 사례가 있어(게이트 18:52/19:35/
## 19:58 오탐), 짧은 재시도를 둔다. 200ms 간격 3회로는 부족해 19:58 게이트에서
## 재발했으므로(정적분석상 PNG는 무변경), 간격을 넓혀 횟수를 늘린다.
## 판정 기준은 불변이며 최종 관측값만 사용한다.
const PNG_OPEN_RETRY := 8
const PNG_OPEN_RETRY_DELAY_MSEC := 400


func _png_size(path: String) -> Vector2i:
	for attempt in range(PNG_OPEN_RETRY):
		var dims := _png_size_once(path)
		if attempt == PNG_OPEN_RETRY - 1 \
				or (dims.x >= MIN_SHOT_WIDTH and dims.y >= MIN_SHOT_HEIGHT):
			return dims
		OS.delay_msec(PNG_OPEN_RETRY_DELAY_MSEC)
	return Vector2i(-1, -1)


func _png_size_once(path: String) -> Vector2i:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Vector2i(-1, -1)
	var header := file.get_buffer(24).hex_encode()
	if not header.begins_with(PNG_SIGNATURE):
		return Vector2i(-1, -1)
	var width := int(header.substr(32, 8).hex_to_int())
	var height := int(header.substr(40, 8).hex_to_int())
	return Vector2i(width, height)


func _artifact_audit() -> void:
	var shots: Dictionary = (load(TOOL_SCRIPT_PATH) as Script).get("SHOTS")
	_check(shots != null and shots.size() == 7,
		"capture contract holds exactly the 7 required screenshots")
	var expected_keys := ["day_overview", "day_worker_zoom", "forest_resource",
		"lumberyard_quarry", "building_placement", "night_tactical", "night_combat"]
	var keys_match := true
	for key in expected_keys:
		if not shots.has(key):
			keys_match = false
	_check(keys_match, "screenshot keys cover every required acceptance cut")
	var all_pngs := true
	var dims_ok := true
	for key in shots:
		var path: String = shots[key]
		if not FileAccess.file_exists(path):
			all_pngs = false
			print("MISSING_SHOT " + key)
			continue
		var dims := _png_size(path)
		if dims.x < MIN_SHOT_WIDTH or dims.y < MIN_SHOT_HEIGHT:
			dims_ok = false
			print("BAD_DIMS %s %s" % [key, str(dims)])
	_check(all_pngs, "all 7 required screenshots exist on disk")
	_check(dims_ok, "screenshots carry real rendered resolution >= %dx%d"
		% [MIN_SHOT_WIDTH, MIN_SHOT_HEIGHT])
	var capture_log := _read_text(CAPTURE_LOG_PATH)
	_check(capture_log.count("CAPTURED ") == 7,
		"capture run log records exactly 7 saved screenshots")
	_check(capture_log.contains("VISUAL_ACCEPTANCE_CAPTURE=COMPLETE"),
		"capture run finished with the COMPLETE marker")
	_check(not capture_log.contains("ERROR") and not capture_log.contains("WARNING"),
		"capture run log is free of ERROR/WARNING (visual blocker gate)")
	var report := _read_text(REPORT_PATH)
	var report_ok := true
	for item in HUMAN_CHECK_ITEMS:
		if not report.contains(item):
			report_ok = false
			print("MISSING_HUMAN_CHECK " + item)
	_check(report_ok, "acceptance report records all 9 HUMAN_CHECK items verbatim")
	_check(report.count("사용자 판단 대기") >= 9,
		"every HUMAN_CHECK item stays deferred to the user (no AI pass marking)")
	_check(report.contains("AI가 임의로 PASS 처리하지 않는다"),
		"acceptance report states the no-AI-pass rule explicitly")
	var indexed := true
	for key in shots:
		if not report.contains(String(shots[key]).get_file()):
			indexed = false
			print("MISSING_INDEX %s" % String(shots[key]).get_file())
	_check(indexed, "report indexes every required screenshot file")
	var int0021_log := _read_text(REGRESSION_INT0021_LOG)
	_check(int0021_log.contains("TASK3DINT0021_RESULT=PASS"),
		"container automated regression (task3dint0021) recorded PASS")
	var smoke_log := _read_text(REGRESSION_SMOKE_LOG)
	_check(smoke_log.contains("SMOKE_RESULT=PASS"),
		"main scene smoke regression recorded PASS")
	_enter(Phase.DONE)
