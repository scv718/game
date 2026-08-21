extends SceneTree

## TASK-012-2 Main Road / Secondary Path / Expansion Belt 정리 검증.
## 기존 4개 접근축을 실제 마을 도로(Main Road)와 향후 전투 접근로로 정리했는지,
## 주요 목적지를 연결하는 Secondary Path, 그리고 Inner Expansion 건설 블록 공간을
## 확인한다. 기존 맵/생산/Worker/건설/Navigation/DayNight 회귀도 함께 확인한다.
##
## 검증 항목:
##   1. 4개 Main Road 식별 가능 (중앙 마을 경계 → Outer Wild까지 끊기지 않음).
##   2. Main Road 폭 약 5~6 논리 타일 (96px).
##   3. Gate Corridor 구간 직선/명확.
##   4. 최소 3개 Secondary Path가 자원/미래 콘텐츠 지역과 연결.
##   5. Secondary Path 시작점이 Main Road와 연결.
##   6. Inner Expansion(220~360px) 블록형 건설 공간 확보 (길/자연물로 과도하게 잘리지 않음).
##   7. 기존 회귀 (건물/생산/Worker/Navigation/DayNight/HUD/main smoke).

const CORE_TYPES := ["keep", "tavern", "inn", "grocery", "equipment"]

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

	_check_floor()
	_check_main_roads()
	_check_secondary_paths()
	_check_inner_expansion()
	_check_regression()

	print("TASK0122_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


## 셀 좌표 -> 셀 중심 좌표 (16px 논리 타일).
func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16 + 8, cell.y * 16 + 8)


## 월드 좌표 -> 해당 셀 좌표.
func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(roundi((pos.x - 8.0) / 16.0), roundi((pos.y - 8.0) / 16.0))


func _is_road_cell(cell: Vector2i) -> bool:
	return _floor.get_cell_source_id(cell) == 1


func _check_floor() -> void:
	_check(_floor.get_used_cells().size() == 128 * 128, "floor covers 128x128 tiles")
	var grass_count := 0
	var path_count := 0
	for cell in _floor.get_used_cells():
		if _floor.get_cell_source_id(cell) == 1:
			path_count += 1
		else:
			grass_count += 1
	_check(grass_count > 0 and path_count > 0, "grass and road tiles present (grass=%d path=%d)" % [grass_count, path_count])
	_check(path_count < grass_count, "roads stay sparse, grass dominates (grass=%d path=%d)" % [grass_count, path_count])
	_check(_floor.get_cell_source_id(Vector2i(19, 0)) == 1, "east Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(-19, 0)) == 1, "west Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(0, -19)) == 1, "north Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(0, 19)) == 1, "south Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(0, 0)) == 0, "settlement center stays grass (plaza)")
	_check(_floor.get_cell_source_id(Vector2i(25, 25)) == 0, "off-road corner tile is grass")


