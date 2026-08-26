extends SceneTree

## TASK-3D-INT-002-2 Basic Performance / Stress.
## 기존 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 3D 전환 후 기본 프로토타입이 "명백하게 사용 불가능한 수준으로 느려지지 않는지"
## 확인하는 성능/스트레스 회귀다. 큐 검증 목록 9항목을 실제 Runtime(main_3d.tscn)에서
## 재생하고 측정값을 PERF 라인으로 남긴다:
##
##   1. 현재 규모        - vertical slice 구성 전후 Worker/Building/Resource 실측 census
##   2. 다수 배치        - Tree 48 + Rock 24 + Prop 24 추가 배치(결정적 좌표) + 배치 비용
##   3. full overview    - 월드 4모서리 순환 pan + 경계 clamp 도달
##   4. zoom 반복        - min<->max wheel zoom 사이클(pan과 동시 진행)
##   5. Worker navigation- probe 8기 동시 장거리 이동(마을 core 관통 -> 우회 부하)
##   6. NIGHT combat     - 용병 focus 교전 구간 frame 비용 샘플링
##   7. DAY/NIGHT 반복   - 3 cycle 반복 + 각 DAY cleanup 고아 검사
##   8. material/mesh 중복 - MeshInstance3D 전수 조사: mesh/material RID 유니크 대비
##                           인스턴스 수(공유 자원 사용 여부), 배치 전후 증분
##   9. per-frame 할당/spawn loop - 무이벤트 대기 구간에서 node/orphan/memory/group
##                           census 불변 + frame 시간 추세(runaway) 판정
##
## 측정 원칙(태스크 제약 반영):
##   - headless에서 GPU 렌더 비용은 측정 대상이 아니며(운영 규칙 15),
##     CPU 측(process/physics frame 시간, bake/spawn wall time)만 자동 검증한다.
##     실제 화면 FPS 체감은 HUMAN_CHECK(INT-002-3 screenshot set)로 남긴다.
##   - 임계값은 "명백히 불가능" 수준만 걸러내는 넉넉한 상한이다. 병목 판단은
##     기록된 PERF 수치로 하며, 추측성 MultiMesh/ECS/LOD 선행 최적화를 하지 않는다.
##
## 확정 병목 기록(완료조건 "확인된 병목은 기록"; 상세 수치는
## test_results/task3dint0022_perf_report.txt):
##   1. [개선 완료] 월드 navmesh 동기 bake 1회 약 3.9~4.6초(parse 4.6ms vs
##      bake 4203ms - 비용 99.9%가 raster). Tree 고갈/regrow마다 debounced
##      rebake가 메인 스레드를 수 초간 막아 사용 불가능 등급이었다.
##      최소 개선: NAV_CELL_SIZE_UNITS 0.125->0.5(세로 해상도 LOCK 유지,
##      약 16배 절감) + 런타임 churn 경로의 bake를 워커 스레드로 이관
##      (navigation_manager_3d.rebuild_navigation_async, generation 순서 보호,
##      대기열 depth-1 collapse). 동기 rebuild_navigation() 계약 유지.
##      개선 후 본 테스트 전 창이 60fps 케이던스(tick wall 평균 16.6~16.7ms),
##      >150ms 스파이크 0건.
##   2. [청결] material/mesh duplication 없음 - instance 400/slot 430에서
##      unique mesh 25/material 17, 배치 +208 instance에 unique mesh 증분 +18.
##   3. [청결] per-frame allocation/scene spawn loop 없음 - 무이벤트 600 tick에
##      node 증감 0, orphan 0, memory +1KB, group census 불변.
##
## 계약 변경 요약(후속 태스크 주의):
##   - debounce flush는 eventually-consistent다. 요청 -> map 반영 지연 상한은
##     bake 소요 시간(현재 약 0.2~0.3s). 물리 collision은 즉시 반영된다.
##   - 결정적 map 신선도가 필요하면 동기 rebuild_navigation()을 쓴다(테스트/
##     초기화가 그렇다).
##   - nav_rebuild_count = "발행된 rebake 수". async 완료는 navigation_baked로
##     관측한다.
##
## 타이밍 규약:
##   - 모든 샘플링 창은 physics tick 경계에서 1회씩 진행한다(-s headless는 process
##     loop가 제한 없이 빨라 process 프레임 수로 창 길이를 정하면 gameplay 진행
##     (physics tick 기반)와 시간 스케일이 어긋난다). Engine.max_fps 상한은
##     loop spin에 따른 무의미한 process 반복만 줄인다.
##   - GameTime은 auto_advance off + advance() 직접 호출로 phase를 제어한다(int0021 규약).
##   - -s 기동 초기 autoload는 트리 노드로만 접근한다(enum 필요 시 runtime load).

enum Phase {
	SETUP, INSTANCE_WAIT, SCALE_AUDIT, BUILD_LUMBERYARD, BUILD_QUARRY,
	HIRE_ASSIGN_WORKERS, PRODUCTION_WAIT, PRODUCTION_CHECK,
	STRESS_BATCH_SPAWN, STRESS_BATCH_BAKE, DUPLICATION_AUDIT,
	CAMERA_ARM, CAMERA_RUN, CAMERA_CHECK,
	NAV_PROBE_SPAWN, NAV_RUN_SETTLE, NAV_RUN, NAV_RESTORE,
	HIRE_MERCENARY, CYCLE_NIGHT_ENTER, CYCLE_FOCUS, CYCLE_SAMPLE,
	CYCLE_TO_DAY, CYCLE_DAY_WAIT, CYCLE_DAY_CHECK,
	RUNAWAY_START, RUNAWAY_END, FINAL_AUDIT, CLEANUP, DONE,
}

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const MERC_DATA_SCRIPT_PATH := "res://scripts/mercenary_data.gd"

