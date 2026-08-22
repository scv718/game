extends SceneTree

## TASK-010-3 Night tactical camera transition 검증 (TASK-CTRL-001-1 반영).
## DAY/NIGHT phase 전환에 따라 World Camera Controller(CameraController)의
## DAY(camera pan)/NIGHT(tactical camera pan) 모드와 zoom target 전환이 올바르게
## 적용되는지 자동 검증한다. WASD는 Player가 아니라 Camera를 pan한다.
## phase 반복 시 카메라 상태가 누적/망가지지 않고 항상 목표 배율로 수렴하는지도 확인한다.

enum TestPhase {
	SETUP, INIT_DAY, DAY_MOVE, TO_NIGHT, NIGHT_NO_MOVE, CYCLE_ZOOM, TO_DAY,
	DAY_MOVE_AGAIN, CYCLE_AGAIN, CYCLE_ZOOM_END, SMOKE, DONE
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _game_time: Node = null
var _player: Node = null
var _controller: Node = null
var _camera: Camera2D = null
var _start_x := 0.0

const ZOOM_TOLERANCE := 0.01
const ZOOM_WAIT_FRAMES := 300
const MOVE_WAIT_FRAMES := 120


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: TestPhase) -> void:
	_phase = new_phase
	_phase_start = _frame
	_step_done = false


func _elapsed() -> int:
	return _frame - _phase_start


func _zoom_near(target: float) -> bool:
	return absf(_camera.zoom.x - target) < ZOOM_TOLERANCE \
			and absf(_camera.zoom.y - target) < ZOOM_TOLERANCE


func _finish() -> void:
	print("TASK0103_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _hold_move(action: String) -> void:
	Input.action_press(action)


func _release_move(action: String) -> void:
	Input.action_release(action)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_game_time = root.get_node("GameTime")
			var main: Node = root.get_node("Main")
			_player = main.get_node("Player")
			var ctrls := get_nodes_in_group("camera_controller")
			_controller = ctrls[0] if ctrls.size() > 0 else null
			_camera = _controller.get_camera() as Camera2D if _controller else null
			var world: Node = main.get_node("World")
			var lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			lj.position = Vector2(300, 200)
			world.add_child(lj)
			var mn = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			mn.position = Vector2(500, 140)
			world.add_child(mn)
			_enter(TestPhase.INIT_DAY)
		TestPhase.INIT_DAY:
			_check(_game_time != null, "GameTime autoload exists")
			_check(_player != null, "Player exists")
			_check(_camera != null, "World Camera2D exists")
			_check(not _controller.is_night_mode(), "camera controller starts in DAY (camera pan mode)")
			_check(_zoom_near(_controller.day_zoom), "camera zoom starts at day_zoom (%.2f)" % _camera.zoom.x)
			_check(_camera.zoom.x == _camera.zoom.y, "camera zoom uniform")
			_game_time.set_auto_advance(false)
			_game_time.set_durations(10.0, 10.0)
			_enter(TestPhase.DAY_MOVE)
		TestPhase.DAY_MOVE:
			if not _step_done:
				_step_done = true
				_controller.global_position = Vector2.ZERO
				_player.global_position = Vector2(0, 0)
				_start_x = _controller.global_position.x
				_hold_move("move_right")
			if _elapsed() >= MOVE_WAIT_FRAMES:
				_release_move("move_right")
				_check(_controller.global_position.x > _start_x, "DAY: camera pans right (WASD = camera pan, x=%s)" % str(_controller.global_position.x))
				_check(_player.global_position == Vector2(0, 0), "DAY: player stays stationary")
				_enter(TestPhase.TO_NIGHT)
		TestPhase.TO_NIGHT:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "advanced into NIGHT")
				_check(_controller.is_night_mode(), "NIGHT: camera controller tactical mode")
				_enter(TestPhase.NIGHT_NO_MOVE)
		TestPhase.NIGHT_NO_MOVE:
			if not _step_done:
				_step_done = true
				_controller.global_position = Vector2.ZERO
				_player.global_position = Vector2(0, 0)
				_start_x = _controller.global_position.x
				_hold_move("move_right")
			if _elapsed() >= MOVE_WAIT_FRAMES:
				_release_move("move_right")
				_check(_controller.global_position.x > _start_x, "NIGHT: tactical camera pans (WASD = tactical camera pan, x=%s)" % str(_controller.global_position.x))
				_check(_player.global_position == Vector2(0, 0), "NIGHT: player entity stays stationary")
				_enter(TestPhase.CYCLE_ZOOM)
		TestPhase.CYCLE_ZOOM:
			if _elapsed() >= ZOOM_WAIT_FRAMES:
				_check(_zoom_near(_controller.night_zoom), "NIGHT: camera converges to night_zoom (%.2f)" % _camera.zoom.x)
				_enter(TestPhase.TO_DAY)
		TestPhase.TO_DAY:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "NIGHT -> DAY transition")
				_check(_game_time.get_day_number() == 2, "day number increments to 2")
				_check(not _controller.is_night_mode(), "DAY: camera controller day mode restored")
				_enter(TestPhase.DAY_MOVE_AGAIN)
		TestPhase.DAY_MOVE_AGAIN:
			if not _step_done:
				_step_done = true
				_controller.global_position = Vector2.ZERO
				_player.global_position = Vector2(0, 0)
				_start_x = _controller.global_position.x
				_hold_move("move_right")
			if _elapsed() >= MOVE_WAIT_FRAMES:
				_release_move("move_right")
				_check(_controller.global_position.x > _start_x, "DAY again: camera pans (control restored, x=%s)" % str(_controller.global_position.x))
				_enter(TestPhase.CYCLE_AGAIN)
		TestPhase.CYCLE_AGAIN:
			if _elapsed() >= ZOOM_WAIT_FRAMES:
				_check(_zoom_near(_controller.day_zoom), "DAY again: camera returns to day_zoom (%.2f)" % _camera.zoom.x)
				_game_time.advance(10.0)
				_check(_controller.is_night_mode(), "repeated cycle: NIGHT mode toggles on again")
				_enter(TestPhase.CYCLE_ZOOM_END)
		TestPhase.CYCLE_ZOOM_END:
			if _elapsed() >= ZOOM_WAIT_FRAMES:
				_check(_zoom_near(_controller.night_zoom), "repeated cycle: camera converges to night_zoom (no accumulation) (%.2f)" % _camera.zoom.x)
				_game_time.advance(10.0)
				_check(not _controller.is_night_mode(), "repeated cycle: DAY mode toggles back")
				_enter(TestPhase.SMOKE)
		TestPhase.SMOKE:
			var main: Node = root.get_node("Main")
			_check(main.get_node("Player") != null, "player exists")
			_check(main.get_node("HUD") != null, "HUD exists")
			var floor_node: TileMapLayer = main.get_node("World/Floor") as TileMapLayer
			_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")
			_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack system intact")
			_check(get_nodes_in_group("miners").size() >= 1, "miner system intact")
			_enter(TestPhase.DONE)
		TestPhase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0103_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
