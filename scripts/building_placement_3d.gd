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
const FARM_SCENE := preload("res://scenes/farm_3d.tscn")
const WALL_SCENE := preload("res://scenes/wall_3d.tscn")
const GATE_SCENE := preload("res://scenes/gate_3d.tscn")
const CUTESKULL_CITY := preload("res://assets/cuteskull-medieval-city/city16.fbx")
const PIXEL_BUILDING_SCENE := preload("res://scenes/pixel_tavern_3d.tscn")
const PIXEL_LEGACY_TAVERN_TEXTURE := preload("res://assets/production/pixel_buildings/tavern.png")
const PIXEL_BLACKSMITH_TEXTURES := {
	"front": preload("res://assets/production/pixel_buildings/blacksmith_front.png"),
	"back": preload("res://assets/production/pixel_buildings/blacksmith_back.png"),
	"side": preload("res://assets/production/pixel_buildings/blacksmith_side.png"),
	"side_2": preload("res://assets/production/pixel_buildings/blacksmith_side_2.png"),
}
const PIXEL_INN_TEXTURES := {
	"front": preload("res://assets/production/pixel_buildings/inn_front.png"),
	"back": preload("res://assets/production/pixel_buildings/inn_back.png"),
	"side": preload("res://assets/production/pixel_buildings/inn_side.png"),
	"side_2": preload("res://assets/production/pixel_buildings/inn_side_2.png"),
}
const PIXEL_TAVERN_TEXTURES := {
	"front": preload("res://assets/production/pixel_buildings/tavern_front.png"),
	"back": preload("res://assets/production/pixel_buildings/tavern_back.png"),
	"side": preload("res://assets/production/pixel_buildings/tavern_side.png"),
	"side_2": preload("res://assets/production/pixel_buildings/tavern_side_2.png"),
}
const PIXEL_KEEP_TEXTURES := {
	"front": preload("res://assets/production/pixel_buildings/keep_front.png"),
	"back": preload("res://assets/production/pixel_buildings/keep_back.png"),
	"side": preload("res://assets/production/pixel_buildings/keep_side.png"),
	"side_2": preload("res://assets/production/pixel_buildings/keep_side_2.png"),
}
const PIXEL_BUILDING_TEXTURES := {
	"Blacksmith": PIXEL_BLACKSMITH_TEXTURES,
	"Inn": PIXEL_INN_TEXTURES,
	"Tavern": PIXEL_TAVERN_TEXTURES,
	"Keep": PIXEL_KEEP_TEXTURES,
}
const THUMBNAIL_RENDERER_SCRIPT := preload("res://scripts/building_thumbnail_renderer.gd")
const CUTESKULL_BUILDINGS := [
	"House_1_1", "House_1_2",
	"House_2_1", "House_2_2", "House_2_3",
	"House_3_1", "House_3_2",
	"House_4_1", "House_4_2",
	"House_5_1", "House_5_2", "House_5_3",
	"House_6_1", "House_6_2",
	"House_7_1", "House_7_2", "House_7_3",
	"Church_1", "Church_2",
]
const CUTESKULL_DEFENSE := [
	"Castle_Wall",
	"Castle_Entrance", "Castle_Entrance__2",
	"Castle_Tower_1", "Castle_Tower_2", "Castle_Tower_3",
	"Castle_Tower_4", "Castle_Tower_5", "Castle_Tower_6",
	"Castle_Wall_Door", "Castle_Tower_Door",
]
const CUTESKULL_SCALE := 0.17
const PIXEL_BUILDING_EXTENTS_PX := {
	"Blacksmith": Vector2(68.0, 40.0),
	"Inn": Vector2(68.0, 40.0),
	"Tavern": Vector2(68.0, 40.0),
	"Keep": Vector2(92.0, 62.0),
}
const BUILD_COSTS := {
	"lumberyard": {"wood": 0},
	"quarry": {"wood": 0},
	"farm": {"wood": 0},
	"wall": {"wood": 0},
	"gate": {"wood": 0},
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
var _catalog_panel: PanelContainer = null
var _catalog_open := false
var _cuteskull_extents_px: Dictionary = {}
var _cuteskull_lengths_px: Dictionary = {}
var _thumbnail_renderer: BuildingThumbnailRenderer
var _catalog_groups: Dictionary = {}
var _catalog_source_paths: Dictionary = {}
var _catalog_category_containers: Dictionary = {}
var _catalog_title: Label = null
var _catalog_hint: Label = null
var _catalog_filter: OptionButton = null
var _catalog_rotation_quarters := 0
var _wall_drag_start := Vector3.INF
var _wall_dragging := false


func _ready() -> void:
	add_to_group("building_placement")
	add_to_group("building_placement_3d")
	var sample: Node3D = LUMBERYARD_SCENE.instantiate()
	_work_radius_units = sample.work_radius * WorldCoords3D.PX_TO_UNIT
	sample.free()
	_cache_cuteskull_extents()
	_discover_additional_catalog_assets()
	_thumbnail_renderer = THUMBNAIL_RENDERER_SCRIPT.new()
	_thumbnail_renderer.configure(CUTESKULL_CITY)
	_thumbnail_renderer.set_source_paths(_catalog_source_paths)
	add_child(_thumbnail_renderer)
	_build_catalog_ui()
	GameSettings.language_changed.connect(_on_catalog_language_changed)


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
		if event.keycode == KEY_5:
			_set_building_type("farm")
			return
		if event.keycode == KEY_R:
			if _active:
				if _is_cuteskull_type():
					_catalog_rotation_quarters = posmod(_catalog_rotation_quarters + 1, 4)
					_refresh_ghost()
					feedback.emit("Rotation %d°" % _catalog_rotation_degrees())
				elif _is_pixel_type():
					_catalog_rotation_quarters = posmod(_catalog_rotation_quarters + 1, 4)
					_refresh_ghost()
					feedback.emit("픽셀 방향 %d°" % _catalog_rotation_degrees())
				else:
					_set_remove_mode(not _remove_mode)
			return
	if event.is_action_pressed("build"):
		_toggle_catalog()
		get_viewport().set_input_as_handled()
		return
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
				_try_place_at(_catalog_target(ground_pos))
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
	var target := _catalog_target(mouse)
	if _building_type == "quarry":
		var deposit := _find_deposit_at(mouse)
		if deposit != null:
			target = deposit.global_position
	elif _building_type == "gate":
		target = _snap_gate(mouse)
	_show_ghost_at(target)


func _catalog_target(mouse: Vector3) -> Vector3:
	if not _is_cuteskull_type():
		return _snap_cell_center(mouse)
	if _is_catalog_wall():
		return _snap_catalog_wall_endpoint(mouse)
	return _snap_cell_center(mouse)


func _catalog_rotation_degrees() -> float:
	return float(_catalog_rotation_quarters * 90)


func _is_catalog_wall() -> bool:
	return _is_cuteskull_type() and _cuteskull_asset_name() == "Castle_Wall"


func _catalog_defense_kind() -> String:
	if not _is_cuteskull_type():
		return "standard"
	var asset := _cuteskull_asset_name()
	if asset == "Castle_Wall":
		return "wall"
	if asset.begins_with("Castle_Entrance") or asset.ends_with("_Door"):
		return "gate"
	if asset.begins_with("Castle_Tower"):
		return "tower"
	return "defense"


func _snap_catalog_wall_endpoint(mouse: Vector3) -> Vector3:
	var best := _snap_cell_center(mouse)
	var best_distance := 1.25
	for node in get_tree().get_nodes_in_group("catalog_defense_nodes_3d"):
		if not is_instance_valid(node):
			continue
		for endpoint in _defense_endpoints(node as Node3D):
			var distance := WorldCoords3D.distance_xz(endpoint, mouse)
			if distance < best_distance:
				best_distance = distance
				var length: float = _cuteskull_lengths_px.get(_cuteskull_asset_name(), 1.0) * WorldCoords3D.PX_TO_UNIT
				var axis := Vector3(cos(deg_to_rad(_catalog_rotation_degrees())), 0.0,
					-sin(deg_to_rad(_catalog_rotation_degrees())))
				best = endpoint + axis * length * 0.5
	return best


func _defense_endpoints(node: Node3D) -> Array:
	var length := float(node.get_meta("connection_span_units", 0.0))
	if length <= 0.0:
		return []
	if node.get_meta("catalog_kind", "") == "tower":
		var radius := length * 0.5
		return [node.global_position + Vector3(radius, 0.0, 0.0),
			node.global_position + Vector3(-radius, 0.0, 0.0),
			node.global_position + Vector3(0.0, 0.0, radius),
			node.global_position + Vector3(0.0, 0.0, -radius)]
	var axis := Vector3(cos(node.rotation.y), 0.0, -sin(node.rotation.y))
	return [node.global_position - axis * length * 0.5,
		node.global_position + axis * length * 0.5]


## TASK-CTRL-001-2 대응 공개 상태 접근자(기존 2D 계약 동일).
## WorldSelection3D가 build mode 활성 여부를 확인할 때 사용한다.
func is_active() -> bool:
	return _active


func _set_building_type(building_type: String) -> void:
	if _building_type == building_type:
		return
	_building_type = building_type
	_remove_mode = false
	_catalog_rotation_quarters = 0
	_wall_drag_start = Vector3.INF
	_wall_dragging = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_rect = null
		_footprint_material = null
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
	if not value:
		_wall_drag_start = Vector3.INF
		_wall_dragging = false
	if not _active:
		_catalog_open = false
		if _catalog_panel != null:
			_catalog_panel.visible = false
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
	_ghost.rotation.y = deg_to_rad(_catalog_rotation_degrees()) if _is_cuteskull_type() else 0.0
	if _is_pixel_type():
		var pixel_preview := _ghost.get_node_or_null("PixelTavern3D") as StaticBody3D
		if pixel_preview != null:
			_configure_pixel_instance(pixel_preview, _pixel_building_name(), _catalog_rotation_quarters)
	if _is_catalog_wall() and _wall_dragging:
		_rebuild_wall_drag_preview(pos)
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
	if _is_cuteskull_type():
		var model := _make_cuteskull_model(_cuteskull_asset_name(), true)
		if model != null:
			_ghost.add_child(model)
	elif _is_pixel_type():
		var preview := PIXEL_BUILDING_SCENE.instantiate() as StaticBody3D
		preview.collision_layer = 0
		preview.remove_from_group("buildings_3d")
		preview.remove_from_group("pixel_buildings_3d")
		var preview_shape := preview.get_node("CollisionShape3D") as CollisionShape3D
		preview_shape.disabled = true
		_configure_pixel_instance(preview, _pixel_building_name(), _catalog_rotation_quarters)
		var sprite := preview.get_node("Sprite3D") as Sprite3D
		sprite.modulate = Color(0.55, 1.0, 0.62, 0.72)
		_ghost.add_child(preview)
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
	if building_type.begins_with("cuteskull/"):
		return _cuteskull_extents_px.get(_cuteskull_asset_name(building_type), BUILDING_FOOTPRINT_PX * 0.5)
	if _is_pixel_type(building_type):
		return _pixel_extents(_pixel_building_name(building_type))
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
	if _is_cuteskull_type() or _is_pixel_type():
		return _is_valid_catalog_position(pos)
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


func _is_valid_catalog_position(pos: Vector3) -> bool:
	var extents := _extents_for_type(_building_type, pos)
	if not _is_footprint_in_bounds(pos, extents):
		return false
	var aabb := _footprint_aabb(pos, extents)
	for hit in _query_blocker_hits(pos, extents, 16):
		var collider = hit.get("collider")
		if collider is Node3D and collider.is_in_group("catalog_defense_nodes_3d") \
				and _is_catalog_wall_connection(pos, collider as Node3D):
			continue
		if collider is Node3D and _rejects_placement_geometry(aabb, collider):
			return false
	return true


func _is_catalog_wall_connection(pos: Vector3, collider: Node3D) -> bool:
	for endpoint in _defense_endpoints(collider):
		if WorldCoords3D.distance_xz(pos, endpoint) <= 0.3:
			return true
	return false


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
	var cost: int = _cost_for_type(_building_type)
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	VillageResources.spend("wood", cost)
	if _is_cuteskull_type():
		if _is_catalog_wall():
			if not _wall_dragging:
				_wall_drag_start = pos
				_wall_dragging = true
				feedback.emit("Wall line start set; click again to confirm")
				_refresh_ghost()
				return
			if _wall_drag_start.is_finite():
				_try_place_wall_line(_wall_drag_start, pos)
				return
		_try_place_cuteskull_at(pos, cost)
		return
	if _is_pixel_type():
		_try_place_pixel_building_at(pos)
		return
	var scene: PackedScene = _building_scene_for(_building_type)
	var building: Node3D = scene.instantiate() as Node3D
	building.position = WorldCoords3D.flatten(pos)
	var world := get_tree().get_first_node_in_group("world3d")
	if world != null:
		world.add_child(building)
	else:
		get_parent().add_child(building)
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
	feedback.emit("%s built" % _building_type.capitalize())
	_set_active(false)


func _try_place_cuteskull_at(pos: Vector3, cost: int, keep_active: bool = false) -> void:
	var building := StaticBody3D.new()
	building.name = "PlayerBuilding_%s" % _cuteskull_asset_name()
	building.collision_layer = CollisionLayers3D.BUILDING
	building.collision_mask = 0
	building.add_to_group("buildings_3d")
	if _catalog_defense_kind() == "wall":
		building.add_to_group("catalog_defense_walls_3d")
	if _catalog_defense_kind() != "standard":
		building.add_to_group("catalog_defense_nodes_3d")
	building.set_meta("asset_source", "Cuteskull city16.fbx")
	building.set_meta("source_node", _cuteskull_asset_name())
	building.set_meta("catalog_kind", _catalog_defense_kind())
	var connection_span := _extents_for_type(_building_type, pos).x * 2.0 * WorldCoords3D.PX_TO_UNIT
	building.set_meta("connection_span_units", connection_span)
	building.set_meta("segment_length_units", connection_span)
	building.set_meta("catalog_cost", {"wood": cost})
	building.rotation.y = deg_to_rad(_catalog_rotation_degrees())
	var half := _extents_for_type(_building_type, pos) * WorldCoords3D.PX_TO_UNIT
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half.x * 2.0, 3.0, half.y * 2.0)
	shape.shape = box
	shape.position.y = 1.5
	building.add_child(shape)
	var model := _make_cuteskull_model(_cuteskull_asset_name(), false)
	if model == null:
		building.free()
		feedback.emit("Building asset unavailable")
		return
	building.add_child(model)
	building.position = WorldCoords3D.flatten(pos)
	var world := get_tree().get_first_node_in_group("world3d")
	if world != null:
		world.add_child(building)
	else:
		get_parent().add_child(building)
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
	feedback.emit("%s built" % _cuteskull_asset_name())
	if not keep_active:
		_set_active(false)


