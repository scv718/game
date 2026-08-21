extends SceneTree

## TASK-015-1 Night Tactical Camera Pan 검증.
## NIGHT에서 Player 이동은 비활성 유지하고 카메라만 키보드로 독립 pan하며,
## 월드 경계 밖으로 벗어나지 않고 N/E/S/W Gate/Combat Field를 확인 가능해야 한다.
## DAY 복귀 시 Player follow/zoom 정상 복구를 검증한다.
##
## 자동검증 항목:
##  1. DAY 시작: camera offset zero + Player follow + day_zoom.
##  2. DAY 이동: Player가 이동하면 camera도 함께 follow.
##  3. NIGHT 전환: Player 이동 비활성.
##  4. NIGHT pan: 키보드 입력으로 camera만 독립 이동(Player entity 고정).
##  5. NIGHT 4방향: N/E/S/W Gate/Combat Field 도달 가능(경계 안).
##  6. NIGHT 경계 clamp: 월드 경계(WORLD_BOUNDS ±1024) 밖으로 벗어나지 않음.
##  7. DAY 복귀: camera offset reset + follow 복구 + day_zoom 복귀.
##  8. 회귀: Player 무공격, 핵심 건물/floor/gate/Wall 시스템 유지.

enum Phase {
	SETUP,
	DAY_FOLLOW,
	DAY_MOVE,
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
var _camera: Camera2D = null

var _start_pf := 0
var _hold_action := ""


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
				_camera = _player.get_node("Camera2D") as Camera2D
				_check(_game_time != null and _world != null and _player != null and _camera != null, "core nodes present")
				if _game_time != null and _game_time.has_method("set_auto_advance"):
					_game_time.set_auto_advance(false)
				if _game_time != null and _game_time.has_method("set_durations"):
					_game_time.set_durations(2.0, 1.0)
				_player.night_pan_speed = 480.0
				_sub = 1
			elif _sub == 1:
				_enter(Phase.DAY_FOLLOW)
		Phase.DAY_FOLLOW:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "starts in DAY")
				_check(_player.get("_night_mode") == false, "player starts in DAY (direct control)")
				_check(_camera.position == Vector2.ZERO, "camera offset zero at DAY")
				_check(_camera_global().distance_to(_player.global_position) < 0.01, "camera follows player at DAY")
				_check(_zoom_near(_player.day_zoom), "camera at day_zoom (%.2f)" % _camera.zoom.x)
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
				_check(_player.global_position.x > 0.0, "DAY: player moves right (x=%s)" % str(_player.global_position.x))
				_check(_camera_global().distance_to(_player.global_position) < 0.01, "DAY: camera keeps following player")
				_check(_camera.position == Vector2.ZERO, "DAY: camera offset stays zero while following")
				_sub = 2
			elif _sub == 2:
				_enter(Phase.TO_NIGHT)
		Phase.TO_NIGHT:
			if _sub == 0:
				_game_time.advance(2.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "DAY -> NIGHT transition")
				_check(_player.get("_night_mode") == true, "NIGHT: player direct movement disabled")
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
				var cpos: Vector2 = _camera_global()
				_check(ppos == Vector2.ZERO, "NIGHT: player entity does not move during pan (pos=%s)" % str(ppos))
				_check(cpos.x > 100.0, "NIGHT: camera pans right independently (x=%s)" % str(cpos.x))
				_check(_camera.position.x > 0.0, "NIGHT: camera offset accumulates (%.0f)" % _camera.position.x)
				release_all_actions()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_enter(Phase.NIGHT_REACH)
		Phase.NIGHT_REACH:
			if _sub == 0:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "still NIGHT for reach test")
				_player.night_pan_speed = 2000.0
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
				_game_time.advance(1.0)
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "NIGHT -> DAY transition")
				_check(_player.get("_night_mode") == false, "DAY: direct control restored")
				_check(_camera.position == Vector2.ZERO, "DAY: camera offset reset to zero (follow restored)")
				_player.global_position = Vector2(0, 60)
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_camera_global().distance_to(_player.global_position) < 0.01, "DAY: camera follows player again (pos=%s)" % str(_camera_global()))
				_check(_zoom_near(_player.day_zoom) or _camera.zoom.x >= _player.night_zoom, "DAY: camera starts returning toward day_zoom (%.2f)" % _camera.zoom.x)
				_sub = 3
			elif _sub == 3:
				_wait_frames(300)
			elif _sub == 4 and not _waited():
				return false
			elif _sub == 4:
				_check(_zoom_near(_player.day_zoom), "DAY: camera converged back to day_zoom (%.2f)" % _camera.zoom.x)
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