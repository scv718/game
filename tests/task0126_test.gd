extends SceneTree

## TASK-012-6 Portal Candidate / Approach Route 정리 검증.
## 기존 SpawnCandidate 4곳을 향후 Portal/Wave가 연결될 Outer Wild 후보지로 재배치/정리한다.
## 실제 Portal/Enemy spawn/웨이브 로직은 구현하지 않는다 (Marker/데이터 수준).
##
## 검증 항목:
##   1. 4개 Spawn/Portal Candidate가 식별 가능 (SpawnCandidate_NORTH/SOUTH/EAST/WEST).
##   2. 각 후보가 작업 좌표 부근에 있고, Gate 정면 완벽 직선상(lane map)이 아니라 오프축에 위치.
##   3. 각 후보에서 해당 방향 Main Road로 이어지는 열린 이동 경로(Approach Route) 존재.
##   4. Approach Route가 대형 자연 장애물(나무/석재)로 완전히 막히지 않음.
##   5. 각 후보가 Gate Corridor 앞 Combat Field를 침범하지 않음.
##   6. 후보/접근로 자체에는 기능 없음 (비기능 Marker).
##   7. 기존 회귀 (핵심 건물/도로/생산/Worker/Navigation/DayNight/marker 구조).

const CORE_TYPES := ["keep", "tavern", "inn", "grocery", "equipment"]

# TASK-012-6 작업 좌표 후보 (부근 허용 오차).
const EXPECTED := {
	"north": Vector2(-140, -900),
	"south": Vector2(120, 900),
	"east": Vector2(900, -120),
	"west": Vector2(-900, 160),
}

var _frame := 0
var _failed := false
var _main: Node
var _world: Node
var _layout: Node
var _floor: TileMapLayer


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame != 10:
		return false

	_main = root.get_node("Main")
	_world = _main.get_node("World")
	_layout = _world.get_node("MapLayout")
	_floor = _world.get_node("Floor") as TileMapLayer
	_check(_main != null, "main.tscn loads")
	_check(_layout != null, "MapLayout node exists")
	_check(_floor != null, "Floor TileMapLayer exists")

	_check_candidates()
	_check_approach_routes()
	_check_not_functional()
	_check_reachability()
	_check_regression()

	print("TASK0126_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _check_candidates() -> void:
	var candidates: Dictionary = _layout.get_spawn_candidates()
	_check(candidates.size() == 4, "4 spawn/portal candidates defined (%d)" % candidates.size())
	var markers: Array = _layout.get_spawn_candidate_nodes()
	_check(markers.size() == 4, "4 spawn candidate markers present (%d)" % markers.size())
	for dir in EXPECTED:
		var pos: Vector2 = _layout.get_spawn_candidate(dir)
		_check(pos.distance_to(EXPECTED[dir]) <= 40.0, "%s portal candidate near work coord (%s, exp %s)" % [dir, str(pos), str(EXPECTED[dir])])
		_check(_layout.is_in_bounds(pos), "%s portal candidate inside map bounds" % dir)
		_check(not _layout.is_in_clearing(pos), "%s portal candidate is in Outer Wild, not village" % dir)
		# Gate 정면 완벽 직선상(lane map)이 되지 않도록, 후보를 해당 방향 카디널 중심선에서
		# 오프셋해 둔다 (예: 남쪽 후보는 x≠0, 동쪽 후보는 y≠0). 그래야 Gate 정면의 완벽한
		# 직선 대기열(스폰 열)처럼 읽히지 않는다. 도로 자체에 가까운 것은 허용한다.
		_check(_is_off_cardinal_line(dir, pos), "%s portal candidate is offset from the gate's direct line (not a lane map)" % dir)
		_check(_layout.get_node_or_null("SpawnCandidate_" + dir.to_upper()) != null, "SpawnCandidate_%s marker exists" % dir.to_upper())


func _check_approach_routes() -> void:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	for dir in EXPECTED:
		var route: Array = _layout.get_approach_route(dir)
		_check(route.size() >= 2, "%s approach route defined with waypoints (%d)" % [dir, route.size()])
		if route.size() < 2:
			continue
		var cand: Vector2 = _layout.get_spawn_candidate(dir)
		var start: Vector2 = route[0]
		var end: Vector2 = route[route.size() - 1]
		# 접근로 시작은 후보 위치(또는 매우 가까운 곳)여야 한다.
		_check(start.distance_to(cand) <= 24.0, "%s approach route starts at the portal candidate" % dir)
		# 접근로 끝은 해당 방향 Main Road(도로 타일) 위에 있어야 한다.
		_check(_layout.is_on_access_axis(end), "%s approach route merges onto a Main Road (end on road)" % dir)
		_check(_floor.get_cell_source_id(_cell_at(end)) == 1, "%s approach route end is a road tile" % dir)

		# 접근로를 따라 샘플링: 대형 자연 장애물(나무/석재)로 완전히 막히지 않아야 한다.
		var blocked := false
		var r0: Vector2 = route[0]
		var r1: Vector2 = route[route.size() - 1]
		for t in range(0, 9):
			var pt: Vector2 = r0.lerp(r1, float(t) / 8.0)
			for tree in get_nodes_in_group("interactable"):
				if (tree as Node2D).global_position.distance_to(pt) <= 16.0:
					blocked = true
			for dep in get_nodes_in_group("stone_deposits"):
				if (dep as Node2D).global_position.distance_to(pt) <= 16.0:
					blocked = true
		_check(not blocked, "%s approach route not blocked by a tree/stone" % dir)

		# Candidate → 접근로 → Main Road 흐름의 nav 경로 존재.
		var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, cand, end, true)
		_check(path.size() >= 2, "%s nav path from candidate to its Main Road merge exists" % dir)

		_check(_layout.get_node_or_null("ApproachRoute_" + dir.to_upper()) != null, "ApproachRoute_%s marker exists" % dir.to_upper())


