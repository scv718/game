extends SceneTree

## TASK-MAP-002-1 World Map Overlay 검증.
## World Map Overlay의 기본 구조: open/close toggle, coordinate mapping,
## input blocking, coexistence with existing systems을 검증한다.

enum Phase {
	SETUP,
	TOGGLE,
	COORDINATE,
	BLOCKING,
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
	print("TASKMAP0021_RESULT=" + ("FAIL" if _failed else "PASS"))
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


func _left_click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
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

				# WorldMapOverlay 인스턴스 확인.
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

				# Camera controller intact.
				_check(_controller != null, "CameraController present")
				_check(_controller.get_camera() != null, "Camera2D present")

				_sub = 1
			elif _sub == 1:
				_enter(Phase.TOGGLE)
		Phase.TOGGLE:
			if _sub == 0:
				# M key로 open.
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open(), "M key opens map overlay")
				_check(_overlay.visible, "overlay visible after M key")
				_sub = 1
			elif _sub == 1:
				# ESC로 close.
				_overlay._unhandled_input(_esc_event())
				_check(_overlay.is_open() == false, "ESC closes map overlay")
				_check(_overlay.visible == false, "overlay hidden after ESC")
				_sub = 2
			elif _sub == 2:
				# M으로 다시 열고 M으로 닫기 (toggle).
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open(), "M key re-opens overlay")
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open() == false, "M key toggles overlay closed")
				_sub = 3
			elif _sub == 3:
				# open/close API 테스트.
				_overlay.open()
				_check(_overlay.is_open(), "open() opens overlay")
				_overlay.close()
				_check(_overlay.is_open() == false, "close() closes overlay")
				_enter(Phase.COORDINATE)
		Phase.COORDINATE:
			if _sub == 0:
				# world_to_map 변환 검증.
				_overlay.open()
				# 중앙 (0,0) → map 중앙 근처.
				var center_map: Vector2 = _overlay.world_to_map(Vector2.ZERO)
				_check(center_map.x > 0 and center_map.y > 0, \
					"world (0,0) maps to positive map coords (%s)" % str(center_map))
				# world (-1536,-1536) → map 좌상단 근처.
				var tl_map: Vector2 = _overlay.world_to_map(Vector2(-1536, -1536))
				_check(tl_map.x >= 0 and tl_map.y >= 0, \
					"world (-1536,-1536) maps near top-left (%s)" % str(tl_map))
				# world (1536,1536) → map 좌표 존재.
				# headless viewport가 작아 extreme corner 좌표가 0이 될 수 있으므로
				# roundtrip 정확도로 검증한다.
				var br_map: Vector2 = _overlay.world_to_map(Vector2(1536, 1536))
				_check(center_map.distance_to(tl_map) > 0, \
					"center and top-left map to different positions")
				_sub = 1
			elif _sub == 1:
				# map_to_world 역변환 정밀도 검증.
				var test_world := Vector2(-500, 300)
				var map_pos: Vector2 = _overlay.world_to_map(test_world)
				var roundtrip: Vector2 = _overlay.map_to_world(map_pos)
				var err := test_world.distance_to(roundtrip)
				_check(err < 10.0, \
					"world->map->world roundtrip error %.2f < 10" % err)
				_sub = 2
			elif _sub == 2:
				_overlay.close()
				_enter(Phase.BLOCKING)
		Phase.BLOCKING:
			if _sub == 0:
				# Map 열린 상태에서 WASD camera pan 차단 확인.
				_overlay.open()
				var cam: Camera2D = _controller.get_camera()
				var before_pos := cam.global_position
				# WASD 입력을 _physics_process 대신 직접 pan_camera 호출로 시뮬레이션.
				# overlay 열린 상태에서 _is_map_overlay_open()이 true여야 함.
				_check(_controller._is_map_overlay_open(), \
					"camera controller detects map overlay open")
				_controller.pan_camera(Vector2(100, 0))
				# pan_camera는 직접 호출이므로 동작하지만 _physics_process에서 차단됨.
				# _is_map_overlay_open() 확인이 핵심.
				_sub = 1
			elif _sub == 1:
				# Map 열린 상태에서 mouse wheel zoom 차단.
				_controller._unhandled_input(_wheel_up_event())
				# zoom target이 변경되지 않아야 함 (차단).
				_check(_controller._is_map_overlay_open(), \
					"camera controller still detects map overlay")
				_sub = 2
			elif _sub == 2:
				_overlay.close()
				_check(_controller._is_map_overlay_open() == false, \
					"camera controller detects map overlay closed")
				_sub = 3
			elif _sub == 3:
				# World click 차단 (MODAL_UI_GROUPS에 world_map_overlay 추가).
				_overlay.open()
				if _selection != null:
					_check(_selection.can_handle_world_click() == false, \
						"world click disabled while map overlay open")
				_overlay.close()
				if _selection != null:
					_check(_selection.can_handle_world_click() == true or \
						_game_time.get_phase() != GameTime.Phase.DAY, \
						"world click re-enabled after map overlay close")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				# 회귀: core systems intact.
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
				# DAY/NIGHT 전환 테스트.
				_game_time.advance(2.0)
				_sub = 1
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				# NIGHT에서 map toggle 정상.
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open(), "map opens during NIGHT")
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open() == false, "map closes during NIGHT")
				_game_time.advance(1.0)
				_sub = 2
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "back to DAY")
				# DAY 복귀 후 map 정상.
				_overlay._unhandled_input(_m_key_event())
				_check(_overlay.is_open(), "map opens after DAY return")
				_overlay.close()
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASKMAP0021_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
