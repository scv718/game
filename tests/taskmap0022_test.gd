extends SceneTree

## TASK-MAP-002-2 Landmark / Region 표시 검증.
## World Map Overlay의 landmark data consistency를 검증한다:
## - world_map.gd 상수에서 가져온 각 landmark 위치가 world_to_map 변환 후
##   유효한 좌표 범위 내에 있는지 확인.
## - 주요 landmark 누락 없음.
## - world position ↔ map position roundtrip 정확도.

enum Phase {
	SETUP,
	LANDMARK_DATA,
	MAP_COORDINATE,
	ROUNDTRIP,
	DONE,
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _failed := false

var _overlay: Node = null
var _world_map: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0


func _finish() -> void:
	print("TASKMAP0022_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _sub == 0:
				if _frame < 8:
					return false
				var overlays := get_nodes_in_group("world_map_overlay")
				_check(overlays.size() == 1, "exactly 1 WorldMapOverlay")
				_overlay = overlays[0] if overlays.size() > 0 else null
				_check(_overlay != null, "WorldMapOverlay exists")

				# WorldMap node accessible through overlay.
				_world_map = _overlay._world_map
				_check(_world_map != null, "WorldMap node resolved in overlay")

				# world_to_map / map_to_world methods exist.
				_check(_overlay.has_method("world_to_map"), "has world_to_map()")
				_check(_overlay.has_method("map_to_world"), "has map_to_world()")

				_sub = 1
			elif _sub == 1:
				_enter(Phase.LANDMARK_DATA)
		Phase.LANDMARK_DATA:
			if _sub == 0:
				# Verify all landmark constants from world_map.gd are accessible.
				# NOTE(TASK-EXP-001-2 FIX): Node에는 has()가 없어 매 프레임 SCRIPT ERROR
				# 루프로 테스트가 완주하지 못했던 pre-existing 버그. taskmap0023과 동일한
				# get(...) != null 접근성 패턴으로 교정(assertion 의도 유지).
				_check(_world_map.get("SETTLEMENT_CENTER") != null, "SETTLEMENT_CENTER constant exists")
				_check(_world_map.get("GATE_ANCHORS") != null, "GATE_ANCHORS constant exists")
				_check(_world_map.get("SPAWN_CANDIDATES") != null, "SPAWN_CANDIDATES constant exists")
				_check(_world_map.get("NE_DUNGEON_CANDIDATE") != null, "NE_DUNGEON_CANDIDATE constant exists")
				_check(_world_map.get("STONE_ZONE") != null, "STONE_ZONE constant exists")
				_check(_world_map.get("FOREST_CLUSTERS") != null, "FOREST_CLUSTERS constant exists")
				_check(_world_map.get("SOUTH_AGRICULTURE_ZONE") != null, "SOUTH_AGRICULTURE_ZONE constant exists")
				_check(_world_map.get("MAIN_ROADS") != null, "MAIN_ROADS constant exists")
				_check(_world_map.get("CLEARING_HALF") != null, "CLEARING_HALF constant exists")
				_sub = 1
			elif _sub == 1:
				# Verify data types and expected counts.
				var gate_anchors: Dictionary = _world_map.get("GATE_ANCHORS")
				_check(gate_anchors.size() == 4, "GATE_ANCHORS has 4 entries (got %d)" % gate_anchors.size())
				var spawn_candidates: Dictionary = _world_map.get("SPAWN_CANDIDATES")
				_check(spawn_candidates.size() == 4, "SPAWN_CANDIDATES has 4 entries (got %d)" % spawn_candidates.size())
				var forests: Array = _world_map.get("FOREST_CLUSTERS")
				_check(forests.size() == 3, "FOREST_CLUSTERS has 3 entries (got %d)" % forests.size())
				var main_roads: Dictionary = _world_map.get("MAIN_ROADS")
				_check(main_roads.has("east"), "MAIN_ROADS contains east (Royal Road)")
				_sub = 2
			elif _sub == 2:
				# Verify required landmark keys in dictionaries.
				var gate_anchors: Dictionary = _world_map.get("GATE_ANCHORS")
				for dir in ["north", "south", "east", "west"]:
					_check(gate_anchors.has(dir), "GATE_ANCHORS has '%s'" % dir)
				var spawn_candidates: Dictionary = _world_map.get("SPAWN_CANDIDATES")
				for dir in ["north", "south", "east", "west"]:
					_check(spawn_candidates.has(dir), "SPAWN_CANDIDATES has '%s'" % dir)
				_enter(Phase.MAP_COORDINATE)
		Phase.MAP_COORDINATE:
			if _sub == 0:
				# Verify each landmark world position maps to valid map coordinates.
				var settlement: Vector2 = _world_map.get("SETTLEMENT_CENTER")
				var mp: Vector2 = _overlay.world_to_map(settlement)
				_check(mp.x >= 0 and mp.y >= 0, \
					"Settlement center maps to positive coords (%s)" % str(mp))
				_sub = 1
			elif _sub == 1:
				# Gate Anchors - all 4 should map to distinct positions.
				var gate_anchors: Dictionary = _world_map.get("GATE_ANCHORS")
				var gate_positions: Array = []
				for dir in gate_anchors:
					var pos: Vector2 = gate_anchors[dir]
					var map_pos: Vector2 = _overlay.world_to_map(pos)
					_check(map_pos.x >= 0 and map_pos.y >= 0, \
						"%s Gate maps to positive coords (%s)" % [dir.capitalize(), str(map_pos)])
					gate_positions.append(map_pos)
				var unique_positions := {}
				for p in gate_positions:
					unique_positions[str(p)] = true
				_check(unique_positions.size() == 4, \
					"4 distinct Gate Anchor map positions (got %d)" % unique_positions.size())
				_sub = 2
			elif _sub == 2:
				# Spawn Candidates / Portals.
				var spawn_candidates: Dictionary = _world_map.get("SPAWN_CANDIDATES")
				for dir in spawn_candidates:
					var pos: Vector2 = spawn_candidates[dir]
					var map_pos: Vector2 = _overlay.world_to_map(pos)
					_check(map_pos.x >= 0 and map_pos.y >= 0, \
						"%s Portal maps to positive coords (%s)" % [dir.capitalize(), str(map_pos)])
				_sub = 3
			elif _sub == 3:
				# NE Dungeon Candidate.
				var dungeon_pos: Vector2 = _world_map.get("NE_DUNGEON_CANDIDATE")
				var dungeon_map: Vector2 = _overlay.world_to_map(dungeon_pos)
				_check(dungeon_map.x >= 0 and dungeon_map.y >= 0, \
					"Dungeon maps to positive coords (%s)" % str(dungeon_map))
				# Stone Zone.
				var stone_center: Vector2 = _world_map.get("STONE_ZONE")["center"]
				var stone_map: Vector2 = _overlay.world_to_map(stone_center)
				_check(stone_map.x >= 0 and stone_map.y >= 0, \
					"Stone Zone maps to positive coords (%s)" % str(stone_map))
				_sub = 4
			elif _sub == 4:
				# Forest Clusters - each cluster center should map.
				var forests: Array = _world_map.get("FOREST_CLUSTERS")
				for cluster in forests:
					var center: Vector2 = cluster["center"]
					var role: String = cluster.get("role", "")
					var forest_map: Vector2 = _overlay.world_to_map(center)
					_check(forest_map.x >= 0 and forest_map.y >= 0, \
						"%s Forest maps to positive coords (%s)" % [role.capitalize(), str(forest_map)])
				_sub = 5
			elif _sub == 5:
				# South Agriculture Zone center.
				var agri_zone: Rect2 = _world_map.get("SOUTH_AGRICULTURE_ZONE")
				var agri_center_world := agri_zone.position + agri_zone.size * 0.5
				var agri_map: Vector2 = _overlay.world_to_map(agri_center_world)
				_check(agri_map.x >= 0 and agri_map.y >= 0, \
					"Agriculture maps to positive coords (%s)" % str(agri_map))
				# Royal Road (east main road).
				var royal_road: Array = _world_map.get("MAIN_ROADS")["east"]
				_check(royal_road.size() >= 2, \
					"Royal Road has %d points (>= 2)" % royal_road.size())
				var road_mid: Vector2 = royal_road[royal_road.size() / 2]
				var road_map: Vector2 = _overlay.world_to_map(road_mid)
				_check(road_map.x >= 0 and road_map.y >= 0, \
					"Royal Road midpoint maps to positive coords (%s)" % str(road_map))
				_enter(Phase.ROUNDTRIP)
		Phase.ROUNDTRIP:
			if _sub == 0:
				# Roundtrip accuracy for key landmarks.
				var test_cases := [
					Vector2.ZERO,
					Vector2(-1500, 0),
					Vector2(1500, 0),
					Vector2(0, -1500),
					Vector2(0, 1500),
					Vector2(-1440, 200),
					Vector2(1060, -1300),
					Vector2(600, 300),
					Vector2(-520, -420),
				]
				var all_ok := true
				for world_pos in test_cases:
					var map_pos: Vector2 = _overlay.world_to_map(world_pos)
					var roundtrip: Vector2 = _overlay.map_to_world(map_pos)
					var err: float = world_pos.distance_to(roundtrip)
					if err >= 10.0:
						_check(false, \
							"roundtrip error %.2f for world %s" % [err, str(world_pos)])
						all_ok = false
				if all_ok:
					_check(true, "all %d landmark roundtrips within 10px error" % test_cases.size())
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASKMAP0022_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