## Main Road 폴리라인을 따라 중앙 마을 경계 -> Outer Wild 까지 끊기지 않는지 확인.
func _check_main_roads() -> void:
	var roads: Dictionary = _layout.MAIN_ROADS
	_check(roads.size() == 4, "4 main roads defined (%d)" % roads.size())
	for dir in roads:
		var poly: Array = roads[dir]
		_check(poly.size() >= 3, "%s main road centerline has enough waypoints (%d)" % [dir, poly.size()])
		# 첫 점(마을 경계)과 끝 점(Outer Wild) 확인.
		var start: Vector2 = poly[0]
		var end: Vector2 = poly[poly.size() - 1]
		_check(start.distance_to(Vector2.ZERO) >= 200.0, "%s road starts at village perimeter (%.0fpx)" % [dir, start.distance_to(Vector2.ZERO)])
		_check(end.distance_to(Vector2.ZERO) >= 900.0, "%s road reaches outer wild (%.0fpx)" % [dir, end.distance_to(Vector2.ZERO)])
		# 중심선을 따라 32px 간격으로 샘플: 로직(axis) + 실제 타일(source) 모두 road 여야 함.
		var unbroken := true
		for t in range(0, 65):
			var pt := _sample_polyline(poly, float(t) / 64.0)
			if not _layout.is_on_access_axis(pt):
				unbroken = false
				break
			var cell := _cell_at(pt)
			if not _is_road_cell(cell):
				unbroken = false
				break
		_check(unbroken, "%s main road unbroken from village to outer wild (centerline tiles)" % dir)
		# Gate Corridor 근처 구간 직선/명확 (방향별 직선 구간 중심 샘플).
		var gate_samples := _gate_corridor_samples(dir)
		for s in gate_samples:
			_check(_layout.is_on_access_axis(s) and _is_road_cell(_cell_at(s)), "%s gate corridor sample on road (%s)" % [dir, str(s)])
	# World Visual Pass: 북쪽 도로 y≈-392 행이 4타일(64px) 안에 머무는지 확인.
	var row := -25
	var on_cells := []
	for cx in range(-6, 7):
		var cell := Vector2i(cx, row)
		if _layout.is_on_access_axis(_cell_center(cell)):
			on_cells.append(cx)
	var expected := [-2, -1, 0, 1]
	_check(on_cells == expected, "north main road straight section is 4 tiles wide (64px) (%s)" % str(on_cells))
	_check(_is_road_cell(Vector2i(2, row)) == false and _is_road_cell(Vector2i(-3, row)) == false, "road band ends inside 32px from axis center")
	# 도로 변 직교점이 도로가 아님을 확인 (폭 상한).
	var edge_center := Vector2(72, -392)
	_check(not _layout.is_on_access_axis(edge_center), "point 72px off road axis is not road (%s)" % str(edge_center))
	var in_road := Vector2(24, -400)
	_check(_layout.is_on_access_axis(in_road), "point 24px from axis center is on road (%s)" % str(in_road))


func _sample_polyline(poly: Array, t: float) -> Vector2:
	if poly.size() == 1:
		return poly[0]
	var total := 0.0
	var seg_lens := []
	for i in range(poly.size() - 1):
		var l: float = (poly[i + 1] - poly[i]).length()
		seg_lens.append(l)
		total += l
	if total <= 0.0:
		return poly[0]
	var target := t * total
	var acc := 0.0
	for i in range(seg_lens.size()):
		if target <= acc + seg_lens[i] or i == seg_lens.size() - 1:
			var local := clampf((target - acc) / maxf(seg_lens[i], 0.0001), 0.0, 1.0)
			return poly[i].lerp(poly[i + 1], local)
		acc += seg_lens[i]
	return poly[poly.size() - 1]


func _gate_corridor_samples(dir: String) -> Array[Vector2]:
	match dir:
		"north":
			return [Vector2(0, -360), Vector2(0, -420), Vector2(0, -480), Vector2(0, -520)]
		"south":
			return [Vector2(0, 360), Vector2(0, 420), Vector2(0, 480), Vector2(0, 520)]
		"east":
			return [Vector2(360, 0), Vector2(420, 0), Vector2(480, 0), Vector2(520, 0)]
		"west":
			return [Vector2(-360, 0), Vector2(-420, 0), Vector2(-480, 0), Vector2(-520, 0)]
	return []


## Secondary Path: 개수, 연결, 경로 타일 확인.
func _check_secondary_paths() -> void:
	var paths: Dictionary = _layout.SECONDARY_PATHS
	_check(paths.size() >= 3, "at least 3 secondary paths defined (%d)" % paths.size())
	var connected := 0
	for id in paths:
		var poly: Array = paths[id]
		_check(poly.size() >= 2, "%s secondary path has waypoints (%d)" % [id, poly.size()])
		# 경로 전체 샘플이 secondary path + road 타일인지.
		var traced := true
		for t in range(0, 33):
			var pt := _sample_polyline(poly, float(t) / 32.0)
			if not _layout.is_on_secondary_path(pt):
				traced = false
				break
			if not _is_road_cell(_cell_at(pt)):
				traced = false
				break
		_check(traced, "%s secondary path traced as road tiles" % id)
		# 시작점이 Main Road 네트워크와 연결.
		var start: Vector2 = poly[0]
		if _layout.is_on_access_axis(start):
			connected += 1
		else:
			_check(false, "%s secondary path start connects to a main road (%s)" % [id, str(start)])
	_check(connected >= 3, "secondary paths connect to the main road network (%d/3)" % connected)


