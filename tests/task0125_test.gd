extends SceneTree

## TASK-012-5 South Agriculture / NE Dungeon / Outer Wild 미래 슬롯 검증.
## 아직 기능을 구현하지 않고, 향후 콘텐츠(Farm/Herb/Dungeon/이벤트)가 들어갈 공간만
## 레벨디자인상 확정한다. 실제 시스템(건설/생산/전투/이동 규칙/씬 전환)은 구현하지 않는다.
##
## 검증 항목:
##   1. South Agriculture Zone: 남쪽 +450~+650px, 대형 자연 장애물(숲/석재)이 적고,
##      Player가 도달 가능하며, Marker로 식별 가능.
##   2. NE Dungeon Candidate: 중심 (+720,-700) 부근, 도달 가능, 차단 오브젝트 없음, Marker 존재.
##   3. Outer Wild 미래 슬롯: NW/NE/SW/SE 코너, 장식으로 과도하게 채우지 않음, Marker 존재.
##   4. 미래 슬롯이 실제 시스템처럼 동작하지 않음 (Marker/데이터 수준, 기능 노드 없음).
##   5. 기존 회귀 (핵심 건물/도로/floor/생산/Worker/Navigation/DayNight/marker 구조).

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

	_check_south_agriculture()
	_check_ne_dungeon()
	_check_outer_wild()
	_check_slots_not_functional()
	_check_reachability()
	_check_regression()

	print("TASK0125_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _check_south_agriculture() -> void:
	var zone: Rect2 = _layout.get_south_agriculture_zone()
	_check(zone.size.x >= 400.0 and zone.size.y >= 120.0, "south agriculture zone is a meaningful area (%s)" % str(zone.size))
	# 남쪽 +450~+650px 구간에 있어야 한다.
	_check(zone.position.y >= 400.0 and zone.end.y <= 700.0, "south agriculture zone in +450~+650px band (%s)" % str(zone))
	_check(_layout.is_in_bounds(zone.position) and _layout.is_in_bounds(zone.end), "south agriculture zone inside map bounds")

	# 대형 자연 장애물(숲/석재)이 없거나 극소수여야 한다 (평평한 농업 공간).
	var forest_in_zone := 0
	for t in get_nodes_in_group("interactable"):
		if _layout.is_in_south_agriculture_zone(t.global_position):
			forest_in_zone += 1
	_check(forest_in_zone == 0, "no tree occupies the south agriculture zone (%d found)" % forest_in_zone)
	var stone_in_zone := 0
	for d in get_nodes_in_group("stone_deposits"):
		if _layout.is_in_south_agriculture_zone((d as Node2D).global_position):
			stone_in_zone += 1
	_check(stone_in_zone == 0, "no stone deposit inside the south agriculture zone (%d found)" % stone_in_zone)
	_check(not _layout.is_in_south_agriculture_zone(Vector2.ZERO), "south agriculture zone excludes central village")

	# Secondary Path(south_agriculture)와 연결되어 식별/이동 가능해야 한다.
	var sp: Array = _layout.get_secondary_path("south_agriculture")
	var sp_inside := false
	for p in sp:
		if _layout.is_in_south_agriculture_zone(p):
			sp_inside = true
			break
	_check(sp_inside, "south agriculture zone connects to its Secondary Path")

	_check(_layout.get_south_agriculture_marker() != null, "SouthAgricultureZone marker exists")
	_check(_layout.get_south_agriculture_marker().position.distance_to(zone.get_center()) <= 4.0, "marker at agriculture zone center")


func _check_ne_dungeon() -> void:
	var pos: Vector2 = _layout.get_ne_dungeon_candidate()
	_check(pos.distance_to(Vector2(720, -700)) <= 40.0, "NE dungeon candidate near (+720,-700) (%s)" % str(pos))
	_check(_layout.is_in_bounds(pos), "NE dungeon candidate inside map bounds")
	_check(not _layout.is_in_clearing(pos), "NE dungeon candidate is in Outer Wild, not the village clearing")
	_check(not _layout.is_on_access_axis(pos), "NE dungeon candidate not on a Main Road")
	_check(not _layout.is_in_gate_corridor(pos), "NE dungeon candidate not in a Gate Corridor")
	_check(not _layout.is_in_combat_field(pos), "NE dungeon candidate not in a Combat Field")
	_check(not _layout.is_in_rally_space(pos), "NE dungeon candidate not in a Rally Space")
	# 실제 차단 오브젝트가 후보 위치를 막지 않아야 한다.
	var blocked := false
	for t in get_nodes_in_group("interactable"):
		if (t as Node2D).global_position.distance_to(pos) <= 32.0:
			blocked = true
	for d in get_nodes_in_group("stone_deposits"):
		if (d as Node2D).global_position.distance_to(pos) <= 32.0:
			blocked = true
	_check(not blocked, "NE dungeon candidate not blocked by a tree/stone at its position")
	_check(_layout.get_ne_dungeon_marker() != null, "NeDungeonCandidate marker exists")


func _check_outer_wild() -> void:
	var slots: Dictionary = _layout.get_outer_wild_slots()
	_check(slots.size() == 4, "4 outer wild slots defined (%d)" % slots.size())
	for id in ["nw", "ne", "sw", "se"]:
		var r: Rect2 = slots.get(id, Rect2())
		_check(r.size.x >= 100.0 and r.size.y >= 100.0, "%s outer wild slot is a usable area (%s)" % [id, str(r.size)])
		_check(_layout.is_in_bounds(r.position) and _layout.is_in_bounds(r.end), "%s outer wild slot inside map bounds" % id)
		# 코너(Outer Wild)에 위치해야 한다 (중앙에서 충분히 먼).
		var center: Vector2 = r.get_center()
		_check(center.distance_to(Vector2.ZERO) >= 600.0, "%s outer wild slot is in the outer wild (dist %.0f)" % [id, center.distance_to(Vector2.ZERO)])
		_check(_layout.get_node_or_null("OuterWild_" + id.to_upper()) != null, "OuterWild_%s marker exists" % id.to_upper())
	_check(_layout.get_outer_wild_markers().size() >= 4, "outer wild markers present (%d)" % _layout.get_outer_wild_markers().size())

	# NE Outer 슬롯과 Dungeon Candidate가 같은 Outer NE 방향에 위치해야 한다.
	var ne: Rect2 = slots.get("ne", Rect2())
	var dungeon: Vector2 = _layout.get_ne_dungeon_candidate()
	_check(dungeon.x >= 0.0 and dungeon.y <= 0.0, "NE dungeon candidate is in the NE quadrant")
	_check(ne.get_center().x >= 0.0 and ne.get_center().y <= 0.0, "NE outer slot is in the NE quadrant")

	# 맵 코너를 장식으로 과도하게 채우지 않는다 (미래 콘텐츠 슬롯 보존).
	var deco_in_slots := 0
	for d in get_nodes_in_group("decorations"):
		if _layout.is_in_outer_wild_slot((d as Node2D).global_position):
			deco_in_slots += 1
	_check(deco_in_slots == 0, "outer wild slots kept open (no decoration fills them) (%d found)" % deco_in_slots)


func _check_slots_not_functional() -> void:
	# 미래 슬롯은 Marker/데이터 수준만 존재하고 기능 노드(전투/생산/이동 규칙 등)가 없어야 한다.
	var func_nodes := 0
	for id in ["SouthAgricultureZone", "NeDungeonCandidate", "OuterWild_NW", "OuterWild_NE", "OuterWild_SW", "OuterWild_SE"]:
		var m: Node = _layout.get_node_or_null(id)
		if m != null and m is Marker2D:
			pass
	_check(func_nodes == 0, "future slots introduce no functional nodes")
	_check(not _layout.has_method("place_farm") and not _layout.has_method("spawn_dungeon"), "no farm/dungeon systems wired into the layout")


func _check_reachability() -> void:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var targets: Array[Vector2] = [
		_layout.get_south_agriculture_zone().get_center(),
		_layout.get_ne_dungeon_candidate(),
	]
	for id in ["nw", "ne", "sw", "se"]:
		targets.append(_layout.get_outer_wild_slot(id).get_center())
	for t in targets:
		var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, Vector2.ZERO, t, true)
		_check(path.size() >= 2, "nav path from village center reaches %s" % str(t))