## 논리 px -> world unit 변환(테스트 배치 좌표 계산용 단일 소스).
const PX := WorldCoords3D.PX_TO_UNIT

const SETTLE_FRAMES := 8
const NAV_SYNC_FRAMES := 10
const SHORT_DAY_DURATION := 2.0
const SHORT_NIGHT_DURATION := 4.0

## -- 스트레스 배치 규모(Tree/Rock/Prop 다수 배치). 기존 Tree 60의 0.8배 추가 +
##    장식 rock/prop 48점 = 결정적 그리드 배치(RNG 없음). --
const STRESS_TREE_COUNT := 48
const STRESS_ROCK_COUNT := 24
const STRESS_PROP_COUNT := 24
const STRESS_GRID_STEP := 6.0
const TREE_SCENE_PATH := "res://scenes/tree_3d.tscn"
const STRESS_ROCK_KEYS := ["rock/medium_1", "rock/medium_2", "rock/medium_3"]
const STRESS_PROP_KEYS := ["prop/barrel", "prop/crate_wooden",
	"prop/chest_wood", "prop/farmcrate_empty"]

## -- 샘플링 창 길이(physics tick 기준). --
const CAMERA_WINDOW_TICKS := 420
const WHEEL_PERIOD_TICKS := 15
const NAV_STRESS_PROBES := 8
const NAV_RUN_FRAME_LIMIT := 1800
## 용병 1기가 raider 3마리(60HP, 8dmg/1.0s)를 모두 처리하는 데 필요한 시간은
## 이동/재획득 포함 약 20초 내외다(int0021 예산 1200 tick 참고). 여유 상한.
const COMBAT_SAMPLE_TICKS := 1600
## cycle당 raiders 전멸 조기 종료(측정에는 충분한 구간 확보 목적).
const COMBAT_CYCLE_CLEAR_DEATHS := 3
const COMBAT_CYCLES := 3
const RUNAWAY_WINDOW_TICKS := 600
const POLL_BUDGET_PRODUCTION := 1500

## -- 판정 상한("명백히 불가능" 수준만 걸러내는 넉넉한 값). --
## 프레임당 process+physics 합산 평균 상한(headless CPU 기준).
## 측정 기준(TASK-3D-INT-002-2): Performance.TIME_PROCESS는 지수평활 값이라
## 1회성 이벤트(테스트 소유의 동기 bake/배치 spawn 등)가 수십 tick간
## 잔상으로 남아 창 평균을 오염시킨다(실측: 422ms 값이 33tick 연속 동일).
## 따라서 판정은 physics tick 경계 사이의 실측 wall time으로 한다.
const TICK_WALL_AVG_BUDGET_SEC := 0.030
## 단일 tick wall time 스파이크 허용 한도와 건수(OS 스케줄링/비동기 착지 여유).
const TICK_WALL_SPIKE_LIMIT_SEC := 0.15
const TICK_WALL_SPIKE_ALLOWANCE := 2
## 창 전반/후반 평균 허용 증가율(runaway 추세 판정). 초과 시 FAIL.
const FRAME_TREND_MAX_RATIO := 2.5
const FRAME_TREND_SLACK_SEC := 0.001
## 월드 navmesh 동기 bake 1회 wall time 상한(pathological runaway 감지용).
const NAV_BAKE_MS_LIMIT := 400.0
## 스트레스 배치 96노드 spawn wall time 상한.
const STRESS_BATCH_MS_LIMIT := 3000.0
## 무이벤트 대기 구간 메모리 성장 상한(리소스 churn 여유 포함).
const RUNAWAY_MEMORY_GROWTH_LIMIT := 16 * 1024 * 1024

## Lumberyard 배치지(int0021과 동일 cell: starter tree 3그루가 work_radius 내).
const YARD_SPOT := Vector3(32, 0, 30)
## Quarry는 StoneDeposit(600,300 px logical)에 스냅된다.
const DEPOSIT_SPOT := Vector3(75, 0, 37.5)

## -- 카메라 overview 순환 목적지(월드 4모서리 + 중심, 경계 clamp 검증 겸용). --
const OVERVIEW_TARGETS := [
	Vector3(150, 0, -150), Vector3(-150, 0, -150),
	Vector3(-150, 0, 150), Vector3(150, 0, 150),
	Vector3(0, 0, 0),
]
const OVERVIEW_PAN_STEP := 14.0

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _start_msec := 0
var _poll_start_pf := -1

var _game_time: Node = null
var _resources: Node = null
var _worker_roster: Node = null
var _ledger: Node = null

var _main: Node = null
var _world: Node = null
var _content: Node = null
var _cam_ctl: Node = null
var _camera: Camera3D = null
var _placement: Node = null
var _tavern_ui: Node = null
var _inn_ui: Node = null
var _nav_manager: Node = null
var _spawner_3d: Node = null
var _roster_3d: Node = null
var _stress_root: Node3D = null
var _lumberyard: Node = null
var _quarry: Node = null

var _wood_baseline := 0
var _ledger_baseline := -1
var _nav_count_at_steady := -1
var _bake_ms_baseline := -1.0
var _bake_ms_stressed := -1.0
var _visual_stats_pre_batch := {}
var _visual_stats_post_batch := {}
var _batch_spawn_ms := -1.0

## -- 샘플링 창 공통 상태. --
var _sample_process: Array[float] = []
var _sample_physics: Array[float] = []
var _sample_navcount: Array[int] = []
var _sample_tick_wall_us: Array[int] = []
var _window_ticks := 0
var _last_sampled_pf := -1
var _last_boundary_us := 0

