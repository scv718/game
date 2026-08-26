extends Node3D
class_name BuildingPlacement3D

## TASK-3D-BLD-001-2 BuildingPlacement XZ Grid.
## 기존 building_placement.gd(Node2D)의 건설 mode 계약을 Camera3D mouse ray +
## XZ logical grid로 이전한 신규 파일이다. 기존 2D 파일은 LOCK 12에 따라 유지되며,
## 이 파일이 대신하는 것은 3D Runtime뿐이다.
##
## - mouse ray -> ground XZ는 camera_controller_3d 그룹의 ground_point_from_screen을
##   소비한다. ghost/click은 모두 판정 시점의 live camera 상태(pan/zoom 포함)로
##   지면 점을 구하므로, pan/zoom 중에도 항상 정확한 target cell을 가리킨다.
## - grid snap은 WorldCoords3D 단일 소스를 사용한다. Building(Lumberyard/Quarry)은
##   기존 2D와 동일한 셀을 점유하도록 cell 중심에 배치한다(2D는 corner snap 후
##   collision shape가 (+16,+16) 오프셋이라 결과적으로 셀 중심이 본체 중심이다).
##   Wall/Gate는 기존처럼 corner snap을 유지한다(연속 Wall 인접 / Corridor
##   중심선 x=0,z=0 고정 의미 보존).
## - ghost는 collision shape 없는 순수 MeshInstance3D + 투명 material이다.
##   valid = 초록, invalid/remove mode = 빨강. 색 값은 기존 2D Polygon2D와 동일.
## - overlap 검증은 CollisionLayers3D.MASK_PLACEMENT_BLOCKERS
##   (BUILDING|WALL|GATE|RESOURCE) shape query다. 지면(GROUND)은 mask에서 제외되어
##   어디든 지상에 배치 가능하고, 대신 footprint가 월드 bounds 밖이면 거부한다
##   (기존 2D boundary wall collider가 PLACE_MASK로 하던 역할의 명시 검사판).
##   Wall/Gate끼리는 인접(edge touch) 허용, 실제 겹침만 거부하는 기존 규약 유지.
## - 비용은 BUILD_COSTS 기준 배치 성공 시 1회 차감, invalid/부족이면 차감 없음.
## - remove/refund 기존 정책 유지: Remove mode(R)에서 Wall/Gate 클릭 시 전액 환불
##   제거. 나머지 건물/자원은 삭제 금지.
## - gameplay footprint(collision shape)와 visual mesh 크기는 분리되어 있다.
##   각 건물 scene의 Visual slot placeholder mesh는 footprint를 따르지 않는다.
## - group: WorldSelection3D/HUD 기존 계약 조회명("building_placement")과
##   3차원 명시 조회용("building_placement_3d")에 동시 등록한다. signal 이름과
##   is_active 계약도 2D와 동일하므로 기존 소비자가 무수정으로 동작한다.

const LUMBERYARD_SCENE := preload("res://scenes/lumberyard_3d.tscn")
const QUARRY_SCENE := preload("res://scenes/quarry_3d.tscn")
const WALL_SCENE := preload("res://scenes/wall_3d.tscn")
const GATE_SCENE := preload("res://scenes/gate_3d.tscn")
const BUILD_COSTS := {
	"lumberyard": {"wood": 10},
	"quarry": {"wood": 10},
	"wall": {"wood": 2},
	"gate": {"wood": 5},
}
## gameplay footprint(논리 px). collision shape 단일 소스이며 visual mesh 크기와 무관.
## 기존 2D BUILDING_SIZE/WALL_FOOTPRINT/GATE 사이즈와 동일 값이다.
const BUILDING_FOOTPRINT_PX := Vector2(32, 32)
const WALL_FOOTPRINT_PX := Vector2(16, 16)
const GATE_HORIZONTAL_SIZE_PX := Vector2(48, 16)
const GATE_VERTICAL_SIZE_PX := Vector2(16, 48)
## placement overlap query mask(Foundation 단일 소스). 지면 제외 - 어디든 지상 배치 가능.
const PLACE_MASK := CollisionLayers3D.MASK_PLACEMENT_BLOCKERS
## 기존 2D DEPOSIT_SNAP_RADIUS(48px)의 unit 환산값.
const DEPOSIT_SNAP_RADIUS_UNITS := 48.0 * WorldCoords3D.PX_TO_UNIT
## 기존 2D 겹침 판정 epsilon(inter.size > 0.5px, 인접 허용)의 unit 환산값.
const OVERLAP_EPSILON_UNITS := 0.5 * WorldCoords3D.PX_TO_UNIT
## 기존 2D remove pick tolerance((pos - target).length_squared() < 1px^2)의 unit 환산값.
const REMOVE_PICK_TOLERANCE_UNITS := 1.0 * WorldCoords3D.PX_TO_UNIT

