extends SceneTree

## TASK-012-3 Defense Belt + Gate Corridor 공간 확정 검증.
## 자유 성벽 배치를 위한 Defense Belt(360~520px)와 각 Main Road 교차 허용 구간인
## Gate Corridor, Gate 바깥 Combat Field(>=200x160), Gate 안쪽 Rally Space(120~160px)가
## 레벨디자인상 확보되어 있는지 자동 확인한다. 실제 Gate/Wall 기능은 구현하지 않는다.
##
## 검증 항목:
##   1. Defense Belt 상수(360/520) 정의 + is_in_defense_belt 동작.
##   2. Gate Corridor 4개 Rect2 정의 (N/S/E/W) 및 좌표 확인.
##   3. Combat Field 4개 (최소 200x160).
##   4. Rally Space 4개 (깊이 120~160px).
##   5. Corridor/Combat/Rally 안에 blocking 오브젝트(StoneDeposit/핵심건물/경계벽/대형 숲) 부재.
##   6. GateCorridor/CombatField/RallySpace Marker 존재 (비기능).
##   7. 기존 회귀 (도로/floor/핵심건물/생산/Worker/Navigation/DayNight/marker 구조).

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

	_check_defense_belt()
	_check_gate_corridors()
	_check_combat_fields()
	_check_rally_spaces()
	_check_zone_clearances()
	_check_markers()
	_check_regression()

	print("TASK0123_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _check_defense_belt() -> void:
	var inner: float = _layout.get_defense_belt_inner()
	var outer: float = _layout.get_defense_belt_outer()
	_check(inner == 380.0, "defense belt inner radius 380 (%s)" % str(inner))
	_check(outer == 640.0, "defense belt outer radius 640 (%s)" % str(outer))
	_check(_layout.is_in_defense_belt(Vector2(0, 400)), "point at 400px is in defense belt")
	_check(_layout.is_in_defense_belt(Vector2(340, 320)), "SE starter tree zone is in belt band (dist 467)")
	_check(not _layout.is_in_defense_belt(Vector2(0, 300)), "300px is inner expansion, not belt")
	_check(not _layout.is_in_defense_belt(Vector2(0, 700)), "700px is production belt, not defense belt")


func _check_gate_corridors() -> void:
	var corridors: Dictionary = _layout.GATE_CORRIDORS
	_check(corridors.size() == 4, "4 gate corridors defined (%d)" % corridors.size())
	var expected := {
		"north": Rect2(-48, -540, 96, 190),
		"south": Rect2(-48, 350, 96, 190),
		"west": Rect2(-540, -48, 190, 96),
		"east": Rect2(350, -48, 190, 96),
	}
	for dir in expected:
		var r: Rect2 = corridors.get(dir, Rect2())
		_check(r == expected[dir], "%s gate corridor rect matches spec (%s)" % [dir, str(r)])
		_check(r.size.x >= 90.0 and r.size.y >= 90.0, "%s corridor is wide enough for a wall/gate" % dir)
		# Corridor 중심이 Main Road 위에 있는지 (도로와 교차하는 허용 구간).
		var center: Vector2 = r.position + r.size * 0.5
		_check(_layout.is_on_access_axis(center), "%s corridor center sits on main road (%s)" % [dir, str(center)])
	# 각 corridor에 road 타일이 실제로 깔려 있는지 (Gate가 도로와 만나는 구간).
	for dir in corridors:
		var r: Rect2 = corridors[dir]
		var center: Vector2 = r.position + r.size * 0.5
		var cell := _cell_at(center)
		_check(_floor.get_cell_source_id(cell) == 1, "%s corridor center cell is road tile (%s)" % [dir, str(cell)])


func _check_combat_fields() -> void:
	var fields: Dictionary = _layout.COMBAT_FIELDS
	_check(fields.size() == 4, "4 combat fields defined (%d)" % fields.size())
	for dir in fields:
		var r: Rect2 = fields[dir]
		var min_dim: float = minf(r.size.x, r.size.y)
		var max_dim: float = maxf(r.size.x, r.size.y)
		_check(min_dim >= 160.0 and max_dim >= 200.0, "%s combat field covers >= 200x160 (%s)" % [dir, str(r.size)])
		# Combat Field가 corridor 바깥(외측)에 위치하는지.
		match dir:
			"north":
				_check(r.position.y + r.size.y <= -540.0, "north combat field is beyond corridor outer edge")
			"south":
				_check(r.position.y >= 540.0, "south combat field is beyond corridor outer edge")
			"west":
				_check(r.position.x + r.size.x <= -540.0, "west combat field is beyond corridor outer edge")
			"east":
				_check(r.position.x >= 540.0, "east combat field is beyond corridor outer edge")
		_check(_layout.is_in_bounds(r.position) and _layout.is_in_bounds(r.end), "%s combat field inside map bounds" % dir)


func _check_rally_spaces() -> void:
	var spaces: Dictionary = _layout.RALLY_SPACES
	_check(spaces.size() == 4, "4 rally spaces defined (%d)" % spaces.size())
	for dir in spaces:
		var r: Rect2 = spaces[dir]
		var depth: float = 0.0
		match dir:
			"north", "south":
				depth = r.size.y
			"west", "east":
				depth = r.size.x
		_check(depth >= 120.0 and depth <= 160.0, "%s rally space depth 120~160px (%.0f)" % [dir, depth])
		# Rally Space가 corridor 안쪽(내측, 마을 방향)에 위치하는지.
		match dir:
			"north":
				_check(r.position.y >= -350.0 and r.end.y <= 0.0, "north rally space is inside corridor inner edge")
			"south":
				_check(r.position.y >= 0.0 and r.end.y <= 350.0, "south rally space is inside corridor inner edge")
			"west":
				_check(r.position.x >= -350.0 and r.end.x <= 0.0, "west rally space is inside corridor inner edge")
			"east":
				_check(r.position.x >= 0.0 and r.end.x <= 350.0, "east rally space is inside corridor inner edge")
		_check(_layout.is_in_bounds(r.position) and _layout.is_in_bounds(r.end), "%s rally space inside map bounds" % dir)


func _check_zone_clearances() -> void:
	# blocking 오브젝트: StoneDeposit / 핵심건물 / 경계벽 / 대형 숲(ForestTree) / 장식은
	# 충돌이 없어 배치/내비게이션을 막지 않으므로 대상에서 제외.
	var block_objs: Array[Node2D] = []
	for d in get_nodes_in_group("stone_deposits"):
		block_objs.append(d)
	for b in get_nodes_in_group("core_buildings"):
		block_objs.append(b)
	for wn in ["BoundaryWall_North", "BoundaryWall_South", "BoundaryWall_East", "BoundaryWall_West"]:
		var wall := _world.get_node_or_null(wn) as Node2D
		if wall != null:
			block_objs.append(wall)
	for t in get_nodes_in_group("interactable"):
		if String(t.name).begins_with("ForestTree"):
			block_objs.append(t)
	# starter tree(Tree1/2/3)는 벌목 가능한 소형 자원이므로 corridor/combat/rally 안에 없기만 하면 됨.
	var starter_trees: Array[Node2D] = []
	for t in get_nodes_in_group("interactable"):
		if not String(t.name).begins_with("ForestTree"):
			starter_trees.append(t)

	var corridor_count := 0
	var combat_count := 0
	var rally_count := 0
	for obj in block_objs:
		var p: Vector2 = obj.global_position
		if _layout.is_in_gate_corridor(p):
			corridor_count += 1
		if _layout.is_in_combat_field(p):
			combat_count += 1
		if _layout.is_in_rally_space(p):
			rally_count += 1
	_check(corridor_count == 0, "no blocking obstacle inside any gate corridor (%d)" % corridor_count)
	_check(combat_count == 0, "no blocking obstacle inside any combat field (%d)" % combat_count)
	_check(rally_count == 0, "no blocking obstacle inside any rally space (%d)" % rally_count)

	# starter tree가 corridor 안에 없어야 함 (Gate 설치 공간 보존).
	var starter_in_corridor := 0
	for t in starter_trees:
		if _layout.is_in_gate_corridor(t.global_position):
			starter_in_corridor += 1
	_check(starter_in_corridor == 0, "no starter tree blocks a gate corridor (%d)" % starter_in_corridor)


func _check_markers() -> void:
	_check(_layout.get_gate_corridor_nodes().size() >= 4, "gate corridor markers present (%d)" % _layout.get_gate_corridor_nodes().size())
	_check(_layout.get_combat_field_nodes().size() >= 4, "combat field markers present (%d)" % _layout.get_combat_field_nodes().size())
	_check(_layout.get_rally_space_nodes().size() >= 4, "rally space markers present (%d)" % _layout.get_rally_space_nodes().size())
	for dir in ["north", "south", "east", "west"]:
		var u: String = dir.to_upper()
		_check(_layout.get_node_or_null("GateCorridor_" + u) != null, "GateCorridor_%s marker exists" % u)
		_check(_layout.get_node_or_null("CombatField_" + u) != null, "CombatField_%s marker exists" % u)
		_check(_layout.get_node_or_null("RallySpace_" + u) != null, "RallySpace_%s marker exists" % u)


func _check_regression() -> void:
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

	# 도로/floor 회귀.
	_check(_floor.get_used_cells().size() == 192 * 192, "floor covers 192x192 tiles")
	_check(_floor.get_cell_source_id(Vector2i(19, 0)) == 1, "east Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(-19, 0)) == 1, "west Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(0, -19)) == 1, "north Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(0, 19)) == 1, "south Main Road reads as road")

	# 숲/장식이 Main Road를 막지 않음.
	var on_axis := 0
	for t in get_nodes_in_group("interactable"):
		if _layout.is_on_access_axis(t.global_position):
			on_axis += 1
	_check(on_axis == 0, "no tree blocks a main road (%d found)" % on_axis)
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
	_check(_layout.get_bounds_rect().size == Vector2(3072, 3072), "bounds size 3072x3072")
	_check(_layout.get_nav_rect().size == Vector2(3072 - 64, 3072 - 64), "nav rect inset 32px")

	# Day/Night 기본 상태 회귀.
	var game_time := root.get_node("GameTime")
	_check(game_time != null, "GameTime autoload exists")
	_check(game_time.get_phase() == game_time.Phase.DAY, "GameTime starts in DAY (%s)" % str(game_time.get_phase_name()))


## 월드 좌표 -> 해당 셀 좌표 (16px 논리 타일).
func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(roundi((pos.x - 8.0) / 16.0), roundi((pos.y - 8.0) / 16.0))


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)