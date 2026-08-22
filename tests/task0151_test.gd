extends SceneTree

## TASK-015-1 Night Tactical Camera Pan 검증 (TASK-CTRL-001-1 Camera Ownership 분리 반영).
## Camera2D는 Player가 아니라 World Camera Controller(CameraController)가 소유한다.
## DAY WASD = camera pan, NIGHT WASD = tactical camera pan이며, Player entity는 이동하지
## 않는다. 카메라는 월드 경계(WORLD_BOUNDS ±1024) 밖으로 벗어나지 않고 N/E/S/W
## Gate/Combat Field를 확인 가능해야 한다. DAY 복귀 시 zoom target 복귀 + position
## jump 없음을 검증한다.
##
## 자동검증 항목:
##  1. DAY 시작: camera는 World Camera Controller 소유 + world origin + day_zoom.
##  2. DAY pan: WASD로 camera만 이동(Player entity 정지).
##  3. Mouse wheel zoom: zoom target 증가/감소/min clamp.
##  4. NIGHT 전환: Camera Controller tactical mode.
##  5. NIGHT pan: 키보드 입력으로 camera만 독립 이동(Player entity 고정).
##  6. NIGHT 4방향: N/E/S/W Gate/Combat Field 도달 가능(경계 안).
##  7. NIGHT 경계 clamp: 월드 경계(WORLD_BOUNDS ±1024) 밖으로 벗어나지 않음.
##  8. DAY 복귀: zoom target 복귀 + camera position jump 없음.
##  9. 회귀: Player 무공격, 핵심 건물/floor/gate/Wall 시스템 유지.

enum Phase {
	SETUP,
	DAY_FOLLOW,
	DAY_MOVE,
	WHEEL_ZOOM,
	TO_NIGHT,
	NIGHT_PAN,
	NIGHT_REACH,
	NIGHT_CLAMP,
	DAY_RETURN,
	REGRESSION,
	DONE,
}

const WORLD_HALF := 1024.0
const ZOOM_TOLERANCE := 0.02
const PAN_HOLD_PF := 30
const REACH_HOLD_PF := 90
const REACH_MARGIN := 960.0

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _player: Node = null
var _controller: Node = null
var _camera: Camera2D = null

var _start_pf := 0
var _hold_action := ""
var _day_cam_pos := Vector2.ZERO
var _zoom_target0 := 0.0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sub = 0
	_wait = 0


func _wait_frames(n: int) -> void:
	_wait = n
	_sub += 1


func _waited() -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	return true


