extends SceneTree

## TASK-026-4 Scout Dispatch / Region Discovery 자동검증 테스트.
## World Map의 UNKNOWN Region에서 Scout/Expedition을 파견하고, expedition의
## EXPLORING 구간 완료 시 Region/POI를 DISCOVERED로 처리하는 흐름을 실제
## WorldMap overlay/버튼 경로로 end-to-end 검증한다. 상세 구현기록은
## impl_fun/TASK-026-4_SCOUT_DISPATCH_REGION_DISCOVERY.md 참고.
##
## 검증 contract:
##   1. UNKNOWN region만 dispatch 가능.
##   2. active EXPLORING region에 duplicate dispatch 차단.
##   3. dead/unavailable member dispatch는 거부되고 region 상태가 바뀌지 않음.
##   4. 발견 시 region DISCOVERED + 고정 deterministic feature(NE Dungeon 연결).
##   5. DISCOVERED 전환은 정확히 1회(duplicate signal 없음).
##   6. World Map marker/label(overlay 패널/버튼)이 발견 상태를 즉시 반영.
##   7. Player가 파견 위치로 직접 이동하지 않음(Player Actor 없음, expedition Actor scene 없음).
##   8. expedition COMPLETED 후 member availability가 복구(roster 해제).
##   9. 회귀: 기존 월드 구조(floor/core buildings) 무손상 + legacy 시작 경로 차단.

enum Phase {
	SETUP,
	FAIL_DISPATCH,
	UI_DISPATCH,
	DUPLICATE_BLOCK,
	PROGRESS,
	DISCOVERY,
	COMPLETE,
	DONE,
}

const REGION_ID := "ne_dungeon"

var _frame := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _failed := false

var _main: Node = null
var _exploration: Node = null
var _game_time: Node = null
var _roster: Node = null
var _sd: Node = null
var _overlay: Node = null
var _explore_button: Button = null
var _region: ExplorationRegion = null
var _exp: ExpeditionPartyData = null

var _started_count := 0
var _discovered_count := 0
var _dispatch_count := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0


