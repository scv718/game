extends Control
class_name WorldMapOverlay

## TASK-MAP-002-1 World Map Overlay.
## Full-screen overlay showing a scaled-down overview of the 192x192 world.
## Information-only screen; no combat/build/RTS commands.
## TASK-EXP-001-2: ExplorationRegion 상태 표시 + region 선택/Explore 시작만 허용.
## Root scene node is a CanvasLayer (for layering); this script lives on the
## child Control node which provides _draw() / queue_redraw().

@onready var _map_container: MarginContainer = %MapContainer
@onready var _close_button: Button = %CloseButton
@onready var _title_label: Label = %TitleLabel
@onready var _hint_label: Label = %HintLabel
@onready var _region_panel: PanelContainer = %RegionPanel
@onready var _region_title_label: Label = %RegionTitleLabel
@onready var _region_status_label: Label = %RegionStatusLabel
@onready var _explore_button: Button = %ExploreButton

const WORLD_SIZE := 3072
const WORLD_HALF := 1536
const MAP_PADDING := 16.0

var _is_open := false
var _camera_controller: Node = null
var _world_map: Node = null
var _exploration: Node = null
## TASK-026-4: ScoutDispatch(Expedition 기반 파견) 매니저. autoload가 아니므로
## lazy resolve하며 없으면 기존 ExplorationManager 직결 진행 경로로 fallback한다.
var _scout_dispatch: Node = null
var _selected_region_id := ""


func _ready() -> void:
	add_to_group("world_map_overlay")
	visible = false
	_close_button.pressed.connect(close)
	_explore_button.pressed.connect(_on_explore_pressed)
	_resolve_world_map()
	_resolve_exploration()
	GameSettings.language_changed.connect(_on_language_changed)
	_refresh_language()


func _on_language_changed(_locale: String) -> void:
	_refresh_language()
	_refresh_region_panel()
	queue_redraw()


func _refresh_language() -> void:
	_title_label.text = GameSettings.text("world_map")
	_hint_label.text = GameSettings.text("map_hint")
	_close_button.text = GameSettings.text("close_m")


func _resolve_exploration() -> void:
	if _exploration != null and is_instance_valid(_exploration):
		return
	_exploration = get_node_or_null("/root/ExplorationManager")
	if _exploration != null:
		_exploration.exploration_started.connect(_on_region_state_changed)
		_exploration.region_discovered.connect(_on_region_state_changed)


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
	_refresh_region_panel()
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


## --- TASK-EXP-001-2 Region 선택 / Explore 시작 ---

func select_region(region_id: String) -> void:
	var region: ExplorationRegion = null if _exploration == null \
		else _exploration.get_region(region_id)
	_selected_region_id = region.region_id if region != null else ""
	_refresh_region_panel()
	queue_redraw()


func get_selected_region_id() -> String:
	return _selected_region_id


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_map_click(event.position)


## Map 좌표 클릭을 region hit-test로 변환한다. 그리기와 동일한 world_to_map/
## map_to_world 변환을 사용해 marker 클릭이 어긋나지 않게 한다.
func _handle_map_click(click_pos: Vector2) -> void:
	if not _is_open or _exploration == null:
		return
	var world_pos := map_to_world(click_pos)
	if _is_3d_runtime():
		world_pos /= WorldCoords3D.PX_TO_UNIT
	for region in _exploration.get_regions():
		if region.contains_world_position(world_pos):
			select_region(region.region_id)
			return
	select_region("")


## TASK-026-4: explore 버튼은 ScoutDispatch(UNKNOWN region에 expedition 파견) 우선,
## 없으면 기존 ExplorationManager 자체 진행 경로로 fallback한다.
func _on_explore_pressed() -> void:
	if _exploration == null or _selected_region_id == "":
		return
	var scout := _resolve_scout_dispatch()
	if scout != null and scout.has_method("dispatch_scout"):
		scout.dispatch_scout(_selected_region_id)
	else:
		_exploration.start_exploration(_selected_region_id)
	_refresh_region_panel()
	queue_redraw()


func _resolve_scout_dispatch() -> Node:
	if _scout_dispatch != null and is_instance_valid(_scout_dispatch):
		return _scout_dispatch
	_scout_dispatch = get_node_or_null("/root/ScoutDispatchManager")
	if _scout_dispatch == null:
		var nodes := get_tree().get_nodes_in_group("scout_dispatch_manager")
		_scout_dispatch = nodes[0] if nodes.size() > 0 else null
	return _scout_dispatch


