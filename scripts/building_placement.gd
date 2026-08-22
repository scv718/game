extends Node2D

const LUMBERYARD_SCENE := preload("res://scenes/lumberyard.tscn")
const QUARRY_SCENE := preload("res://scenes/quarry.tscn")
const WALL_SCENE := preload("res://scenes/wall.tscn")
const GATE_SCENE := preload("res://scenes/gate.tscn")
const BUILD_COSTS := {
	"lumberyard": {"wood": 10},
	"quarry": {"wood": 10},
	"wall": {"wood": 2},
	"gate": {"wood": 5},
}
const GRID_SIZE := 16
const BUILDING_SIZE := 32
const WALL_FOOTPRINT := 16
## TASK-013-3: 성문 footprint. N/S Gate = 도로를 가로지르는 수평(48x16, 3 logical tiles),
## E/W Gate = 수직(16x48). Road 반폭 40px/corridor 96px에 맞춘 prototype 값.
const GATE_HORIZONTAL_SIZE := Vector2(48, 16)
const GATE_VERTICAL_SIZE := Vector2(16, 48)
const PLACE_MASK := 0b111
## Wall은 Player(layer 1)와 Building/Tree/StoneDeposit/Boundary(layer 3) 겹침을 거부한다.
## (StaticBody blocking bodies는 collision_layer=4 → bit value 4 = layer 3)
const WALL_PLACE_MASK := 0b101
const DEPOSIT_SNAP_RADIUS := 48.0

signal mode_changed(active: bool)
signal feedback(text: String)
signal building_type_changed(building_type: String)

var _active := false
var _remove_mode := false
var _building_type := "lumberyard"
var _ghost: Node2D = null
var _ghost_rect: Polygon2D = null
var _ghost_rect_extents := Vector2(BUILDING_SIZE, BUILDING_SIZE) * 0.5
var _ghost_radius_fill: Polygon2D = null
var _ghost_radius_line: Line2D = null
var _work_radius: float = 192.0
var _query_shape := RectangleShape2D.new()


func _ready() -> void:
	_query_shape.size = Vector2(BUILDING_SIZE, BUILDING_SIZE)
	var sample: Node2D = LUMBERYARD_SCENE.instantiate()
	_work_radius = sample.work_radius
	sample.free()