## ghost 색(기존 2D Polygon2D valid/invalid/radius fill/radius line과 동일 값).
const COLOR_VALID := Color(0.3, 0.9, 0.4, 0.6)
const COLOR_INVALID := Color(0.9, 0.3, 0.3, 0.6)
const COLOR_RADIUS_FILL := Color(0.3, 0.9, 0.4, 0.12)
const COLOR_RADIUS_LINE := Color(0.3, 0.9, 0.4, 0.85)

## ghost/검증 볼륨 치수(unit). footprint XZ는 위 px 상수에서 환산되며
## 높이류는 표현/검증용으로 footprint와 분리된 독립 값이다.
const FOOTPRINT_BOX_HEIGHT_UNITS := 0.5
const QUERY_HEIGHT_UNITS := 4.0
const RADIUS_DISC_HEIGHT_UNITS := 0.04
const RADIUS_RING_THICKNESS_UNITS := 0.2
const RADIUS_RING_Y_UNITS := 0.08

signal mode_changed(active: bool)
signal feedback(text: String)
signal building_type_changed(building_type: String)

var _active := false
var _remove_mode := false
var _building_type := "lumberyard"
var _ghost: Node3D = null
var _ghost_rect: MeshInstance3D = null
var _footprint_material: StandardMaterial3D = null
var _ghost_rect_extents_px := BUILDING_FOOTPRINT_PX * 0.5
var _ghost_radius_fill: MeshInstance3D = null
var _ghost_radius_line: MeshInstance3D = null
var _work_radius_units := 192.0 * WorldCoords3D.PX_TO_UNIT
var _query_shape := BoxShape3D.new()
## 마지막 mouse screen 좌표. motion event가 unhandled로 도달할 때 갱신되며,
## ghost _process가 이 좌표의 지면 교차점을 따라간다(2D get_global_mouse_position 역할).
var _last_mouse_screen_pos := Vector2.ZERO