func _finish() -> void:
	print("TASK0151_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _zoom_near(target: float) -> bool:
	return absf(_camera.zoom.x - target) < ZOOM_TOLERANCE \
			and absf(_camera.zoom.y - target) < ZOOM_TOLERANCE


func _camera_global() -> Vector2:
	return _camera.global_position


func _pan_until(action: String) -> void:
	release_all_actions()
	_hold_action = action
	Input.action_press(action)
	_start_pf = _pf


func release_all_actions() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


## Mouse wheel zoom을 Camera Controller의 unhandled input 경로로 직접 전달한다.
## headless에서 viewport GUI 소비 여부와 무관하게 동일 입력 정책을 검증하기 위함.
func _send_wheel(dir: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	_controller._unhandled_input(ev)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _sub == 0:
				if _frame < 8:
					return false
				_game_time = root.get_node("GameTime")
				_world = root.get_node("Main").get_node("World")
				_player = root.get_node("Main").get_node("Player")
				var ctrls := get_nodes_in_group("camera_controller")
				_controller = ctrls[0] if ctrls.size() > 0 else null
				_camera = _controller.get_camera() as Camera2D if _controller else null
				_check(_game_time != null and _world != null and _player != null and _controller != null and _camera != null, "core nodes present (incl. CameraController)")
				_check(_camera != null and _camera.get_parent() == _controller, "camera owned by World Camera Controller (not Player)")
				if _game_time != null and _game_time.has_method("set_auto_advance"):
					_game_time.set_auto_advance(false)
				if _game_time != null and _game_time.has_method("set_durations"):
					_game_time.set_durations(2.0, 1.0)
				_controller.night_pan_speed = 480.0
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DAY_FOLLOW)
		Phase.DAY_FOLLOW:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "starts in DAY")
				_check(not _controller.is_night_mode(), "camera controller starts in DAY mode")
				_check(_controller.global_position == Vector2.ZERO, "camera at world origin (independent of Player)")
				_check(_zoom_near(_controller.day_zoom), "camera at day_zoom (%.2f)" % _camera.zoom.x)
				_check(_camera.zoom.x == _camera.zoom.y, "camera zoom uniform")
				_player.global_position = Vector2.ZERO
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DAY_MOVE)
		Phase.DAY_MOVE:
			if _sub == 0:
				_pan_until("move_right")
				_sub = 1
			elif _sub == 1:
				if _pf - _start_pf < 60:
					return false
				release_all_actions()
				_check(_player.global_position == Vector2.ZERO, "DAY: player entity does not move (WASD = camera pan)")
				_check(_controller.global_position.x > 0.0, "DAY: camera pans right (x=%s)" % str(_controller.global_position.x))
				_check(_camera.position == Vector2.ZERO, "DAY: camera offset stays zero (controller-centered)")
				_sub = 2
			elif _sub == 2:
				_enter(Phase.WHEEL_ZOOM)
		Phase.WHEEL_ZOOM:
			if _sub == 0:
				_zoom_target0 = _controller.get_zoom_target()
				_send_wheel(1)
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_controller.get_zoom_target() > _zoom_target0,
					"mouse wheel up increases zoom target (%.2f -> %.2f)" % [_zoom_target0, _controller.get_zoom_target()])
				_check(_controller.get_zoom_target() <= _zoom_target0 + _controller.wheel_zoom_step + 0.001,
					"wheel zoom step bounded by wheel_zoom_step")
				_send_wheel(-1)
				_send_wheel(-1)
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_controller.get_zoom_target() < _zoom_target0,
					"mouse wheel down decreases zoom target (%.2f -> %.2f)" % [_zoom_target0, _controller.get_zoom_target()])
				for i in 50:
					_send_wheel(-1)
				_check(_controller.get_zoom_target() >= _controller.min_zoom - 0.001,
					"wheel zoom clamped at min_zoom (%.2f)" % _controller.get_zoom_target())
				_sub = 3
			elif _sub == 3:
				_enter(Phase.TO_NIGHT)
		Phase.TO_NIGHT:
			if _sub == 0:
				_game_time.advance(2.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "DAY -> NIGHT transition")
				_check(_controller.is_night_mode(), "NIGHT: camera controller tactical mode")
				_player.global_position = Vector2.ZERO
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_enter(Phase.NIGHT_PAN)
		Phase.NIGHT_PAN:
			if _sub == 0:
				_pan_until("move_right")
				_sub = 1
			elif _sub == 1:
				if _pf - _start_pf < PAN_HOLD_PF:
					return false
				var ppos: Vector2 = _player.global_position
				var cpos: Vector2 = _controller.global_position
				_check(ppos == Vector2.ZERO, "NIGHT: player entity does not move during pan (pos=%s)" % str(ppos))
				_check(cpos.x > 100.0, "NIGHT: tactical camera pans right independently (x=%s)" % str(cpos.x))
				_check(cpos.x > 0.0, "NIGHT: camera position accumulates (%.0f)" % cpos.x)
				release_all_actions()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_enter(Phase.NIGHT_REACH)
		Phase.NIGHT_REACH:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "still NIGHT for reach test")
				_controller.night_pan_speed = 2000.0
				_pan_until("move_up")
				_sub = 1
			elif _sub == 1:
				if _pf - _start_pf < REACH_HOLD_PF:
					return false
				_check(_camera_global().y <= -REACH_MARGIN, "NIGHT: camera reaches North Gate/Combat Field (y=%s)" % str(_camera_global().y))
				_check(_player.global_position == Vector2.ZERO, "NIGHT: player still stationary while reaching north")
				release_all_actions()
				_pan_until("move_down")
				_sub = 2
			elif _sub == 2:
				if _pf - _start_pf < REACH_HOLD_PF:
					return false
				_check(_camera_global().y >= REACH_MARGIN, "NIGHT: camera reaches South Gate/Combat Field (y=%s)" % str(_camera_global().y))
				release_all_actions()
				_pan_until("move_left")
				_sub = 3
			elif _sub == 3:
				if _pf - _start_pf < REACH_HOLD_PF:
					return false
				_check(_camera_global().x <= -REACH_MARGIN, "NIGHT: camera reaches West Gate/Combat Field (x=%s)" % str(_camera_global().x))
				release_all_actions()
				_pan_until("move_right")
				_sub = 4
			elif _sub == 4:
				if _pf - _start_pf < REACH_HOLD_PF:
					return false
				_check(_camera_global().x >= REACH_MARGIN, "NIGHT: camera reaches East Gate/Combat Field (x=%s)" % str(_camera_global().x))
				release_all_actions()
				_sub = 5
			elif _sub == 5:
				_enter(Phase.NIGHT_CLAMP)
		Phase.NIGHT_CLAMP:
			if _sub == 0:
				_pan_until("move_right")
				_sub = 1
			elif _sub == 1:
				if _pf - _start_pf < 200:
					return false
				var cpos: Vector2 = _camera_global()
				_check(cpos.x >= WORLD_HALF - 1.0 and cpos.x <= WORLD_HALF + 1.0, "NIGHT: camera clamps at east world boundary (x=%.1f)" % cpos.x)
				_check(cpos.y >= -WORLD_HALF - 1.0 and cpos.y <= WORLD_HALF + 1.0, "NIGHT: camera y within world boundary (y=%.1f)" % cpos.y)
				release_all_actions()
				_pan_until("move_up")
				_sub = 2
			elif _sub == 2:
				if _pf - _start_pf < 200:
					return false
				var cpos: Vector2 = _camera_global()
				_check(cpos.y >= -WORLD_HALF - 1.0 and cpos.y <= -WORLD_HALF + 1.0, "NIGHT: camera clamps at north world boundary (y=%.1f)" % cpos.y)
				_check(cpos.x >= -WORLD_HALF - 1.0 and cpos.x <= WORLD_HALF + 1.0, "NIGHT: camera x within world boundary (x=%.1f)" % cpos.x)
				release_all_actions()
				_sub = 3
			elif _sub == 3:
				_enter(Phase.DAY_RETURN)
		Phase.DAY_RETURN:
			if _sub == 0:
				_day_cam_pos = _controller.global_position
				_game_time.advance(1.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "NIGHT -> DAY transition")
				_check(not _controller.is_night_mode(), "DAY: camera controller day mode restored")
				_check(_controller.global_position == _day_cam_pos, "DAY: camera position continuous (no jump on transition)")
				_player.global_position = Vector2(0, 60)
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_camera.get_parent() == _controller, "DAY: camera still owned by Camera Controller (player-independent)")
				_check(_camera.zoom.x >= _controller.night_zoom, "DAY: camera starts returning toward day_zoom (%.2f)" % _camera.zoom.x)
				_wait_frames(300)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_zoom_near(_controller.day_zoom), "DAY: camera converged back to day_zoom (%.2f)" % _camera.zoom.x)
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				_check(not _player.has_method("attack") and not _player.has_method("_attack"), "player has no attack method")
				_check(not _player.is_in_group("enemies") and not _player.is_in_group("mercenaries"), "player excluded from combat groups")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")
				_check(get_nodes_in_group("gates").size() == 0, "no gates pre-placed (placement intact)")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0151_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	_pf += 1
	return false


func _initialize() -> void:
	release_all_actions()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)