func _is_cuteskull_type() -> bool:
	return _building_type.begins_with("cuteskull/")


func _is_pixel_type(building_type: String = "") -> bool:
	var value := building_type if building_type != "" else _building_type
	return value.begins_with("pixel/") and (_pixel_building_name(value) in PIXEL_BUILDING_TEXTURES or _pixel_building_name(value) == "Tavern_Pixel")


func _try_place_pixel_building_at(pos: Vector3) -> void:
	var building := PIXEL_BUILDING_SCENE.instantiate() as StaticBody3D
	_configure_pixel_instance(building, _pixel_building_name(), _catalog_rotation_quarters)
	building.position = WorldCoords3D.flatten(pos)
	var world := get_tree().get_first_node_in_group("world3d")
	if world != null:
		world.add_child(building)
	else:
		get_parent().add_child(building)
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
	feedback.emit("픽셀 건물 건설 완료" if GameSettings.locale == "ko" else "Pixel building built")
	_set_active(false)


func _pixel_building_name(building_type: String = "") -> String:
	var value := building_type if building_type != "" else _building_type
	return value.trim_prefix("pixel/")


func _pixel_extents(asset_name: String) -> Vector2:
	return PIXEL_BUILDING_EXTENTS_PX.get(asset_name, Vector2(68.0, 40.0))


