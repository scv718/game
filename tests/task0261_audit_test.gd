extends SceneTree

## TASK-026-1 Exploration Runtime Audit 자동검증 테스트.
## audit-only 산출물로, 신규 구현 없이 기존 Exploration/WorldMap/Region/Threat/Roster
## 구조의 재사용 경계를 assertion으로 고정한다(대규모 수정 없음).
## 상세 구현기록은 impl_fun/TASK-026-1_EXPLORATION_RUNTIME_AUDIT.md 참고.
##
## 검증 contract:
##   1. Region data owner: ExplorationRegion(RefCounted 순수 데이터) + UNKNOWN/EXPLORING/DISCOVERED.
##   2. World Map marker/region click flow: WorldMapOverlay + MapLayout + NE Dungeon Candidate marker.
##   3. GameTime/day progression API와 ExplorationManager.advance() 연동.
##   4. Mercenary/Worker stable identity API(String id 기반 roster).
##   5. Scout/Expedition placeholder 미존재 확인(TASK-026 신규 구현 GAP).
##   6. Player direct exploration 경로 불필요(Player Actor 없음).
##   7. 기존 월드 회귀(floor/core buildings).

const REGION_ID := "ne_dungeon"
const DURATION := 45.0

var _frame := 0
var _failed := false

var _main: Node = null
var _manager: Node = null
var _game_time: Node = null


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
	if _frame > 300:
		print("TASK0261_RESULT=TIMEOUT")
		quit()
		return true
	if _frame == 10:
		_run_audit()
		return true
	return false


func _run_audit() -> void:
	_main = root.get_node("Main")
	_check(_main != null, "main.tscn loads")

	_manager = root.get_node_or_null("ExplorationManager")
	_check(_manager != null, "ExplorationManager autoload registered")
	_game_time = root.get_node_or_null("GameTime")
	_check(_game_time != null, "GameTime autoload registered")

	# --- 1. Region data owner + UNKNOWN/EXPLORING/DISCOVERED state ---
	var region: ExplorationRegion = _manager.get_region(REGION_ID)
	_check(region != null, "prototype region '%s' registered" % REGION_ID)
	_check(region.get_class() == "RefCounted", \
		"region is pure RefCounted data (no Node/Actor reference)")
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.UNKNOWN \
		and region.get_discovery_state_name() == "UNKNOWN", \
		"region starts UNKNOWN")
	_check(region.set_discovery_state(ExplorationRegion.DiscoveryState.EXPLORING) \
		and region.get_discovery_state() == ExplorationRegion.DiscoveryState.EXPLORING, \
		"UNKNOWN -> EXPLORING accepted")
	_check(region.set_discovery_state(ExplorationRegion.DiscoveryState.DISCOVERED) \
		and region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED, \
		"EXPLORING -> DISCOVERED accepted")
	_check(region.set_discovery_state(-1) == false and region.set_discovery_state(99) == false, \
		"invalid discovery states rejected")
	region.set_discovery_state(ExplorationRegion.DiscoveryState.UNKNOWN)

	# --- 2. World Map marker / dungeon candidate / click flow ---
	var layout: Node = _main.get_node("World").get_node("MapLayout")
	_check(layout != null, "MapLayout node exists")
	_check(region.source_marker_id == "NeDungeonCandidate", \
		"region linked to existing WorldMap marker by String id")
	_check(layout.get_ne_dungeon_marker() != null, "NeDungeonCandidate marker exists")
	_check(region.world_position == WorldMap.NE_DUNGEON_CANDIDATE, \
		"world_position matches NE Dungeon Candidate (%s)" % str(WorldMap.NE_DUNGEON_CANDIDATE))
	_check(_manager.get_region_at(region.world_position) == region, \
		"get_region_at hit-test works")

	var overlay: Node = _main.get_node("WorldMapOverlay").get_node("Control")
	_check(overlay != null \
		and overlay.has_method("open") and overlay.has_method("select_region") \
		and overlay.has_method("world_to_map") and overlay.has_method("map_to_world"), \
		"WorldMapOverlay click/select/coordinate API present")
	_check(_manager.can_start_exploration(REGION_ID), "UNKNOWN region can start exploration")

	# --- 3. GameTime / day progression API integration ---
	_check(_game_time.has_method("get_day_number") and _game_time.has_method("get_phase") \
		and _game_time.has_method("get_time_scale"), \
		"GameTime progression API present")
	_manager.set_auto_advance(false)
	_game_time.set_auto_advance(false)
	_check(_manager.start_exploration(REGION_ID), "start_exploration accepts UNKNOWN region")
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.EXPLORING, \
		"region switched to EXPLORING")
	_manager.advance(9.0)
	_check(_approx(_manager.get_progress(REGION_ID), 9.0 / DURATION), \
		"exploration progress accumulates with GameTime-scaled advance (1x)")
	_check(_game_time.get_phase() == GameTime.Phase.DAY \
		or _game_time.get_phase() == GameTime.Phase.NIGHT, \
		"GameTime phase valid")
	region.set_discovery_state(ExplorationRegion.DiscoveryState.UNKNOWN)

	# --- 4. Mercenary/Resident/Worker stable identity API (String id) ---
	var worker_roster := root.get_node_or_null("WorkerRoster")
	var merc_roster := root.get_node_or_null("MercenaryRoster")
	_check(worker_roster != null and worker_roster.has_method("get_worker"), \
		"WorkerRoster identity API present (get_worker(id))")
	_check(merc_roster != null and merc_roster.has_method("get_mercenary"), \
		"MercenaryRoster identity API present (get_mercenary(id))")
	var w := WorkerData.new("w_audit_1", "Test", WorkerData.Job.LUMBERJACK)
	var m := MercenaryData.new("m_audit_1", "Test")
	_check(typeof(w.id) == TYPE_STRING and typeof(m.id) == TYPE_STRING, \
		"worker/mercenary identity is stable String id")
	_check(worker_roster.add_worker(w) and worker_roster.get_worker("w_audit_1") == w, \
		"WorkerRoster add/get by id")
	_check(merc_roster.add_mercenary(m) and merc_roster.get_mercenary("m_audit_1") == m, \
		"MercenaryRoster add/get by id")
	worker_roster.remove_worker(w)
	merc_roster.remove_mercenary(m)

	# --- 5. Scout/Expedition GAP 상태(TASK-026-2 구현 후) ---
	# TASK-026-2에서 GAP가 ExpeditionPartyData(순수 RefCounted)로 채워졌다.
	_check(ResourceLoader.exists("res://scripts/expedition_party_data.gd") \
		and ResourceLoader.exists("res://scripts/expedition_manager.gd"), \
		"ExpeditionPartyData/ExpeditionManager implemented (TASK-026-2 fills the GAP)")
	_check(not ResourceLoader.exists("res://scenes/expedition.tscn"), \
		"no runtime expedition Actor scene (data-only, no Actor)")

	# --- 6. Player direct exploration 경로 불필요 ---
	_check(get_nodes_in_group("player").size() == 0, \
		"no runtime player Actor (exploration is manager/UI-driven)")

	# --- 7. 회귀: 기존 월드 구조 무손상 ---
	var floor_node: TileMapLayer = _main.get_node("World").get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() >= 128 * 128, \
		"TASK-012 world floor intact (>=128x128 cells)")
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")

	print("TASK0261_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