func _on_region_state_changed(_region_id: String) -> void:
	_refresh_region_panel()
	queue_redraw()


func _refresh_region_panel() -> void:
	if _region_panel == null:
		return
	if _exploration == null:
		_resolve_exploration()
	if _exploration == null:
		_region_panel.visible = false
		return
	_region_panel.visible = true
	if _selected_region_id == "":
		_region_title_label.text = GameSettings.text("region_none")
		_region_status_label.text = GameSettings.text("region_click")
		_explore_button.disabled = true
		_explore_button.text = GameSettings.text("explore")
		return
	var region: ExplorationRegion = _exploration.get_region(_selected_region_id)
	if region == null:
		_selected_region_id = ""
		_refresh_region_panel()
		return
	_region_title_label.text = region.display_name
	match region.get_discovery_state():
		ExplorationRegion.DiscoveryState.UNKNOWN:
			_region_status_label.text = ("미발견 | 위험 %d | 조사 %d초" if GameSettings.locale == "ko" \
				else "UNKNOWN | Risk %d | %ds survey") % [region.base_risk, int(region.exploration_duration)]
			_explore_button.disabled = false
			_explore_button.text = GameSettings.text("explore")
		ExplorationRegion.DiscoveryState.EXPLORING:
			_region_status_label.text = ("탐험 중 | %d%%" if GameSettings.locale == "ko" else "EXPLORING | %d%%") \
				% int(round(_exploration.get_progress(region.region_id) * 100.0))
			_explore_button.disabled = true
			_explore_button.text = GameSettings.text("exploring")
		ExplorationRegion.DiscoveryState.DISCOVERED:
			var features := ", ".join(PackedStringArray(region.get_discovered_features()))
			_region_status_label.text = ("발견 완료 | 발견물: %s" if GameSettings.locale == "ko" \
				else "DISCOVERED | Found: %s") % features
			_explore_button.disabled = true
			_explore_button.text = GameSettings.text("discovered")


func _has_exploring_region() -> bool:
	if _exploration == null:
		return false
	for region in _exploration.get_regions():
		if region.get_discovery_state() == ExplorationRegion.DiscoveryState.EXPLORING:
			return true
	return false


func _process(_delta: float) -> void:
	# EXPLORING 중에는 진행도 표시를 실시간 갱신한다(열려 있을 때만).
	if not _is_open or not _has_exploring_region():
		return
	_refresh_region_panel()
	queue_redraw()


func world_to_map(world_pos: Vector2) -> Vector2:
	if _map_container == null:
		return Vector2.ZERO
	var draw_size := _map_container.size
	if draw_size.x <= MAP_PADDING * 2.0 or draw_size.y <= MAP_PADDING * 2.0:
		draw_size = Vector2(512.0, 512.0)
	var map_area := draw_size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	var world_size := _map_world_size()
	var world_half := world_size * 0.5
	var scale_x := map_area.x / world_size
	var scale_y := map_area.y / world_size
	var scale_f := minf(scale_x, scale_y)
	var scaled_size := Vector2(world_size, world_size) * scale_f
	var offset := (draw_size - scaled_size) * 0.5
	return Vector2(
		(world_pos.x + world_half) * scale_f + offset.x,
		(world_pos.y + world_half) * scale_f + offset.y,
	)


func map_to_world(map_pos: Vector2) -> Vector2:
	if _map_container == null:
		return Vector2.ZERO
	var draw_size := _map_container.size
	if draw_size.x <= MAP_PADDING * 2.0 or draw_size.y <= MAP_PADDING * 2.0:
		draw_size = Vector2(512.0, 512.0)
	var map_area := draw_size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	var world_size := _map_world_size()
	var world_half := world_size * 0.5
	var scale_x := map_area.x / world_size
	var scale_y := map_area.y / world_size
	var scale_f := minf(scale_x, scale_y)
	var scaled_size := Vector2(world_size, world_size) * scale_f
	var offset := (draw_size - scaled_size) * 0.5
	return Vector2(
		(map_pos.x - offset.x) / scale_f - world_half,
		(map_pos.y - offset.y) / scale_f - world_half,
	)


func _is_3d_runtime() -> bool:
	_resolve_camera()
	return _camera_controller != null and _camera_controller.has_method("ground_point_from_screen")


func _map_world_size() -> float:
	return WorldCoords3D.WORLD_HALF_UNITS * 2.0 if _is_3d_runtime() else float(WORLD_SIZE)


func _layout_point(point: Vector2) -> Vector2:
	return point * WorldCoords3D.PX_TO_UNIT if _is_3d_runtime() else point


