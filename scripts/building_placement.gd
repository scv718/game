extends Node2D

const LUMBERYARD_SCENE := preload("res://scenes/lumberyard.tscn")
const BUILD_COST := {"wood": 10}
const GRID_SIZE := 16
const BUILDING_SIZE := 32
const PLACE_MASK := 0b111

signal mode_changed(active: bool)
signal feedback(text: String)

var _active := false
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
	if event.is_action_pressed("build"):
		_set_active(not _active)
	elif event.is_action_pressed("ui_cancel"):
		if _active:
			_set_active(false)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _active:
		_try_place_at(_snap(get_global_mouse_position()))


func _process(_delta: float) -> void:
	if not _active:
		return
	_show_ghost_at(_snap(get_global_mouse_position()))


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
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_shape
	query.transform = Transform2D(0.0, pos + Vector2(BUILDING_SIZE, BUILDING_SIZE) * 0.5)
	query.collision_mask = PLACE_MASK
	var hits := space.intersect_shape(query, 1)
	return hits.is_empty()


func _try_place_at(pos: Vector2) -> void:
	if not _is_valid_position(pos):
		feedback.emit("Invalid position")
		return
	var cost: int = int(BUILD_COST.get("wood", 0))
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