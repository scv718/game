extends SceneTree

## TASK-012-4 Resource Region 재배치 검증.
## Wood/Stone 생산 위치가 게임플레이 기준으로 재배치되었는지 자동 확인한다.
##  - NW Starter Forest: 초반 직접 벌목/첫 Lumberyard 대상. SE(마을쪽) 가장자리 성기게,
##    내부(NW)로 갈수록 밀도 증가, 내부 이동 틈 유지, Secondary Path 미차단.
##  - SW Large Forest: 중심 (-600, +470) 부근, starter보다 큰 대규모 Wood 지역.
##    Defense Belt(360~520px)를 침범하지 않도록 외곽에 위치.
##  - NE Sparse Forest: 중심 (+520, -440) 부근, 적고 넓게 분산된 탐색 지역.
##  - SE Stone Zone: 첫 StoneDeposit을 (+480, +360) 부근으로 이동, 외곽 거리 ~600px.
##    장식 바위(충돌 없음)로 시각 구분, Quarry placement는 막지 않음.
##  - 정착지 근처 소형 나무 그로브 3그루(초반 채집→첫 Lumberyard 루프용)만 Inner Expansion에 남김.
## 기존 시스템(생산/건설/Worker/Navigation/DayNight/HUD/main smoke) 회귀도 함께 확인한다.

enum Phase {
	SETUP, VERIFY_REGIONS, VERIFY_STARTER, VERIFY_LARGE, VERIFY_SPARSE,
	VERIFY_STONE, VERIFY_GROVE, SETUP_LUMBERYARD, WAIT_WOOD, SETUP_QUARRY,
	WAIT_STONE, REGRESSION, DONE
}

const CORE_TYPES := ["keep", "tavern", "inn", "grocery", "equipment"]

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _failed := false

var _main: Node
var _world: Node
var _layout: Node
var _floor: TileMapLayer
var _placement: Node
var _resources: Node

var _trees_by_name := {}
var _deposit: Node = null
var _wood_before := 0
var _stone_before := 0
var _lumberyard: Node = null
var _quarry: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: Phase) -> void:
	_phase = new_phase
	_phase_start = _frame


func _elapsed() -> int:
	return _frame - _phase_start


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16 + 8, cell.y * 16 + 8)


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(roundi((pos.x - 8.0) / 16.0), roundi((pos.y - 8.0) / 16.0))


func _is_road_cell(cell: Vector2i) -> bool:
	return _floor.get_cell_source_id(cell) == 1


func _dist_point_polyline(point: Vector2, poly: Array) -> float:
	var best := INF
	for i in range(poly.size() - 1):
		best = minf(best, _dist_point_segment(point, poly[i], poly[i + 1]))
	if poly.size() == 1:
		best = minf(best, point.distance_to(poly[0]))
	return best