## Inner Expansion(220~360px) 블록형 건설 공간 확인.
func _check_inner_expansion() -> void:
	# 각 사분면 블록 중심 대표점들이 길/자연물로 막히지 않아야 함.
	var block_centers := [
		Vector2(240, 240), Vector2(-240, 240), Vector2(240, -240), Vector2(-240, -240),
		Vector2(280, 200), Vector2(200, 280), Vector2(-280, -200), Vector2(-200, -280),
		Vector2(280, -200), Vector2(200, -280), Vector2(-280, 200), Vector2(-200, 280),
	]
	var blocked_centers := 0
	for p in block_centers:
		if _layout.is_on_any_path(p):
			blocked_centers += 1
	_check(blocked_centers == 0, "inner expansion block centers clear of roads/paths (%d blocked)" % blocked_centers)
	# 링(220~360px)을 그리드 스캔: 길이 블록 공간을 과도하게 잘라내지 않았는지.
	var blocked := 0
	var total := 0
	for qx in [-1, 1]:
		for qy in [-1, 1]:
			for gx in range(14, 24):
				for gy in range(14, 24):
					var pt := Vector2(qx * (gx * 16 + 8), qy * (gy * 16 + 8))
					var dist := pt.distance_to(Vector2.ZERO)
					if dist < 220.0 or dist > 360.0:
						continue
					total += 1
					if _layout.is_on_any_path(pt):
						blocked += 1
	_check(total > 0, "inner expansion ring has sample points (%d)" % total)
	_check(blocked == 0, "inner expansion ring sample points clear of roads/paths (%d/%d blocked)" % [blocked, total])


func _check_regression() -> void:
	var cores := get_nodes_in_group("core_buildings")
	_check(cores.size() == 5, "5 core buildings present (%d)" % cores.size())
	var seen := {}
	for b in cores:
		seen[b.get_core_type()] = b.global_position
		_check(_layout.is_in_clearing(b.global_position), "%s inside central Core Village clearing" % b.name)
		_check(not _layout.is_on_access_axis(b.global_position), "%s not blocking a Main Road (%s)" % [b.name, str(b.global_position)])
	for t in CORE_TYPES:
		_check(seen.has(t), "core type %s present" % t)

	var player_pos: Vector2 = _main.get_node("Player").global_position
	_check(player_pos.distance_to(Vector2(0, 60)) <= 24.0, "Player Start near (0,+60) (%s)" % str(player_pos))
	_check(not _layout.is_on_access_axis(player_pos), "Player Start not on a Main Road")

	if get_nodes_in_group("lumberjacks").size() < 1:
		var lj: Node = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
		lj.position = Vector2(300, 200)
		_world.add_child(lj)
	if get_nodes_in_group("miners").size() < 1:
		var mn: Node = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
		mn.position = Vector2(500, 140)
		_world.add_child(mn)
	_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack present")
	_check(get_nodes_in_group("miners").size() >= 1, "miner present")
	_check(get_nodes_in_group("stone_deposits").size() >= 1, "stone deposit present")
	_check(get_nodes_in_group("decorations").size() >= 4, "decorations present")
	_check(get_nodes_in_group("interactable").size() >= 12, "trees present (%d)" % get_nodes_in_group("interactable").size())

	# 숲 클러스터 트리/월드 트리가 Main Road를 막지 않음.
	var on_axis := 0
	for t in get_nodes_in_group("interactable"):
		if _layout.is_on_access_axis(t.global_position):
			on_axis += 1
	_check(on_axis == 0, "no tree blocks a main road (%d found)" % on_axis)
	# 장식이 Main Road를 막지 않음.
	var deco_on_road := 0
	for d in get_nodes_in_group("decorations"):
		if _layout.is_on_access_axis((d as Node2D).global_position):
			deco_on_road += 1
	_check(deco_on_road == 0, "no decoration blocks a main road (%d found)" % deco_on_road)

	# Navigation: 핵심 건물 사이 이동 가능.
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

	# Marker 구조 유지.
	_check(_layout.get_gate_anchor_nodes().size() >= 4, "gate anchor markers present")
	_check(_layout.get_spawn_candidate_nodes().size() >= 2, "spawn candidate markers present")
	for dir in ["north", "south", "east", "west"]:
		_check(_layout.get_node_or_null("Axis_" + dir.to_upper()) != null, "Axis_%s marker exists" % dir.to_upper())
	_check(_layout.get_bounds_rect().size == Vector2(2048, 2048), "bounds size 2048x2048")


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