func _pixel_texture(asset_name: String, rotation_quarters: int = 0) -> Texture2D:
	if asset_name == "Tavern_Pixel":
		return PIXEL_LEGACY_TAVERN_TEXTURE
	var variants: Dictionary = PIXEL_BUILDING_TEXTURES.get(asset_name, {})
	var keys := ["front", "side", "back", "side_2"]
	return variants.get(keys[posmod(rotation_quarters, keys.size())], null)


func _configure_pixel_instance(instance: StaticBody3D, asset_name: String, rotation_quarters: int) -> void:
	var sprite := instance.get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null:
		return
	sprite.texture = _pixel_texture(asset_name, rotation_quarters)
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# The supplied pixel sheets use a black matte. Remove only near-black matte
	# pixels in the shader while retaining the building's internal dark outlines.
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, blend_mix; uniform sampler2D sprite_tex; void fragment(){ vec4 c=texture(sprite_tex,UV); float l=max(c.r,max(c.g,c.b)); ALBEDO=c.rgb; ALPHA=c.a*smoothstep(0.008,0.035,l); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("sprite_tex", sprite.texture)
	sprite.material_override = material


func _cuteskull_asset_name(building_type: String = "") -> String:
	var value := building_type if building_type != "" else _building_type
	return value.trim_prefix("cuteskull/")


func _cache_cuteskull_extents() -> void:
	var source_root := CUTESKULL_CITY.instantiate()
	for asset_name in CUTESKULL_BUILDINGS + CUTESKULL_DEFENSE:
		_cache_asset_extents(source_root, asset_name, "88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + asset_name)
	source_root.free()


func _cache_asset_extents(source_root: Node, asset_name: String, source_path: String) -> void:
	var source := source_root.get_node_or_null(source_path) as Node3D
	if source == null:
		return
	for child in source.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var size: Vector3 = (child as MeshInstance3D).mesh.get_aabb().size
			_cuteskull_extents_px[asset_name] = Vector2(
				size.x * CUTESKULL_SCALE / WorldCoords3D.PX_TO_UNIT * 0.5,
				size.y * CUTESKULL_SCALE / WorldCoords3D.PX_TO_UNIT * 0.5)
			_cuteskull_lengths_px[asset_name] = size.x * CUTESKULL_SCALE / WorldCoords3D.PX_TO_UNIT
			break


func _discover_additional_catalog_assets() -> void:
	_catalog_groups = {
		"Pixel Buildings": ["Blacksmith", "Inn", "Tavern", "Keep"],
		"Buildings": CUTESKULL_BUILDINGS.duplicate(),
		"Defense": CUTESKULL_DEFENSE.duplicate(),
		"Castle Parts": ["Castle_Roof_1", "Castle_Roof_2"],
		"Market / Props": [],
		"Environment": [],
		"Characters": [],
	}
	var source_root := CUTESKULL_CITY.instantiate()
	for asset_name in CUTESKULL_BUILDINGS + CUTESKULL_DEFENSE:
		_catalog_source_paths[asset_name] = "88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + asset_name
	for asset_name in _catalog_groups["Castle Parts"]:
		_catalog_source_paths[asset_name] = "88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + asset_name
		_cache_asset_extents(source_root, asset_name, _catalog_source_paths[asset_name])
	var categories := {
		"Market / Props": "Market",
		"Environment": "Environment_001",
		"Characters": "People_empty",
	}
	for category in categories:
		var parent := source_root.get_node_or_null(
			"88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + categories[category])
		if parent == null:
			continue
		for child in parent.get_children():
			if not child is Node3D or not _contains_mesh(child):
				continue
			var asset_name := str(child.name)
			_catalog_groups[category].append(asset_name)
			_catalog_source_paths[asset_name] = "88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/%s/%s" % [categories[category], asset_name]
			_cache_asset_extents(source_root, asset_name, _catalog_source_paths[asset_name])
	source_root.free()


func _contains_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return true
	for child in node.get_children():
		if _contains_mesh(child):
			return true
	return false


func _all_catalog_assets() -> Array:
	var result: Array = []
	for category in _catalog_groups:
		for asset_name in _catalog_groups[category]:
			if not result.has(asset_name):
				result.append(asset_name)
	return result


func _make_cuteskull_model(asset_name: String, ghost: bool) -> Node3D:
	var source_root := CUTESKULL_CITY.instantiate()
	var source := source_root.get_node_or_null(_catalog_source_paths.get(
		asset_name, "88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + asset_name)) as Node3D
	if source == null:
		source_root.free()
		return null
	var model := source.duplicate() as Node3D
	model.name = "Cuteskull_%s" % asset_name
	model.scale = Vector3.ONE * CUTESKULL_SCALE
	_normalize_cuteskull_model(model)
	_orient_cuteskull_model(model)
	model.set_meta("asset_source", "Cuteskull city16.fbx")
	model.set_meta("source_node", asset_name)
	if ghost:
		var mat := _ghost_material(COLOR_VALID)
		_apply_ghost_material(model, mat)
	source_root.free()
	return model


func _rebuild_wall_drag_preview(endpoint: Vector3) -> void:
	if _ghost == null or not _wall_drag_start.is_finite():
		return
	for child in _ghost.get_children():
		if child is Node3D and child.name.begins_with("DragWall_"):
			child.queue_free()
	var delta := endpoint - _wall_drag_start
	var horizontal := absf(delta.x) >= absf(delta.z)
	var direction := 1.0 if (delta.x if horizontal else delta.z) >= 0.0 else -1.0
	var distance := absf(delta.x) if horizontal else absf(delta.z)
	var segment_length: float = _cuteskull_lengths_px.get(_cuteskull_asset_name(), 1.0) * WorldCoords3D.PX_TO_UNIT
	var count := maxi(1, int(floor(distance / maxf(segment_length, 0.01))))
	var angle := 0.0 if horizontal else 90.0
	if direction < 0.0:
		angle += 180.0
	_ghost.rotation.y = deg_to_rad(angle)
	for index in count:
		var model := _make_cuteskull_model(_cuteskull_asset_name(), true)
		if model == null:
			continue
		model.name = "DragWall_%d" % index
		model.position = Vector3((index + 0.5) * segment_length, 0.0, 0.0)
		_ghost.add_child(model)


func _try_place_wall_line(start: Vector3, endpoint: Vector3) -> void:
	var delta := endpoint - start
	var horizontal := absf(delta.x) >= absf(delta.z)
	var direction := 1.0 if (delta.x if horizontal else delta.z) >= 0.0 else -1.0
	var distance := absf(delta.x) if horizontal else absf(delta.z)
	var segment_length: float = _cuteskull_lengths_px.get(_cuteskull_asset_name(), 1.0) * WorldCoords3D.PX_TO_UNIT
	var count := maxi(1, int(floor(distance / maxf(segment_length, 0.01))))
	var angle := 0.0 if horizontal else 90.0
	if direction < 0.0:
		angle += 180.0
	_catalog_rotation_quarters = int(round(angle / 90.0)) % 4
	var cost := _cost_for_type(_building_type) * count
	if not VillageResources.has("wood", cost):
		feedback.emit("Not enough Wood")
		return
	for index in count:
		var axis := Vector3(cos(deg_to_rad(angle)), 0.0, -sin(deg_to_rad(angle)))
		var center: Vector3 = start + axis * segment_length * (index + 0.5)
		if not _is_valid_position(center):
			feedback.emit("Invalid wall line")
			return
	VillageResources.spend("wood", cost)
	for index in count:
		var axis := Vector3(cos(deg_to_rad(angle)), 0.0, -sin(deg_to_rad(angle)))
		var center: Vector3 = start + axis * segment_length * (index + 0.5)
		_try_place_cuteskull_at(center, _cost_for_type(_building_type), true)
	feedback.emit("Wall line built (%d segments)" % count)
	_wall_drag_start = Vector3.INF
	_wall_dragging = false
	_set_active(false)


func _normalize_cuteskull_model(model: Node) -> void:
	for child in model.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var aabb := (child as MeshInstance3D).mesh.get_aabb()
			child.position = Vector3(-aabb.position.x - aabb.size.x * 0.5,
				-aabb.position.y - aabb.size.y * 0.5, -aabb.position.z)
			return


func _orient_cuteskull_model(model: Node3D) -> void:
	model.basis = Basis(Vector3.RIGHT, deg_to_rad(-90.0))


func _apply_ghost_material(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_ghost_material(child, mat)


func _cost_for_type(building_type: String) -> int:
	if building_type.begins_with("cuteskull/") or building_type.begins_with("pixel/"):
		return 0
	return int(BUILD_COSTS.get(building_type, {}).get("wood", 0))


func _toggle_catalog() -> void:
	_catalog_open = not _catalog_open
	if _catalog_panel != null:
		_catalog_panel.visible = _catalog_open
	if _catalog_open:
		if not _active:
			_set_active(true)
		feedback.emit(GameSettings.text("catalog_select_prompt"))
	else:
		_set_active(false)


func _build_catalog_ui() -> void:
	var scene_root := get_tree().current_scene
	var hud := scene_root.get_node_or_null("HUD") if scene_root != null else null
	if hud == null:
		hud = get_parent().get_node_or_null("HUD")
	if hud == null:
		return
	_catalog_panel = PanelContainer.new()
	_catalog_panel.name = "BuildingCatalog"
	_catalog_panel.position = Vector2(700, 86)
	_catalog_panel.custom_minimum_size = Vector2(470, 540)
	_catalog_panel.visible = false
	hud.add_child(_catalog_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_catalog_panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	_catalog_title = title
	title.text = GameSettings.text("catalog_title")
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	var hint := Label.new()
	_catalog_hint = hint
	hint.text = GameSettings.text("catalog_hint")
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	column.add_child(hint)
	var category_select := OptionButton.new()
	_catalog_filter = category_select
	category_select.name = "CategoryFilter"
	category_select.custom_minimum_size = Vector2(0, 34)
	for category in _catalog_groups:
		category_select.add_item("%s (%d)" % [_category_display_name(category), _catalog_groups[category].size()])
	category_select.item_selected.connect(_on_catalog_category_changed)
	column.add_child(category_select)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var category_column := VBoxContainer.new()
	category_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(category_column)
	for category in _catalog_groups:
		var category_box := VBoxContainer.new()
		category_box.name = "Category_%s" % category.replace("/", "_").replace(" ", "_")
		category_box.visible = _catalog_category_containers.is_empty()
		_catalog_category_containers[category] = category_box
		category_column.add_child(category_box)
		var section := Label.new()
		section.text = "%s  (%d)" % [_category_display_name(category), _catalog_groups[category].size()]
		section.set_meta("catalog_category", category)
		section.add_theme_font_size_override("font_size", 15)
		section.add_theme_color_override("font_color", Color(0.95, 0.78, 0.42))
		category_box.add_child(section)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_box.add_child(grid)
		for asset_name in _catalog_groups[category]:
			_add_catalog_button(grid, asset_name, category)


func _on_catalog_category_changed(index: int) -> void:
	var categories := _catalog_groups.keys()
	if index < 0 or index >= categories.size():
		return
	for category in _catalog_category_containers:
		_catalog_category_containers[category].visible = category == categories[index]


func _add_catalog_section(grid: GridContainer, title_text: String) -> void:
	var section := Label.new()
	section.text = title_text
	section.add_theme_font_size_override("font_size", 15)
	section.add_theme_color_override("font_color", Color(0.95, 0.78, 0.42))
	grid.add_child(section)
	var spacer := Control.new()
	grid.add_child(spacer)


func _add_catalog_button(grid: GridContainer, asset_name: String, category: String) -> void:
	var item := PanelContainer.new()
	item.custom_minimum_size = Vector2(205, 150)
	grid.add_child(item)
	var column := VBoxContainer.new()
	item.add_child(column)
	var thumbnail := TextureRect.new()
	thumbnail.custom_minimum_size = Vector2(0, 92)
	thumbnail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.texture = _pixel_texture(asset_name, 0) if asset_name in PIXEL_BUILDING_TEXTURES \
		else (_thumbnail_renderer.get_thumbnail(asset_name) if _thumbnail_renderer else null)
	if thumbnail.texture == null:
		thumbnail.tooltip_text = "Preview unavailable: %s" % asset_name
		var fallback := Label.new()
		fallback.text = "[3D PREVIEW\nUNAVAILABLE]"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		thumbnail.add_child(fallback)
	column.add_child(thumbnail)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 50)
	button.text = "%s\n%s • %s" % [asset_name, _category_display_name(category), GameSettings.text("free")]
	button.set_meta("catalog_asset", asset_name)
	button.set_meta("catalog_category", category)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = "%s: %s" % [category, asset_name]
	button.pressed.connect(_on_catalog_item_pressed.bind(asset_name))
	column.add_child(button)


func _category_display_name(category: String) -> String:
	var keys := {
		"Buildings": "buildings", "Defense": "defense", "Castle Parts": "castle_parts",
		"Market / Props": "market_props", "Environment": "environment", "Characters": "characters",
		"Pixel Buildings": "pixel_buildings"}
	return GameSettings.text(keys.get(category, category))


func _on_catalog_language_changed(_locale: String) -> void:
	if _catalog_title == null:
		return
	_catalog_title.text = GameSettings.text("catalog_title")
	_catalog_hint.text = GameSettings.text("catalog_hint")
	var categories := _catalog_groups.keys()
	for index in categories.size():
		var category: String = categories[index]
		_catalog_filter.set_item_text(index, "%s (%d)" % [
			_category_display_name(category), _catalog_groups[category].size()])
	for category in _catalog_category_containers:
		var box: VBoxContainer = _catalog_category_containers[category]
		for node in box.find_children("*", "Label", true, false):
			if node.has_meta("catalog_category"):
				node.text = "%s  (%d)" % [_category_display_name(category), _catalog_groups[category].size()]
		for node in box.find_children("*", "Button", true, false):
			if node.has_meta("catalog_asset"):
				node.text = "%s\n%s • %s" % [str(node.get_meta("catalog_asset")),
					_category_display_name(category), GameSettings.text("free")]


func _on_catalog_item_pressed(asset_name: String) -> void:
	_set_building_type("pixel/%s" % asset_name if asset_name in PIXEL_BUILDING_TEXTURES \
		else "cuteskull/%s" % asset_name)
	_catalog_open = false
	if _catalog_panel != null:
		_catalog_panel.visible = false
	_set_active(true)
	feedback.emit("%s selected" % asset_name)


func get_building_catalog() -> Array:
	var result: Array = []
	for category in _catalog_groups:
		for asset_name in _catalog_groups[category]:
			result.append({"asset_name": asset_name, "category": category, "cost": {"wood": 0},
				"complete": category == "Buildings" or category == "Pixel Buildings"})
	return result


func get_selected_catalog_asset() -> String:
	if _is_cuteskull_type():
		return _cuteskull_asset_name()
	return _pixel_building_name() if _is_pixel_type() else ""


func is_catalog_open() -> bool:
	return _catalog_open


## TASK-019-1: free-building 타입(Lumberyard/Farm)의 scene을 반환.
func _building_scene_for(building_type: String) -> PackedScene:
	if building_type == "farm":
		return FARM_SCENE
	return LUMBERYARD_SCENE


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
