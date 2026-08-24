extends SceneTree

## TASK-EXP-001-2 Minimal Exploration Action 검증.
## - ExplorationManager autoload와 NE Dungeon prototype region 등록.
## - UNKNOWN -> EXPLORING -> DISCOVERED 전환.
## - repeated start duplicate 차단(manager 가드 + UI 버튼 disabled).
## - GameTime 기반 progress. DAY/NIGHT 전환과 무관하게 동일 정책으로 누적.
## - 발견 결과는 고정 deterministic feature.
## - WorldMapOverlay region 선택/Explore 시작/발견 후 패널 갱신.
##   - region 선택은 실제 입력 경로(root.push_input -> Control._gui_input)로 검증.
##     headless 기본 window가 64x64라 레이아웃이 붕괴되므로 프로젝트 해상도로 강제한다.
## - 기존 월드 회귀(floor/core buildings/no player).

const REGION_ID := "ne_dungeon"
const DURATION := 45.0

var _frame := 0
var _failed := false

var _main: Node = null
var _overlay_ctrl: Node = null
var _manager: Node = null
var _game_time: Node = null
var _explore_button: Button = null

var _started_count := 0
var _discovered_count := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 1000:
		print("TASKEXP0012_RESULT=TIMEOUT")
		quit()
		return true
	if _frame == 20:
		# headless 기본 window(64x64)는 overlay 레이아웃을 붕괴시키므로
		# 프로젝트 해상도로 강제한다. 컨테이너 재배치 후(frame 26) UI 검증.
		root.size = Vector2i(1152, 648)
		_run_setup()
		return false
	if _frame != 26:
		return false
	_run_ui_and_progress()
	return true


func _run_setup() -> void:
	_main = root.get_node("Main")
	_check(_main != null, "main.tscn loads")

	_manager = root.get_node_or_null("ExplorationManager")
	_check(_manager != null, "ExplorationManager autoload registered")

	_game_time = root.get_node("GameTime")
	_manager.exploration_started.connect(func(_id): _started_count += 1)
	_manager.region_discovered.connect(func(_id): _discovered_count += 1)
	# 자동 진행을 끄고 advance()로 결정적으로 제어한다(GameTime 패턴 재사용).
	_manager.set_auto_advance(false)
	_game_time.set_auto_advance(false)

	var region: ExplorationRegion = _manager.get_region(REGION_ID)
	_check(region != null, "prototype region '%s' registered" % REGION_ID)
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.UNKNOWN \
		and region.get_discovery_state_name() == "UNKNOWN", \
		"region starts UNKNOWN")
	_check(region.display_name == "NE Dungeon", "display_name set")
	_check(region.source_marker_id == "NeDungeonCandidate", \
		"linked to existing WorldMap marker id")
	_check(region.world_position == WorldMap.NE_DUNGEON_CANDIDATE, \
		"world_position matches NE Dungeon Candidate")
	_check(region.exploration_duration == DURATION and region.base_risk == 3, \
		"duration/risk configured (%ds)" % int(DURATION))
	_check(_manager.get_region_at(region.world_position) == region \
		and _manager.get_region_at(Vector2.ZERO) == null, \
		"get_region_at hit-test works")
	_check(_approx(_manager.get_progress(REGION_ID), 0.0), "initial progress 0")
	_check(_manager.can_start_exploration(REGION_ID), "can_start_exploration true")

	_overlay_ctrl = _main.get_node("WorldMapOverlay").get_node("Control")
	_explore_button = _overlay_ctrl.get_node("%ExploreButton")