func _check_not_functional() -> void:
	# 후보/접근로는 Marker/데이터 수준만 존재하고 기능 로직이 없어야 한다.
	for s in _layout.get_spawn_candidate_nodes():
		_check(s.get_script() == null, "spawn candidate %s is a non-functional marker" % s.name)
	for m in _layout.get_approach_route_nodes():
		_check(m.get_script() == null, "approach route marker %s is a non-functional marker" % m.name)
	_check(not _layout.has_method("spawn_enemy") and not _layout.has_method("start_wave") and not _layout.has_method("open_portal"), "no portal/enemy/wave systems wired into the layout")


func _check_reachability() -> void:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	for dir in EXPECTED:
		var cand: Vector2 = _layout.get_spawn_candidate(dir)
		var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, Vector2.ZERO, cand, true)
		_check(path.size() >= 2, "nav path from village center reaches %s portal candidate (%s)" % [dir, str(cand)])
		# Candidate가 Gate Corridor 앞 Combat Field를 침범하지 않아야 한다.
		_check(not _layout.is_in_combat_field(cand), "%s portal candidate does not intrude on the Combat Field" % dir)
		_check(not _layout.is_in_gate_corridor(cand), "%s portal candidate outside the Gate Corridor" % dir)


func _check_regression() -> void:
	var cores := get_nodes_in_group("core_buildings")
	_check(cores.size() == 5, "5 core buildings present (%d)" % cores.size())
	var seen := {}
	for b in cores:
		seen[b.get_core_type()] = b.global_position
		_check(_layout.is_in_clearing(b.global_position), "%s inside central Core Village clearing" % b.name)
	for t in CORE_TYPES:
		_check(seen.has(t), "core type %s present" % t)

	var start_pos := Vector2(0, 60)
	_check(_layout.is_in_clearing(start_pos), "settlement start point (0,+60) inside clearing")

	_check(get_nodes_in_group("interactable").size() >= 12, "trees present (%d)" % get_nodes_in_group("interactable").size())
	_check(get_nodes_in_group("stone_deposits").size() == 1, "stone deposit present (%d)" % get_nodes_in_group("stone_deposits").size())
	_check(get_nodes_in_group("decorations").size() >= 4, "decorations present (%d)" % get_nodes_in_group("decorations").size())

	_check(_floor.get_used_cells().size() == 192 * 192, "floor covers 192x192 tiles")
	_check(_floor.get_cell_source_id(Vector2i(19, 0)) == 1, "east Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(0, 19)) == 1, "south Main Road reads as road")

	var on_axis := 0
	for t in get_nodes_in_group("interactable"):
		if _layout.is_on_access_axis(t.global_position):
			on_axis += 1
	_check(on_axis == 0, "no tree blocks a Main Road (%d found)" % on_axis)

	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var reachable := true
	for i in cores.size():
		for j in cores.size():
			if i == j:
				continue
			var a: Vector2 = (cores[i] as Node2D).global_position
			var b: Vector2 = (cores[j] as Node2D).global_position
			var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
			if path.is_empty() or path.size() < 2:
				reachable = false
	_check(reachable, "nav path exists between every pair of core buildings")

	_check(_layout.get_gate_anchor_nodes().size() >= 4, "gate anchor markers present")
	_check(_layout.get_spawn_candidate_nodes().size() >= 4, "spawn candidate markers present")
	_check(_layout.get_bounds_rect().size == Vector2(3072, 3072), "bounds size 3072x3072")

	var game_time := root.get_node("GameTime")
	_check(game_time != null, "GameTime autoload exists")
	_check(game_time.get_phase() == game_time.Phase.DAY, "GameTime starts in DAY (%s)" % str(game_time.get_phase_name()))


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(roundi((pos.x - 8.0) / 16.0), roundi((pos.y - 8.0) / 16.0))


## 후보가 해당 방향 Gate 정면의 카디널 중심선에서 벗어났는지 (직선 lane 아님) 확인.
func _is_off_cardinal_line(dir: String, pos: Vector2) -> bool:
	match dir:
		"north", "south":
			# 남/북 후보는 x=0 직선 정면이 아니라 가로 방향으로 오프셋되어야 한다.
			return absf(pos.x) >= 40.0
		"east", "west":
			# 동/서 후보는 y=0 직선 정면이 아니라 세로 방향으로 오프셋되어야 한다.
			return absf(pos.y) >= 40.0
	return true


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