func _finish() -> void:
	print("TASK0264_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 2000:
		print("TASK0264_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	match _phase:
		Phase.SETUP:
			if _sub == 0:
				if _frame < 8:
					return false
				# headless 기본 window(64x64)는 overlay 레이아웃을 붕괴시키므로
				# 프로젝트 해상도로 강제한다(taskexp0012 패턴).
				root.size = Vector2i(1152, 648)
				_main = root.get_node("Main")
				_exploration = root.get_node_or_null("ExplorationManager")
				_game_time = root.get_node("GameTime")
				_roster = root.get_node("MercenaryRoster")
				_check(_exploration != null and _game_time != null and _roster != null, \
					"autoloads available (ExplorationManager/GameTime/MercenaryRoster)")

				_exploration.exploration_started.connect(func(_id): _started_count += 1)
				_exploration.region_discovered.connect(func(_id): _discovered_count += 1)
				# legacy/게임 시간 자동 진행은 끄고 dispatch 진행만 수동 제어한다.
				_exploration.set_auto_advance(false)
				_game_time.set_auto_advance(false)
				_game_time.set_time_scale(GameTime.TIME_SCALE_1X)

				_region = _exploration.get_region(REGION_ID)
				_check(_region != null and _region.get_discovery_state() \
					== ExplorationRegion.DiscoveryState.UNKNOWN, "region starts UNKNOWN")

				# roster에 alive 용병 2명 + dead 1명.
				_roster.add_mercenary(MercenaryData.new("scout_m1", "Scout One"))
				_roster.add_mercenary(MercenaryData.new("scout_m2", "Scout Two"))
				var dead := MercenaryData.new("scout_m3", "Scout Three")
				dead.alive = false
				_roster.add_mercenary(dead)

				# ScoutDispatchManager를 /root/ScoutDispatchManager로 추가(overlay가 조회).
				_sd = load("res://scripts/scout_dispatch_manager.gd").new()
				_sd.name = "ScoutDispatchManager"
				root.add_child(_sd)
				_sd.set_auto_advance(false)
				_sd.scout_dispatched.connect(func(_id, _r): _dispatch_count += 1)

				_check(_sd.get_expedition_manager() != null, \
					"ScoutDispatchManager owns an ExpeditionManager (expedition lifecycle)")
				_check(_sd.can_dispatch(REGION_ID), "UNKNOWN region can dispatch scout")
				_check(_exploration.can_start_exploration(REGION_ID), \
					"legacy can_start_exploration also true (fallback intact)")

				_overlay = _main.get_node("WorldMapOverlay").get_node("Control")
				_explore_button = _overlay.get_node("%ExploreButton")
				_sub = 1
			elif _sub == 1:
				if _frame < 26:
					return false
				_enter(Phase.FAIL_DISPATCH)
		Phase.FAIL_DISPATCH:
			# dead member dispatch는 거부되고 region 상태가 그대로 유지된다.
			var ok_dead = _sd.dispatch_scout(REGION_ID, ["scout_m1", "scout_m3"], "exp_dead")
			_check(ok_dead == false, "dispatch with dead member rejected")
			_check(String(_sd.get_dispatch_error()) != "", "dispatch error reason recorded")
			_check(_region.get_discovery_state() \
				== ExplorationRegion.DiscoveryState.UNKNOWN, \
				"region stays UNKNOWN after rejected dispatch")
			_check(_sd.get_expedition_manager().has_expedition("exp_dead") == false \
				and _sd.get_expedition_manager().is_member_in_active_expedition("scout_m1") == false, \
				"failed dispatch cleaned up (no orphan expedition/member lock)")
			# 동일 dispatch 내 member duplicate도 거부된다.
			var ok_dup = _sd.dispatch_scout(REGION_ID, ["scout_m1", "scout_m1"], "exp_dup")
			_check(ok_dup == false \
				and _region.get_discovery_state() == ExplorationRegion.DiscoveryState.UNKNOWN, \
				"duplicate-member dispatch rejected without state change")
			_enter(Phase.UI_DISPATCH)
		Phase.UI_DISPATCH:
			if _sub == 0:
				# 실제 Map 경로: 열고 marker 클릭 선택 → Explore 버튼(dispatch 경로).
				_overlay.open()
				_check(_overlay.is_open(), "world map opens")
				_overlay._handle_map_click(_overlay.world_to_map(_region.world_position))
				_check(_overlay.get_selected_region_id() == REGION_ID, \
					"region selected on map click")
				_check(not _explore_button.disabled, "Explore enabled for UNKNOWN region")
				_explore_button.pressed.emit()
				_check(_region.get_discovery_state() \
					== ExplorationRegion.DiscoveryState.EXPLORING, \
					"UI Explore dispatches scout (region EXPLORING)")
				_check(_started_count == 1, "exploration_started emitted once")
				_check(_dispatch_count == 1, "scout_dispatched emitted once")
				_exp = _sd.find_expedition_for_region(REGION_ID)
				_check(_exp != null and _exp is ExpeditionPartyData, \
					"active expedition for region exists")
				_check(_exp.destination_region_id == REGION_ID, \
					"expedition destination matches region")
				_check(_exp.get_member_ids() == ["scout_m1", "scout_m2"], \
					"dispatch auto-fills alive mercenaries (member order deterministic)")
				_check(_sd.get_expedition_manager().is_member_in_active_expedition("scout_m1") \
					and _sd.get_expedition_manager().is_member_in_active_expedition("scout_m2"), \
					"dispatched members reserved during expedition")
				_check(_exploration.is_region_expedition_driven(REGION_ID), \
					"region marked expedition-driven")
				_check(_approx(_exploration.get_progress(REGION_ID), 0.0), \
					"region progress starts 0 (outbound)")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DUPLICATE_BLOCK)
		Phase.DUPLICATE_BLOCK:
			# active EXPLORING region duplicate dispatch 금지.
			_check(_sd.can_dispatch(REGION_ID) == false, "can_dispatch false while EXPLORING")
			var ok_again = _sd.dispatch_scout(REGION_ID, ["scout_m1"], "exp_dup2")
			_check(ok_again == false, "duplicate dispatch while EXPLORING rejected")
			_check(_sd.get_expedition_manager().has_expedition("exp_dup2") == false, \
				"duplicate dispatch creates no expedition")
			_check(_sd.get_expedition_manager().get_active_expeditions().size() == 1, \
				"only one active expedition (no duplicate scout)")
			_check(_started_count == 1 and _dispatch_count == 1, \
				"no duplicate dispatch signals from blocked attempts")
			_check(_explore_button.disabled \
				and String(_explore_button.text) == "Exploring...", \
				"map Explore button disabled while EXPLORING")
			_enter(Phase.PROGRESS)
		Phase.PROGRESS:
			if _sub == 0:
				# 구간 duration을 테스트 fixture로 짧게 설정 후 수동 진행.
				_exp.outbound_duration = 10.0
				_exp.exploration_duration = 5.0
				_exp.return_duration = 2.0

				_sd.advance(5.0)
				_check(_exp.get_status() == ExpeditionPartyData.Status.OUTBOUND \
					and _approx(_exp.progress, 0.5), \
					"outbound progress 5/10 while region EXPLORING (status kept)")
				_check(_region.get_discovery_state() \
					== ExplorationRegion.DiscoveryState.EXPLORING, "region stays EXPLORING")
				_check(_approx(_exploration.get_progress(REGION_ID), 0.0), \
					"region progress synced 0 during outbound")

				_sd.advance(5.0)
				_check(_exp.get_status() == ExpeditionPartyData.Status.EXPLORING \
					and _approx(_exp.progress, 0.0), "outbound done -> EXPLORING phase")
				_check(_dcount() == 0, "no discovery before exploration phase completes")

				_sd.advance(2.5)
				_check(_approx(_exp.progress, 0.5), "exploration phase progress 2.5/5")
				_check(_approx(_exploration.get_progress(REGION_ID), 0.5), \
					"region progress synced to expedition exploration phase")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DISCOVERY)
		Phase.DISCOVERY:
			if _sub == 0:
				# EXPLORING 구간 완료 → expedition RETURNING 전환 → region DISCOVERED.
				_sd.advance(2.5)
				_check(_exp.get_status() == ExpeditionPartyData.Status.RETURNING, \
					"exploration done -> expedition RETURNING")
				_check(_region.get_discovery_state() \
					== ExplorationRegion.DiscoveryState.DISCOVERED, "region DISCOVERED")
				_check(_dcount() == 1, "region_discovered emitted exactly once")
				_check(_region.has_discovered_feature("dungeon_entrance") \
					and _region.has_discovered_feature("safe_approach") \
					and _region.get_discovered_features().size() == 2, \
					"fixed deterministic features applied (NE Dungeon candidate link)")
				_check(_exploration.is_region_expedition_driven(REGION_ID) == false, \
					"expedition-driven marker cleared after discovery")
				_check(_approx(_exploration.get_progress(REGION_ID), 1.0), \
					"region progress synced to 1.0 after discovery")
				# legacy advance가 이미 DISCOVERED region을 다시 처리하지 않는지.
				_exploration.advance(100.0)
				_check(_dcount() == 1, "legacy extra advance creates no duplicate discovery")
				_sub = 1
			elif _sub == 1:
				# Map marker/label이 발견 상태를 즉시 반영(열린 Map, 재선택 없이).
				_check(_overlay.is_open(), "map still open during discovery (live refresh)")
				_check(_overlay.get_selected_region_id() == REGION_ID, "selection preserved")
				var status_text := String(_overlay.get_node("%RegionStatusLabel").text)
				_check(_overlay.get_node("%RegionTitleLabel").text == "NE Dungeon" \
					and "DISCOVERED" in status_text and "dungeon_entrance" in status_text, \
					"map panel refreshed to DISCOVERED with features (%s)" % status_text)
				_check(_explore_button.disabled \
					and String(_explore_button.text) == "Discovered", \
					"map Explore button switched to disabled 'Discovered'")
				# DISCOVERED 후 재파견/재탐사 모두 차단.
				_check(_sd.can_dispatch(REGION_ID) == false \
					and _sd.dispatch_scout(REGION_ID, ["scout_m1"], "exp_x") == false, \
					"dispatch blocked after DISCOVERED")
				_check(_exploration.can_start_exploration(REGION_ID) == false \
					and _exploration.start_exploration(REGION_ID) == false, \
					"legacy explore blocked after DISCOVERED")
				_overlay.close()
				_enter(Phase.COMPLETE)
		Phase.COMPLETE:
			if _sub == 0:
				# RETURNING → COMPLETED 후 member availability 복구.
				_sd.advance(2.0)
				_check(_exp.get_status() == ExpeditionPartyData.Status.COMPLETED, \
					"scout expedition returns and completes")
				_check(_sd.get_expedition_manager().is_member_in_active_expedition("scout_m1") \
					== false and _sd.get_expedition_manager().is_member_in_active_expedition("scout_m2") \
					== false, "members released after completion (roster availability restored)")
				_check(_sd.get_expedition_manager().get_active_expeditions().size() == 0, \
					"no active expeditions after completion")
				_check(_dcount() == 1, "discovery signal stays single after completion")
				_check(_region.get_discovery_state() \
					== ExplorationRegion.DiscoveryState.DISCOVERED, \
					"region stays DISCOVERED")
				# Player가 해당 위치로 직접 이동하지 않는다(경로 자체가 data-only).
				_check(get_nodes_in_group("player").size() == 0, "no runtime Player Actor")
				_check(not ResourceLoader.exists("res://scenes/expedition.tscn"), \
					"no runtime expedition Actor scene (data-driven dispatch)")
				_check(_sd.find_expedition_for_region(REGION_ID) == null, \
					"no active expedition query for completed region")
				_overlay.open()
				_overlay.select_region(REGION_ID)
				_check("DISCOVERED" in String(_overlay.get_node("%RegionStatusLabel").text), \
					"map state persists after reopen")
				_sub = 1
			elif _sub == 1:
				# 회귀: 기존 월드 구조 무손상.
				var floor_node: TileMapLayer = _main.get_node("World").get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() >= 128 * 128, \
					"world floor intact (>=128x128 cells)")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	return false


func _dcount() -> int:
	return _discovered_count


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
