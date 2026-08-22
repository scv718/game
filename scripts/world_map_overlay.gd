extends Control
class_name WorldMapOverlay

## TASK-MAP-002-1 World Map Overlay.
## Full-screen overlay showing a scaled-down overview of the 192x192 world.
## Information-only screen; no combat/build/RTS commands.
## Root scene node is a CanvasLayer (for layering); this script lives on the
## child Control node which provides _draw() / queue_redraw().

@onready var _map_container: MarginContainer = %MapContainer
@onready var _close_button: Button = %CloseButton
@onready var _title_label: Label = %TitleLabel
@onready var _hint_label: Label = %HintLabel

const WORLD_SIZE := 3072
const WORLD_HALF := 1536
const MAP_PADDING := 16.0

var _is_open := false
var _camera_controller: Node = null


func _ready() -> void:
	add_to_group("world_map_overlay")
	visible = false
	_close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_map"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_is_open = true
	visible = true
	_resolve_camera()
	queue_redraw()


func close() -> void:
	_is_open = false
	visible = false


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func is_open() -> bool:
	return _is_open


func world_to_map(world_pos: Vector2) -> Vector2:
	if _map_container == null:
		return Vector2.ZERO
	var draw_size := _map_container.size
	if draw_size.x <= 0 or draw_size.y <= 0:
		return Vector2.ZERO
	var map_area := draw_size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	var scale_x := map_area.x / float(WORLD_SIZE)
	var scale_y := map_area.y / float(WORLD_SIZE)
	var scale_f := minf(scale_x, scale_y)
	var scaled_size := Vector2(WORLD_SIZE, WORLD_SIZE) * scale_f
	var offset := (draw_size - scaled_size) * 0.5
	return Vector2(
		(world_pos.x + WORLD_HALF) * scale_f + offset.x,
		(world_pos.y + WORLD_HALF) * scale_f + offset.y,
	)


func map_to_world(map_pos: Vector2) -> Vector2:
	if _map_container == null:
		return Vector2.ZERO
	var draw_size := _map_container.size
	if draw_size.x <= 0 or draw_size.y <= 0:
		return Vector2.ZERO
	var map_area := draw_size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	var scale_x := map_area.x / float(WORLD_SIZE)
	var scale_y := map_area.y / float(WORLD_SIZE)
	var scale_f := minf(scale_x, scale_y)
	var scaled_size := Vector2(WORLD_SIZE, WORLD_SIZE) * scale_f
	var offset := (draw_size - scaled_size) * 0.5
	return Vector2(
		(map_pos.x - offset.x) / scale_f - WORLD_HALF,
		(map_pos.y - offset.y) / scale_f - WORLD_HALF,
	)


func _resolve_camera() -> void:
	if _camera_controller != null and is_instance_valid(_camera_controller):
		return
	var ctrls := get_tree().get_nodes_in_group("camera_controller")
	if ctrls.size() > 0:
		_camera_controller = ctrls[0]


func _get_camera_viewport_rect() -> Rect2:
	_resolve_camera()
	if _camera_controller == null:
		return Rect2()
	var cam: Camera2D = _camera_controller.get_camera()
	if cam == null:
		return Rect2()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: Vector2 = cam.zoom
	if zoom.x <= 0.0:
		zoom = Vector2.ONE
	var half_size := (viewport_size / zoom) * 0.5
	var cam_pos := cam.global_position
	return Rect2(cam_pos - half_size, half_size * 2.0)


func _draw() -> void:
	if not _is_open or _map_container == null:
		return
	var draw_size := _map_container.size
	if draw_size.x <= 0 or draw_size.y <= 0:
		return
	var map_area := draw_size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	var scale_x := map_area.x / float(WORLD_SIZE)
	var scale_y := map_area.y / float(WORLD_SIZE)
	var scale_f := minf(scale_x, scale_y)
	var scaled_size := Vector2(WORLD_SIZE, WORLD_SIZE) * scale_f
	var offset := (draw_size - scaled_size) * 0.5
	var bounds_rect := Rect2(offset, scaled_size)

	draw_rect(bounds_rect, Color(0.05, 0.07, 0.09, 0.85))
	draw_rect(bounds_rect, Color(0.4, 0.5, 0.45, 0.8), false, 2.0)

	var clearing_half := Vector2(192, 192)
	var clearing_center := world_to_map(Vector2.ZERO)
	var clearing_size := clearing_half * 2.0 * scale_f
	var clearing_rect := Rect2(clearing_center - clearing_size * 0.5, clearing_size)
	draw_rect(clearing_rect, Color(0.25, 0.35, 0.22, 0.5))
	draw_rect(clearing_rect, Color(0.5, 0.65, 0.5, 0.7), false, 1.0)

	_draw_landmarks(scale_f)

	var vp := _get_camera_viewport_rect()
	if vp.size.x > 0.0 and vp.size.y > 0.0:
		var vp_tl := world_to_map(vp.position)
		var vp_size := vp.size * scale_f
		var vp_rect := Rect2(vp_tl, vp_size)
		draw_rect(vp_rect, Color(1.0, 0.9, 0.3, 0.7), false, 2.0)
		var cam_center := world_to_map(vp.position + vp.size * 0.5)
		draw_circle(cam_center, 3.0, Color(1.0, 0.9, 0.3, 0.9))


func _draw_landmarks(scale_f: float) -> void:
	var landmarks: Array[Dictionary] = [
		{"pos": Vector2.ZERO, "color": Color(0.4, 0.7, 0.4), "sz": 4.0},
		{"pos": Vector2(-1500, 200), "color": Color(0.8, 0.3, 0.3), "sz": 3.0},
		{"pos": Vector2(0, -1500), "color": Color(0.8, 0.5, 0.2), "sz": 3.0},
		{"pos": Vector2(1500, -200), "color": Color(0.3, 0.5, 0.8), "sz": 3.0},
		{"pos": Vector2(0, 1500), "color": Color(0.5, 0.8, 0.3), "sz": 3.0},
		{"pos": Vector2(-1440, 200), "color": Color(0.9, 0.2, 0.2), "sz": 4.0},
		{"pos": Vector2(-200, -1440), "color": Color(0.7, 0.4, 0.7), "sz": 3.0},
		{"pos": Vector2(1060, -1300), "color": Color(0.6, 0.5, 0.3), "sz": 3.0},
		{"pos": Vector2(600, 300), "color": Color(0.5, 0.5, 0.5), "sz": 3.0},
		{"pos": Vector2(-520, -420), "color": Color(0.2, 0.6, 0.2), "sz": 3.0},
		{"pos": Vector2(-750, 600), "color": Color(0.2, 0.5, 0.2), "sz": 3.0},
		{"pos": Vector2(650, -550), "color": Color(0.3, 0.5, 0.3), "sz": 2.5},
	]
	for lm in landmarks:
		var mp := world_to_map(lm["pos"])
		var col: Color = lm["color"]
		var sz: float = lm["sz"]
		draw_circle(mp, sz, col)
		draw_circle(mp, sz + 1.0, Color(col.r, col.g, col.b, 0.3))


func _draw_road_line(road: Array, scale_f: float) -> void:
	if road.size() < 2:
		return
	var pts := PackedVector2Array()
	for p in road:
		pts.append(world_to_map(p))
	draw_polyline(pts, Color(0.35, 0.28, 0.18, 0.6), 1.0)
