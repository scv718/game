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
var _world_map: Node = null


func _ready() -> void:
	add_to_group("world_map_overlay")
	visible = false
	_close_button.pressed.connect(close)
	_resolve_world_map()


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


func _resolve_world_map() -> void:
	if _world_map != null and is_instance_valid(_world_map):
		return
	var world := get_node_or_null("/root/Main/World")
	if world == null:
		return
	_world_map = world.get_node_or_null("MapLayout")


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

	var clearing_half: Vector2 = _world_map.get("CLEARING_HALF") if _world_map != null else Vector2(192, 192)
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
	if _world_map == null:
		return
	var font := ThemeDB.fallback_font
	var font_size := int(10.0 * scale_f)
	if font_size < 8:
		font_size = 8
	var label_offset := Vector2(6.0, -6.0)
	
	# Central Settlement
	var settlement_pos: Vector2 = _world_map.get("SETTLEMENT_CENTER")
	_draw_landmark_marker(world_to_map(settlement_pos), Color(0.4, 0.7, 0.4), 5.0, "Settlement", font, font_size, label_offset)
	
	# Gate Anchors (4 directions)
	var gate_anchors: Dictionary = _world_map.get("GATE_ANCHORS")
	var gate_colors := {
		"north": Color(0.8, 0.5, 0.2),
		"south": Color(0.5, 0.8, 0.3),
		"east": Color(0.3, 0.5, 0.8),
		"west": Color(0.8, 0.3, 0.3),
	}
	for dir in gate_anchors:
		var pos: Vector2 = gate_anchors[dir]
		var col: Color = gate_colors.get(dir, Color.WHITE)
		_draw_landmark_marker(world_to_map(pos), col, 3.0, dir.capitalize() + " Gate", font, font_size, label_offset)
	
	# Spawn Candidates / Portals
	var spawn_candidates: Dictionary = _world_map.get("SPAWN_CANDIDATES")
	var spawn_colors := {
		"north": Color(0.7, 0.4, 0.7),
		"south": Color(0.4, 0.7, 0.4),
		"east": Color(0.3, 0.5, 0.8),
		"west": Color(0.9, 0.2, 0.2),
	}
	for dir in spawn_candidates:
		var pos: Vector2 = spawn_candidates[dir]
		var col: Color = spawn_colors.get(dir, Color.WHITE)
		_draw_landmark_marker(world_to_map(pos), col, 4.0, dir.capitalize() + " Portal", font, font_size, label_offset)
	
	# NE Dungeon Candidate
	var dungeon_pos: Vector2 = _world_map.get("NE_DUNGEON_CANDIDATE")
	_draw_landmark_marker(world_to_map(dungeon_pos), Color(0.6, 0.5, 0.3), 3.0, "Dungeon", font, font_size, label_offset)
	
	# Stone Zone
	var stone_center: Vector2 = _world_map.get("STONE_ZONE")["center"]
	_draw_landmark_marker(world_to_map(stone_center), Color(0.5, 0.5, 0.5), 3.0, "Stone Zone", font, font_size, label_offset)
	
	# Forest Clusters
	var forests: Array = _world_map.get("FOREST_CLUSTERS")
	var forest_colors := {
		"starter": Color(0.2, 0.6, 0.2),
		"large": Color(0.2, 0.5, 0.2),
		"sparse": Color(0.3, 0.5, 0.3),
	}
	for cluster in forests:
		var center: Vector2 = cluster["center"]
		var role: String = cluster.get("role", "")
		var col: Color = forest_colors.get(role, Color.GREEN)
		_draw_landmark_marker(world_to_map(center), col, 3.0, role.capitalize() + " Forest", font, font_size, label_offset)
	
	# South Agriculture Zone
	var agri_zone: Rect2 = _world_map.get("SOUTH_AGRICULTURE_ZONE")
	var agri_center := world_to_map(agri_zone.position + agri_zone.size * 0.5)
	_draw_landmark_marker(agri_center, Color(0.5, 0.8, 0.3), 3.0, "Agriculture", font, font_size, label_offset)
	
	# Royal Road (east main road)
	var royal_road: Array = _world_map.get("MAIN_ROADS")["east"]
	_draw_road_line(royal_road, scale_f)
	var road_mid: Vector2 = royal_road[royal_road.size() / 2]
	_draw_landmark_marker(world_to_map(road_mid), Color(0.3, 0.5, 0.8), 2.5, "Royal Road", font, font_size, label_offset)


func _draw_landmark_marker(pos: Vector2, color: Color, radius: float, label: String, font: Font, font_size: int, label_offset: Vector2) -> void:
	draw_circle(pos, radius, color)
	draw_circle(pos, radius + 1.5, Color(color.r, color.g, color.b, 0.3))
	draw_string(font, pos + label_offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.85))


func _draw_road_line(road: Array, scale_f: float) -> void:
	if road.size() < 2:
		return
	var pts := PackedVector2Array()
	for p in road:
		pts.append(world_to_map(p))
	draw_polyline(pts, Color(0.35, 0.28, 0.18, 0.6), 1.0)
