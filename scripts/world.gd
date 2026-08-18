extends Node2D

const BOUNDS_RECT := Rect2(-256, -256, 1664, 1152)
const PARSE_AGENT_RADIUS := 8.0

@onready var _nav_region: NavigationRegion2D = $NavigationRegion2D

var _nav_rebuild_pending := false
var _nav_rebuild_timer: SceneTreeTimer = null
var nav_rebuild_count := 0


func _ready() -> void:
	add_to_group("world")
	NavigationServer2D.map_set_active(get_world_2d().get_navigation_map(), true)
	rebuild_navigation()


func rebuild_navigation_debounced() -> void:
	if not is_inside_tree():
		return
	_nav_rebuild_pending = true
	if _nav_rebuild_timer != null:
		return
	_nav_rebuild_timer = get_tree().create_timer(0.1)
	_nav_rebuild_timer.timeout.connect(_flush_nav_rebuild)


func _flush_nav_rebuild() -> void:
	_nav_rebuild_timer = null
	if not is_inside_tree() or not _nav_rebuild_pending:
		return
	_nav_rebuild_pending = false
	nav_rebuild_count += 1
	rebuild_navigation()


func rebuild_navigation() -> void:
	var source_geometry := NavigationMeshSourceGeometryData2D.new()
	var nav_poly := NavigationPolygon.new()
	nav_poly.agent_radius = PARSE_AGENT_RADIUS
	NavigationServer2D.parse_source_geometry_data(nav_poly, source_geometry, self)
	source_geometry.add_traversable_outline(_closed_rect(BOUNDS_RECT))
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
	_nav_region.navigation_polygon = nav_poly


func _closed_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
		rect.position,
	])
