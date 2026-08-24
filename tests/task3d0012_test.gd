extends SceneTree

## TASK-3D-001-2 World3D / Coordinate / Collision Foundation 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. 빈 3D World(scenes/world3d.tscn) 로드 및 실행.
##   2. WorldCoords3D logical grid -> XZ 변환 상수/유틸리티.
##   3. World bounds / Rect2 zone의 XZ 표현이 기존 WorldMap 판정과 일치.
##   4. CollisionLayers3D 공통 layer/mask 정책(카테고리 구분 + 충돌 동작).
##   5. 기존 UI(CanvasLayer HUD)가 3D World 위에 표시 가능.
##   6. physics-heavy terrain 금지(Ground collision shape 수 제한).

enum Phase {
	SETUP, WORLD_BASIC, COORDS, REGIONS, COLLISION_SETUP, COLLISION_QUERIES,
	UI_OVERLAY, RUNTIME, DONE,
}

const GODOT_EPS := 0.0001

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _hud: Node = null
var _map: WorldMap = null
var _probes: Array[Node] = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	for probe in _probes:
		if is_instance_valid(probe):
			probe.free()
	_probes.clear()
	if _map != null and is_instance_valid(_map):
		_map.free()
	print("TASK3D0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= GODOT_EPS


func _v3_near(a: Vector3, b: Vector3) -> bool:
	return _near(a.x, b.x) and _near(a.y, b.y) and _near(a.z, b.z)


func _hit_names(hits: Array) -> Array[String]:
	var names: Array[String] = []
	for hit in hits:
		var collider: Node = hit.get("collider")
		if collider != null and is_instance_valid(collider):
			names.append(String(collider.name))
	return names


func _add_body_probe(pos: Vector3, layer_bit: int, probe_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = probe_name
	body.collision_layer = layer_bit
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	body.add_child(shape)
	body.position = pos
	_world.add_child(body)
	return body


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.WORLD_BASIC:
			_world_basic()
		Phase.COORDS:
			_coords()
		Phase.REGIONS:
			_regions()
		Phase.COLLISION_SETUP:
			_collision_setup()
		Phase.COLLISION_QUERIES:
			_wait += 1
			if _wait >= 3:
				_collision_queries()
		Phase.UI_OVERLAY:
			_ui_overlay()
		Phase.RUNTIME:
			_runtime()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3D0012_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_hud = root.get_node_or_null("HUD")
	_check(_world != null, "empty 3D world loads and runs")
	_check(_world is Node3D, "world root is Node3D based")
	_check(_hud != null, "existing HUD overlay loads")
	_enter(Phase.WORLD_BASIC)


## -- WORLD_BASIC --
func _world_basic() -> void:
	_check(_world.is_in_group("world3d"), "world root joins world3d group")
	_check(get_nodes_in_group("world").size() == 0,
		"legacy 2D world group untouched in this runtime")
	_check(WorldCoords3D.GROUND_Y == 0.0, "ground Y = 0 (XZ ground plane policy)")
	var ground := _world.get_ground_body() as StaticBody3D
	_check(ground != null, "ground StaticBody3D exists")
	_check(ground.collision_layer == CollisionLayers3D.GROUND,
		"ground body uses GROUND layer")
	_check(ground.collision_mask == 0, "static ground body mask is passive 0")
	_enter(Phase.COORDS)


## -- COORDS --
func _coords() -> void:
	_check(_near(WorldCoords3D.PX_TO_UNIT, 0.125), "PX_TO_UNIT = 0.125")
	_check(_near(WorldCoords3D.TILE_SIZE_UNITS, 2.0),
		"logical tile 16px = 2 world units")
	_check(_near(WorldCoords3D.GRID_CELL_UNITS, 2.0), "grid cell = 2 units")

	var samples := [
		Vector2.ZERO, Vector2(600, 300), Vector2(-1500, 200),
		Vector2(1536, -1536), Vector2(16, -16),
	]
	var roundtrip_ok := true
	for s in samples:
		if WorldCoords3D.to_logical(WorldCoords3D.to_world_xz(s)) != s:
			roundtrip_ok = false
	_check(roundtrip_ok, "logical <-> world round trip preserves coordinates")

	var stone := WorldCoords3D.to_world_xz(_map.get_stone_deposit_pos())
	_check(_v3_near(stone, Vector3(75.0, 0.0, 37.5)),
		"stone deposit (600,300) -> (75,0,37.5)")
	var north_gate := WorldCoords3D.to_world_xz(_map.get_gate_anchor("north"))
	_check(north_gate.z < 0.0 and _near(north_gate.x, 0.0),
		"north gate anchor stays on -Z (direction semantics preserved)")
	var west_gate := WorldCoords3D.to_world_xz(_map.get_gate_anchor("west"))
	_check(west_gate.x < 0.0 and _near(west_gate.z, 0.0),
		"west gate anchor stays on -X")

	var d2d: float = WorldMap.SETTLEMENT_CENTER.distance_to(_map.get_stone_deposit_pos())
	var d3d := WorldCoords3D.distance_xz(
		WorldCoords3D.to_world_xz(WorldMap.SETTLEMENT_CENTER), stone)
	_check(_near(d3d, d2d * WorldCoords3D.PX_TO_UNIT),
		"gameplay distance preserved by uniform scale (no rebalance)")

	_check(WorldCoords3D.DIRECTION_XZ["north"].z < 0.0
		and WorldCoords3D.DIRECTION_XZ["south"].z > 0.0
		and WorldCoords3D.DIRECTION_XZ["east"].x > 0.0
		and WorldCoords3D.DIRECTION_XZ["west"].x < 0.0,
		"4 direction axes mapped to XZ consistently")

	var snapped := WorldCoords3D.snap_xz_to_grid(Vector3(75.0, 5.0, 37.5))
	var logical_snap := (Vector2(600, 300) / float(WorldMap.TILE_SIZE)).floor() \
		* float(WorldMap.TILE_SIZE)
	_check(_v3_near(WorldCoords3D.flatten(snapped),
		WorldCoords3D.to_world_xz(logical_snap)),
		"snap_xz_to_grid matches legacy building grid snap")

	_check(_v3_near(WorldCoords3D.flatten(Vector3(3.0, 7.0, -4.0)), Vector3(3.0, 0.0, -4.0)),
		"flatten projects to ground plane (no free height drift)")
	_enter(Phase.REGIONS)


## -- REGIONS --
func _regions() -> void:
	var bounds: AABB = _world.get_bounds_aabb()
	_check(_v3_near(bounds.position, Vector3(-192.0, 0.0, -192.0))
		and _v3_near(bounds.size, Vector3(384.0, 0.0, 384.0)),
		"world bounds AABB = legacy BOUNDS_RECT in XZ units")

	var edge_samples := [
		Vector2.ZERO, Vector2(1535, 1000), Vector2(-1536, 500),
		Vector2(1536, 0), Vector2(0, -2000), Vector2(1200, -1200),
		Vector2(-1500, 200),
	]
	var parity_ok := true
	for s in edge_samples:
		var expected: bool = _map.is_in_bounds(s)
		var actual := WorldCoords3D.is_in_bounds_xz(WorldCoords3D.to_world_xz(s))
		if expected != actual:
			parity_ok = false
			print("  mismatch at %s: 2D=%s 3D=%s" % [str(s), str(expected), str(actual)])
	_check(parity_ok, "is_in_bounds_xz matches legacy WorldMap.is_in_bounds on edges")

	var corridor: Rect2 = WorldMap.GATE_CORRIDORS["south"]
	var corridor_box := WorldCoords3D.rect_to_aabb(corridor)
	var corridor_center := WorldCoords3D.to_world_xz(corridor.get_center())
	_check(WorldCoords3D.aabb_contains_xz(corridor_box, corridor_center)
		== corridor.has_point(corridor.get_center()),
		"Rect2 zone center containment parity (gate corridor south)")
	var outside := WorldCoords3D.to_world_xz(Vector2(300, 700))
	_check(not WorldCoords3D.aabb_contains_xz(corridor_box, outside)
		== not corridor.has_point(Vector2(300, 700)),
		"Rect2 zone outside exclusion parity")

	var road_points := WorldCoords3D.polyline_to_world(WorldMap.MAIN_ROADS["north"])
	_check(road_points.size() == WorldMap.MAIN_ROADS["north"].size(),
		"polyline conversion keeps waypoint count (%d)" % road_points.size())
	_check(_v3_near(road_points[0], Vector3(0.0, 0.0, -28.0)),
		"main road first waypoint converted with direction preserved")

	var rally := WorldCoords3D.rect_to_aabb(WorldMap.RALLY_SPACES["east"])
	_check(_near(rally.size.x, 150.0 * WorldCoords3D.PX_TO_UNIT)
		and _near(rally.size.z, 180.0 * WorldCoords3D.PX_TO_UNIT),
		"rally space rect scaled without size distortion")
	_enter(Phase.COLLISION_SETUP)


## -- COLLISION_SETUP --
func _collision_setup() -> void:
	var specs := {
		"ProbeBuilding": CollisionLayers3D.BUILDING,
		"ProbeWall": CollisionLayers3D.WALL,
		"ProbeGate": CollisionLayers3D.GATE,
		"ProbeResource": CollisionLayers3D.RESOURCE,
		"ProbeWorker": CollisionLayers3D.WORKER,
		"ProbeMercenary": CollisionLayers3D.MERCENARY,
		"ProbeEnemy": CollisionLayers3D.ENEMY,
	}
	var x := -30.0
	for probe_name in specs:
		_probes.append(_add_body_probe(Vector3(x, 1.0, 40.0), specs[probe_name], probe_name))
		x += 10.0

	var interact := Area3D.new()
	interact.name = "ProbeInteractable"
	interact.collision_layer = CollisionLayers3D.INTERACTABLE
	interact.collision_mask = 0
	var ishape := CollisionShape3D.new()
	var isphere := SphereShape3D.new()
	isphere.radius = 1.0
	ishape.shape = isphere
	interact.add_child(ishape)
	interact.position = Vector3(x, 1.0, 40.0)
	_world.add_child(interact)
	_probes.append(interact)

	# 상수 배치 자체 검증: 요구된 8개 카테고리가 서로 다른 bit로 구분 가능.
	var bits := [
		CollisionLayers3D.BUILDING, CollisionLayers3D.WALL, CollisionLayers3D.GATE,
		CollisionLayers3D.RESOURCE, CollisionLayers3D.WORKER,
		CollisionLayers3D.MERCENARY, CollisionLayers3D.ENEMY,
		CollisionLayers3D.INTERACTABLE,
	]
	var unique := {}
	for b in bits:
		unique[b] = true
	_check(bits.size() == unique.size(), "8 categories use distinct collision bits")
	_check(CollisionLayers3D.MASK_ACTOR_SOLID == 31, "actor solid mask = ground+statics")
	_check((CollisionLayers3D.MASK_ACTOR_SOLID & CollisionLayers3D.MASK_ACTORS) == 0,
		"actors do not physically collide with actors (matches 2D actor mask=statics)")

	_enter(Phase.COLLISION_QUERIES)


## -- COLLISION_QUERIES --
func _collision_queries() -> void:
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var single_masks := {
		CollisionLayers3D.BUILDING: "ProbeBuilding",
		CollisionLayers3D.WALL: "ProbeWall",
		CollisionLayers3D.GATE: "ProbeGate",
		CollisionLayers3D.RESOURCE: "ProbeResource",
		CollisionLayers3D.WORKER: "ProbeWorker",
		CollisionLayers3D.MERCENARY: "ProbeMercenary",
		CollisionLayers3D.ENEMY: "ProbeEnemy",
	}
	var exclusive := true
	for mask in single_masks:
		var hits := _shape_query(space, single_masks[mask], mask)
		var names := _hit_names(hits)
		if names.size() != 1 or names[0] != String(single_masks[mask]):
			exclusive = false
			print("  mask=%d hits=%s" % [mask, str(names)])
	_check(exclusive, "each category layer isolates its own body in shape queries")

	var blockers := _hit_names(_shape_query(space, "ProbeBuilding",
		CollisionLayers3D.MASK_PLACEMENT_BLOCKERS))
	_check(blockers.has("ProbeBuilding"),
		"placement blocker mask detects building")
	var blocker_worker := _hit_names(_shape_query(space, "ProbeWorker",
		CollisionLayers3D.MASK_PLACEMENT_BLOCKERS))
	_check(blocker_worker.is_empty(),
		"placement blocker mask ignores actor bodies")

	var solid_hit := _hit_names(_shape_query(space, "ProbeWall",
		CollisionLayers3D.MASK_ACTOR_SOLID))
	_check(solid_hit.has("ProbeWall"), "actor solid mask collides with wall")
	var solid_actor := _hit_names(_shape_query(space, "ProbeEnemy",
		CollisionLayers3D.MASK_ACTOR_SOLID))
	_check(solid_actor.is_empty(), "actor solid mask ignores enemy body")

	var picked := _point_query(space, "ProbeInteractable", CollisionLayers3D.MASK_SELECTION)
	var picked_names := _hit_names(picked)
	_check(picked_names.size() == 1 and picked_names[0] == "ProbeInteractable",
		"selection mask picks interactable area via point query")
	var wrong_pick := _point_query(space, "ProbeInteractable", CollisionLayers3D.ENEMY)
	_check(_hit_names(wrong_pick).is_empty(),
		"enemy layer is not picked by selection mask (categories separated)")

	var ground_hits := _hit_names(_shape_query(space, "GroundOrigin", CollisionLayers3D.GROUND))
	_check(ground_hits.has("Ground"), "ground plane queryable on GROUND layer")
	var boundary_hits := _hit_names(_shape_query(space, "BoundaryEast", CollisionLayers3D.GROUND))
	_check(boundary_hits.has("Ground"), "world boundary expressible in 3D XZ on GROUND layer")

	for probe in _probes:
		if is_instance_valid(probe):
			probe.queue_free()
	_probes.clear()
	_enter(Phase.UI_OVERLAY)


func _shape_query(space: PhysicsDirectSpaceState3D, marker: String, mask: int) -> Array:
	var pos := _marker_position(marker)
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	params.shape = sphere
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = mask
	params.collide_with_bodies = true
	params.collide_with_areas = true
	return space.intersect_shape(params, 32)


func _point_query(space: PhysicsDirectSpaceState3D, marker: String, mask: int) -> Array:
	var params := PhysicsPointQueryParameters3D.new()
	params.position = _marker_position(marker)
	params.collision_mask = mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	return space.intersect_point(params, 32)


## 마커 이름 -> 실제 노드 위치(쿼리 좌표는 대상 노드에서 읽어 온다).
func _marker_position(marker: String) -> Vector3:
	match marker:
		"GroundOrigin":
			return Vector3(0.0, 0.25, 0.0)
		"BoundaryEast":
			return Vector3(191.5, 2.0, 0.0)
		_:
			var node := _world.get_node_or_null(NodePath(marker)) as Node3D
			return node.global_position if node != null else Vector3.ZERO


## -- UI_OVERLAY --
func _ui_overlay() -> void:
	_check(_hud is CanvasLayer, "HUD stays a CanvasLayer above 3D world")
	_check(_hud.visible, "HUD overlay visible over empty 3D world")
	_check(_hud.layer >= 1, "HUD canvas layer renders above default 3D viewport")
	_check(_hud.get_parent() == root and _world.get_parent() == root,
		"UI and 3D world remain separate branches (no UI reparenting into world)")
	_enter(Phase.RUNTIME)


## -- RUNTIME --
func _runtime() -> void:
	_check(get_nodes_in_group("world3d").size() == 1, "exactly one 3D world root")
	var shapes := _count_shapes(_world)
	_check(shapes <= 8,
		"foundation world stays light on physics shapes (%d)" % shapes)
	_check(_world.is_in_bounds(WorldCoords3D.to_world_xz(Vector2(100, 100))),
		"in-bounds ground coordinate accepted after full run")
	_check(not _world.is_in_bounds(Vector3(500.0, 0.0, 0.0)),
		"outside-bound coordinate rejected")
	_finish()


func _count_shapes(node: Node) -> int:
	var total := 0
	if node is CollisionShape3D:
		total += 1
	for child in node.get_children():
		total += _count_shapes(child)
	return total


func _initialize() -> void:
	_map = WorldMap.new()
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	var hud: Node = (load("res://ui/hud.tscn") as PackedScene).instantiate()
	hud.name = "HUD"
	root.add_child(hud)
