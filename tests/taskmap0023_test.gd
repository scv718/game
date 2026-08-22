extends SceneTree

## TASK-MAP-002-3 World Map 통합 검증.
## World Map Overlay의 전반적인 동작을 검증한다:
## - DAY/NIGHT 모두에서 map open/close 정상.
## - landmark 표시.
## - camera viewport 표시.
## - camera pan/zoom 정상.
## - Tactical Command state 보존.
## - 기존 시스템 회귀.

enum Phase {
	SETUP,
	DAY_MAP_OPEN,
	CAMERA_VIEWPORT,
	MAP_CLOSE,
	CAMERA_PAN_ZOOM,
	NIGHT_TRANSITION,
	NIGHT_MAP,
	TACTICAL_COMMAND,
	DAY_RETURN,
	REGRESSION,
	DONE,
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _failed := false

var _main: Node = null
var _world: Node = null
var _overlay: Node = null
var _game_time: Node = null
var _selection: Node = null
var _controller: Node = null
var _tactical_ui: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0


func _finish() -> void:
	print("TASKMAP0023_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _m_key_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_M
	ev.physical_keycode = KEY_M
	ev.pressed = true
	return ev


func _esc_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


func _wheel_up_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	return ev


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _sub == 0:
				if _frame < 8:
					return false
				_main = root.get_node("Main")
				_world = _main.get_node("World")
				_game_time = root.get_node("GameTime")
				_game_time.set_auto_advance(false)
				_game_time.set_durations(2.0, 1.0)
				_selection = _main.get_node_or_null("WorldSelection")
				var ctrls := get_nodes_in_group("camera_controller")
				_controller = ctrls[0] if ctrls.size() > 0 else null

				var overlays := get_nodes_in_group("world_map_overlay")
				_check(overlays.size() == 1, "exactly 1 WorldMapOverlay (%d)" % overlays.size())
				_overlay = overlays[0] if overlays.size() > 0 else null
				_check(_overlay != null, "WorldMapOverlay exists")
				_check(_overlay.has_method("is_open"), "WorldMapOverlay has is_open()")
				_check(_overlay.has_method("open"), "WorldMapOverlay has open()")
				_check(_overlay.has_method("close"), "WorldMapOverlay has close()")
				_check(_overlay.has_method("toggle"), "WorldMapOverlay has toggle()")
				_check(_overlay.has_method("world_to_map"), "WorldMapOverlay has world_to_map()")
				_check(_overlay.has_method("map_to_world"), "WorldMapOverlay has map_to_world()")
				_check(_overlay.is_open() == false, "overlay starts closed")
				_check(_overlay.visible == false, "overlay hidden initially")

				_check(_controller != null, "CameraController present")
				_check(_controller.get_camera() != null, "Camera2D present")

				var tactical_nodes := get_nodes_in_group("tactical_command_ui")
				_check(tactical_nodes.size() == 1, "exactly 1 TacticalCommandUI (%d)" % tactical_nodes.size())
				_tactical_ui = tactical_nodes[0] if tactical_nodes.size() > 0 else null

				_sub = 1
			elif _sub == 1:
				_enter(Phase.DAY_MAP_OPEN)
		Phase.DAY_MAP_OPEN:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "starting in DAY phase")
				_overlay.open()
				_check(_overlay.is_open(), "map opens in DAY")
				_check(_overlay.visible, "overlay visible in DAY")
				_sub = 1
			elif _sub == 1:
				var wm: Node = _overlay._world_map
				_check(wm != null, "world_map resolved in overlay")
				_check(wm.get("SETTLEMENT_CENTER") != null, "SETTLEMENT_CENTER accessible")
				_check(wm.get("GATE_ANCHORS") != null, "GATE_ANCHORS accessible")
				_check(wm.get("SPAWN_CANDIDATES") != null, "SPAWN_CANDIDATES accessible")
				_check(wm.get("NE_DUNGEON_CANDIDATE") != null, "NE_DUNGEON_CANDIDATE accessible")
				_check(wm.get("STONE_ZONE") != null, "STONE_ZONE accessible")
				_check(wm.get("FOREST_CLUSTERS") != null, "FOREST_CLUSTERS accessible")
				_check(wm.get("SOUTH_AGRICULTURE_ZONE") != null, "SOUTH_AGRICULTURE_ZONE accessible")
				_check(wm.get("MAIN_ROADS") != null, "MAIN_ROADS accessible")
				_check(wm.get("CLEARING_HALF") != null, "CLEARING_HALF accessible")
				_sub = 2
			elif _sub == 2:
				var settlement: Vector2 = _overlay._world_map.get("SETTLEMENT_CENTER")
				var mp: Vector2 = _overlay.world_to_map(settlement)
				_check(mp.x >= 0 and mp.y >= 0, \
					"Settlement center maps to positive coords (%s)" % str(mp))
				var gate_anchors: Dictionary = _overlay._world_map.get("GATE_ANCHORS")
				var gate_positions: Array = []
				for dir in gate_anchors:
					var pos: Vector2 = gate_anchors[dir]
					var map_pos: Vector2 = _overlay.world_to_map(pos)
					_check(map_pos.x >= 0 and map_pos.y >= 0, \
						"%s Gate maps to positive coords (%s)" % [dir.capitalize(), str(map_pos)])
					gate_positions.append(map_pos)
				var unique_positions := {}
				for p in gate_positions:
					unique_positions[str(p)] = true
				_check(unique_positions.size() == 4, \
					"4 distinct Gate Anchor map positions (got %d)" % unique_positions.size())
				_sub = 3
			elif _sub == 3:
				var spawn_candidates: Dictionary = _overlay._world_map.get("SPAWN_CANDIDATES")
				for dir in spawn_candidates:
					var pos: Vector2 = spawn_candidates[dir]
					var map_pos: Vector2 = _overlay.world_to_map(pos)
					_check(map_pos.x >= 0 and map_pos.y >= 0, \
						"%s Portal maps to positive coords (%s)" % [dir.capitalize(), str(map_pos)])
				_sub = 4
			elif _sub == 4:
				var dungeon_pos: Vector2 = _overlay._world_map.get("NE_DUNGEON_CANDIDATE")
				var dungeon_map: Vector2 = _overlay.world_to_map(dungeon_pos)
				_check(dungeon_map.x >= 0 and dungeon_map.y >= 0, \
					"Dungeon maps to positive coords (%s)" % str(dungeon_map))
				var stone_center: Vector2 = _overlay._world_map.get("STONE_ZONE")["center"]
				var stone_map: Vector2 = _overlay.world_to_map(stone_center)
				_check(stone_map.x >= 0 and stone_map.y >= 0, \
					"Stone Zone maps to positive coords (%s)" % str(stone_map))
				_sub = 5
			elif _sub == 5:
				var forests: Array = _overlay._world_map.get("FOREST_CLUSTERS")
				for cluster in forests:
					var center: Vector2 = cluster["center"]
					var role: String = cluster.get("role", "")
					var forest_map: Vector2 = _overlay.world_to_map(center)
					_check(forest_map.x >= 0 and forest_map.y >= 0, \
						"%s Forest maps to positive coords (%s)" % [role.capitalize(), str(forest_map)])
				_sub = 6
			elif _sub == 6:
				var agri_zone: Rect2 = _overlay._world_map.get("SOUTH_AGRICULTURE_ZONE")
				var agri_center_world := agri_zone.position + agri_zone.size * 0.5
				var agri_map: Vector2 = _overlay.world_to_map(agri_center_world)
				_check(agri_map.x >= 0 and agri_map.y >= 0, \
					"Agriculture maps to positive coords (%s)" % str(agri_map))
				var royal_road: Array = _overlay._world_map.get("MAIN_ROADS")["east"]
				_check(royal_road.size() >= 2, \
					"Royal Road has %d points (>= 2)" % royal_road.size())
				var road_mid: Vector2 = royal_road[royal_road.size() / 2]
				var road_map: Vector2 = _overlay.world_to_map(road_mid)
				_check(road_map.x >= 0 and road_map.y >= 0, \
					"Royal Road midpoint maps to positive coords (%s)" % str(road_map))
				_enter(Phase.CAMERA_VIEWPORT)
		Phase.CAMERA_VIEWPORT:
			if _sub == 0:
				var vp: Rect2 = _overlay._get_camera_viewport_rect()
				_check(vp.size.x > 0 and vp.size.y > 0, \
					"camera viewport rect has positive size (%s)" % str(vp.size))
				var cam_center: Vector2 = vp.position + vp.size * 0.5
				var world_bounds: Rect2 = _controller.get_world_bounds()
				_check(world_bounds.has_point(cam_center), \
					"camera viewport center within world bounds (%s)" % str(cam_center))
				_sub = 1
			elif _sub == 1:
				var vp2: Rect2 = _overlay._get_camera_viewport_rect()
				var tl_map: Vector2 = _overlay.world_to_map(vp2.position)
				var br_map: Vector2 = _overlay.world_to_map(vp2.position + vp2.size)
				_check(tl_map.x >= 0 and tl_map.y >= 0, \
					"viewport top-left maps to positive coords (%s)" % str(tl_map))
				_check(br_map.x >= 0 and br_map.y >= 0, \
					"viewport bottom-right maps to positive coords (%s)" % str(br_map))
				_enter(Phase.MAP_CLOSE)
		Phase.MAP_CLOSE:
			if _sub == 0:
				_overlay.close()
				_check(_overlay.is_open() == false, "map closes")
				_check(_overlay.visible == false, "overlay hidden after close")
				_sub = 1
			elif _sub == 1:
				_check(_controller._is_map_overlay_open() == false, \
					"camera controller detects map overlay closed")
				if _selection != null:
					_check(_selection.can_handle_world_click() == true or \
						_game_time.get_phase() != GameTime.Phase.DAY, \
						"world click re-enabled after map overlay close")
				_enter(Phase.CAMERA_PAN_ZOOM)
		Phase.CAMERA_PAN_ZOOM:
			if _sub == 0:
				var cam: Camera2D = _controller.get_camera()
				var before_pos: Vector2 = cam.global_position
				_controller.pan_camera(Vector2(100, 0))
				var after_pos: Vector2 = cam.global_position
				_check(after_pos.x > before_pos.x, \
					"camera pan right increased x (%.1f -> %.1f)" % [before_pos.x, after_pos.x])
				_sub = 1
			elif _sub == 1:
				var cam2: Camera2D = _controller.get_camera()
				var before_zoom: float = cam2.zoom.x
				_controller._unhandled_input(_wheel_up_event())
				var target: float = _controller.get_zoom_target()
				_check(target > before_zoom or target >= _controller.max_zoom, \
					"zoom target changed after wheel up (%.2f -> %.2f)" % [before_zoom, target])
				_sub = 2
			elif _sub == 2:
				var cam3: Camera2D = _controller.get_camera()
				var world_bounds2: Rect2 = _controller.get_world_bounds()
				_check(world_bounds2.has_point(cam3.global_position), \
					"camera position within world bounds after pan/zoom (%s)" % str(cam3.global_position))
				_enter(Phase.NIGHT_TRANSITION)
		Phase.NIGHT_TRANSITION:
			if _sub == 0:
				_game_time.advance(2.0)
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_check(_controller.is_night_mode(), "camera controller in night mode")
				_sub = 1
			elif _sub == 1:
				_check(_tactical_ui != null, "tactical command UI exists")
				_check(_tactical_ui.visible, "tactical command UI visible in NIGHT")
				_enter(Phase.NIGHT_MAP)
		Phase.NIGHT_MAP:
			if _sub == 0:
				_overlay.open()
				_check(_overlay.is_open(), "map opens during NIGHT")
				_check(_overlay.visible, "overlay visible during NIGHT")
				_sub = 1
			elif _sub == 1:
				_overlay.close()
				_check(_overlay.is_open() == false, "map closes during NIGHT")
				_check(_overlay.visible == false, "overlay hidden after NIGHT close")
				_sub = 2
			elif _sub == 2:
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open(), "M key opens map during NIGHT")
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open() == false, "M key toggles map closed during NIGHT")
				_enter(Phase.TACTICAL_COMMAND)
		Phase.TACTICAL_COMMAND:
			if _sub == 0:
				_check(_tactical_ui.visible, "tactical UI still visible after map operations")
				_check(_tactical_ui.get_regroup_button() != null, "regroup button exists")
				_check(_tactical_ui.get_retreat_button() != null, "retreat button exists")
				_check(_tactical_ui.get_focus_target_button() != null, "focus target button exists")
				_check(_tactical_ui.get_time_pause_button() != null, "time pause button exists")
				_check(_tactical_ui.get_time_1x_button() != null, "time 1x button exists")
				_check(_tactical_ui.get_time_2x_button() != null, "time 2x button exists")
				_sub = 1
			elif _sub == 1:
				var zone_order := [
					MercenaryData.DefenseZone.NORTH,
					MercenaryData.DefenseZone.EAST,
					MercenaryData.DefenseZone.SOUTH,
					MercenaryData.DefenseZone.WEST,
				]
				for zone in zone_order:
					var btn: Button = _tactical_ui.get_defense_zone_button(zone)
					_check(btn != null, "defense zone button %d exists" % zone)
				_enter(Phase.DAY_RETURN)
		Phase.DAY_RETURN:
			if _sub == 0:
				_game_time.advance(1.0)
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "back to DAY")
				_check(_controller.is_night_mode() == false, "camera controller in day mode")
				_sub = 1
			elif _sub == 1:
				_check(_tactical_ui.visible == false, "tactical UI hidden in DAY")
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open(), "map opens after DAY return")
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open() == false, "map closes after DAY return")
				_sub = 2
			elif _sub == 2:
				var cam4: Camera2D = _controller.get_camera()
				var before_pos2: Vector2 = cam4.global_position
				_controller.pan_camera(Vector2(-50, 50))
				var after_pos2: Vector2 = cam4.global_position
				_check(after_pos2 != before_pos2, "camera pan works after DAY return")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(get_nodes_in_group("camera_controller").size() == 1, \
					"camera controller intact")
				_check(get_nodes_in_group("world_selection").size() == 1, \
					"world selection intact")
				_check(get_nodes_in_group("building_placement").size() == 1, \
					"building placement intact")
				_check(get_nodes_in_group("core_buildings").size() == 5, \
					"5 core buildings intact")
				_check(get_nodes_in_group("player").size() == 0, \
					"no player actor")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null, "floor exists")
				_sub = 1
			elif _sub == 1:
				_game_time.advance(2.0)
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, \
					"second NIGHT phase")
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open(), "map opens during second NIGHT")
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open() == false, "map closes during second NIGHT")
				_game_time.advance(1.0)
				_sub = 2
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, \
					"second DAY phase")
				_check(get_nodes_in_group("world_map_overlay").size() == 1, \
					"exactly 1 overlay after repeated cycles")
				_check(get_nodes_in_group("camera_controller").size() == 1, \
					"exactly 1 camera controller after repeated cycles")
				_check(get_nodes_in_group("tactical_command_ui").size() == 1, \
					"exactly 1 tactical UI after repeated cycles")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASKMAP0023_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)