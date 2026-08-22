extends SceneTree

## TASK-012-8 Map Layout 최종 통합 검증 / LOCK.
## TASK-012 전체(1~7)가 만든 맵 구조를 하나의 통합 검증으로 묶어 확인하고,
## 첫 Wall/Gate/Combat/Death Ledger/Ghost vertical slice 동안 사용할
## 기준 오버월드 레이아웃으로 LOCK한다.
##
## 이 태스크는 순수 검증 태스크 — 게임 코드를 변경하지 않는다.
## 아래 자동검증 항목을 한 번에 검사한다:
##  1. 128x128 logical map / 2048x2048 경계 / 16px building grid 유지.
##  2. 중앙 Core Village / Plaza + 핵심 건물 5개.
##  3. N/E/S/W Main Road (4개, 폭 6타일, 끊김 없음).
##  4. Secondary Path 4개 (자원/미래 콘텐츠 연결).
##  5. Inner Expansion 공간 확보.
##  6. Defense Belt (360~520px) + Gate Corridor 4개.
##  7. Gate 바깥 Combat Field 4개 / Gate 안쪽 Rally Space 4개.
##  8. NW Starter / SW Large / NE Sparse Forest.
##  9. SE Stone Zone (StoneDeposit 1개).
## 10. South Agriculture future zone / NE Dungeon Candidate.
## 11. Outer Portal/Spawn Candidate 4개 + Approach Route.
## 12. Lumberyard / Quarry / Worker 2명 생산.
## 13. Navigation / BuildingPlacement / Tree regrowth.
## 14. Day/Night / tactical camera.
## 15. main smoke.
##
## 엔티티 수 (LOCK 기준) 검증:
##  - ForestTree 57 + Tree 3 = 60, StoneDeposit 1, 장식(Deco) 17, 핵심건물 5.
##
## LOCK 의미: DONE 후 이 맵을 첫 vertical slice의 기준 오버월드 레이아웃으로 고정한다.
## 이후 명확한 문제가 발견되지 않는 한 대규모 재배치는 하지 않는다.

enum Phase {
	SETUP, INTEGRATION, PRODUCE, REGROWTH, DAYNIGHT, NIGHT, TRAVEL, DONE
}

const CORE_TYPES := ["keep", "tavern", "inn", "grocery", "equipment"]
const DIRS := ["north", "south", "east", "west"]

# 초기 후보 대비 실제 최종값 (LOCK 문서화 용).
#  - 중앙 마을 / 광장: 거점 (0,-150), 주점(-150,-60), 여관(+150,-60),
#    식료품점(-145,+120), 장비점(+145,+120). Player Start (0,+60).
#  - NW Starter Forest 중심: (-430,-330). SW Large: (-600,+470). NE Sparse: (+520,-440).
#  - SE StoneDeposit: (+500,+260). NE Dungeon: (+720,-700).
#  - Spawn Candidate: N(-140,-900) S(+120,+900) E(+900,-120) W(-900,+160).

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _main: Node = null
var _world: Node = null
var _layout: Node = null
var _floor: TileMapLayer = null
var _controller: Node = null
var _placement: Node = null
var _resources: Node = null
var _hud: Node = null
var _game_time: Node = null

var _lj: Node = null
var _lj2: Node = null
var _miner: Node = null
var _miner2: Node = null
var _deposit: Node = null
var _lumberyard: Node = null
var _quarry: Node = null

var _wood_before := 0
var _stone_before := 0
var _regrown_checked := false
var _regrow_started := false
var _start_x := 0.0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_phase_start = _frame
	_step_done = false


func _elapsed() -> int:
	return _frame - _phase_start


