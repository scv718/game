extends Node2D

const LUMBERYARD_SCENE := preload("res://scenes/lumberyard.tscn")
const QUARRY_SCENE := preload("res://scenes/quarry.tscn")
const BUILD_COSTS := {
	"lumberyard": {"wood": 10},
	"quarry": {"wood": 10},
}
const GRID_SIZE := 16
const BUILDING_SIZE := 32
const PLACE_MASK := 0b111
const DEPOSIT_SNAP_RADIUS := 48.0

signal mode_changed(active: bool)
signal feedback(text: String)
signal building_type_changed(building_type: String)

var _active := false
var _building_type := "lumberyard"
var _ghost: Node2D = null
var _ghost_rect: Polygon2D = null
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
	if event.is_action_pressed("build"):
		_set_active(not _active)
	elif event.is_action_pressed("ui_cancel"):
		if _active:
			_set_active(false)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _active:
		if _building_type == "quarry":
			_try_place_quarry_at(get_global_mouse_position())
		else:
			_try_place_at(_snap(get_global_mouse_position()))


func _process(_delta: float) -> void:
	if not _active:
		return
	var mouse := get_global_mouse_position()
	var target := _snap(mouse)
	if _building_type == "quarry":
		var deposit := _find_deposit_at(mouse)
		if deposit != null:
			target = deposit.global_position
	_show_ghost_at(target)


func _set_building_type(building_type: String) -> void:
	if _building_type == building_type:
		return
	_building_type = building_type
	if _active:
		_show_ghost_at(_snap(get_global_mouse_position()))
	building_type_changed.emit(_building_type)


func _set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	if _active:
		_show_ghost_at(_snap(get_global_mouse_position()))
	elif _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_rect = null
	mode_changed.emit(_active)


func _show_ghost_at(pos: Vector2) -> void:
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
		_ghost_rect.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(BUILDING_SIZE, 0),
			Vector2(BUILDING_SIZE, BUILDING_SIZE), Vector2(0, BUILDING_SIZE)])
		_ghost.add_child(_ghost_rect)
		add_child(_ghost)
	_ghost.position = pos
	_update_ghost_color()


func _circle_polygon(radius: float, segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _update_ghost_color() -> void:
	if _ghost_rect == null:
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
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_shape
	query.transform = Transform2D(0.0, pos + Vector2(BUILDING_SIZE, BUILDING_SIZE) * 0.5)
	query.collision_mask = PLACE_MASK
	var hits := space.intersect_shape(query, 1)
	return hits.is_empty()


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