func _ready() -> void:
	add_to_group("building_placement")
	add_to_group("building_placement_3d")
	var sample: Node3D = LUMBERYARD_SCENE.instantiate()
	_work_radius_units = sample.work_radius_px * WorldCoords3D.PX_TO_UNIT
	sample.free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_mouse_screen_pos = event.position
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_set_building_type("lumberyard")
			return
		if event.keycode == KEY_2:
			_set_building_type("quarry")
			return
		if event.keycode == KEY_3:
			_set_building_type("wall")
			return
		if event.keycode == KEY_4:
			_set_building_type("gate")
			return
		if event.keycode == KEY_R:
			if _active:
				_set_remove_mode(not _remove_mode)
			return
	if event.is_action_pressed("build"):
		_set_active(not _active)
	elif event.is_action_pressed("ui_cancel"):
		if _active:
			_set_active(false)
	elif event is InputEventMouseButton and event.pressed and _active:
		# Build mode가 활성인 동안 left/right click은 건설 mode가 소유한다.
		# Right Click = build mode cancel(ESC와 동일한 contextual mode 취소).
		# handled 처리로 배치 click이 WorldSelection 등으로 전파돼 이중 동작되지 않게 한다.
		var ground_pos := _ground_point_at(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT and ground_pos.is_finite():
			if _remove_mode:
				_try_remove_wall_at(ground_pos)
			elif _building_type == "quarry":
				_try_place_quarry_at(ground_pos)
			elif _building_type == "wall":
				_try_place_wall_at(WorldCoords3D.snap_xz_to_grid(ground_pos))
			elif _building_type == "gate":
				_try_place_gate_at(_snap_gate(ground_pos))
			else:
				_try_place_at(_snap_cell_center(ground_pos))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_set_active(false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _active:
		return
	_refresh_ghost()


func _refresh_ghost() -> void:
	var mouse := _ground_point_at(_last_mouse_screen_pos)
	if not mouse.is_finite():
		return
	var target := _snap_cell_center(mouse)
	if _building_type == "quarry":
		var deposit := _find_deposit_at(mouse)
		if deposit != null:
			target = deposit.global_position
	elif _building_type == "gate":
		target = _snap_gate(mouse)
	_show_ghost_at(target)


## TASK-CTRL-001-2 대응 공개 상태 접근자(기존 2D 계약 동일).
## WorldSelection3D가 build mode 활성 여부를 확인할 때 사용한다.
func is_active() -> bool:
	return _active


func _set_building_type(building_type: String) -> void:
	if _building_type == building_type:
		return
	_building_type = building_type
	_remove_mode = false
	if _active:
		_refresh_ghost()
	building_type_changed.emit(_building_type)


func _set_remove_mode(value: bool) -> void:
	if _remove_mode == value:
		return
	_remove_mode = value
	if _active:
		_refresh_ghost()
	if value:
		feedback.emit("Remove mode: click Wall to demolish")
	else:
		feedback.emit("Remove mode off")


func _set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	_remove_mode = false
	if _active:
		_refresh_ghost()
	elif _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_rect = null
		_footprint_material = null
	mode_changed.emit(_active)


func _show_ghost_at(pos: Vector3) -> void:
	var extents := _extents_for_type(_building_type, pos)
	if _ghost == null:
		_create_ghost(extents)
	elif _ghost_rect_extents_px != extents:
		_ghost_rect_extents_px = extents
		_apply_footprint_size(extents)
	_ghost.position = WorldCoords3D.flatten(pos)
	_update_ghost_color()


func _create_ghost(extents: Vector2) -> void:
	# work radius 표현. fill + ring 2겹(기존 2D Polygon2D/Line2D 색 정책 동일).
	_ghost = Node3D.new()
	_ghost_radius_fill = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.height = RADIUS_DISC_HEIGHT_UNITS
	disc.top_radius = _work_radius_units
	disc.bottom_radius = _work_radius_units
	disc.radial_segments = 48
	_ghost_radius_fill.mesh = disc
	_ghost_radius_fill.material_override = _ghost_material(COLOR_RADIUS_FILL)
	_ghost_radius_fill.position.y = RADIUS_DISC_HEIGHT_UNITS * 0.5
	_ghost.add_child(_ghost_radius_fill)
	_ghost_radius_line = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = _work_radius_units - RADIUS_RING_THICKNESS_UNITS
	ring.outer_radius = _work_radius_units
	_ghost_radius_line.mesh = ring
	_ghost_radius_line.material_override = _ghost_material(COLOR_RADIUS_LINE)
	_ghost_radius_line.position.y = RADIUS_RING_Y_UNITS
	_ghost.add_child(_ghost_radius_line)
	_ghost_rect = MeshInstance3D.new()
	_footprint_material = _ghost_material(COLOR_VALID)
	_ghost_rect.material_override = _footprint_material
	_ghost_rect.mesh = BoxMesh.new()
	_ghost_rect.position.y = FOOTPRINT_BOX_HEIGHT_UNITS * 0.5
	_ghost.add_child(_ghost_rect)
	_apply_footprint_size(extents)
	add_child(_ghost)


func _apply_footprint_size(extents: Vector2) -> void:
	_ghost_rect_extents_px = extents
	var half := extents * WorldCoords3D.PX_TO_UNIT
	(_ghost_rect.mesh as BoxMesh).size = Vector3(
		half.x * 2.0, FOOTPRINT_BOX_HEIGHT_UNITS, half.y * 2.0)


func _ghost_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


## 현재 build type/위치에 맞는 ghost footprint 반폭(논리 px)을 반환.
func _extents_for_type(building_type: String, pos: Vector3) -> Vector2:
	match building_type:
		"wall":
			return WALL_FOOTPRINT_PX * 0.5
		"gate":
			return _extents_for_gate(pos)
		_:
			return BUILDING_FOOTPRINT_PX * 0.5


func _update_ghost_color() -> void:
	if _ghost_rect == null:
		return
	if _remove_mode or not _is_valid_position(_ghost.position):
		_footprint_material.albedo_color = COLOR_INVALID
	else:
		_footprint_material.albedo_color = COLOR_VALID


## Building(Lumberyard/Quarry) 배치용 cell 중심 snap. 기존 2D building 배치와
## 동일한 셀을 점유한다(2D = corner snap + shape (+16,+16) 오프셋 = 셀 중심 본체).
func _snap_cell_center(pos: Vector3) -> Vector3:
	var c := WorldCoords3D.GRID_CELL_UNITS
	return Vector3(
		floorf(pos.x / c) * c + c * 0.5,
		pos.y,
		floorf(pos.z / c) * c + c * 0.5)


func _is_valid_position(pos: Vector3) -> bool:
	if _building_type == "quarry":
		var deposit := _find_deposit_at(pos)
		return deposit != null and not deposit.is_occupied()
	if _building_type == "wall":
		return _is_valid_wall_position(pos)
	if _building_type == "gate":
		return _is_valid_gate_position(pos)
	var extents := _extents_for_type(_building_type, pos)
	return _is_footprint_in_bounds(pos, extents) \
		and _query_blocker_hits(pos, extents, 1).is_empty()


func _is_valid_wall_position(pos: Vector3) -> bool:
	var extents := WALL_FOOTPRINT_PX * 0.5
	if not _is_footprint_in_bounds(pos, extents):
		return false
	# wall의 실제 collision footprint는 pos 중심 16x16이므로 query도 중심 기준으로 검사.
	var aabb := _footprint_aabb(pos, extents)
	for hit in _query_blocker_hits(pos, extents, 16):
		var collider = hit.get("collider")
		if collider is Node3D and _rejects_placement_geometry(aabb, collider):
			return false
	return true


func _is_valid_gate_position(pos: Vector3) -> bool:
	var dir := _gate_direction_at(pos)
	if dir == "":
		return false
	var corridor := WorldCoords3D.rect_to_aabb(WorldMap.GATE_CORRIDORS[dir])
	var half := _extents_for_gate(pos)
	var aabb := _footprint_aabb(pos, half)
	if not corridor.encloses(aabb):
		return false
	if not _is_footprint_in_bounds(pos, half):
		return false
	for hit in _query_blocker_hits(pos, half, 16):
		var collider = hit.get("collider")
		if collider is Node3D and _rejects_placement_geometry(aabb, collider):
			return false
	return true


## Wall/Gate 배치 겹침 판정(기존 2D 규약 동일).
## Wall/Gate 계열은 인접(edge touch, 겹침 부피 0)만 허용하고 실제 겹침만 거부한다.
## 그 외 body(Building 본체/Tree trunk/Deposit Block 등)는 항상 거부한다.
func _rejects_placement_geometry(query_aabb: AABB, collider: Node3D) -> bool:
	if collider.is_in_group("walls_3d") or collider.is_in_group("gates_3d"):
		var other_half_px := WALL_FOOTPRINT_PX * 0.5
		if collider.is_in_group("gates_3d") and collider.has_method("get_footprint_size"):
			other_half_px = collider.get_footprint_size() * 0.5
		var other_half := other_half_px * WorldCoords3D.PX_TO_UNIT
		var other_center: Vector3 = collider.global_position
		var other_aabb := AABB(
			Vector3(other_center.x - other_half.x, WorldCoords3D.GROUND_Y,
				other_center.z - other_half.y),
			Vector3(other_half.x * 2.0, 0.0, other_half.y * 2.0))
		var inter := query_aabb.intersection(other_aabb)
		if inter.size.x > OVERLAP_EPSILON_UNITS and inter.size.z > OVERLAP_EPSILON_UNITS:
			return true
		return false
	return true


## Gate Corridor 내부면 Main Road 중심선 축으로 snap.
## N/S Gate는 x=0(중심선)으로 고정, E/W Gate는 z=0으로 고정한다(기존 2D 규약 동일).
func _snap_gate(mouse: Vector3) -> Vector3:
	var dir := _gate_direction_at(mouse)
	if dir == "":
		return WorldCoords3D.snap_xz_to_grid(mouse)
	var snapped := WorldCoords3D.snap_xz_to_grid(mouse)
	if dir == "north" or dir == "south":
		return Vector3(0.0, snapped.y, snapped.z)
	return Vector3(snapped.x, snapped.y, 0.0)


## 마우스/셀 위치를 기준으로 성문 방향/형태를 판정(world_map.gd 상수 읽기 전용 참조).
func _extents_for_gate(pos: Vector3) -> Vector2:
	var dir := _gate_direction_at(pos)
	if dir == "north" or dir == "south":
		return GATE_HORIZONTAL_SIZE_PX * 0.5
	return GATE_VERTICAL_SIZE_PX * 0.5


## world_map.gd의 GATE_CORRIDORS 상수를 logical 좌표로 재사용하고 XZ 해석만
## WorldCoords3D로 수행한다(migration map 운영 규칙 2: 상수 읽기 전용 참조).
func _gate_direction_at(pos: Vector3) -> String:
	var logical := WorldCoords3D.to_logical(pos)
	for dir in WorldMap.GATE_CORRIDORS:
		if WorldMap.GATE_CORRIDORS[dir].has_point(logical):
			return dir
	return ""


## Screen 좌표 -> 지면(XZ) 교차점(camera_controller_3d 소비).
## 카메라 컨트롤러 부재/광선 미교차 시 Vector3.INF(안전 no-op).
func _ground_point_at(screen_pos: Vector2) -> Vector3:
	var cam_ctl := get_tree().get_first_node_in_group("camera_controller_3d")
	if cam_ctl == null or not cam_ctl.has_method("ground_point_from_screen"):
		return Vector3.INF
	return cam_ctl.ground_point_from_screen(screen_pos)


## footprint 중심 pos와 반폭(논리 px)으로 지면 Y=0 평면 AABB를 만든다.
func _footprint_aabb(pos: Vector3, extents_px: Vector2) -> AABB:
	var half := extents_px * WorldCoords3D.PX_TO_UNIT
	return AABB(
		Vector3(pos.x - half.x, WorldCoords3D.GROUND_Y, pos.z - half.y),
		Vector3(half.x * 2.0, 0.0, half.y * 2.0))


## footprint 전체가 월드 bounds 안인지. 기존 2D 경계 StaticBody2D가 placement
## mask로 막아주던 역할을 명시 bounds 검사로 수행한다(GROUND는 mask 제외).
func _is_footprint_in_bounds(pos: Vector3, extents_px: Vector2) -> bool:
	return WorldCoords3D.world_bounds_aabb().encloses(_footprint_aabb(pos, extents_px))


## MASK_PLACEMENT_BLOCKERS shape query. query box는 footprint XZ에 높이
## QUERY_HEIGHT_UNITS(0..4 unit)를 더해 지상 블록(trunk/deposit/건물 본체)을 커버한다.
func _query_blocker_hits(pos: Vector3, extents_px: Vector2, max_results: int) -> Array:
	var half := extents_px * WorldCoords3D.PX_TO_UNIT
	_query_shape.size = Vector3(half.x * 2.0, QUERY_HEIGHT_UNITS, half.y * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _query_shape
	query.transform = Transform3D(Basis.IDENTITY,
		Vector3(pos.x, QUERY_HEIGHT_UNITS * 0.5, pos.z))
	query.collision_mask = PLACE_MASK
	return get_world_3d().direct_space_state.intersect_shape(query, max_results)


func _find_deposit_at(pos: Vector3) -> Node:
	var best: Node = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("stone_deposits_3d"):
		var deposit := node as Node3D
		if deposit == null or not is_instance_valid(deposit):
			continue
		var d := WorldCoords3D.distance_xz(deposit.global_position, pos)
		if d < best_dist:
			best = deposit
			best_dist = d
	if best != null and best_dist <= DEPOSIT_SNAP_RADIUS_UNITS:
		return best
	return null


func _try_place_at(pos: Vector3) -> void:
	if not _is_valid_position(pos):
		feedback.emit("Invalid position")
		return
	var cost: int = int(BUILD_COSTS["lumberyard"].get("wood", 0))
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	VillageResources.spend("wood", cost)
	var lumberyard: Node3D = LUMBERYARD_SCENE.instantiate() as Node3D
	lumberyard.position = WorldCoords3D.flatten(pos)
	var world := get_tree().get_first_node_in_group("world3d")
	if world != null:
		world.add_child(lumberyard)
	else:
		get_parent().add_child(lumberyard)
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
	feedback.emit("Lumberyard built")
	_set_active(false)


func _try_place_quarry_at(pos: Vector3) -> void:
	var deposit := _find_deposit_at(pos)
	if deposit == null:
		feedback.emit("No Stone Deposit nearby")
		return
	if deposit.is_occupied():
		feedback.emit("Deposit already has a Quarry")
		return
	var cost: int = int(BUILD_COSTS["quarry"].get("wood", 0))
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	VillageResources.spend("wood", cost)
	var quarry: Node3D = QUARRY_SCENE.instantiate() as Node3D
	quarry.position = deposit.global_position
	var world := get_tree().get_first_node_in_group("world3d")
	if world != null:
		world.add_child(quarry)
	else:
		get_parent().add_child(quarry)
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
	if not deposit.occupy(quarry):
		VillageResources.add("wood", cost)
		quarry.queue_free()
		feedback.emit("Deposit already has a Quarry")
		return
	quarry.bind_deposit(deposit)
	feedback.emit("Quarry built")
	_set_active(false)


## TASK-013-1 연속 배치 정책 유지. 배치 후에도 build mode를 유지해
## 여러 segment를 연속으로 놓을 수 있다. 비용은 segment마다 1회 차감.
func _try_place_wall_at(pos: Vector3) -> void:
	if not _is_valid_wall_position(pos):
		feedback.emit("Invalid wall position")
		return
	var cost: int = int(BUILD_COSTS["wall"].get("wood", 0))
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	VillageResources.spend("wood", cost)
	var wall: Node3D = WALL_SCENE.instantiate() as Node3D
	wall.position = WorldCoords3D.flatten(pos)
	var world := get_tree().get_first_node_in_group("world3d")
	if world != null:
		world.add_child(wall)
	else:
		get_parent().add_child(wall)
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
	_refresh_neighbor_visuals(pos)
	feedback.emit("Wall built")


func _try_place_gate_at(pos: Vector3) -> void:
	if not _is_valid_gate_position(pos):
		feedback.emit("Invalid gate position")
		return
	var cost: int = int(BUILD_COSTS["gate"].get("wood", 0))
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	VillageResources.spend("wood", cost)
	var gate: Node3D = GATE_SCENE.instantiate() as Node3D
	gate.position = WorldCoords3D.flatten(pos)
	var dir := _gate_direction_at(pos)
	if gate.has_method("setup"):
		gate.setup(dir)
	var world := get_tree().get_first_node_in_group("world3d")
	if world != null:
		world.add_child(gate)
	else:
		get_parent().add_child(gate)
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
	feedback.emit("Gate built")


## TASK-013-2 철거 정책 유지. Remove mode에서 Wall/Gate 클릭 시 Wood 전액 환불하고
## 제거한다. 제거 가능 대상은 Wall/Gate뿐(나머지 건물/자원은 삭제 금지).
func _try_remove_wall_at(pos: Vector3) -> void:
	var target: Node3D = null
	var target_is_gate := false
	for node in get_tree().get_nodes_in_group("walls_3d"):
		if not is_instance_valid(node):
			continue
		var wall := node as Node3D
		if wall == null:
			continue
		if WorldCoords3D.distance_xz(wall.global_position, pos) < REMOVE_PICK_TOLERANCE_UNITS:
			target = wall
			break
	if target == null:
		for node in get_tree().get_nodes_in_group("gates_3d"):
			if not is_instance_valid(node):
				continue
			var gate := node as Node3D
			if gate == null:
				continue
			if WorldCoords3D.distance_xz(gate.global_position, pos) < REMOVE_PICK_TOLERANCE_UNITS:
				target = gate
				target_is_gate = true
				break
	if target == null:
		feedback.emit("No wall to remove")
		return
	var cost: int = int(BUILD_COSTS["gate"].get("wood", 0)) if target_is_gate \
			else int(BUILD_COSTS["wall"].get("wood", 0))
	VillageResources.add("wood", cost)
	# queue_free 전에 그룹에서 먼저 제거해, 이후 neighbor 비주얼 갱신 시
	# 제거된 Wall/Gate가 인접으로 잡히지 않게 한다(stale visual 방지).
	target.remove_from_group("gates_3d" if target_is_gate else "walls_3d")
	_refresh_neighbor_visuals(pos)
	target.queue_free()
	# queue_free는 프레임 종료 시 실제 제거되므로, 제거된 Wall/Gate의 collision/nav가
	# stale로 남지 않게 Foundation debounce nav rebuild로 제거 후 갱신한다.
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
	if target_is_gate:
		feedback.emit("Gate removed (+%d Wood)" % cost)
	else:
		feedback.emit("Wall removed (+%d Wood)" % cost)


## 인접(상하좌우 1 tile) Wall들의 연결 비주얼을 갱신.
## 현재 3D placeholder wall에는 merge visual이 없어 has_method 가드로 생략된다.
func _refresh_neighbor_visuals(pos: Vector3) -> void:
	var reach := WALL_FOOTPRINT_PX.x * WorldCoords3D.PX_TO_UNIT
	for node in get_tree().get_nodes_in_group("walls_3d"):
		if not is_instance_valid(node):
			continue
		var wall := node as Node3D
		if wall == null:
			continue
		var diff: Vector3 = wall.global_position - pos
		if absf(diff.x) <= reach and absf(diff.z) <= reach \
				and diff.length_squared() > 0.0000001:
			if wall.has_method("refresh_visual"):
				wall.refresh_visual()