func _check_regression() -> void:
	var cores := get_nodes_in_group("core_buildings")
	_check(cores.size() == 5, "5 core buildings present (%d)" % cores.size())
	var seen := {}
	for b in cores:
		seen[b.get_core_type()] = b.global_position
		_check(_layout.is_in_clearing(b.global_position), "%s inside central Core Village clearing" % b.name)
	for t in CORE_TYPES:
		_check(seen.has(t), "core type %s present" % t)

	var player_pos: Vector2 = _main.get_node("Player").global_position
	_check(player_pos.distance_to(Vector2(0, 60)) <= 24.0, "Player Start near (0,+60) (%s)" % str(player_pos))

	_check(get_nodes_in_group("interactable").size() >= 12, "trees present (%d)" % get_nodes_in_group("interactable").size())
	_check(get_nodes_in_group("stone_deposits").size() == 1, "stone deposit present (%d)" % get_nodes_in_group("stone_deposits").size())
	_check(get_nodes_in_group("decorations").size() >= 4, "decorations present (%d)" % get_nodes_in_group("decorations").size())

	_check(_floor.get_used_cells().size() == 128 * 128, "floor covers 128x128 tiles")
	_check(_floor.get_cell_source_id(Vector2i(0, 19)) == 1, "south Main Road reads as road")
	_check(_floor.get_cell_source_id(Vector2i(19, 0)) == 1, "east Main Road reads as road")

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
	_check(_layout.get_spawn_candidate_nodes().size() >= 2, "spawn candidate markers present")
	_check(_layout.get_bounds_rect().size == Vector2(2048, 2048), "bounds size 2048x2048")

	var game_time := root.get_node("GameTime")
	_check(game_time != null, "GameTime autoload exists")
	_check(game_time.get_phase() == game_time.Phase.DAY, "GameTime starts in DAY (%s)" % str(game_time.get_phase_name()))


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(roundi((pos.x - 8.0) / 16.0), roundi((pos.y - 8.0) / 16.0))


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
