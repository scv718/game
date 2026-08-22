extends SceneTree

## TASK-CTRL-001-3 Building Placement Mouse Workflow 검증.
## Player 직접 이동 제거 후에도 BuildingPlacement가 Camera + Mouse 기반으로
## 자연스럽게 동작하도록 입력 ownership이 정리되었는지 확인한다.
##
## 검증 항목:
##  1. 16px logical grid 유지 (GRID_SIZE, _snap).
##  2. Camera pan/zoom 중 world mouse position 계산 정상 (get_global_mouse_position).
##  3. Build mode Left Click = place (정확한 grid cell 배치).
##  4. build click 후 normal selection과 동시 실행되지 않음 (handled + 선택 없음).
##  5. ESC / Right Click = build mode cancel (TASK-CTRL-001-3 핵심).
##  6. Wall continuous placement 유지 (배치 후에도 build mode 유지).
##  7. Remove mode 유지 (KEY_R 진입, Wall 제거, 환불).
##  8. Gate Corridor validation 유지 (valid/invalid 배치, 비용 차감).
##  9. placement 후 nav rebuild 정책 유지 (Wall barrier 차단 / path 정상).
## 10. valid/invalid ghost 유지 (배치 가능 판정).

enum Phase {
	SETUP,
	GRID,
	CAMERA,
	PLACE_LEFT,
	CANCEL,
	WALL,
	NAV,
	GATE,
	REMOVE,
	REGRESSION,
	DONE,
}

const LUMBERYARD_COST := 10
const WALL_COST := 2
const GATE_COST := 5
const LUMBERYARD_TARGET := Vector2(256, 224)
const WALL_TARGET := Vector2(0, 300)
const WEST_GATE := Vector2(-528, 0)

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _phase_start := 0
var _failed := false

var _main: Node = null
var _world: Node = null
var _placement: Node = null
var _selection: Node = null
var _controller: Node = null
var _resources: Node = null
var _game_time: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0
	_phase_start = _frame