var _nav_probe_events: Array = []
var _nav_probes: Array[WorkerActor3D] = []
var _nav_run_ticks := 0
var _overview_index := 0
var _cycle_index := 0
var _cycle_deaths_start := 0
var _runaway_census := {}
var _runaway_nodes_start := -1
var _runaway_orphans_start := -1
var _runaway_memory_start := -1


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


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _perf_monitor(monitor_name: String) -> float:
	var enum_value: int = Performance.get(monitor_name)
	if enum_value == -1:
		return -1.0
	return Performance.get_monitor(enum_value)


## physics tick 경계에서 정확히 1회 true. 샘플링 창 진행 게이트다.
## 경계 사이 wall time을 함께 적산한다(스무딩 없는 실측 프레임 비용).
func _advance_window_tick() -> bool:
	var pf := Engine.get_physics_frames()
	if pf == _last_sampled_pf:
		return false
	_last_sampled_pf = pf
	var now_us := Time.get_ticks_usec()
	if _last_boundary_us > 0:
		_sample_tick_wall_us.append(now_us - _last_boundary_us)
	_last_boundary_us = now_us
	_window_ticks += 1
	return true


func _arm_window() -> void:
	_sample_process.clear()
	_sample_physics.clear()
	_sample_navcount.clear()
	_sample_tick_wall_us.clear()
	_window_ticks = 0
	_last_sampled_pf = -1
	_last_boundary_us = 0


func _sample_frame() -> void:
	_sample_process.append(_perf_monitor("TIME_PROCESS"))
	_sample_physics.append(_perf_monitor("TIME_PHYSICS_PROCESS"))
	if _nav_manager != null and is_instance_valid(_nav_manager):
		_sample_navcount.append(_nav_manager.nav_rebuild_count)
	else:
		_sample_navcount.append(-1)


