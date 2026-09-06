extends Control

const MAP_MARGIN := 10.0
const PORTAL_POS := Vector3(-570.0, 0.0, -210.0)
const CLEARING := Rect2(-180.0, -180.0, 360.0, 360.0)

var _camera_controller: Node = null
var _redraw_elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameSettings.language_changed.connect(_on_language_changed)
	_resolve_camera()
	queue_redraw()


func _process(delta: float) -> void:
	_redraw_elapsed += delta
	if _redraw_elapsed >= 0.12:
		_redraw_elapsed = 0.0
		queue_redraw()


func _on_language_changed(_locale: String) -> void:
	queue_redraw()


func _resolve_camera() -> void:
	if is_instance_valid(_camera_controller):
		return
	_camera_controller = get_tree().get_first_node_in_group("camera_controller_3d")


func _world_to_map(pos: Vector3) -> Vector2:
	var half := WorldCoords3D.WORLD_HALF_UNITS
	var area := size - Vector2.ONE * MAP_MARGIN * 2.0
	return Vector2(
		MAP_MARGIN + (pos.x + half) / (half * 2.0) * area.x,
		MAP_MARGIN + (pos.z + half) / (half * 2.0) * area.y)


func _draw() -> void:
	var bounds := Rect2(Vector2.ONE * MAP_MARGIN, size - Vector2.ONE * MAP_MARGIN * 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.05, 0.055, 0.94))
	draw_rect(bounds, Color(0.18, 0.26, 0.12, 1.0))
	# Western corruption and separating ridge.
	var corrupt_a := _world_to_map(Vector3(-768, 0, -430))
	var corrupt_b := _world_to_map(Vector3(-340, 0, 430))
	draw_rect(Rect2(corrupt_a, corrupt_b - corrupt_a), Color(0.16, 0.08, 0.18, 0.9))
	var north_ridge := PackedVector2Array()
	var south_ridge := PackedVector2Array()
	for z in range(-700, -64, 35):
		north_ridge.append(_world_to_map(Vector3(-325.0 + sin(z * .007) * 27.0, 0, z)))
	for z in range(65, 701, 35):
		south_ridge.append(_world_to_map(Vector3(-325.0 + sin(z * .007) * 27.0, 0, z)))
	draw_polyline(north_ridge, Color(0.48, 0.47, 0.43, 1), 4.0, true)
	draw_polyline(south_ridge, Color(0.48, 0.47, 0.43, 1), 4.0, true)
	# Buildable central clearing.
	var clear_a := _world_to_map(Vector3(CLEARING.position.x, 0, CLEARING.position.y))
	var clear_b := _world_to_map(Vector3(CLEARING.end.x, 0, CLEARING.end.y))
	draw_rect(Rect2(clear_a, clear_b - clear_a), Color(0.31, 0.43, 0.19, 0.78))
	# Meandering river from the production world function.
	var river := PackedVector2Array()
	for z in range(-768, 769, 16):
		river.append(_world_to_map(Vector3(_river_x(float(z)), 0, z)))
	draw_polyline(river, Color(0.16, 0.55, 0.67, 1), 4.0, true)
	# Portal landmark and currently built structures.
	var portal := _world_to_map(PORTAL_POS)
	draw_circle(portal, 7.0, Color(0.54, 0.06, 0.88, 0.45))
	draw_circle(portal, 4.0, Color(0.9, 0.27, 1.0, 1.0))
	for building in get_tree().get_nodes_in_group("buildings_3d"):
		if building is Node3D:
			draw_rect(Rect2(_world_to_map(building.global_position) - Vector2(2, 2), Vector2(4, 4)),
				Color(0.93, 0.76, 0.34, 1.0))
	_draw_camera_view()
	draw_rect(bounds, Color(0.67, 0.59, 0.38, 0.95), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(12, 18), GameSettings.text("minimap"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.88, 0.66, 1.0))


func _draw_camera_view() -> void:
	_resolve_camera()
	if _camera_controller == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var polygon := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(viewport_size.x, 0), viewport_size,
		Vector2(0, viewport_size.y), Vector2.ZERO]:
		var point: Vector3 = _camera_controller.ground_point_from_screen(corner)
		if not point.is_finite():
			return
		polygon.append(_world_to_map(point))
	draw_polyline(polygon, Color(1.0, 0.89, 0.25, 1.0), 1.5, true)
	draw_circle(_world_to_map(_camera_controller.global_position), 2.5,
		Color(1.0, 0.94, 0.45, 1.0))


func _river_x(z: float) -> float:
	return 336.0 + sin(z * 0.016 / 3.0) * 81.0 + sin(z * 0.033 / 3.0 + 0.7) * 27.0