func _finish() -> void:
	print("TASKCTRL0013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _elapsed() -> int:
	return _frame - _phase_start


func _camera() -> Camera2D:
	return _controller.get_camera() as Camera2D


## 카메라를 world 좌표 target이 화면상 마우스 위치에 오도록 배치한다 (zoom 반영).
func _set_camera_to_world(target: Vector2) -> void:
	var vp := root.get_viewport()
	var mouse := vp.get_mouse_position()
	var center := vp.get_visible_rect().size * 0.5
	var zoom: float = _camera().zoom.x
	_controller.global_position = target - (mouse - center) / zoom


func _snap_of_world_under_mouse() -> Vector2:
	return (_placement.get_global_mouse_position() / 16.0).floor() * 16.0


func _left_click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func _right_click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	return ev


func _esc_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


func _key_event(key: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	return ev


func _path_len(a: Vector2, b: Vector2) -> float:
	var nav_map: RID = _world.get_world_2d().get_navigation_map()
	var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, a, b, true)
	if path.size() < 2:
		return -1.0
	var len := 0.0
	for i in range(1, path.size()):
		len += path[i - 1].distance_to(path[i])
	return len


func _lumberyard_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("lumberyards"):
		if not is_instance_valid(node):
			continue
		var ly := node as Node2D
		if ly != null and ly.position.distance_to(pos) < 1.0:
			return node
	return null


func _wall_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("walls"):
		if not is_instance_valid(node):
			continue
		var w := node as Node2D
		if w != null and w.position.distance_to(pos) < 1.0:
			return node
	return null


func _gate_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("gates"):
		if not is_instance_valid(node):
			continue
		var g := node as Node2D
		if g != null and g.position.distance_to(pos) < 1.0:
			return node
	return null


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _sub == 0:
				if _frame < 8:
					return false
				_main = root.get_node("Main")
				_world = _main.get_node("World")
				_placement = _main.get_node("BuildingPlacement")
				_selection = _main.get_node("WorldSelection")
				_resources = root.get_node("VillageResources")
				_game_time = root.get_node("GameTime")
				var ctrls := get_nodes_in_group("camera_controller")
				_controller = ctrls[0] if ctrls.size() > 0 else null
				_game_time.set_auto_advance(false)
				_game_time.set_durations(2.0, 1.0)
				_resources._amounts["wood"] = 10000
				_check(_main != null and _world != null and _placement != null \
					and _selection != null and _controller != null, "core nodes present")
				_check(_placement.is_in_group("building_placement"), \
					"BuildingPlacement in building_placement group")
				_check(_placement.has_method("is_active"), \
					"BuildingPlacement exposes is_active()")
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "starts in DAY")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.GRID)
		Phase.GRID:
			if _sub == 0:
				_check(_placement.GRID_SIZE == 16, "16px logical grid kept (GRID_SIZE=16)")
				_check(_placement._snap(Vector2(100.0, 100.0)) == Vector2(96, 96), \
					"_snap(100,100) -> (96,96)")
				_check(_placement._snap(Vector2(-20.5, 33.7)) == Vector2(-32, 32), \
					"_snap negative/offset -> (-32,32)")
				_check(_placement._snap(Vector2(7.9, 15.9)) == Vector2(0, 0), \
					"_snap near-origin stays within grid")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.CAMERA)
		Phase.CAMERA:
			if _sub == 0:
				_controller.global_position = Vector2.ZERO
				_camera().zoom = Vector2.ONE
				_controller._zoom_target = 1.0
				var wm0: Vector2 = _placement.get_global_mouse_position()
				_controller.pan_camera(Vector2(96, -64))
				var wm1: Vector2 = _placement.get_global_mouse_position()
				_check((wm1 - wm0).distance_to(Vector2(96, -64)) < 0.5, \
					"camera pan moves world mouse position by offset (%.1f,%.1f)" % [wm1.x - wm0.x, wm1.y - wm0.y])
				_check(_controller.global_position.distance_to(Vector2(96, -64)) < 0.5, \
					"camera controller panned to (96,-64)")
				_sub = 1
			elif _sub == 1:
				# zoom 2x: world-under-mouse가 camera 중심으로 절반 거리로 수렴.
				var cam_pos: Vector2 = _controller.global_position
				var before: Vector2 = _placement.get_global_mouse_position()
				_camera().zoom = Vector2(2, 2)
				_controller._zoom_target = 2.0
				var after: Vector2 = _placement.get_global_mouse_position()
				_check((after - cam_pos).distance_to((before - cam_pos) * 0.5) < 0.5, \
					"camera zoom 2x halves world mouse offset from camera center")
				# zoom 1x 복귀 + build mode 활성 시 ghost 표시.
				_camera().zoom = Vector2.ONE
				_controller._zoom_target = 1.0
				_controller.global_position = Vector2.ZERO
				_placement._set_active(true)
				_check(_placement._active and _placement._ghost != null, \
					"build mode active shows ghost")
				_check(_placement._ghost.position == _snap_of_world_under_mouse(), \
					"ghost follows snapped world mouse cell")
				_placement._set_active(false)
				_sub = 2
			elif _sub == 2:
				_enter(Phase.PLACE_LEFT)
		Phase.PLACE_LEFT:
			if _sub == 0:
				_selection.clear_selection()
				_set_camera_to_world(LUMBERYARD_TARGET)
				_placement._set_building_type("lumberyard")
				_placement._set_active(true)
				var snap := _snap_of_world_under_mouse()
				_check(snap == LUMBERYARD_TARGET, \
					"world mouse snaps to target cell (%s) under pan/zoom" % str(snap))
				_check(_placement._is_valid_position(LUMBERYARD_TARGET), \
					"target cell is a valid placement (valid ghost)")
				var wood0: int = _resources.get_amount("wood")
				_placement._unhandled_input(_left_click_event())
				var ly := _lumberyard_at(LUMBERYARD_TARGET)
				_check(ly != null, "left click in build mode places Lumberyard at exact grid cell")
				_check(_resources.get_amount("wood") == wood0 - LUMBERYARD_COST, \
					"Lumberyard cost deducted once (%d wood)" % LUMBERYARD_COST)
				_check(_placement._active == false, \
					"Lumberyard placement exits build mode")
				_check(root.get_viewport().is_input_handled(), \
					"build left click is handled (no leak to world selection)")
				_check(_selection.get_selected() == null, \
					"build click does not select placed building (no double action)")
				_check(ly != null and ly.get_node("Interact") != null \
					and _selection._is_managed_target(ly.get_node("Interact")), \
					"placed Lumberyard would be selectable if click leaked (risk real)")
				_sub = 1
			elif _sub == 1:
				# build mode가 아니면 left click으로 배치되지 않는다.
				var walls0 := get_nodes_in_group("walls").size()
				var wood0: int = _resources.get_amount("wood")
				_set_camera_to_world(WALL_TARGET)
				_placement._unhandled_input(_left_click_event())
				_check(_wall_at(WALL_TARGET) == null, \
					"left click without build mode places nothing")
				_check(_resources.get_amount("wood") == wood0, \
					"no cost without build mode")
				_check(get_nodes_in_group("walls").size() == walls0, \
					"no wall created without build mode")
				_sub = 2
			elif _sub == 2:
				_enter(Phase.CANCEL)
		Phase.CANCEL:
			if _sub == 0:
				# FIX: build mode에서 Right Click = cancel.
				_placement._set_building_type("wall")
				_placement._set_active(true)
				_check(_placement._active, "build mode active before right click")
				_placement._unhandled_input(_right_click_event())
				_check(_placement._active == false, \
					"right click cancels build mode (TASK-CTRL-001-3)")
				_check(_placement.is_active() == false, \
					"is_active() reflects right-click cancel")
				_check(root.get_viewport().is_input_handled(), \
					"right click during build mode is handled")
				_sub = 1
			elif _sub == 1:
				# ESC = cancel.
				_placement._set_active(true)
				_check(_placement._active, "build mode active before ESC")
				_placement._unhandled_input(_esc_event())
				_check(_placement._active == false, \
					"ESC cancels build mode")
				# build 입력으로 진입/토글.
				_placement._unhandled_input(_key_event(KEY_B))
				_check(_placement._active, "build key enters build mode")
				_placement._unhandled_input(_key_event(KEY_B))
				_check(_placement._active == false, \
					"build key toggles build mode off")
				_sub = 2
			elif _sub == 2:
				_enter(Phase.WALL)
		Phase.WALL:
			if _sub == 0:
				# wall 연속 배치: 마우스 배치 후에도 build mode 유지.
				_set_camera_to_world(WALL_TARGET)
				_placement._set_building_type("wall")
				_placement._set_active(true)
				var wood0: int = _resources.get_amount("wood")
				_placement._unhandled_input(_left_click_event())
				_check(_wall_at(WALL_TARGET) != null, \
					"wall placed via mouse at exact grid cell (%s)" % str(WALL_TARGET))
				_check(_placement._active, \
					"wall continuous placement keeps build mode active")
				_check(_resources.get_amount("wood") == wood0 - WALL_COST, \
					"wall cost deducted once")
				# 연속 배치 2번째 segment (직접 호출).
				var wood1: int = _resources.get_amount("wood")
				_placement._try_place_wall_at(Vector2(16, WALL_TARGET.y))
				_check(_wall_at(Vector2(16, WALL_TARGET.y)) != null, \
					"second wall segment placed while still in build mode")
				_check(_resources.get_amount("wood") == wood1 - WALL_COST, \
					"second wall cost deducted once")
				_sub = 1
			elif _sub == 1:
				# 수평 장벽 (x=32..112, y=-200) 쌓기.
				for x in range(32, 128, 16):
					_placement._try_place_wall_at(Vector2(x, -200))
				_check(get_nodes_in_group("walls").size() >= 8, \
					"wall barrier built (8 segments)")
				_placement._unhandled_input(_right_click_event())
				_check(_placement._active == false, \
					"right click exits after wall placement")
				_enter(Phase.NAV)
		Phase.NAV:
			if _sub == 0:
				_pf = 0
				_sub = 1
			elif _sub == 1:
				if _pf >= 30:
					var direct := (Vector2(56, -170) - Vector2(56, -230)).length()
					var path_len := _path_len(Vector2(56, -170), Vector2(56, -230))
					_check(path_len > direct + 60.0, \
						"wall barrier blocks nav after placement (path %.0f > direct %.0f +60)" % [path_len, direct])
					_check(_path_len(Vector2(0, 400), Vector2(0, -400)) > 0.0, \
						"nav still generates across world (rebuild policy intact)")
					_enter(Phase.GATE)
		Phase.GATE:
			if _sub == 0:
				_placement._set_building_type("gate")
				_check(_placement._snap_gate(Vector2(-48, 0)) == Vector2(-48, 0), \
					"west corridor gate snaps to centerline y=0")
				_check(_placement._is_valid_gate_position(WEST_GATE), \
					"west corridor gate position valid")
				_check(_placement._is_valid_gate_position(Vector2(0, 0)) == false, \
					"gate outside corridor invalid")
				var wood0: int = _resources.get_amount("wood")
				var gates0 := get_nodes_in_group("gates").size()
				_placement._try_place_gate_at(WEST_GATE)
				var gate := _gate_at(WEST_GATE)
				_check(gate != null, "west gate placed in corridor")
				_check(get_nodes_in_group("gates").size() == gates0 + 1, \
					"gate count incremented")
				_check(_resources.get_amount("wood") == wood0 - GATE_COST, \
					"gate cost deducted once")
				if gate != null:
					_check(gate.get_direction() == "west", \
						"gate direction west")
				# invalid 위치: 배치 거부 + 비용 차감 없음.
				var wood1: int = _resources.get_amount("wood")
				var gates1 := get_nodes_in_group("gates").size()
				_placement._try_place_gate_at(Vector2(0, 0))
				_check(get_nodes_in_group("gates").size() == gates1, \
					"gate rejected outside corridor")
				_check(_resources.get_amount("wood") == wood1, \
					"no wood deducted on invalid gate position")
				_sub = 1
			elif _sub == 1:
				if _pf >= 45:
					_check(_path_len(Vector2(0, 400), Vector2(0, -400)) > 0.0, \
						"nav intact after gate placement")
					_enter(Phase.REMOVE)
		Phase.REMOVE:
			if _sub == 0:
				_set_camera_to_world(WALL_TARGET)
				_placement._set_building_type("wall")
				_placement._set_active(true)
				_placement._unhandled_input(_key_event(KEY_R))
				_check(_placement._remove_mode, \
					"KEY_R enters remove mode while build mode active")
				var wood0: int = _resources.get_amount("wood")
				_placement._unhandled_input(_left_click_event())
				_check(_wall_at(WALL_TARGET) == null, \
					"remove mode left click demolishes wall")
				_check(_resources.get_amount("wood") == wood0 + WALL_COST, \
					"wall removal refunds full Wood (+%d)" % WALL_COST)
				_check(_placement._active, \
					"remove mode keeps build mode active")
				_placement._unhandled_input(_right_click_event())
				_check(_placement._active == false and _placement._remove_mode == false, \
					"right click exits build mode and resets remove mode")
				_sub = 1
			elif _sub == 1:
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(_controller != null and _controller.get_camera() != null, \
					"Camera Controller intact (TASK-CTRL-001-1)")
				_check(get_nodes_in_group("world_selection").size() == 1, \
					"WorldSelection still present (TASK-CTRL-001-2)")
				_check(_selection.can_handle_world_click(), \
					"world click enabled after build mode reset (DAY, no modal)")
				_check(_placement._ghost == null or not is_instance_valid(_placement._ghost), \
					"ghost cleaned up after build mode exit")
				_selection.clear_selection()
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASKCTRL0013_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)