func _window_avg(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for v in samples:
		total += v
	return total / samples.size()


func _window_max(samples: Array[float]) -> float:
	var best := 0.0
	for v in samples:
		best = maxf(best, v)
	return best


func _tick_wall_avg() -> float:
	if _sample_tick_wall_us.is_empty():
		return 0.0
	var total := 0
	for v in _sample_tick_wall_us:
		total += v
	return float(total) / _sample_tick_wall_us.size() / 1000000.0


func _tick_wall_spikes() -> int:
	var count := 0
	for v in _sample_tick_wall_us:
		if v > int(TICK_WALL_SPIKE_LIMIT_SEC * 1000000.0):
			count += 1
	return count


func _print_window(tag: String) -> void:
	print("PERF %s ticks=%d tick_wall_avg_ms=%.3f tick_wall_spikes_gt_%dms=%d process_avg_ms=%.3f physics_avg_ms=%.3f"
		% [tag, _window_ticks,
		_tick_wall_avg() * 1000.0,
		int(TICK_WALL_SPIKE_LIMIT_SEC * 1000.0), _tick_wall_spikes(),
		_window_avg(_sample_process) * 1000.0,
		_window_avg(_sample_physics) * 1000.0])
	# 병목 규명용: 스파이크 tick의 위치와 nav rebake 카운터 상관을 기록한다.
	for i in _sample_tick_wall_us.size():
		var wall_sec: float = float(_sample_tick_wall_us[i]) / 1000000.0
		if wall_sec > TICK_WALL_SPIKE_LIMIT_SEC:
			var prev := _sample_navcount[i] if i < _sample_navcount.size() \
				else -1
			print("PERF %s spike tick=%d wall_ms=%.1f nav_count=%d"
				% [tag, i, wall_sec * 1000.0, prev])


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DINT0022_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.INSTANCE_WAIT:
			_instance_wait()
		Phase.SCALE_AUDIT:
			_scale_audit()
		Phase.BUILD_LUMBERYARD:
			_build_lumberyard()
		Phase.BUILD_QUARRY:
			_build_quarry()
		Phase.HIRE_ASSIGN_WORKERS:
			_hire_assign_workers()
		Phase.PRODUCTION_WAIT:
			_production_wait()
		Phase.PRODUCTION_CHECK:
			_production_check()
		Phase.STRESS_BATCH_SPAWN:
			_stress_batch_spawn()
		Phase.STRESS_BATCH_BAKE:
			_stress_batch_bake()
		Phase.DUPLICATION_AUDIT:
			_duplication_audit()
		Phase.CAMERA_ARM:
			_camera_arm()
		Phase.CAMERA_RUN:
			_camera_run()
		Phase.CAMERA_CHECK:
			_camera_check()
		Phase.NAV_PROBE_SPAWN:
			_nav_probe_spawn()
		Phase.NAV_RUN_SETTLE:
			_nav_run_settle()
		Phase.NAV_RUN:
			_nav_run()
		Phase.NAV_RESTORE:
			_nav_restore()
		Phase.HIRE_MERCENARY:
			_hire_mercenary()
		Phase.CYCLE_NIGHT_ENTER:
			_cycle_night_enter()
		Phase.CYCLE_FOCUS:
			_cycle_focus()
		Phase.CYCLE_SAMPLE:
			_cycle_sample()
		Phase.CYCLE_TO_DAY:
			_cycle_to_day()
		Phase.CYCLE_DAY_WAIT:
			_cycle_day_wait()
		Phase.CYCLE_DAY_CHECK:
			_cycle_day_check()
		Phase.RUNAWAY_START:
			_runaway_start()
		Phase.RUNAWAY_END:
			_runaway_end()
		Phase.FINAL_AUDIT:
			_final_audit()
		Phase.CLEANUP:
			_cleanup()
		Phase.DONE:
			_finish()
			return true
	if Time.get_ticks_msec() - _start_msec > 480000:
		print("TASK3DINT0022_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	_ledger = root.get_node_or_null("DeathLedger")
	_check(_game_time != null and _resources != null \
			and _worker_roster != null and _ledger != null,
		"shared autoloads are available to the performance runtime")
	if _game_time == null or _resources == null:
		_enter(Phase.DONE)
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(SHORT_DAY_DURATION, SHORT_NIGHT_DURATION)
	# headless 기본 window(64x64)는 GUI hit-test/unproject를 왜곡하므로 프로젝트 해상도로
	# 올린다(INT-001-2 입력 경로 규약 동일).
	root.size = Vector2i(1152, 648)
	# process loop spin 상한(측정 창을 physics tick 기준으로 유지하기 위한 것일 뿐,
	# 측정값 자체에는 영향 없음).
	Engine.max_fps = 240
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
	_cam_ctl = get_first_node_in_group("camera_controller_3d")
	_camera = _cam_ctl.get_camera() if _cam_ctl != null else null
	_placement = get_first_node_in_group("building_placement_3d")
	_tavern_ui = get_first_node_in_group("recruitment_ui")
	_inn_ui = get_first_node_in_group("inn_roster_ui")
	_nav_manager = _world.get_node_or_null("NavigationManager3D")
	_spawner_3d = _main.get_node_or_null("FirstEncounterSpawner3D")
	_roster_3d = _main.get_node_or_null("MercenaryRoster3D")
	_check(_cam_ctl != null and _placement != null and _tavern_ui != null \
			and _inn_ui != null and _nav_manager != null and _spawner_3d != null \
			and _roster_3d != null,
		"camera/placement/UI/navigation/spawner services are all wired")
	_ledger_baseline = _ledger.get_all_records().size()
	_enter(Phase.SCALE_AUDIT)


## -- 검증 1(전반): 현재 실제 Resource/Building 규모 --
func _scale_audit() -> void:
	_check(_content != null and _content.get_tree_count() == 60,
		"baseline composed world holds exactly 60 gameplay trees")
	_check(_group_count("core_buildings_3d") == 5
			and _group_count("stone_deposits_3d") == 1,
		"baseline scale is 5 core buildings + 1 stone deposit")
	_bake_ms_baseline = _measure_rebuild_ms()
	_check(_bake_ms_baseline >= 0.0
			and _bake_ms_baseline < NAV_BAKE_MS_LIMIT,
		"baseline synchronous nav bake stays under the pathological limit (%.1fms)"
			% _bake_ms_baseline)
	print("PERF baseline.nav_bake_ms=%.1f" % _bake_ms_baseline)
	var split := _measure_parse_bake_split_ms()
	print("PERF baseline.parse_split_ms=%.1f bake_only_ms=%.1f"
		% [split["parse_ms"], split["bake_ms"]])
	print("PERF baseline.nodes=%d resources=%d memory_kb=%d"
		% [int(_perf_monitor("OBJECT_NODE_COUNT")),
		int(_perf_monitor("OBJECT_RESOURCE_COUNT")),
		int(_perf_monitor("MEMORY_STATIC")) / 1024])
	_visual_stats_pre_batch = _collect_visual_stats(_world)
	_enter(Phase.BUILD_LUMBERYARD)


## 동기 rebuild_navigation 1회 wall time(ms). 카운터도 함께 증가시킨다.
func _measure_rebuild_ms() -> float:
	if _nav_manager == null or not is_instance_valid(_nav_manager):
		return -1.0
	var t0 := Time.get_ticks_usec()
	_nav_manager.rebuild_navigation()
	return float(Time.get_ticks_usec() - t0) / 1000.0


## 병목 위치 규명용 분해 측정: parse(정적 collider 수집) vs bake(raster) 비용.
## policy 상수를 읽기 전용 소비한다(manager와 동일 설정).
func _measure_parse_bake_split_ms() -> Dictionary:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = NavigationPolicy3D.BAKE_MASK
	nav_mesh.agent_radius = NavigationPolicy3D.ACTOR_RADIUS_UNITS
	nav_mesh.agent_height = NavigationPolicy3D.ACTOR_HEIGHT_UNITS
	nav_mesh.cell_size = NavigationPolicy3D.NAV_CELL_SIZE_UNITS
	nav_mesh.cell_height = NavigationPolicy3D.NAV_CELL_HEIGHT_UNITS
	var source := NavigationMeshSourceGeometryData3D.new()
	var t0 := Time.get_ticks_usec()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, _world)
	var parse_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	var bake_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	return {"parse_ms": parse_ms, "bake_ms": bake_ms}


## -- vertical slice 구성(int0021 입력 경로 축소 재생): 건설 2종 + Worker 4명 --
func _build_lumberyard() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_resources.add("wood", 60)
	_pan_for(YARD_SPOT)
	_push_key(KEY_1)
	_push_key(KEY_B)
	_push_left_click(_screen_pos_of(YARD_SPOT))
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
	_pan_for(DEPOSIT_SPOT)
	_push_key(KEY_2)
	_push_key(KEY_B)
	_push_left_click(_screen_pos_of(DEPOSIT_SPOT))
	var quarries := get_nodes_in_group("quarries")
	_check(quarries.size() == 1, "Quarry placed onto the Stone Deposit snap")
	if quarries.size() == 1:
		_quarry = quarries[0]
	_wait = 0
	_enter(Phase.HIRE_ASSIGN_WORKERS)


func _hire_assign_workers() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_tavern_ui.open()
	for id in ["lumberjack_A", "lumberjack_B", "miner_A", "miner_B"]:
		_tavern_ui._hire_buttons[id].pressed.emit()
	_tavern_ui.close()
	_inn_ui.open()
	for id in ["lumberjack_A", "lumberjack_B", "miner_A", "miner_B"]:
		_inn_ui._assign_buttons[id].pressed.emit()
	_inn_ui.close()
	_check(_worker_roster.get_assigned_count() == 4,
		"vertical slice staffs both workplaces with 4 residents")
	_check(_group_count("workers_3d") == 4,
		"assignment spawns exactly 4 Worker Actors (current worker scale)")
	_wood_baseline = _resources.get_amount("wood")
	_wait = 0
	_enter(Phase.PRODUCTION_WAIT)


func _production_wait() -> void:
	# 두 직업군 모두 첫 반납을 마친 안정 상태에서 측정을 시작한다(석재만 보면
	# 벌목 첫 반납 전에 통과할 수 있다 - 각 반납 주기가 달라서 생긴 경합).
	var steady: bool = _resources.get_amount("stone") >= 6 \
		and _resources.get_amount("wood") > _wood_baseline
	if steady or _poll_budget_exhausted(POLL_BUDGET_PRODUCTION):
		_enter(Phase.PRODUCTION_CHECK)


func _production_check() -> void:
	if not is_instance_valid(_lumberyard) or not is_instance_valid(_quarry):
		_check(false, "workplaces exist for the production steady state")
		_enter(Phase.STRESS_BATCH_SPAWN)
		return
	_check(_resources.get_amount("stone") >= 6,
		"workers reach the steady production loop before measurements")
	_check(_resources.get_amount("wood") > _wood_baseline,
		"lumberjacks deposit Wood during the steady production loop")
	_nav_count_at_steady = _nav_manager.nav_rebuild_count
	_enter(Phase.STRESS_BATCH_SPAWN)


## -- 검증 2: Tree/Rock/Prop 다수 배치(결정적 그리드, 배치 비용 1회 측정) --
func _stress_positions(origin_x: float, origin_z: float, cols: int, rows: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for row in rows:
		for col in cols:
			out.append(Vector3(origin_x + col * STRESS_GRID_STEP, 0.0,
				origin_z + row * STRESS_GRID_STEP))
	return out


func _spawn_stress_trees() -> void:
	# 북동 외곽 블록: 생산 동선/방어 구역/main path와 무관한 빈 땅이다.
	var spots := _stress_positions(90.0, -150.0, 8, 6)
	var tree_scene: PackedScene = load(TREE_SCENE_PATH)
	var spawned := 0
	for i in mini(STRESS_TREE_COUNT, spots.size()):
		var tree := tree_scene.instantiate() as WorldTree3D
		tree.position = WorldCoords3D.flatten(spots[i])
		_stress_root.add_child(tree)
		spawned += 1
	_check(spawned == STRESS_TREE_COUNT,
		"%d stress trees placed on a deterministic grid" % spawned)


func _spawn_stress_models(keys: Array, origin_x: float, origin_z: float,
		cols: int, rows: int, kind: String) -> void:
	var spots := _stress_positions(origin_x, origin_z, cols, rows)
	var spawned := 0
	for i in rows * cols:
		var key: String = keys[i % keys.size()]
		var model := VisualAssetCatalog3D.instantiate_model(key)
		if model == null:
			continue
		model.position = WorldCoords3D.flatten(spots[i])
		model.rotation.y = deg_to_rad(float((i * 37) % 360))
		model.set_meta("catalog_key", key)
		model.set_meta("kind", kind)
		_stress_root.add_child(model)
		spawned += 1
	_check(spawned == rows * cols,
		"%d stress %s models placed from the shared catalog" % [spawned, kind])


func _stress_batch_spawn() -> void:
	_stress_root = Node3D.new()
	_stress_root.name = "Int0022StressBatch"
	_world.add_child(_stress_root)
	var t0 := Time.get_ticks_usec()
	_spawn_stress_trees()
	_spawn_stress_models(STRESS_ROCK_KEYS, -150.0, 90.0, 4, 6, "rock")
	_spawn_stress_models(STRESS_PROP_KEYS, 90.0, 90.0, 4, 6, "prop")
	_batch_spawn_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_check(_group_count("resource_nodes_3d") == 60 + STRESS_TREE_COUNT,
		"stress batch registers exactly %d gameplay resource nodes"
			% (60 + STRESS_TREE_COUNT))
	_check(_batch_spawn_ms >= 0.0 and _batch_spawn_ms < STRESS_BATCH_MS_LIMIT,
		"one-shot batch spawn of %d nodes stays bounded (%.1fms)"
			% [STRESS_TREE_COUNT + STRESS_ROCK_COUNT + STRESS_PROP_COUNT,
			_batch_spawn_ms])
	print("PERF stress.batch_spawn_ms=%.1f instances=%d"
		% [_batch_spawn_ms, STRESS_TREE_COUNT + STRESS_ROCK_COUNT + STRESS_PROP_COUNT])
	print("PERF scale.after_batch trees=%d rocks_props=%d"
		% [60 + STRESS_TREE_COUNT, STRESS_ROCK_COUNT + STRESS_PROP_COUNT])
	_enter(Phase.STRESS_BATCH_BAKE)


## 새 trunk 장애물이 nav에 반영되어야 이후 측정이 유효하다(테스트 소유 rebake).
func _stress_batch_bake() -> void:
	if _wait == 0:
		_bake_ms_stressed = _measure_rebuild_ms()
		_check(_bake_ms_stressed >= 0.0
				and _bake_ms_stressed < NAV_BAKE_MS_LIMIT,
			"stressed-world nav bake stays under the pathological limit (%.1fms)"
				% _bake_ms_stressed)
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	print("PERF stressed.nav_bake_ms=%.1f" % _bake_ms_stressed)
	_enter(Phase.DUPLICATION_AUDIT)


## -- 검증 8: material/mesh duplication 감사 --
func _collect_visual_stats(from_node: Node) -> Dictionary:
	var stack: Array = [from_node]
	var instances := 0
	var surface_slots := 0
	var mesh_rids := {}
	var material_rids := {}
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			instances += 1
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				mesh_rids[mi.mesh.get_rid()] = true
				for s in mi.mesh.get_surface_count():
					surface_slots += 1
					var mat := mi.mesh.surface_get_material(s)
					if mat != null:
						material_rids[mat.get_rid()] = true
			for s2 in mi.get_surface_override_material_count():
				var override_mat := mi.get_surface_override_material(s2)
				if override_mat != null:
					surface_slots += 1
					material_rids[override_mat.get_rid()] = true
	return {
		"instances": instances,
		"surface_slots": surface_slots,
		"unique_meshes": mesh_rids.size(),
		"unique_materials": material_rids.size(),
	}


func _duplication_audit() -> void:
	_visual_stats_post_batch = _collect_visual_stats(_world)
	var pre: Dictionary = _visual_stats_pre_batch
	var post: Dictionary = _visual_stats_post_batch
	print("PERF dup.pre instances=%d slots=%d unique_mesh=%d unique_mat=%d"
		% [pre["instances"], pre["surface_slots"],
		pre["unique_meshes"], pre["unique_materials"]])
	print("PERF dup.post instances=%d slots=%d unique_mesh=%d unique_mat=%d"
		% [post["instances"], post["surface_slots"],
		post["unique_meshes"], post["unique_materials"]])
	var added_instances: int = post["instances"] - pre["instances"]
	var added_unique_meshes: int = post["unique_meshes"] - pre["unique_meshes"]
	print("PERF dup.batch_delta instances=%d unique_mesh=%d"
		% [added_instances, added_unique_meshes])
	_check(added_instances >= STRESS_TREE_COUNT + STRESS_ROCK_COUNT
				+ STRESS_PROP_COUNT,
		"stress batch adds the intended mesh population: +%d MeshInstance3D for %d placed models"
			% [added_instances,
			STRESS_TREE_COUNT + STRESS_ROCK_COUNT + STRESS_PROP_COUNT])
	_check(int(post["unique_meshes"]) * 2 < int(post["instances"]),
		"mesh resources are shared across instances (unique %d << instances %d)"
			% [post["unique_meshes"], post["instances"]])
	_check(added_unique_meshes * 2 <= added_instances,
		"repeated placement reuses catalog meshes instead of duplicating "
			+ "(+%d unique meshes for +%d instances)"
			% [added_unique_meshes, added_instances])
	_check(int(post["unique_materials"]) * 4 <= int(post["surface_slots"]),
		"materials are shared across surfaces instead of per-instance copies "
			+ "(%d unique materials / %d slots)"
			% [post["unique_materials"], post["surface_slots"]])
	_enter(Phase.CAMERA_ARM)


## 공통 창 판정: 평균 wall 비용 / 스파이크 건수 / 전반-후반 추세(runaway).
func _check_window_budgets(tag: String) -> void:
	var avg_wall := _tick_wall_avg()
	_check(avg_wall < TICK_WALL_AVG_BUDGET_SEC,
		"%s keeps average tick wall cost under budget (%.4fs)"
			% [tag, avg_wall])
	_check(_tick_wall_spikes() <= TICK_WALL_SPIKE_ALLOWANCE,
		"%s keeps heavy ticks within the allowance (%d ticks over %.0fms)"
			% [tag, _tick_wall_spikes(), TICK_WALL_SPIKE_LIMIT_SEC * 1000.0])
	var half := _sample_tick_wall_us.size() / 2
	var early_total := 0
	var late_total := 0
	for i in _sample_tick_wall_us.size():
		if i < half:
			early_total += _sample_tick_wall_us[i]
		else:
			late_total += _sample_tick_wall_us[i]
	var early := float(early_total) / maxf(1.0, float(half)) / 1000000.0
	var late := float(late_total) \
		/ maxf(1.0, float(_sample_tick_wall_us.size() - half)) / 1000000.0
	_check(late <= early * FRAME_TREND_MAX_RATIO + FRAME_TREND_SLACK_SEC,
		"%s shows no runaway cost trend (early %.4fs -> late %.4fs)"
			% [tag, early, late])


## -- 검증 3/4: Camera full overview + zoom in/out 반복(프레임 비용 샘플링) --
func _camera_arm() -> void:
	_overview_index = 0
	_arm_window()
	_cam_ctl.pan_camera(WorldCoords3D.flatten(OVERVIEW_TARGETS[0]) \
		- _cam_ctl.position)
	_enter(Phase.CAMERA_RUN)


func _camera_run() -> void:
	if not _advance_window_tick():
		return
	_sample_frame()
	var target: Vector3 = OVERVIEW_TARGETS[_overview_index]
	var camera_pivot: Vector3 = _cam_ctl.position
	var offset: Vector3 = WorldCoords3D.flatten(target) - camera_pivot
	offset.y = 0.0
	if offset.length() <= OVERVIEW_PAN_STEP:
		_overview_index = (_overview_index + 1) % OVERVIEW_TARGETS.size()
	else:
		_cam_ctl.pan_camera(offset.normalized() * OVERVIEW_PAN_STEP)
	if _window_ticks % WHEEL_PERIOD_TICKS == 0:
		var zoom_up := (_window_ticks / WHEEL_PERIOD_TICKS) % 2 == 0
		_push_wheel(MOUSE_BUTTON_WHEEL_UP if zoom_up else MOUSE_BUTTON_WHEEL_DOWN)
	if _window_ticks >= CAMERA_WINDOW_TICKS:
		_enter(Phase.CAMERA_CHECK)


func _camera_check() -> void:
	_print_window("camera_overview_zoom")
	_check_window_budgets("camera_overview_zoom")
	_check(_cam_ctl.get_zoom_target() >= _cam_ctl.min_zoom
			and _cam_ctl.get_zoom_target() <= _cam_ctl.max_zoom,
		"repeated wheel zoom stays clamped inside the configured range")
	_check(absf(_cam_ctl.position.x) <= WorldCoords3D.WORLD_HALF_UNITS \
			and absf(_cam_ctl.position.z) <= WorldCoords3D.WORLD_HALF_UNITS,
		"full overview pan respects the shared world bounds")
	_enter(Phase.NAV_PROBE_SPAWN)


## -- 검증 5: Worker navigation 스트레스(probe 8기 동시 장거리 이동) --
func _on_probe_move_finished(status: int, final_position: Vector3,
		index: int, sink: Array) -> void:
	sink.append([index, status, final_position])


func _nav_probe_spawn() -> void:
	for i in NAV_STRESS_PROBES:
		var angle := TAU * float(i) / float(NAV_STRESS_PROBES)
		var start := Vector3(cos(angle), 0.0, sin(angle)) * 80.0
		var probe := WorkerActor3D.new()
		probe.name = "Int0022NavProbe%d" % i
		_world.add_child(probe)
		probe.global_position = Vector3(start.x, WorldCoords3D.GROUND_Y, start.z)
		probe.move_finished.connect(
			_on_probe_move_finished.bind(i, _nav_probe_events), CONNECT_ONE_SHOT)
		_nav_probes.append(probe)
		# 마을 core를 관통하는 대각 목적지: 우회 경로 부하가 의도된 스트레스다.
		probe.begin_move_to(Vector3(-start.x, 0.0, -start.z))
	_arm_window()
	_nav_run_ticks = 0
	_enter(Phase.NAV_RUN_SETTLE)


## add_child 직후 첫 path 질의 map sync 규약(001-5)에 맞춰 1 tick 양보한다.
func _nav_run_settle() -> void:
	if not _advance_window_tick():
		return
	_enter(Phase.NAV_RUN)


func _nav_run() -> void:
	if not _advance_window_tick():
		return
	_nav_run_ticks += 1
	_sample_frame()
	if _nav_probe_events.size() < NAV_STRESS_PROBES:
		if _nav_run_ticks > NAV_RUN_FRAME_LIMIT:
			_check(false, "all navigation probes finish within the frame limit "
				+ "(no permanent stall)")
			_enter(Phase.NAV_RESTORE)
		return
	var arrived := 0
	var bounded := 0
	for event in _nav_probe_events:
		if event[1] == WorkerActor3D.MoveStatus.ARRIVED:
			arrived += 1
		else:
			bounded += 1
	_check(arrived + bounded == NAV_STRESS_PROBES
			and arrived >= NAV_STRESS_PROBES - 2,
		"concurrent long-distance navigation mostly arrives with bounded endings "
			+ "(arrived %d / bounded %d)" % [arrived, bounded])
	_print_window("nav_stress")
	_check_window_budgets("nav_stress")
	_enter(Phase.NAV_RESTORE)


func _nav_restore() -> void:
	if _wait == 0:
		for probe in _nav_probes:
			if is_instance_valid(probe):
				probe.free()
		_nav_probes.clear()
		_nav_probe_events.clear()
		_nav_manager.rebuild_navigation()
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_enter(Phase.HIRE_MERCENARY)


## -- 검증 6/7: NIGHT combat + DAY/NIGHT 반복 --
func _hire_mercenary() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_tavern_ui.open()
	_tavern_ui._mercenary_hire_buttons["mercenary_A"].pressed.emit()
	_tavern_ui.close()
	var defense_zone_west: int = (load(MERC_DATA_SCRIPT_PATH) as Script).DefenseZone.WEST
	_inn_ui.open()
	var merc = _roster_3d.get_mercenary("mercenary_A")
	_inn_ui._on_defense_zone_pressed(merc, defense_zone_west)
	_inn_ui.close()
	_check(merc.defense_zone == defense_zone_west,
		"zone-assigned mercenary deploys during the combat cycles")
	_cycle_index = 0
	_enter(Phase.CYCLE_NIGHT_ENTER)


## 현재 phase 경계까지 정확히 진행한다(int0021 규약: advance carry 보정 포함).
func _advance_to_next_phase() -> void:
	var need: float = _game_time.get_phase_duration() \
		- _game_time.get_phase_elapsed()
	_game_time.advance(need + 0.05)


func _cycle_night_enter() -> void:
	if _wait < SETTLE_FRAMES:
		_wait += 1
		return
	_advance_to_next_phase()
	_enter(Phase.CYCLE_FOCUS)


func _cycle_focus() -> void:
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	_check(_game_time.get_phase_name() == "NIGHT",
		"combat cycle %d reaches NIGHT" % (_cycle_index + 1))
	_check(get_nodes_in_group("enemies_3d").size() == 3,
		"combat cycle %d spawns the encounter exactly once" % (_cycle_index + 1))
	# focus 명령으로 교전 개시를 보장한다(자동 접근 대기 제거).
	var enemies := get_nodes_in_group("enemies_3d")
	if not enemies.is_empty() and not get_nodes_in_group("mercenaries_3d").is_empty():
		var best: Node = null
		var best_dist := INF
		for enemy in enemies:
			var d: float = WorldCoords3D.distance_xz(enemy.global_position,
				Vector3(-38.125, 0, 0))
			if d < best_dist:
				best_dist = d
				best = enemy
		_roster_3d.set_focus_target(best)
	_cycle_deaths_start = _ledger.get_all_records().size()
	_arm_window()
	_enter(Phase.CYCLE_SAMPLE)


func _cycle_sample() -> void:
	if not _advance_window_tick():
		return
	_sample_frame()
	var cycle_deaths: int = _ledger.get_all_records().size() - _cycle_deaths_start
	if _window_ticks >= COMBAT_SAMPLE_TICKS \
			or cycle_deaths >= COMBAT_CYCLE_CLEAR_DEATHS:
		_enter(Phase.CYCLE_TO_DAY)


func _cycle_to_day() -> void:
	var tag := "night_combat_cycle_%d" % (_cycle_index + 1)
	_print_window(tag)
	_check_window_budgets(tag)
	# source_uid 유일성은 "같은 encounter 내 서로 다른 개체" 계약이라
	# cycle 신규 기록 범위에서만 판정한다(encounter 간 id 재사용은 기존 계약).
	var new_uids := {}
	var cycle_unique := true
	for i in range(_cycle_deaths_start, _ledger.get_all_records().size()):
		var uid: Variant = _ledger.get_all_records()[i].source_uid
		if new_uids.has(uid):
			cycle_unique = false
		new_uids[uid] = true
	_check(cycle_unique,
		"combat cycle %d death records hold no duplicate uids" % (_cycle_index + 1))
	_advance_to_next_phase()
	_enter(Phase.CYCLE_DAY_WAIT)


func _cycle_day_wait() -> void:
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	_enter(Phase.CYCLE_DAY_CHECK)


func _cycle_day_check() -> void:
	var deaths: int = _ledger.get_all_records().size() - _cycle_deaths_start
	print("PERF combat.cycle_%d lethal_deaths=%d" % [_cycle_index + 1, deaths])
	_check(_game_time.get_phase_name() == "DAY",
		"combat cycle %d returns to DAY" % (_cycle_index + 1))
	_check(_group_count("enemies_3d") == 0,
		"combat cycle %d cleanup despawns every enemy" % (_cycle_index + 1))
	var orphans := 0
	for child in _world.get_children():
		if child is EnemyActor3D or child is MercenaryActor3D:
			orphans += 1
	_check(orphans == 0,
		"combat cycle %d leaves no orphan combat actor under the world"
			% (_cycle_index + 1))
	_cycle_index += 1
	if _cycle_index >= COMBAT_CYCLES:
		_enter(Phase.RUNAWAY_START)
	else:
		_enter(Phase.CYCLE_NIGHT_ENTER)


## -- 검증 9: per-frame allocation / scene spawn loop 감사(무이벤트 대기 구간) --
func _census() -> Dictionary:
	var groups := ["workers_3d", "lumberjacks_3d", "miners_3d",
		"resource_nodes_3d", "core_buildings_3d", "lumberyards_3d",
		"quarries", "walls_3d", "gates_3d", "enemies_3d", "mercenaries_3d",
		"stone_deposits_3d"]
	var out := {}
	for group in groups:
		out[group] = _group_count(group)
	return out


func _runaway_start() -> void:
	_runaway_census = _census()
	_runaway_nodes_start = int(_perf_monitor("OBJECT_NODE_COUNT"))
	_runaway_orphans_start = int(_perf_monitor("OBJECT_ORPHAN_NODE_COUNT"))
	_runaway_memory_start = int(_perf_monitor("MEMORY_STATIC"))
	_wait = 0
	_enter(Phase.RUNAWAY_END)


func _runaway_end() -> void:
	_wait += 1
	if _wait < RUNAWAY_WINDOW_TICKS:
		return
	var census_end := _census()
	var nodes_end := int(_perf_monitor("OBJECT_NODE_COUNT"))
	var orphans_end := int(_perf_monitor("OBJECT_ORPHAN_NODE_COUNT"))
	var memory_end := int(_perf_monitor("MEMORY_STATIC"))
	print("PERF runaway.node_delta=%d orphan_start=%d orphan_end=%d memory_growth_kb=%d"
		% [nodes_end - _runaway_nodes_start, _runaway_orphans_start, orphans_end,
		(memory_end - _runaway_memory_start) / 1024])
	_check(census_end == _runaway_census,
		"group census is identical across the idle window (no scene spawn loop)")
	_check(nodes_end == _runaway_nodes_start,
		"live node count is stable while idle (delta %d)"
			% (nodes_end - _runaway_nodes_start))
	_check(orphans_end <= _runaway_orphans_start + 4 and orphans_end < 50,
		"orphan node count stays flat and small (%d -> %d)"
			% [_runaway_orphans_start, orphans_end])
	_check(memory_end - _runaway_memory_start < RUNAWAY_MEMORY_GROWTH_LIMIT,
		"static memory growth over the idle window stays bounded (%dKB)"
			% ((memory_end - _runaway_memory_start) / 1024))
	_enter(Phase.FINAL_AUDIT)


func _final_audit() -> void:
	var total_deaths: int = _ledger.get_all_records().size() - _ledger_baseline
	print("PERF summary.lethal_records=%d nav_rebuilds_total=%d steady_to_final_delta=%d"
		% [total_deaths, _nav_manager.nav_rebuild_count,
		_nav_manager.nav_rebuild_count - _nav_count_at_steady])
	_check(total_deaths >= 1,
		"NIGHT combat produced lethal deaths under repeated cycles (%d)" % total_deaths)
	_check(_nav_manager.is_inside_tree(),
		"navigation manager survived the whole stress run")
	_enter(Phase.CLEANUP)


func _cleanup() -> void:
	if _stress_root != null and is_instance_valid(_stress_root):
		_stress_root.free()
	_main.queue_free()
	_enter(Phase.DONE)


## -- 입력/좌표 헬퍼(int0021 push_input 규약 동일) --

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