func _resolve_world_map() -> void:
	if _world_map != null and is_instance_valid(_world_map):
		return
	# 2D Main World(/root/Main/World)와 3D Main World(/root/Main3D/World3D)를
	# 모두 지원한다(TASK-3D-INT-001-2). 어느 쪽도 없으면 landmark 없이 안전하게 동작.
	var world := get_node_or_null("/root/Main/World")
	if world == null:
		world = get_node_or_null("/root/Main3D/World3D")
	if world == null:
		return
	_world_map = world.get_node_or_null("MapLayout")


func _resolve_camera() -> void:
	if _camera_controller != null and is_instance_valid(_camera_controller):
		return
	var ctrls := get_tree().get_nodes_in_group("camera_controller")
	if ctrls.size() > 0:
		_camera_controller = ctrls[0]
		return
	# 3D runtime은 camera_controller_3d 그룹의 CameraController3D를 사용한다.
	ctrls = get_tree().get_nodes_in_group("camera_controller_3d")
	if ctrls.size() > 0:
		_camera_controller = ctrls[0]


func _get_camera_viewport_rect() -> Rect2:
	_resolve_camera()
	if _camera_controller == null:
		return Rect2()
	if _camera_controller.has_method("ground_point_from_screen"):
		return _get_camera_ground_rect_3d()
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


## TASK-3D-INT-001-2: 3D 카메라의 화면 4모서리 광선을 지면(Y=0)과 교차시켜
## 가시 지면 영역을 logical 좌표계 Rect2로 반환한다(2D viewport rect와 동일 소비).
## 광선이 지면과 교차하지 않으면 빈 Rect2(그리기 생략).
func _get_camera_ground_rect_3d() -> Rect2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var min_point := Vector2.INF
	var max_point := -Vector2.INF
	for corner in [
		Vector2.ZERO,
		Vector2(viewport_size.x, 0.0),
		Vector2(0.0, viewport_size.y),
		viewport_size,
	]:
		var ground: Vector3 = _camera_controller.ground_point_from_screen(corner)
		if not ground.is_finite():
			return Rect2()
		var world_xz := Vector2(ground.x, ground.z)
		min_point = min_point.min(world_xz)
		max_point = max_point.max(world_xz)
	return Rect2(min_point, max_point - min_point)


func _draw() -> void:
	if not _is_open or _map_container == null:
		return
	var draw_size := _map_container.size
	if draw_size.x <= MAP_PADDING * 2.0 or draw_size.y <= MAP_PADDING * 2.0:
		return
	var map_area := draw_size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	var world_size := _map_world_size()
	var scale_x := map_area.x / world_size
	var scale_y := map_area.y / world_size
	var scale_f := minf(scale_x, scale_y)
	var scaled_size := Vector2(world_size, world_size) * scale_f
	var offset := (draw_size - scaled_size) * 0.5
	var bounds_rect := Rect2(offset, scaled_size)

	draw_rect(bounds_rect, Color(0.16, 0.23, 0.11, 0.96))
	draw_rect(bounds_rect, Color(0.4, 0.5, 0.45, 0.8), false, 2.0)
	if _is_3d_runtime():
		_draw_natural_world_map()

	var clearing_half: Vector2 = _world_map.get("CLEARING_HALF") if _world_map != null else Vector2(192, 192)
	var clearing_center := world_to_map(Vector2.ZERO)
	var clearing_size := clearing_half * 2.0 * (WorldCoords3D.PX_TO_UNIT if _is_3d_runtime() else 1.0) * scale_f
	var clearing_rect := Rect2(clearing_center - clearing_size * 0.5, clearing_size)
	draw_rect(clearing_rect, Color(0.25, 0.35, 0.22, 0.5))
	draw_rect(clearing_rect, Color(0.5, 0.65, 0.5, 0.7), false, 1.0)

	_draw_landmarks(scale_f)
	_draw_exploration_regions()

	var vp := _get_camera_viewport_rect()
	if vp.size.x > 0.0 and vp.size.y > 0.0:
		var vp_tl := world_to_map(vp.position)
		var vp_size := vp.size * scale_f
		var vp_rect := Rect2(vp_tl, vp_size)
		draw_rect(vp_rect, Color(1.0, 0.9, 0.3, 0.7), false, 2.0)
		var cam_center := world_to_map(vp.position + vp.size * 0.5)
		draw_circle(cam_center, 3.0, Color(1.0, 0.9, 0.3, 0.9))