func _dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.VERIFY_REGIONS:
			_verify_regions()
		Phase.VERIFY_STARTER:
			_verify_starter()
		Phase.VERIFY_LARGE:
			_verify_large()
		Phase.VERIFY_SPARSE:
			_verify_sparse()
		Phase.VERIFY_STONE:
			_verify_stone()
		Phase.VERIFY_GROVE:
			_verify_grove()
		Phase.SETUP_LUMBERYARD:
			_setup_lumberyard()
		Phase.WAIT_WOOD:
			_wait_wood()
		Phase.SETUP_QUARRY:
			_setup_quarry()
		Phase.WAIT_STONE:
			_wait_stone()
		Phase.REGRESSION:
			_verify_regression()
		Phase.DONE:
			print("TASK0124_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 30000:
		print("TASK0124_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _setup() -> void:
	if _frame < 8:
		return
	_main = root.get_node("Main")
	_world = _main.get_node("World")
	_layout = _world.get_node("MapLayout")
	_floor = _world.get_node("Floor") as TileMapLayer
	_placement = _main.get_node("BuildingPlacement")
	_resources = root.get_node("VillageResources")
	_check(_main != null, "main.tscn loads")
	_check(_layout != null, "MapLayout node exists")
	_check(_floor != null, "Floor TileMapLayer exists")

	for t in get_nodes_in_group("interactable"):
		_trees_by_name[t.name] = t.global_position
		t.regrow_time = 10000.0

	var deposits := get_nodes_in_group("stone_deposits")
	_deposit = deposits[0] if deposits.size() > 0 else null
	_enter(Phase.VERIFY_REGIONS)


func _verify_regions() -> void:
	_check(get_nodes_in_group("interactable").size() >= 12, "trees present (%d)" % get_nodes_in_group("interactable").size())
	_check(get_nodes_in_group("stone_deposits").size() == 1, "exactly 1 stone deposit (%d)" % get_nodes_in_group("stone_deposits").size())
	_check(get_nodes_in_group("decorations").size() >= 4, "decorations present (%d)" % get_nodes_in_group("decorations").size())

	var clusters: Array = _layout.get_forest_clusters()
	_check(clusters.size() >= 3, "at least 3 forest clusters defined (%d)" % clusters.size())
	for cluster in clusters:
		var trees: Array = cluster.get("trees", [])
		_check(trees.size() >= 3, "cluster %s has >= 3 trees (%d)" % [cluster.get("id", "?"), trees.size()])
		for pos in trees:
			_check(_layout.is_in_bounds(pos), "cluster %s tree inside map bounds (%s)" % [cluster.get("id", "?"), str(pos)])
			_check(not _layout.is_in_clearing(pos), "cluster %s tree not inside settlement clearing" % cluster.get("id", "?"))
			_check(not _layout.is_on_access_axis(pos), "cluster %s tree not on a Main Road" % cluster.get("id", "?"))
			_check(not _layout.is_on_secondary_path(pos), "cluster %s tree not on a Secondary Path" % cluster.get("id", "?"))
			_check(not _layout.is_in_gate_corridor(pos), "cluster %s tree not in a Gate Corridor" % cluster.get("id", "?"))
			_check(not _layout.is_in_combat_field(pos), "cluster %s tree not in a Combat Field" % cluster.get("id", "?"))
			_check(not _layout.is_in_rally_space(pos), "cluster %s tree not in a Rally Space" % cluster.get("id", "?"))
	_enter(Phase.VERIFY_STARTER)


func _verify_starter() -> void:
	var cluster: Dictionary = _layout.get_forest_cluster("starter")
	_check(not cluster.is_empty(), "starter forest cluster exists")
	if cluster.is_empty():
		_enter(Phase.VERIFY_LARGE)
		return
	var trees: Array = cluster.get("trees", [])
	_check(trees.size() >= 18 and trees.size() <= 25, "starter forest ~18~25 trees (got %d)" % trees.size())
	var center := _cluster_center(trees)
	_check(center.distance_to(Vector2(-430, -330)) <= 80.0, "starter forest center near (-430,-330) (%.0f)" % center.distance_to(Vector2(-430, -330)))
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for t in trees:
		min_x = minf(min_x, t.x)
		max_x = maxf(max_x, t.x)
		min_y = minf(min_y, t.y)
		max_y = maxf(max_y, t.y)
	var w: float = max_x - min_x
	var h: float = max_y - min_y
	_check(w >= 180.0 and h >= 150.0, "starter forest is a meaningful cluster (%dx%d)" % [int(w), int(h)])

	var se_trees := 0
	var nw_trees := 0
	for t in trees:
		if t.x >= center.x and t.y >= center.y:
			se_trees += 1
		elif t.x <= center.x and t.y <= center.y:
			nw_trees += 1
	_check(nw_trees >= se_trees, "starter forest denser toward interior/NW (se=%d nw=%d)" % [se_trees, nw_trees])

	var min_gap := INF
	for i in trees.size():
		for j in range(i + 1, trees.size()):
			min_gap = minf(min_gap, (trees[i] - trees[j]).length())
	_check(min_gap >= 20.0, "starter forest keeps walkable gaps (min spacing %.0f)" % min_gap)

	var sp: Array = _layout.get_secondary_path("starter_forest")
	var path_blocked := 0
	for t in trees:
		if _dist_point_polyline(t, sp) < 28.0:
			path_blocked += 1
	_check(path_blocked == 0, "starter forest does not block its Secondary Path (%d found)" % path_blocked)
	_enter(Phase.VERIFY_LARGE)


func _verify_large() -> void:
	var cluster: Dictionary = _layout.get_forest_cluster("large")
	_check(not cluster.is_empty(), "large forest cluster exists")
	if cluster.is_empty():
		_enter(Phase.VERIFY_SPARSE)
		return
	var trees: Array = cluster.get("trees", [])
	var starter: Array = _layout.get_forest_cluster_trees("starter")
	_check(trees.size() > starter.size(), "large forest bigger than starter (%d vs %d)" % [trees.size(), starter.size()])
	var center := _cluster_center(trees)
	_check(center.distance_to(Vector2(-600, 470)) <= 80.0, "large forest center near (-600,470) (%.0f)" % center.distance_to(Vector2(-600, 470)))
	var in_belt := 0
	for t in trees:
		if _layout.is_in_defense_belt(t):
			in_belt += 1
	_check(in_belt == 0, "large forest avoids the Defense Belt (in_belt=%d)" % in_belt)
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for t in trees:
		min_x = minf(min_x, t.x)
		max_x = maxf(max_x, t.x)
		min_y = minf(min_y, t.y)
		max_y = maxf(max_y, t.y)
	var w: float = max_x - min_x
	var h: float = max_y - min_y
	_check(w >= 260.0 and h >= 220.0, "large forest is a wide cluster (%dx%d)" % [int(w), int(h)])
	var gap := _cluster_distance(trees, starter)
	_check(gap >= 60.0, "large and starter forests are distinct clusters (gap %.0f)" % gap)
	_enter(Phase.VERIFY_SPARSE)


func _verify_sparse() -> void:
	var cluster: Dictionary = _layout.get_forest_cluster("sparse")
	_check(not cluster.is_empty(), "sparse forest cluster exists")
	if cluster.is_empty():
		_enter(Phase.VERIFY_STONE)
		return
	var trees: Array = cluster.get("trees", [])
	var center := _cluster_center(trees)
	_check(center.distance_to(Vector2(520, -440)) <= 90.0, "sparse forest center near (+520,-440) (%.0f)" % center.distance_to(Vector2(520, -440)))
	var large: Array = _layout.get_forest_cluster_trees("large")
	_check(trees.size() < large.size(), "sparse forest has fewer trees than large (%d vs %d)" % [trees.size(), large.size()])
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for t in trees:
		min_x = minf(min_x, t.x)
		max_x = maxf(max_x, t.x)
		min_y = minf(min_y, t.y)
		max_y = maxf(max_y, t.y)
	var area: float = maxf(1.0, (max_x - min_x) * (max_y - min_y))
	_check(float(trees.size()) / area < float(large.size()) / _cluster_area(large), "sparse forest is more spread out (lower density)")
	_enter(Phase.VERIFY_STONE)


func _verify_stone() -> void:
	_check(_deposit != null, "stone deposit exists")
	if _deposit == null:
		_enter(Phase.VERIFY_GROVE)
		return
	var pos: Vector2 = _deposit.global_position
	_check(pos.distance_to(Vector2(500, 260)) <= 32.0, "stone deposit near (+500,260) (%s)" % str(pos))
	var dist := pos.distance_to(Vector2.ZERO)
	_check(dist >= 420.0, "stone deposit is a meaningful expansion target (dist %.0f)" % dist)
	_check(not _layout.is_in_clearing(pos), "stone deposit outside central clearing")
	_check(_layout.is_in_bounds(pos), "stone deposit inside map bounds")
	# Defense Belt(360~520px) 바깥에 두어 성벽 안/밖 포함 여부를 선택할 수 있게 한다.
	_check(not _layout.is_in_defense_belt(pos), "stone deposit outside the Defense Belt (wall in/out choice)")
	var sp: Array = _layout.get_secondary_path("stone_zone")
	_check(_dist_point_polyline(pos, sp) <= 90.0, "stone deposit reachable via stone_zone Secondary Path")
	_check(not _layout.is_in_gate_corridor(pos), "stone deposit not in a Gate Corridor")
	_check(not _layout.is_in_combat_field(pos), "stone deposit not in a Combat Field")
	_check(not _layout.is_in_rally_space(pos), "stone deposit not in a Rally Space")

	var stone_decos := 0
	var deco_on_deposit := 0
	for d in get_nodes_in_group("decorations"):
		if (d as Node2D).global_position.distance_to(pos) <= 110.0:
			stone_decos += 1
		var has_collision := false
		for child in d.get_children():
			if child is StaticBody2D or child is CollisionShape2D or child is Area2D:
				has_collision = true
		if (d as Node2D).global_position.distance_to(pos) <= 110.0 and has_collision:
			deco_on_deposit += 1
	_check(stone_decos >= 3, "stone zone has decorative rocks nearby (%d)" % stone_decos)
	_check(deco_on_deposit == 0, "stone-zone decorations are pure visual (no collision) (%d)" % deco_on_deposit)
	_enter(Phase.VERIFY_GROVE)


func _verify_grove() -> void:
	var starter_trees: Array = _layout.get_starter_trees()
	_check(starter_trees.size() == 3, "3 starter grove trees defined (%d)" % starter_trees.size())
	var present := 0
	for p in starter_trees:
		var found := false
		for name in _trees_by_name:
			if (_trees_by_name[name] - p).length() <= 2.0 and String(name).begins_with("Tree"):
				found = true
				break
		if found:
			present += 1
	_check(present == 3, "starter grove trees present in world (%d/3)" % present)
	for p in starter_trees:
		_check(not _layout.is_on_access_axis(p), "grove tree not on a Main Road (%s)" % str(p))
		_check(not _layout.is_on_secondary_path(p), "grove tree not on a Secondary Path (%s)" % str(p))
		_check(not _layout.is_in_clearing(p), "grove tree not inside central clearing (%s)" % str(p))
		# 소형 starter grove는 Defense Belt 내부를 일부 지나갈 수 있으나(TASK-012-3 허용),
		# 성벽/문을 방해하는 Gate Corridor / Combat Field / Rally Space는 피해야 한다.
		_check(not _layout.is_in_gate_corridor(p), "grove tree not in a Gate Corridor (%s)" % str(p))
		_check(not _layout.is_in_combat_field(p), "grove tree not in a Combat Field (%s)" % str(p))
		_check(not _layout.is_in_rally_space(p), "grove tree not in a Rally Space (%s)" % str(p))

	var on_axis := 0
	for t in get_nodes_in_group("interactable"):
		if _layout.is_on_access_axis(t.global_position):
			on_axis += 1
	_check(on_axis == 0, "no tree blocks a Main Road (%d found)" % on_axis)
	var on_path := 0
	for t in get_nodes_in_group("interactable"):
		if _layout.is_on_secondary_path(t.global_position):
			on_path += 1
	_check(on_path == 0, "no tree blocks a Secondary Path (%d found)" % on_path)
	_enter(Phase.SETUP_LUMBERYARD)


func _setup_lumberyard() -> void:
	_check(_placement != null and _resources != null, "placement/resources available")
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var reachable := true
	for p in _layout.get_forest_cluster_trees("starter"):
		var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, Vector2.ZERO, p, true)
		if path.is_empty() or path.size() < 2:
			reachable = false
			break
	_check(reachable, "nav path from village center to every starter forest tree exists")

	# Lumberjack/Miner Actor 준비 (실제 생산 회귀).
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

	# Lumberyard를 그로브/정착지 인근에 배치, 2 Worker가 실제 벌목 루프를 수행하는지 확인.
	if get_nodes_in_group("lumberyards").size() == 0:
		var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
		_lumberyard = ly_scene.instantiate() as Node2D
		_lumberyard.name = "Lumberyard_T"
		_lumberyard.position = Vector2(180, 180)
		_lumberyard.work_radius = 320.0
		_world.add_child(_lumberyard)
		_world.rebuild_navigation()
	else:
		_lumberyard = get_nodes_in_group("lumberyards")[0]
	var ljs := get_nodes_in_group("lumberjacks")
	if _lumberyard != null and ljs.size() > 0:
		_lumberyard.assign_worker(ljs[0])
		if ljs.size() > 1:
			_lumberyard.assign_worker(ljs[1])
	_wood_before = _resources.get_amount("wood")
	_enter(Phase.WAIT_WOOD)


func _wait_wood() -> void:
	var wood: int = _resources.get_amount("wood")
	if wood > _wood_before:
		_check(wood > _wood_before, "lumberjack produced wood from starter forest region (+%d)" % (wood - _wood_before))
		_enter(Phase.SETUP_QUARRY)
	elif _elapsed() >= 4000:
		_check(false, "lumberjack production loop within timeout (wood=%d)" % wood)
		_enter(Phase.SETUP_QUARRY)


func _setup_quarry() -> void:
	if _deposit != null:
		_placement._set_building_type("quarry")
		var wood_now: int = _resources.get_amount("wood")
		_resources._amounts["wood"] = 200
		if get_nodes_in_group("quarries").size() == 0:
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "quarry built on relocated stone deposit")
		_quarry = get_nodes_in_group("quarries")[0] if get_nodes_in_group("quarries").size() > 0 else null
		if _quarry != null:
			var miners := get_nodes_in_group("miners")
			for i in mini(miners.size(), 2):
				_quarry.assign_worker(miners[i])
		_resources._amounts["wood"] = wood_now
	_stone_before = _resources.get_amount("stone")
	_enter(Phase.WAIT_STONE)