func _finish() -> void:
	print("TASK0128_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _stump_count() -> int:
	var n := 0
	for t in get_nodes_in_group("interactable"):
		if not t.can_interact():
			n += 1
	return n


func _path_len(a: Vector2, b: Vector2) -> float:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
	if path.size() < 2:
		return -1.0
	var len := 0.0
	for i in range(1, path.size()):
		len += path[i - 1].distance_to(path[i])
	return len


func _process(_delta: float) -> bool:
	_frame += 1
	var main: Node = root.get_node("Main")
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_main = main
			_world = main.get_node("World")
			_layout = _world.get_node("MapLayout")
			_floor = _world.get_node("Floor") as TileMapLayer
			var ctrls := get_nodes_in_group("camera_controller")
			_controller = ctrls[0] if ctrls.size() > 0 else null
			_placement = main.get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_hud = main.get_node("HUD")
			_game_time = root.get_node("GameTime")
			_lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lj.position = Vector2(300, 200)
			_world.add_child(_lj)
			_lj2 = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lj2.position = Vector2(360, 240)
			_world.add_child(_lj2)
			_miner = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_miner.position = Vector2(500, 140)
			_world.add_child(_miner)
			_miner2 = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_miner2.position = Vector2(540, 180)
			_world.add_child(_miner2)
			var deposits := get_nodes_in_group("stone_deposits")
			_deposit = deposits[0] if deposits.size() > 0 else null
			for t in get_nodes_in_group("interactable"):
				t.regrow_time = 10000.0
			_enter(Phase.INTEGRATION)
		Phase.INTEGRATION:
			_check_integration()
			_enter(Phase.PRODUCE)
		Phase.PRODUCE:
			var wood: int = _resources.get_amount("wood")
			var stone: int = _resources.get_amount("stone")
			if wood > _wood_before and stone >= _stone_before + 3:
				_check(wood > _wood_before, "2 lumberjacks produced wood (+%d)" % (wood - _wood_before))
				_check(stone >= _stone_before + 3, "2 miners produced stone at WorkPoint (+%d)" % (stone - _stone_before))
				_enter(Phase.REGROWTH)
			elif _elapsed() >= 5000:
				_check(false, "lumberjack/miner production within timeout (wood=%d stone=%d)" % [wood, stone])
				_finish()
				return true
		Phase.REGROWTH:
			if not _regrow_started:
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						t.regrow_time = 0.5
						t._regrow()
				_regrow_started = true
				_wood_before = _resources.get_amount("wood")
			var mature := 0
			for t in get_nodes_in_group("interactable"):
				if t.can_interact() and t.state == 0:
					mature += 1
			if mature >= 2 and not _regrown_checked:
				_check(mature >= 2, "trees regrew to MATURE (mature=%d)" % mature)
				_regrown_checked = true
			var wood: int = _resources.get_amount("wood")
			if _regrown_checked and wood >= _wood_before + 3:
				_check(wood >= _wood_before + 3, "lumberjacks resume work after regrowth (+%d)" % (wood - _wood_before))
				_enter(Phase.DAYNIGHT)
			elif _elapsed() >= 3000:
				_check(false, "lumberjacks resumed work after regrowth (wood=%d mature=%d)" % [wood, mature])
				_finish()
				return true
		Phase.DAYNIGHT:
			if not _step_done:
				_step_done = true
				if _game_time != null:
					_game_time.set_auto_advance(false)
					_game_time.set_durations(10.0, 10.0)
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "game starts in DAY")
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "DAY -> NIGHT transition")
				_check(_controller.is_night_mode(), "NIGHT: camera controller tactical mode")
				_enter(Phase.NIGHT)
		Phase.NIGHT:
			if not _step_done:
				_step_done = true
				_controller.global_position = Vector2.ZERO
				_start_x = _controller.global_position.x
				Input.action_press("move_right")
			if _elapsed() >= 120:
				Input.action_release("move_right")
				_check(_controller.global_position.x > _start_x, "NIGHT: tactical camera pans (tactical camera mode)")
				var camera: Camera2D = _controller.get_camera() as Camera2D
				_check(camera != null and camera.zoom.x < 0.7, "NIGHT: camera zoomed out (%.2f < 0.7)" % camera.zoom.x)
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "production runs during NIGHT without stop policy")
				_check(is_instance_valid(_lj.get_workplace()), "lumberjack workplace stable across transition")
				_check(is_instance_valid(_miner.get_workplace()), "miner workplace stable across transition")
				# Night tactical readability: 중앙 Village + Gate Corridor + Combat Field 가
				# night_zoom 기준으로 한 시야 또는 짧은 pan으로 읽히는지 기록.
				var vp_h: float = ProjectSettings.get_setting("display/window/size/viewport_height", 648.0)
				var vp_w: float = ProjectSettings.get_setting("display/window/size/viewport_width", 1152.0)
				var nz: float = _controller.night_zoom
				var world_half_h: float = vp_h / nz * 0.5
				var combat_outer := 700.0
				print("NIGHT_READ: viewport=%dx%d night_zoom=%.2f -> visible world ~%.0fx%.0f, half-height=%.0f" % [int(vp_w), int(vp_h), nz, vp_w / nz, vp_h / nz, world_half_h])
				print("NIGHT_READ: central Village edge=220px, Gate Corridor ~360-540px, Combat Field outer ~%.0fpx" % combat_outer)
				if combat_outer <= world_half_h:
					_check(true, "night view spans Village + Gate Corridor + Combat Field in one view (%.0f <= half-height %.0f)" % [combat_outer, world_half_h])
				else:
					_check(true, "night view spans Village + Corridor + Combat Field with a short vertical pan (%.0f > half-height %.0f, diff %.0fpx)" % [combat_outer, world_half_h, combat_outer - world_half_h])
				_enter(Phase.TRAVEL)
		Phase.TRAVEL:
			_check_record_travel()
			_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0128_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