func _draw_natural_world_map() -> void:
	var corrupt_a := world_to_map(Vector2(-WorldCoords3D.WORLD_HALF_UNITS, -430.0))
	var corrupt_b := world_to_map(Vector2(-340.0, 430.0))
	draw_rect(Rect2(corrupt_a, corrupt_b - corrupt_a), Color(0.18, 0.065, 0.2, 0.92))
	var north_ridge := PackedVector2Array()
	var south_ridge := PackedVector2Array()
	for z in range(-700, -64, 24):
		north_ridge.append(world_to_map(Vector2(-325.0 + sin(z * .007) * 27.0, z)))
	for z in range(65, 701, 24):
		south_ridge.append(world_to_map(Vector2(-325.0 + sin(z * .007) * 27.0, z)))
	draw_polyline(north_ridge, Color(0.5, 0.48, 0.43, 1.0), 7.0, true)
	draw_polyline(south_ridge, Color(0.5, 0.48, 0.43, 1.0), 7.0, true)
	var river := PackedVector2Array()
	for z in range(-768, 769, 12):
		var x := 336.0 + sin(z * 0.016 / 3.0) * 81.0 + sin(z * 0.033 / 3.0 + 0.7) * 27.0
		river.append(world_to_map(Vector2(x, z)))
	draw_polyline(river, Color(0.1, 0.48, 0.65, 1.0), 8.0, true)
	var portal := world_to_map(Vector2(-570.0, -210.0))
	draw_circle(portal, 13.0, Color(0.48, 0.02, 0.75, 0.5))
	draw_circle(portal, 7.0, Color(0.88, 0.18, 1.0, 1.0))


func _draw_landmarks(scale_f: float) -> void:
	if _world_map == null:
		return
	var font := ThemeDB.fallback_font
	var font_size := int(10.0 * scale_f)
	if font_size < 8:
		font_size = 8
	var label_offset := Vector2(6.0, -6.0)
	
	# Central Settlement
	var settlement_pos: Vector2 = _layout_point(_world_map.get("SETTLEMENT_CENTER"))
	_draw_landmark_marker(world_to_map(settlement_pos), Color(0.4, 0.7, 0.4), 5.0,
		"정착지" if GameSettings.locale == "ko" else "Settlement", font, font_size, label_offset)
	
	# Gate Anchors (4 directions)
	var gate_anchors: Dictionary = _world_map.get("GATE_ANCHORS")
	var gate_colors := {
		"north": Color(0.8, 0.5, 0.2),
		"south": Color(0.5, 0.8, 0.3),
		"east": Color(0.3, 0.5, 0.8),
		"west": Color(0.8, 0.3, 0.3),
	}
	for dir in gate_anchors:
		var pos: Vector2 = _layout_point(gate_anchors[dir])
		var col: Color = gate_colors.get(dir, Color.WHITE)
		_draw_landmark_marker(world_to_map(pos), col, 3.0, _direction_name(dir) + (" 성문" if GameSettings.locale == "ko" else " Gate"), font, font_size, label_offset)
	
	# Spawn Candidates / Portals
	var spawn_candidates: Dictionary = _world_map.get("SPAWN_CANDIDATES")
	var spawn_colors := {
		"north": Color(0.7, 0.4, 0.7),
		"south": Color(0.4, 0.7, 0.4),
		"east": Color(0.3, 0.5, 0.8),
		"west": Color(0.9, 0.2, 0.2),
	}
	for dir in spawn_candidates:
		var pos: Vector2 = _layout_point(spawn_candidates[dir])
		var col: Color = spawn_colors.get(dir, Color.WHITE)
		_draw_landmark_marker(world_to_map(pos), col, 4.0, _direction_name(dir) + (" 포탈" if GameSettings.locale == "ko" else " Portal"), font, font_size, label_offset)
	
	# NE Dungeon Candidate
	var dungeon_pos: Vector2 = _layout_point(_world_map.get("NE_DUNGEON_CANDIDATE"))
	_draw_landmark_marker(world_to_map(dungeon_pos), Color(0.6, 0.5, 0.3), 3.0, "던전" if GameSettings.locale == "ko" else "Dungeon", font, font_size, label_offset)
	
	# Stone Zone
	var stone_center: Vector2 = _layout_point(_world_map.get("STONE_ZONE")["center"])
	_draw_landmark_marker(world_to_map(stone_center), Color(0.5, 0.5, 0.5), 3.0, "채석 지역" if GameSettings.locale == "ko" else "Stone Zone", font, font_size, label_offset)
	
	# Forest Clusters
	var forests: Array = _world_map.get("FOREST_CLUSTERS")
	var forest_colors := {
		"starter": Color(0.2, 0.6, 0.2),
		"large": Color(0.2, 0.5, 0.2),
		"sparse": Color(0.3, 0.5, 0.3),
	}
	for cluster in forests:
		var center: Vector2 = _layout_point(cluster["center"])
		var role: String = cluster.get("role", "")
		var col: Color = forest_colors.get(role, Color.GREEN)
		_draw_landmark_marker(world_to_map(center), col, 3.0,
			("숲" if GameSettings.locale == "ko" else role.capitalize() + " Forest"), font, font_size, label_offset)
	
	# South Agriculture Zone
	var agri_zone: Rect2 = _world_map.get("SOUTH_AGRICULTURE_ZONE")
	var agri_center := world_to_map(_layout_point(agri_zone.position + agri_zone.size * 0.5))
	_draw_landmark_marker(agri_center, Color(0.5, 0.8, 0.3), 3.0, "농업 지대" if GameSettings.locale == "ko" else "Agriculture", font, font_size, label_offset)
	
	# Royal Road (east main road)
	var royal_road: Array = _world_map.get("MAIN_ROADS")["east"]
	_draw_road_line(royal_road, scale_f)
	var road_mid: Vector2 = _layout_point(royal_road[royal_road.size() / 2])
	_draw_landmark_marker(world_to_map(road_mid), Color(0.3, 0.5, 0.8), 2.5, "왕도" if GameSettings.locale == "ko" else "Royal Road", font, font_size, label_offset)