func _wait_stone() -> void:
	var stone: int = _resources.get_amount("stone")
	if stone > _stone_before:
		_check(stone > _stone_before, "miner produced stone at relocated stone deposit (+%d)" % (stone - _stone_before))
		_enter(Phase.REGRESSION)
	elif _elapsed() >= 4000:
		_check(false, "miner production loop within timeout (stone=%d)" % stone)
		_enter(Phase.REGRESSION)


func _verify_regression() -> void:
	var cores := get_nodes_in_group("core_buildings")
	_check(cores.size() == 5, "5 core buildings present (%d)" % cores.size())
	var seen := {}
	for b in cores:
		seen[b.get_core_type()] = b.global_position
		_check(_layout.is_in_clearing(b.global_position), "%s inside central Core Village clearing" % b.name)
		_check(not _layout.is_on_access_axis(b.global_position), "%s not blocking a Main Road" % b.name)
	for t in CORE_TYPES:
		_check(seen.has(t), "core type %s present" % t)

	var start_pos := Vector2(0, 60)
	_check(_layout.is_in_clearing(start_pos), "settlement start point (0,+60) inside clearing")

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

	_check(_world.has_method("rebuild_navigation"), "world exposes rebuild_navigation")
	_world.rebuild_navigation()

	_check(_layout.get_bounds_rect().size == Vector2(2048, 2048), "bounds size 2048x2048")
	_check(_floor.get_used_cells().size() == 128 * 128, "floor covers 128x128 tiles")
	_check(_floor.get_cell_source_id(Vector2i(19, 0)) == 1, "east Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(0, 19)) == 1, "south Main Road reads as road")
	var game_time := root.get_node("GameTime")
	_check(game_time != null, "GameTime autoload exists")
	_check(game_time.get_phase() == game_time.Phase.DAY, "GameTime starts in DAY")
	_enter(Phase.DONE)


func _cluster_center(trees: Array) -> Vector2:
	if trees.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for t in trees:
		sum += t
	return sum / float(trees.size())


func _cluster_area(trees: Array) -> float:
	if trees.is_empty():
		return 1.0
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for t in trees:
		min_x = minf(min_x, t.x)
		max_x = maxf(max_x, t.x)
		min_y = minf(min_y, t.y)
		max_y = maxf(max_y, t.y)
	return maxf(1.0, (max_x - min_x) * (max_y - min_y))


func _cluster_distance(a: Array, b: Array) -> float:
	var best := INF
	for pa in a:
		for pb in b:
			best = minf(best, pa.distance_to(pb))
	return best


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