func _run_ui_and_progress() -> void:
	var region: ExplorationRegion = _manager.get_region(REGION_ID)

	# --- UI: Map open + region 선택 ---
	_overlay_ctrl.open()
	_check(_overlay_ctrl.is_open(), "map overlay opens")
	_check(_overlay_ctrl.get_selected_region_id() == "" \
		and _explore_button.disabled, "no selection: Explore disabled")

	# 실제 입력 경로 검증: Backdrop(IGNORE)을 통과한 클릭이 루트 Control._gui_input에
	# 도달해 region을 선택해야 한다(push_input으로 실제 GUI 라우팅을 통과시킨다).
	var click_ev := InputEventMouseButton.new()
	click_ev.button_index = MOUSE_BUTTON_LEFT
	click_ev.pressed = true
	click_ev.position = _overlay_ctrl.world_to_map(region.world_position)
	click_ev.global_position = click_ev.position
	root.push_input(click_ev)
	_check(_overlay_ctrl.get_selected_region_id() == REGION_ID, \
		"real mouse input selects region (Backdrop IGNORE click-through)")

	_overlay_ctrl.select_region("")
	_overlay_ctrl._handle_map_click(
		_overlay_ctrl.world_to_map(region.world_position))
	_check(_overlay_ctrl.get_selected_region_id() == REGION_ID, \
		"click on region marker selects region")
	_check(not _explore_button.disabled and _overlay_ctrl.get_node("%RegionTitleLabel").text \
		== "NE Dungeon", "selected region shows Explore enabled")
	_check("UNKNOWN" in String(_overlay_ctrl.get_node("%RegionStatusLabel").text), \
		"status label shows UNKNOWN")
	_overlay_ctrl._handle_map_click(_overlay_ctrl.world_to_map(Vector2.ZERO))
	_check(_overlay_ctrl.get_selected_region_id() == "", \
		"click outside region clears selection")
	_overlay_ctrl.select_region(REGION_ID)

	# --- UI: Explore 버튼으로 시작, 중복 시작 차단 ---
	_explore_button.pressed.emit()
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.EXPLORING, \
		"UI Explore starts exploration (EXPLORING)")
	_check(_started_count == 1, "exploration_started emitted exactly once")
	_explore_button.pressed.emit()
	_check(_started_count == 1 \
		and region.get_discovery_state() == ExplorationRegion.DiscoveryState.EXPLORING, \
		"repeated UI press does not duplicate start")
	_check(_manager.start_exploration(REGION_ID) == false, \
		"manager rejects duplicate start while EXPLORING")
	_check(_explore_button.disabled \
		and String(_explore_button.text) == "Exploring...", \
		"button disabled while EXPLORING")
	_overlay_ctrl.close()

	# --- Progress: GameTime 기준 누적 ---
	_manager.advance(0.0)
	_manager.advance(-5.0)
	_check(_approx(_manager.get_progress(REGION_ID), 0.0), \
		"non-positive advance ignored")
	_manager.advance(9.0)
	_check(_approx(_manager.get_progress(REGION_ID), 9.0 / DURATION), \
		"progress accumulates 9s/45s")
	_manager.advance(4.5)
	_check(_approx(_manager.get_progress(REGION_ID), 13.5 / DURATION), \
		"progress monotonic accumulation")

	# --- DAY/NIGHT 전환에서도 progress 정책 일관 ---
	_game_time.set_durations(2.0, 2.0)
	_game_time.advance(3.0)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "DAY->NIGHT crossed")
	_check(_approx(_manager.get_progress(REGION_ID), 13.5 / DURATION), \
		"phase transition does not alter progress")
	_manager.advance(4.5)
	_check(_approx(_manager.get_progress(REGION_ID), 18.0 / DURATION), \
		"progress advances during NIGHT (same policy)")
	_game_time.advance(2.0)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "NIGHT->DAY crossed")
	_manager.advance(4.5)
	_check(_approx(_manager.get_progress(REGION_ID), 22.5 / DURATION), \
		"progress advances during DAY again (same policy)")

	# --- 완료: DISCOVERED + 고정 deterministic 결과 ---
	_manager.advance(22.5)
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED, \
		"completion switches to DISCOVERED")
	_check(_approx(_manager.get_progress(REGION_ID), 1.0), "progress clamped to 1.0")
	_check(_discovered_count == 1, "region_discovered emitted exactly once")
	_check(region.has_discovered_feature("dungeon_entrance") \
		and region.has_discovered_feature("safe_approach") \
		and region.get_discovered_features().size() == 2, \
		"fixed deterministic discovery features applied")
	_manager.advance(10.0)
	_check(_discovered_count == 1, "extra advance after completion emits nothing")
	_check(_manager.can_start_exploration(REGION_ID) == false \
		and _manager.start_exploration(REGION_ID) == false, \
		"restart rejected after DISCOVERED")

	# --- 발견 후 Map View 갱신 ---
	_overlay_ctrl.open()
	_overlay_ctrl.select_region(REGION_ID)
	var status_text := String(_overlay_ctrl.get_node("%RegionStatusLabel").text)
	_check(_overlay_ctrl.get_node("%RegionTitleLabel").text == "NE Dungeon" \
		and "DISCOVERED" in status_text and "dungeon_entrance" in status_text, \
		"map panel refreshed after discovery")
	_check(_explore_button.disabled, "Explore stays disabled after discovery")
	_overlay_ctrl.close()

	# --- 회귀: 기존 월드 구조 무손상 ---
	var floor_node: TileMapLayer = _main.get_node("World").get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() >= 128 * 128, \
		"TASK-012 world floor intact (>=128x128 cells)")
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
	_check(_game_time.get_phase() == GameTime.Phase.DAY \
		or _game_time.get_phase() == GameTime.Phase.NIGHT, "GameTime phase valid")

	print("TASKEXP0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
