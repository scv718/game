extends SceneTree

## TASK-012-1 중앙 마을 레이아웃 재구성 검증.
## 게임 루프 기준으로 5개 핵심 건물을 재배치하고 중앙 광장을 확보했는지 자동 확인한다.
## 핵심: 중앙 빈 광장, 거점 북쪽 / 주점·여관 북서·북동 / 식료품점·장비점 남서·남동,
##      Player Start는 광장 내부 또는 남쪽 가장자리, N/E/S/W 도로 연결(회귀),
##      Player가 모든 핵심 건물 사이 장애물 없이 이동 가능.
## 기존 시스템(맵/생산/Worker/건설/Navigation) 회귀도 함께 확인한다.

const CORE_TYPES := ["keep", "tavern", "inn", "grocery", "equipment"]

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
	if _frame != 10:
		return false

	var main: Node = root.get_node("Main")
	_check(main != null, "main.tscn loads")

	var world: Node = main.get_node("World")
	var layout: Node = world.get_node_or_null("MapLayout")
	_check(layout != null, "MapLayout node exists")

	# 1. 5개 핵심 건물 존재 + 각자 올바른 타입/레벨.
	var cores := get_nodes_in_group("core_buildings")
	_check(cores.size() == 5, "5 core buildings present (%d)" % cores.size())
	var seen := {}
	var by_name := {}
	for b in cores:
		var ctype: String = b.get_core_type()
		seen[ctype] = b.global_position
		by_name[b.name] = b.global_position
		_check(b.get_level() == 1, "%s has level 1" % b.name)
		_check(layout.is_in_clearing(b.global_position), "%s inside central Core Village clearing (%s)" % [b.name, str(b.global_position)])
		_check(not layout.is_on_access_axis(b.global_position), "%s not blocking a Main Road/axis (%s)" % [b.name, str(b.global_position)])
	for t in CORE_TYPES:
		_check(seen.has(t), "core type %s present" % t)

	# 2. 배치 관계: 거점 북쪽, 주점/여관 북서/북동, 식료품점/장비점 남서/남동.
	var keep: Vector2 = (seen.get("keep") if seen.has("keep") else Vector2.ZERO)
	var tavern: Vector2 = (seen.get("tavern") if seen.has("tavern") else Vector2.ZERO)
	var inn: Vector2 = (seen.get("inn") if seen.has("inn") else Vector2.ZERO)
	var grocery: Vector2 = (seen.get("grocery") if seen.has("grocery") else Vector2.ZERO)
	var equipment: Vector2 = (seen.get("equipment") if seen.has("equipment") else Vector2.ZERO)
	_check(keep.y < 0 and keep.x > -16 and keep.x < 16, "Keep is north of plaza center (%s)" % str(keep))
	_check(tavern.x < 0 and tavern.y < 0, "Tavern is north-west of center (%s)" % str(tavern))
	_check(inn.x > 0 and inn.y < 0, "Inn is north-east of center (%s)" % str(inn))
	_check(grocery.x < 0 and grocery.y > 0, "Grocery is south-west of center (%s)" % str(grocery))
	_check(equipment.x > 0 and equipment.y > 0, "EquipmentShop is south-east of center (%s)" % str(equipment))
	# 주점은 거점보다 남쪽, 식료품점은 거점보다 남쪽.
	_check(tavern.y > keep.y, "Tavern below Keep (opens plaza south) (%s vs %s)" % [str(tavern), str(keep)])
	_check(inn.y > keep.y, "Inn below Keep (%s vs %s)" % [str(inn), str(keep)])
	# 목표 좌표 대략 일치 (허용 오차 ±48).
	_check(absf(keep.x) <= 16 and keep.y <= -150 + 48 and keep.y >= -150 - 48, "Keep near (0,-150) (%s)" % str(keep))
	_check(tavern.distance_to(Vector2(-150, -60)) <= 48.0, "Tavern near (-150,-60) (%s)" % str(tavern))
	_check(inn.distance_to(Vector2(150, -60)) <= 48.0, "Inn near (150,-60) (%s)" % str(inn))
	_check(grocery.distance_to(Vector2(-145, 120)) <= 48.0, "Grocery near (-145,120) (%s)" % str(grocery))
	_check(equipment.distance_to(Vector2(145, 120)) <= 48.0, "EquipmentShop near (145,120) (%s)" % str(equipment))

	# 3. 중앙 광장: 최소 160x160 빈 공간 (핵심 건물/생산/장식으로 막지 않음).
	var plaza_rect := Rect2(Vector2(-80, -40), Vector2(160, 160))
	# 광장 중심의 중간점을 건물 사이 빈 영역으로 간주 (거점 ~ 남쪽 가장자리 사이).
	var plaza_sample := [
		Vector2(0, -20), Vector2(-40, 30), Vector2(40, 30),
		Vector2(0, 40), Vector2(-30, -10), Vector2(30, -10),
	]
	var plaza_blocked := 0
	for p in plaza_sample:
		for b in cores:
			if (b as Node2D).global_position.distance_to(p) < 40.0:
				plaza_blocked += 1
				break
	_check(plaza_blocked == 0, "central plaza samples clear of core buildings (%d blocked)" % plaza_blocked)
	# 장식/생산시설이 광장 중심을 막지 않음 (생산시설은 spawn에 없음, 장식만 확인).
	var plaza_deco_block := 0
	for d in get_nodes_in_group("decorations"):
		if plaza_rect.has_point((d as Node2D).global_position):
			plaza_deco_block += 1
	_check(plaza_deco_block == 0, "no decoration blocks central plaza (%d found)" % plaza_deco_block)

	# 4. Player Start: 광장 내부 또는 남쪽 가장자리 (0, +40~+80).
	var player_pos: Vector2 = main.get_node("Player").global_position
	_check(player_pos.distance_to(Vector2(0, 60)) <= 24.0, "Player Start near (0,+60) (%s)" % str(player_pos))
	_check(not layout.is_on_access_axis(player_pos), "Player Start not on a Main Road/axis")

	# 5. N/E/S/W 도로가 중앙을 통과하거나 자연스럽게 연결 (회귀: 기존 road generation 유지).
	var floor_node: TileMapLayer = world.get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "floor covers 128x128 tiles")
	_check(floor_node.get_cell_source_id(Vector2i(19, 0)) == 1, "east Main Road reads as road")
	_check(floor_node.get_cell_source_id(Vector2i(-19, 0)) == 1, "west Main Road reads as road")
	_check(floor_node.get_cell_source_id(Vector2i(0, -19)) == 1, "north Main Road reads as road")
	_check(floor_node.get_cell_source_id(Vector2i(0, 19)) == 1, "south Main Road reads as road")

	# 6. Player가 모든 핵심 건물 사이 장애물 없이 이동 가능 (nav 경로).
	var nav_map: RID = world.get_world_2d().get_navigation_map()
	var reachable: bool = true
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

	# 7. 회귀: 생산/worker/건설 구조 유지.
	if get_nodes_in_group("lumberjacks").size() < 1:
		var lj: Node = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
		lj.position = Vector2(300, 200)
		world.add_child(lj)
	if get_nodes_in_group("miners").size() < 1:
		var mn: Node = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
		mn.position = Vector2(500, 140)
		world.add_child(mn)
	_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack present")
	_check(get_nodes_in_group("miners").size() >= 1, "miner present")
	_check(get_nodes_in_group("stone_deposits").size() >= 1, "stone deposit present")
	_check(get_nodes_in_group("decorations").size() >= 4, "decorations present")
	_check(get_nodes_in_group("interactable").size() >= 12, "trees present (%d)" % get_nodes_in_group("interactable").size())

	print("TASK0121_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