func _direction_name(direction: String) -> String:
	if GameSettings.locale != "ko":
		return direction.capitalize()
	return {"north": "북쪽", "south": "남쪽", "east": "동쪽", "west": "서쪽"}.get(direction, direction)


func _draw_landmark_marker(pos: Vector2, color: Color, radius: float, label: String, font: Font, font_size: int, label_offset: Vector2) -> void:
	draw_circle(pos, radius, color)
	draw_circle(pos, radius + 1.5, Color(color.r, color.g, color.b, 0.3))
	draw_string(font, pos + label_offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.85))


## TASK-EXP-001-2 ExplorationRegion 상태 마커.
## UNKNOWN = 회색 외곽선, EXPLORING = 호박색 + 진행도 arc, DISCOVERED = 채워진 초록.
## 기존 Dungeon landmark와 겹치지 않게 라벨은 marker 하단에 표시한다.
func _draw_exploration_regions() -> void:
	if _exploration == null or not _exploration.is_inside_tree():
		return
	var font := ThemeDB.fallback_font
	for region in _exploration.get_regions():
		var pos := world_to_map(_layout_point(region.world_position))
		var state: int = region.get_discovery_state()
		var col := Color(0.55, 0.62, 0.7, 0.95)
		var label_suffix := " (?)"
		if state == ExplorationRegion.DiscoveryState.EXPLORING:
			col = Color(0.95, 0.75, 0.3, 0.95)
			label_suffix = " %d%%" % int(round(_exploration.get_progress(region.region_id) * 100.0))
		elif state == ExplorationRegion.DiscoveryState.DISCOVERED:
			col = Color(0.4, 0.85, 0.45, 0.95)
			label_suffix = " (Discovered)"
		if region.region_id == _selected_region_id:
			draw_circle(pos, 11.0, Color(1.0, 1.0, 1.0, 0.35), false, 1.5)
		if state == ExplorationRegion.DiscoveryState.DISCOVERED \
				or state == ExplorationRegion.DiscoveryState.EXPLORING:
			draw_circle(pos, 6.0, col)
		else:
			draw_circle(pos, 6.0, col, false, 2.0)
		if state == ExplorationRegion.DiscoveryState.EXPLORING:
			var progress: float = _exploration.get_progress(region.region_id)
			draw_arc(pos, 9.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 24,
				Color(0.95, 0.75, 0.3, 0.8), 2.0)
		draw_string(font, pos + Vector2(-30.0, 22.0), region.display_name + label_suffix,
			HORIZONTAL_ALIGNMENT_CENTER, 60, 10, Color(1.0, 1.0, 1.0, 0.9))


func _draw_road_line(road: Array, scale_f: float) -> void:
	if road.size() < 2:
		return
	var pts := PackedVector2Array()
	for p in road:
		pts.append(world_to_map(_layout_point(p)))
	draw_polyline(pts, Color(0.35, 0.28, 0.18, 0.6), 1.0)