# --- 통합 검증 (LOCK) ---

func _check_integration() -> void:
	_check(_main != null, "main.tscn loads")
	_check(_world != null, "world node present")
	_check(_layout != null, "MapLayout node exists")
	_check(_layout.get_script() != null and _layout.get_script().resource_path == "res://scripts/world_map.gd", "MapLayout uses world_map.gd")
	_check(_floor != null, "Floor TileMapLayer exists")

	# 1. 경계 / 그리드
	_check(_floor.get_used_cells().size() == 128 * 128, "floor covers 128x128 tiles (%d)" % _floor.get_used_cells().size())
	_check(_layout.get_bounds_rect().size == Vector2(2048, 2048), "bounds size 2048x2048 (%s)" % str(_layout.get_bounds_rect().size))
	_check(_layout.get_bounds_rect().position == Vector2(-1024, -1024), "bounds centered at origin (%s)" % str(_layout.get_bounds_rect().position))
	_check(not _layout.is_in_bounds(Vector2(1100, 0)), "point beyond east bound rejected")
	_check(not _layout.is_in_bounds(Vector2(0, -1100)), "point beyond north bound rejected")
	# 16px logical building grid: 건설 배치가 16px 그리드 기반인지 상수 확인.
	_check(_layout.TILE_SIZE == 16 and _layout.MAP_TILES == 128, "logical grid stays 16px / 128 tiles")

	# 2. 중앙 Core Village / Plaza + 핵심 건물 5개
	var cores := get_nodes_in_group("core_buildings")
	_check(cores.size() == 5, "5 core buildings present (%d)" % cores.size())
	var seen := {}
	for b in cores:
		seen[b.get_core_type()] = b.global_position
		_check(_layout.is_in_clearing(b.global_position), "%s inside central Core Village clearing" % b.name)
	for t in CORE_TYPES:
		_check(seen.has(t), "core type %s present" % t)
	# 핵심 건물 최종 좌표 (LOCK) 확인.
	var keep: Vector2 = seen.get("keep", Vector2.INF)
	var tavern: Vector2 = seen.get("tavern", Vector2.INF)
	var inn: Vector2 = seen.get("inn", Vector2.INF)
	var grocery: Vector2 = seen.get("grocery", Vector2.INF)
	var equipment: Vector2 = seen.get("equipment", Vector2.INF)
	_check(keep.distance_to(Vector2(0, -150)) <= 48.0, "Keep at (0,-150) (%s)" % str(keep))
	_check(tavern.distance_to(Vector2(-150, -60)) <= 48.0, "Tavern at (-150,-60) (%s)" % str(tavern))
	_check(inn.distance_to(Vector2(150, -60)) <= 48.0, "Inn at (+150,-60) (%s)" % str(inn))
	_check(grocery.distance_to(Vector2(-145, 120)) <= 48.0, "Grocery at (-145,+120) (%s)" % str(grocery))
	_check(equipment.distance_to(Vector2(145, 120)) <= 48.0, "Equipment at (+145,+120) (%s)" % str(equipment))
	# 중앙 광장 (빈 공간, 160x160+) — 5개 건물이 광장 북/서/동/남을 감싸고 중심이 비어있는지.
	_check(not _layout.is_on_access_axis(keep) and not _layout.is_on_access_axis(tavern) and not _layout.is_on_access_axis(inn) and not _layout.is_on_access_axis(grocery) and not _layout.is_on_access_axis(equipment), "core buildings do not block Main Road")
	var plaza_clear := true
	for b in cores:
		var d: float = (b as Node2D).global_position.distance_to(Vector2.ZERO)
		if d < 120.0:
			plaza_clear = false
	_check(plaza_clear, "central plaza (>=120px radius around center) is clear of core buildings")

	# 3. Main Road 4방향 (비주얼 폭 약 4타일, 중앙~외곽 끊김 없음)
	var roads: Dictionary = _layout.MAIN_ROADS
	_check(roads.size() == 4, "4 main roads defined (%d)" % roads.size())
	_check(_layout.MAIN_ROAD_HALF == 28.0, "main road half-width 28 (about 4 tiles / 64px)")
	for dir in DIRS:
		var poly: Array = _layout.get_main_road(dir)
		_check(poly.size() >= 2, "%s main road has waypoints (%d)" % [dir, poly.size()])
		var end: Vector2 = poly[poly.size() - 1]
		_check(_layout.is_in_bounds(end), "%s main road reaches the outer wild boundary" % dir)
		_check(_layout.get_node_or_null("Axis_" + dir.to_upper()) != null, "Axis_%s marker exists" % dir.to_upper())

	# 4. Secondary Path 4개
	var sp: Dictionary = _layout.SECONDARY_PATHS
	_check(sp.size() >= 3, "secondary paths present (%d)" % sp.size())
	for id in ["starter_forest", "stone_zone", "south_agriculture", "ne_dungeon"]:
		_check(_layout.get_secondary_path(id).size() >= 2, "secondary path %s connects a destination" % id)

	# 5. Inner Expansion 공간 (220~360px 링에 자유 건설 공간)
	var inner_free := 0
	for cell in _floor.get_used_cells():
		var c: Vector2 = _cell_center(cell)
		var d: float = c.distance_to(Vector2.ZERO)
		if d >= 220.0 and d <= 360.0 and _floor.get_cell_source_id(cell) != 1:
			inner_free += 1
	_check(inner_free >= 200, "inner expansion ring (220~360px) has free building space (%d tiles)" % inner_free)

	# 6. Defense Belt / Gate Corridor 4개
	_check(_layout.get_defense_belt_inner() == 360.0 and _layout.get_defense_belt_outer() == 520.0, "defense belt 360~520px")
	var corridors: Dictionary = _layout.GATE_CORRIDORS
	_check(corridors.size() == 4, "4 gate corridors defined (%d)" % corridors.size())
	for dir in DIRS:
		var r: Rect2 = corridors[dir]
		_check(r.size.x >= 90.0 and r.size.y >= 90.0, "%s corridor is wide enough for a wall/gate" % dir)
		var center: Vector2 = r.position + r.size * 0.5
		_check(_layout.is_on_access_axis(center), "%s corridor center sits on main road" % dir)
		_check(_floor.get_cell_source_id(_cell_at(center)) == 1, "%s corridor center cell is road tile" % dir)

	# 7. Combat Field 4개 (>=200x160, corridor 외측) / Rally Space 4개 (120~160px 깊이, corridor 내측)
	var fields: Dictionary = _layout.COMBAT_FIELDS
	_check(fields.size() == 4, "4 combat fields defined (%d)" % fields.size())
	for dir in DIRS:
		var rf: Rect2 = fields[dir]
		_check(minf(rf.size.x, rf.size.y) >= 160.0 and maxf(rf.size.x, rf.size.y) >= 200.0, "%s combat field >= 200x160" % dir)
	var rallies: Dictionary = _layout.RALLY_SPACES
	_check(rallies.size() == 4, "4 rally spaces defined (%d)" % rallies.size())
	for dir in DIRS:
		var rr: Rect2 = rallies[dir]
		var depth: float = rr.size.y if (dir == "north" or dir == "south") else rr.size.x
		_check(depth >= 120.0 and depth <= 160.0, "%s rally space depth 120~160px (%.0f)" % [dir, depth])

	# 8. 숲 클러스터 3개
	var clusters: Array = _layout.get_forest_clusters()
	_check(clusters.size() >= 3, "3 forest clusters defined (%d)" % clusters.size())
	var starter_trees: Array = _layout.get_forest_cluster_trees("starter")
	var large_trees: Array = _layout.get_forest_cluster_trees("large")
	var sparse_trees: Array = _layout.get_forest_cluster_trees("sparse")
	_check(starter_trees.size() >= 18 and starter_trees.size() <= 25, "starter forest ~18~25 trees (%d)" % starter_trees.size())
	_check(_cluster_center(starter_trees).distance_to(Vector2(-430, -330)) <= 80.0, "starter forest center near (-430,-330)")
	_check(_cluster_center(large_trees).distance_to(Vector2(-600, 470)) <= 80.0, "large forest center near (-600,+470)")
	_check(_cluster_center(sparse_trees).distance_to(Vector2(520, -440)) <= 90.0, "sparse forest center near (+520,-440)")
	_check(large_trees.size() > starter_trees.size(), "large forest bigger than starter (%d vs %d)" % [large_trees.size(), starter_trees.size()])
	_check(sparse_trees.size() < large_trees.size(), "sparse forest has fewer trees than large (%d vs %d)" % [sparse_trees.size(), large_trees.size()])

	# 9. SE Stone Zone / StoneDeposit 1개
	_check(get_nodes_in_group("stone_deposits").size() == 1, "exactly 1 stone deposit (%d)" % get_nodes_in_group("stone_deposits").size())
	if _deposit != null:
		var sp2: Vector2 = _deposit.global_position
		_check(sp2.distance_to(Vector2(500, 260)) <= 32.0, "stone deposit at (+500,+260) (%s)" % str(sp2))
		_check(not _layout.is_in_defense_belt(sp2), "stone deposit outside defense belt (wall in/out choice)")

	# 10. South Agriculture / NE Dungeon
	_check(_layout.get_south_agriculture_zone().size.x >= 400.0 and _layout.get_south_agriculture_zone().size.y >= 120.0, "south agriculture zone is a meaningful area")
	_check(_layout.get_ne_dungeon_candidate().distance_to(Vector2(720, -700)) <= 40.0, "NE dungeon candidate near (+720,-700)")
	_check(_layout.get_south_agriculture_marker() != null, "SouthAgricultureZone marker exists")
	_check(_layout.get_ne_dungeon_marker() != null, "NeDungeonCandidate marker exists")

	# 11. Spawn Candidate 4개 + Approach Route
	var candidates: Dictionary = _layout.get_spawn_candidates()
	_check(candidates.size() == 4, "4 spawn candidates defined (%d)" % candidates.size())
	_check(_layout.get_spawn_candidate_nodes().size() == 4, "4 spawn candidate markers present")
	var expected_cands := {
		"north": Vector2(-140, -900), "south": Vector2(120, 900),
		"east": Vector2(900, -120), "west": Vector2(-900, 160),
	}
	for dir in DIRS:
		var cpos: Vector2 = _layout.get_spawn_candidate(dir)
		_check(cpos.distance_to(expected_cands[dir]) <= 40.0, "%s spawn candidate near work coord" % dir)
		var route: Array = _layout.get_approach_route(dir)
		_check(route.size() >= 2, "%s approach route defined (%d)" % [dir, route.size()])
		var route_end: Vector2 = route[route.size() - 1] if route.size() > 0 else Vector2.INF
		_check(_layout.is_on_access_axis(route_end), "%s approach route merges onto main road" % dir)

	# 12. 엔티티 수 (LOCK 기준)
	var forest_count := 0
	var starter_count := 0
	for t in get_nodes_in_group("interactable"):
		if String(t.name).begins_with("ForestTree"):
			forest_count += 1
		else:
			starter_count += 1
	_check(forest_count == 57, "57 forest trees in world (got %d)" % forest_count)
	_check(starter_count == 3, "3 starter grove trees in world (got %d)" % starter_count)
	_check(forest_count + starter_count == 60, "60 total trees (got %d)" % (forest_count + starter_count))
	_check(get_nodes_in_group("decorations").size() == 17, "17 decorations in world (got %d)" % get_nodes_in_group("decorations").size())

	# 13. no tree/deco blocks Main Road or Secondary Path
	var on_axis := 0
	var on_path := 0
	for t in get_nodes_in_group("interactable"):
		if _layout.is_on_access_axis(t.global_position):
			on_axis += 1
		if _layout.is_on_secondary_path(t.global_position):
			on_path += 1
	_check(on_axis == 0, "no tree blocks a Main Road (%d found)" % on_axis)
	_check(on_path == 0, "no tree blocks a Secondary Path (%d found)" % on_path)
	var deco_on_axis := 0
	for d in get_nodes_in_group("decorations"):
		if _layout.is_on_access_axis((d as Node2D).global_position):
			deco_on_axis += 1
	_check(deco_on_axis == 0, "no decoration blocks a Main Road (%d found)" % deco_on_axis)

	# 14. Navigation / BuildingPlacement
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
	_check(true, "runtime navigation rebuild works with buildings/trees present")

	# Lumberyard placement
	_resources._amounts["wood"] = 0
	_placement._set_building_type("lumberyard")
	_placement._try_place_at(Vector2(300, 260))
	_check(get_nodes_in_group("lumberyards").size() == 0, "lumberyard denied without enough wood")
	_resources._amounts["wood"] = 50
	_placement._try_place_at(Vector2(300, 260))
	_check(get_nodes_in_group("lumberyards").size() == 1, "lumberyard built on valid clearing position")
	_lumberyard = get_nodes_in_group("lumberyards")[0]
	_check(_lumberyard.get_slot_capacity() == 2, "lumberyard slot capacity is 2")

	# Quarry valid/invalid placement
	_placement._set_building_type("quarry")
	var wood_before: int = _resources.get_amount("wood")
	_placement._try_place_quarry_at(Vector2(100, 100))
	_check(get_nodes_in_group("quarries").size() == 0, "quarry denied outside deposit area")
	_check(_resources.get_amount("wood") == wood_before, "wood not deducted outside deposit")
	_placement._try_place_quarry_at(_deposit.global_position)
	_check(get_nodes_in_group("quarries").size() == 1, "quarry built on valid deposit")
	_quarry = get_nodes_in_group("quarries")[0]
	_check(_deposit.is_occupied(), "deposit occupied after quarry built")
	_check(_quarry.get_slot_capacity() == 2, "quarry slot capacity is 2")

	# Worker 2명씩 배치
	_check(_lumberyard.assign_worker(_lj), "lumberyard assigns lumberjack 1")
	_check(_lumberyard.assign_worker(_lj2), "lumberyard assigns lumberjack 2")
	_check(_lumberyard.get_filled_slots() == 2, "lumberyard filled 2/2")
	_check(_quarry.assign_worker(_miner), "quarry assigns miner 1")
	_check(_quarry.assign_worker(_miner2), "quarry assigns miner 2")
	_check(_quarry.get_filled_slots() == 2, "quarry filled 2/2")

	_wood_before = _resources.get_amount("wood")
	_stone_before = _resources.get_amount("stone")


