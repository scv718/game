extends SceneTree

## TASK-EXP-001-1 ExplorationRegion Data 검증.
## 순수 데이터 클래스의 생성/조회/상태 변경, WorldMap marker 연결(NE Dungeon
## Candidate / resource region), snapshot 직렬화 순수성(Actor/Node ref 없음),
## 기존 월드 회귀를 headless로 확인한다.

const DUNGEON_MARKER_ID := "NeDungeonCandidate"
const SPARSE_FOREST_ID := "sparse_forest"

var _frame := 0
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 1000:
		print("TASKEXP0011_RESULT=TIMEOUT")
		quit()
		return true
	if _frame != 20:
		return false

	var main: Node = root.get_node("Main")
	_check(main != null, "main.tscn loads")

	# --- Region 생성/조회 ---
	var region := ExplorationRegion.new("exp_ne_dungeon")
	_check(region != null, "ExplorationRegion created")
	_check(region.region_id == "exp_ne_dungeon", "region_id retained")
	_check(region.display_name == "", "display_name defaults to empty")
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.UNKNOWN, \
		"default discovery_state is UNKNOWN")
	_check(region.get_discovery_state_name() == "UNKNOWN", "state name 'UNKNOWN'")
	_check(region.exploration_duration == 0.0 and region.base_risk == 0, \
		"exploration_duration/base_risk default to 0")
	_check(region.get_discovered_features().is_empty() and region.get_metadata().is_empty(), \
		"features/metadata start empty")
	_check(region.source_marker_id == "", "source_marker_id starts empty")

	region.display_name = "NE Dungeon"
	region.exploration_duration = 45.0
	region.base_risk = 3
	_check(region.display_name == "NE Dungeon" and region.base_risk == 3, \
		"basic fields assignable")

	# --- 상태 변경 (UNKNOWN / EXPLORING / DISCOVERED) ---
	_check(region.set_discovery_state(ExplorationRegion.DiscoveryState.EXPLORING), \
		"UNKNOWN -> EXPLORING accepted (optional progress state)")
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.EXPLORING \
		and region.get_discovery_state_name() == "EXPLORING", "state is EXPLORING")
	_check(region.set_discovery_state(ExplorationRegion.DiscoveryState.DISCOVERED), \
		"EXPLORING -> DISCOVERED accepted")
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED \
		and region.get_discovery_state_name() == "DISCOVERED", "state is DISCOVERED")
	_check(region.set_discovery_state(-1) == false and region.set_discovery_state(99) == false, \
		"invalid enum values rejected")
	_check(region.get_discovery_state() == ExplorationRegion.DiscoveryState.DISCOVERED, \
		"state unchanged after rejected set")

	# --- discovered_features / metadata 복사 보호 ---
	_check(region.add_discovered_feature("ancient_rune"), "feature added")
	_check(region.add_discovered_feature("") == false, "empty feature id rejected")
	_check(region.add_discovered_feature("ancient_rune") == false, "duplicate feature rejected")
	var external_features := ["hidden_grove"]
	region.set_discovered_features(external_features)
	external_features.append("MUTATED")
	_check(not region.has_discovered_feature("MUTATED"), \
		"set_discovered_features stores a copy (external mutation isolated)")
	var fetched: Array = region.get_discovered_features()
	fetched.append("MUTATED")
	_check(not region.has_discovered_feature("MUTATED"), \
		"get_discovered_features returns a copy (internal state protected)")
	var external_meta := {"threat_level": 3}
	region.set_metadata(external_meta)
	external_meta["threat_level"] = 999
	_check(int(region.get_metadata()["threat_level"]) == 3, "set_metadata stores a copy")
	var fetched_meta: Dictionary = region.get_metadata()
	fetched_meta["injected"] = true
	_check(region.get_metadata().has("injected") == false, \
		"get_metadata returns a copy (internal state protected)")

	# --- WorldMap marker 연결 (Actor/Node reference 없이 String id로) ---
	var layout: Node = main.get_node("World").get_node("MapLayout")
	_check(layout != null, "MapLayout node exists")

	var ne_pos: Vector2 = layout.get_ne_dungeon_candidate()
	_check(ne_pos == WorldMap.NE_DUNGEON_CANDIDATE, \
		"dungeon candidate from layout matches WorldMap const (%s)" % str(ne_pos))
	region.world_position = ne_pos
	region.region_bounds = Rect2(ne_pos - Vector2(90, 90), Vector2(180, 180))
	region.source_marker_id = DUNGEON_MARKER_ID
	_check(layout.get_ne_dungeon_marker() != null \
		and region.source_marker_id == String(layout.get_ne_dungeon_marker().name), \
		"dungeon region linkable to existing WorldMap marker by id ('%s')" % region.source_marker_id)
	_check(region.contains_world_position(ne_pos), "center inside dungeon region bounds")
	_check(region.contains_world_position(Vector2.ZERO) == false, \
		"village center outside dungeon region bounds")

	# get_forest_cluster는 role("sparse")로 매칭한다.
	var sparse: Dictionary = layout.get_forest_cluster("sparse")
	_check(not sparse.is_empty() and String(sparse.get("id", "")) == SPARSE_FOREST_ID, \
		"sparse_forest resource region exists on WorldMap")
	var forest_region := ExplorationRegion.new("exp_sparse_forest")
	forest_region.display_name = "Sparse Forest"
	forest_region.world_position = Vector2(sparse["center"])
	forest_region.region_bounds = Rect2(Vector2(sparse["center"]) - Vector2(200, 120), Vector2(400, 240))
	forest_region.source_marker_id = SPARSE_FOREST_ID
	_check(forest_region.world_position == Vector2(650, -550), \
		"resource region bound to WorldMap forest cluster center")
	_check(forest_region.contains_world_position(Vector2(650, -550)), \
		"forest cluster center inside resource region bounds")
	_check(forest_region.contains_world_position(Vector2(650 + 400, -550)) == false, \
		"point beyond bounds rejected")

	# --- 순수 데이터 / snapshot (Actor 없이 유지 가능) ---
	_check(region.get_class() == "RefCounted", \
		"region is pure RefCounted data (no Actor/Node)")
	var snap := region.to_snapshot()
	_check(_snapshot_is_pure(snap), "snapshot contains only pure save-safe values")
	var restored := ExplorationRegion.from_snapshot(snap)
	_check(restored.region_id == region.region_id \
		and restored.display_name == region.display_name \
		and restored.world_position == region.world_position \
		and restored.region_bounds == region.region_bounds \
		and restored.get_discovery_state() == region.get_discovery_state() \
		and restored.exploration_duration == region.exploration_duration \
		and restored.base_risk == region.base_risk \
		and restored.source_marker_id == region.source_marker_id, \
		"snapshot round-trip restores all fields")
	_check(restored.has_discovered_feature("hidden_grove") \
		and not restored.has_discovered_feature("MUTATED"), \
		"discovered_features survive round-trip")
	_check(int(restored.get_metadata()["threat_level"]) == 3, "metadata survives round-trip")
	snap["injected"] = true
	_check(region.to_snapshot().has("injected") == false, \
		"to_snapshot returns an independent copy")

	# --- 회귀: 기존 월드 구조 무손상 ---
	var floor_node: TileMapLayer = main.get_node("World").get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() >= 128 * 128, \
		"TASK-012 world floor intact (>=128x128 cells)")
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")

	print("TASKEXP0011_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _snapshot_is_pure(snap: Dictionary) -> bool:
	var valid_types := [
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
		TYPE_VECTOR2, TYPE_RECT2, TYPE_DICTIONARY, TYPE_ARRAY,
	]
	for key in snap.keys():
		if typeof(snap[key]) not in valid_types:
			return false
	return true


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