func _unhandled_input(event: InputEvent) -> void:
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
		# TASK-CTRL-001-3: Build mode가 활성인 동안 mouse click은 건설 mode가 소유한다.
		# Right Click = build mode cancel (ESC와 동일하게 contextual mode 취소).
		# 배치 후에도 같은 click이 WorldSelection 등으로 전파돼 건물 선택/UI가
		# 동시에 실행되는 이중 동작을 막기 위해 handled로 처리한다.
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _remove_mode:
				_try_remove_wall_at(_snap(get_global_mouse_position()))
			elif _building_type == "quarry":
				_try_place_quarry_at(get_global_mouse_position())
			elif _building_type == "wall":
				_try_place_wall_at(_snap(get_global_mouse_position()))
			elif _building_type == "gate":
				_try_place_gate_at(_snap_gate(get_global_mouse_position()))
			else:
				_try_place_at(_snap(get_global_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_set_active(false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _active:
		return
	var mouse := get_global_mouse_position()
	var target := _snap(mouse)
	if _building_type == "quarry":
		var deposit := _find_deposit_at(mouse)
		if deposit != null:
			target = deposit.global_position
	elif _building_type == "gate":
		target = _snap_gate(mouse)
	_show_ghost_at(target)


## TASK-CTRL-001-2: 월드 선택/건설 mode 충돌 방지용 공개 상태 접근자.
## WorldSelection 등 다른 입력 소유자가 build mode 활성 여부를 확인할 때 사용한다.
func is_active() -> bool:
	return _active


func _set_building_type(building_type: String) -> void:
	if _building_type == building_type:
		return
	_building_type = building_type
	_remove_mode = false
	if _active:
		var mouse := get_global_mouse_position()
		var target := _snap(mouse)
		if building_type == "gate":
			target = _snap_gate(mouse)
		_show_ghost_at(target)
	building_type_changed.emit(_building_type)


func _set_remove_mode(value: bool) -> void:
	if _remove_mode == value:
		return
	_remove_mode = value
	if _active:
		_show_ghost_at(_snap(get_global_mouse_position()))
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
		_show_ghost_at(_snap(get_global_mouse_position()))
	elif _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_rect = null
	mode_changed.emit(_active)


func _show_ghost_at(pos: Vector2) -> void:
	var extents := _extents_for_type(_building_type, pos)
	if _ghost == null:
		_ghost = Node2D.new()
		_ghost_radius_fill = Polygon2D.new()
		_ghost_radius_fill.polygon = _circle_polygon(_work_radius)
		_ghost_radius_fill.color = Color(0.3, 0.9, 0.4, 0.12)
		_ghost.add_child(_ghost_radius_fill)
		_ghost_radius_line = Line2D.new()
		var ring := _circle_polygon(_work_radius)
		ring.append(ring[0])
		_ghost_radius_line.points = ring
		_ghost_radius_line.width = 2.0
		_ghost_radius_line.default_color = Color(0.3, 0.9, 0.4, 0.85)
		_ghost.add_child(_ghost_radius_line)
		_ghost_rect = Polygon2D.new()
		_ghost_rect.polygon = _rect_polygon_from_extents(extents)
		_ghost.add_child(_ghost_rect)
		_ghost_rect_extents = extents
		_query_shape.size = extents * 2.0
		add_child(_ghost)
	elif _ghost_rect_extents != extents:
		_ghost_rect_extents = extents
		_query_shape.size = extents * 2.0
		_ghost_rect.polygon = _rect_polygon_from_extents(extents)
	_ghost.position = pos
	_update_ghost_color()


## 현재 build type/위치에 맞는 ghost 사각 반폭(extents)을 반환.
func _extents_for_type(building_type: String, pos: Vector2) -> Vector2:
	match building_type:
		"wall":
			return Vector2(WALL_FOOTPRINT, WALL_FOOTPRINT) * 0.5
		"gate":
			return _extents_for_gate(pos)
		_:
			return Vector2(BUILDING_SIZE, BUILDING_SIZE) * 0.5


func _rect_polygon_from_extents(extents: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2.ZERO,
		Vector2(extents.x * 2.0, 0.0),
		extents * 2.0,
		Vector2(0.0, extents.y * 2.0),
	])


func _circle_polygon(radius: float, segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _update_ghost_color() -> void:
	if _ghost_rect == null:
		return
	if _remove_mode:
		_ghost_rect.color = Color(0.9, 0.3, 0.3, 0.6)
		return
	if _is_valid_position(_ghost.position):
		_ghost_rect.color = Color(0.3, 0.9, 0.4, 0.6)
	else:
		_ghost_rect.color = Color(0.9, 0.3, 0.3, 0.6)


func _snap(pos: Vector2) -> Vector2:
	return (pos / GRID_SIZE).floor() * GRID_SIZE


func _is_valid_position(pos: Vector2) -> bool:
	if _building_type == "quarry":
		var deposit := _find_deposit_at(pos)
		return deposit != null and not deposit.is_occupied()
	if _building_type == "wall":
		return _is_valid_wall_position(pos)
	if _building_type == "gate":
		return _is_valid_gate_position(pos)
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_shape
	query.transform = Transform2D(0.0, pos + Vector2(_ghost_rect_extents.x, _ghost_rect_extents.y))
	query.collision_mask = PLACE_MASK
	var hits := space.intersect_shape(query, 1)
	return hits.is_empty()


func _is_valid_wall_position(pos: Vector2) -> bool:
	_query_shape.size = Vector2(WALL_FOOTPRINT, WALL_FOOTPRINT)
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_shape
	# wall의 실제 collision footprint는 pos 중심 16x16이므로 query도 중심 기준으로 검사.
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = WALL_PLACE_MASK
	var hits := space.intersect_shape(query, 16)
	var aabb := Rect2(pos - Vector2(WALL_FOOTPRINT, WALL_FOOTPRINT) * 0.5, Vector2(WALL_FOOTPRINT, WALL_FOOTPRINT))
	for hit in hits:
		var collider = hit.get("collider")
		if collider is Node2D and _rejects_placement_geometry(aabb, collider):
			return false
	return true


## TASK-013-3: 성문 placement validation.
##  - Gate Corridor(N/E/S/W) 내부에만 허용 (그 외 corridor 밖 invalid).
##  - footprint가 corridor 안에 완전히 들어와야 함.
##  - Wall/Gate는 인접(edge touch) 허용, 실제 겹침(positive area)만 거부.
func _is_valid_gate_position(pos: Vector2) -> bool:
	var layout := _get_world_map()
	if layout == null:
		return false
	var dir: String = layout.get_gate_corridor_direction(pos)
	if dir == "":
		return false
	var corridor: Rect2 = layout.get_gate_corridor(dir)
	var half := _extents_for_gate(pos)
	var aabb := Rect2(pos - half, half * 2.0)
	if not corridor.encloses(aabb):
		return false
	_query_shape.size = half * 2.0
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_shape
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = WALL_PLACE_MASK
	var hits := space.intersect_shape(query, 16)
	for hit in hits:
		var collider = hit.get("collider")
		if collider is Node2D and _rejects_placement_geometry(aabb, collider):
			return false
	return true


## Wall/Gate 배치 겹침 판정.
## Wall/Gate 계열은 인접(edge touch, 겹침 면적 0)만 허용하고 실제 겹침만 거부한다.
## 그 외 body(Player/Core Building/Tree trunk/StoneDeposit/Boundary)는 항상 거부.
func _rejects_placement_geometry(query_rect: Rect2, collider: Node2D) -> bool:
	if collider.is_in_group("walls") or collider.is_in_group("gates"):
		var other_size := Vector2(WALL_FOOTPRINT, WALL_FOOTPRINT)
		if collider.is_in_group("gates") and collider.has_method("get_footprint_size"):
			other_size = collider.get_footprint_size()
		var other_rect := Rect2(collider.position - other_size * 0.5, other_size)
		var inter := query_rect.intersection(other_rect)
		if inter.size.x > 0.5 and inter.size.y > 0.5:
			return true
		return false
	return true


## 마우스/셀 위치를 기준으로 성문 방향/형태를 판정.
func _extents_for_gate(pos: Vector2) -> Vector2:
	var dir := _gate_direction_at(pos)
	if dir == "north" or dir == "south":
		return GATE_HORIZONTAL_SIZE * 0.5
	return GATE_VERTICAL_SIZE * 0.5


## Gate Corridor 내부면 Main Road 중심선 축으로 snap.
## N/S Gate는 x=0(중심선)으로 고정, E/W Gate는 y=0으로 고정한다.
func _snap_gate(mouse: Vector2) -> Vector2:
	var dir := _gate_direction_at(mouse)
	if dir == "":
		return _snap(mouse)
	if dir == "north" or dir == "south":
		return Vector2(0, _snap(mouse).y)
	return Vector2(_snap(mouse).x, 0)


func _gate_direction_at(pos: Vector2) -> String:
	var layout := _get_world_map()
	if layout == null:
		return ""
	if layout.has_method("get_gate_corridor_direction"):
		return String(layout.get_gate_corridor_direction(pos))
	return ""


func _get_world_map() -> Node:
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return null
	return world.get_node_or_null("MapLayout")


func _find_deposit_at(pos: Vector2) -> Node:
	var best: Node = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("stone_deposits"):
		var deposit := node as Node2D
		if deposit == null or not is_instance_valid(deposit):
			continue
		var d := deposit.global_position.distance_squared_to(pos)
		if d < best_dist:
			best = deposit
			best_dist = d
	if best != null and best_dist <= DEPOSIT_SNAP_RADIUS * DEPOSIT_SNAP_RADIUS:
		return best
	return null


func _try_place_at(pos: Vector2) -> void:
	if not _is_valid_position(pos):
		feedback.emit("Invalid position")
		return
	var cost: int = int(BUILD_COSTS["lumberyard"].get("wood", 0))
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	VillageResources.spend("wood", cost)
	var lumberyard: Node2D = LUMBERYARD_SCENE.instantiate() as Node2D
	lumberyard.position = pos
	var world = get_tree().get_first_node_in_group("world")
	if world != null:
		world.add_child(lumberyard)
		world.rebuild_navigation()
	else:
		get_parent().add_child(lumberyard)
	feedback.emit("Lumberyard built")
	_set_active(false)


func _try_place_quarry_at(pos: Vector2) -> void:
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
	var quarry: Node2D = QUARRY_SCENE.instantiate() as Node2D
	quarry.position = deposit.global_position
	var world = get_tree().get_first_node_in_group("world")
	if world != null:
		world.add_child(quarry)
		world.rebuild_navigation()
	else:
		get_parent().add_child(quarry)
	if not deposit.occupy(quarry):
		VillageResources.add("wood", cost)
		quarry.queue_free()
		feedback.emit("Deposit already has a Quarry")
		return
	quarry.bind_deposit(deposit)
	feedback.emit("Quarry built")
	_set_active(false)


## TASK-013-1: Wall 연속 배치. 배치 후에도 build mode를 유지해
## 여러 segment를 연속으로 놓을 수 있게 한다. 비용은 segment마다 1회 차감.
func _try_place_wall_at(pos: Vector2) -> void:
	if not _is_valid_wall_position(pos):
		feedback.emit("Invalid wall position")
		return
	var cost: int = int(BUILD_COSTS["wall"].get("wood", 0))
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	VillageResources.spend("wood", cost)
	var wall: Node2D = WALL_SCENE.instantiate() as Node2D
	wall.position = pos
	var world = get_tree().get_first_node_in_group("world")
	if world != null:
		world.add_child(wall)
		world.rebuild_navigation()
	else:
		get_parent().add_child(wall)
	_refresh_neighbor_visuals(pos)
	feedback.emit("Wall built")


## TASK-013-3: 성문 배치. N/E/S/W Gate Corridor 안에서만 허용하며,
## 배치 후 nav rebuild로 collision/navigation에 반영한다.
func _try_place_gate_at(pos: Vector2) -> void:
	if not _is_valid_gate_position(pos):
		feedback.emit("Invalid gate position")
		return
	var cost: int = int(BUILD_COSTS["gate"].get("wood", 0))
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	VillageResources.spend("wood", cost)
	var gate: Node2D = GATE_SCENE.instantiate() as Node2D
	gate.position = pos
	var dir := _gate_direction_at(pos)
	if gate.has_method("setup"):
		gate.setup(dir)
	var world = get_tree().get_first_node_in_group("world")
	if world != null:
		world.add_child(gate)
		world.rebuild_navigation()
	else:
		get_parent().add_child(gate)
	feedback.emit("Gate built")


## TASK-013-2: 간단 철거. Build mode에서 R로 Remove mode 진입 후 Wall/Gate 클릭 시
## Wood 전액 환불하고 제거. 제거 가능 대상은 Wall/Gate뿐(나머지 건물/자원은 삭제 금지).
func _try_remove_wall_at(pos: Vector2) -> void:
	var target: Node2D = null
	var target_is_gate := false
	for node in get_tree().get_nodes_in_group("walls"):
		if not is_instance_valid(node):
			continue
		var wall := node as Node2D
		if wall == null:
			continue
		if (wall.position - pos).length_squared() < 1.0:
			target = wall
			break
	if target == null:
		for node in get_tree().get_nodes_in_group("gates"):
			if not is_instance_valid(node):
				continue
			var gate := node as Node2D
			if gate == null:
				continue
			if (gate.position - pos).length_squared() < 1.0:
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
	target.remove_from_group("gates" if target_is_gate else "walls")
	_refresh_neighbor_visuals(pos)
	target.queue_free()
	var world = get_tree().get_first_node_in_group("world")
	# queue_free는 프레임 종료 시 실제 제거되므로, 제거된 Wall/Gate의 collision/nav가
	# stale로 남지 않도록 debounce nav rebuild로 제거 후 갱신한다.
	if world != null:
		world.rebuild_navigation_debounced()
	if target_is_gate:
		feedback.emit("Gate removed (+%d Wood)" % cost)
	else:
		feedback.emit("Wall removed (+%d Wood)" % cost)


## 인접(상하좌우 1 tile) Wall들의 연결 비주얼을 갱신.
func _refresh_neighbor_visuals(pos: Vector2) -> void:
	for node in get_tree().get_nodes_in_group("walls"):
		if not is_instance_valid(node):
			continue
		var wall := node as Node2D
		if wall == null:
			continue
		var diff: Vector2 = wall.position - pos
		if abs(diff.x) <= WALL_FOOTPRINT and abs(diff.y) <= WALL_FOOTPRINT \
				and diff.length_squared() > 0.1:
			if wall.has_method("refresh_visual"):
				wall.refresh_visual()