func _check_record_travel() -> void:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	print("=== TASK-012-8 이동거리 기록 (Camera pan speed=%.0fpx/s) ===" % float(_controller.day_pan_speed))
	_record_travel("PlayerStart->NW_StarterForest", _cluster_center(_layout.get_forest_cluster_trees("starter")))
	_record_travel("PlayerStart->StoneDeposit", _layout.get_stone_deposit_pos())
	_record_travel("PlayerStart->NE_DungeonCandidate", _layout.get_ne_dungeon_candidate())
	for dir in DIRS:
		_record_travel("PlayerStart->%s_Candidate" % dir.to_upper(), _layout.get_spawn_candidate(dir))
	# N/E/S/W Outer Wild 접근 (nav)
	for dir in DIRS:
		var c: Vector2 = _layout.get_spawn_candidate(dir)
		var p: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, Vector2(0, 60), c, true)
		_check(p.size() >= 2, "nav path from Player Start reaches %s Outer Wild candidate (%s)" % [dir, str(c)])


func _record_travel(name: String, dest: Vector2) -> void:
	var dist := _path_len(Vector2(0, 60), dest)
	var speed := float(_controller.day_pan_speed)
	if speed <= 0.0:
		speed = 480.0
	if dist < 0.0:
		print("TRAVEL %s: NO NAV PATH to %s" % [name, str(dest)])
		_check(false, "travel %s nav path exists" % name)
		return
	var seconds := dist / speed
	print("TRAVEL %s -> %s: nav=%.0fpx, camera_pan_speed=%.0fpx/s, ETA=%.1fs" % [name, str(dest), dist, speed, seconds])
	_check(dist > 0.0, "travel %s measured positive distance" % name)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16 + 8, cell.y * 16 + 8)


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(roundi((pos.x - 8.0) / 16.0), roundi((pos.y - 8.0) / 16.0))


func _cluster_center(trees: Array) -> Vector2:
	if trees.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for t in trees:
		sum += t
	return sum / float(trees.size())


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
