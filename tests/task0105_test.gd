extends SceneTree

## TASK-010-5 Day/Night 통합 테스트.
## 여러 DAY/NIGHT 사이클을 빠른 테스트 설정으로 반복하여
## 상태(phase/day number)/카메라/입력/HUD/기존 생산/Worker 배치를 하나의 흐름으로
## 통합 검증한다.
##
## 자동검증 항목:
##  1. DAY 시작 (phase=DAY, day=1, 직접 조작 가능, camera day_zoom).
##  2. NIGHT 전환 (phase=NIGHT, day=1).
##  3. Player 이동 입력 비활성.
##  4. camera night state (night_zoom 수렴).
##  5. DAY 재전환 (phase=DAY, day=2).
##  6. day number 증가.
##  7. Player 이동 복구.
##  8. Wood/Stone 생산 시스템 오류 없음 (DAY/NIGHT 모두, 정지 정책 없음).
##  9. Worker Assignment 유지 (phase 전환 중 workplace/FMS 안전).
## 10. UI state 동기화 (DayTimeLabel = phase/day/progress).
## 11. main smoke (회귀).

enum TestPhase {
	SETUP, INIT_DAY, DAY_START, TO_NIGHT, NIGHT_CHECK, NIGHT_ZOOM, DAY2,
	DAY2_CHECK, DAY2_ZOOM, PRODUCE_ASSIGN, TO_NIGHT2, NIGHT2_CHECK, TO_DAY3,
	DAY3_CHECK, UI_SYNC, SMOKE, DONE
}

const LUMBERYARD_SCENE := preload("res://scenes/lumberyard.tscn")

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _player: Node = null
var _controller: Node = null
var _camera: Camera2D = null
var _placement: Node = null
var _resources: Node = null
var _hud: Node = null
var _daytime_label: Label = null
var _lumberjack: Node = null
var _miner: Node = null
var _deposit: Node = null
var _quarry: Node = null
var _lumberyard: Node = null

var _start_x := 0.0
var _wood_before := 0
var _stone_before := 0

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


func _finish() -> void:
	print("TASK0105_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _zoom_near(target: float) -> bool:
	return absf(_camera.zoom.x - target) < ZOOM_TOLERANCE \
			and absf(_camera.zoom.y - target) < ZOOM_TOLERANCE


func _hold_move(action: String) -> void:
	Input.action_press(action)


func _release_move(action: String) -> void:
	Input.action_release(action)


func _label_matches(prefix: String) -> bool:
	return _daytime_label != null and _daytime_label.text.begins_with(prefix)


func _stump_count() -> int:
	var n := 0
	for t in get_nodes_in_group("interactable"):
		if not t.can_interact():
			n += 1
	return n


func _process(_delta: float) -> bool:
	_frame += 1
	var main: Node = root.get_node("Main")
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_game_time = root.get_node("GameTime")
			_world = main.get_node("World")
			_player = main.get_node("Player")
			var ctrls := get_nodes_in_group("camera_controller")
			_controller = ctrls[0] if ctrls.size() > 0 else null
			_camera = _controller.get_camera() as Camera2D if _controller else null
			_placement = main.get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_hud = main.get_node("HUD")
			_daytime_label = _hud.get_node("DayTimeLabel") as Label
			_miner = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_miner.position = Vector2(500, 140)
			_world.add_child(_miner)
			_lumberjack = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lumberjack.position = Vector2(300, 200)
			_world.add_child(_lumberjack)
			var deposits := get_nodes_in_group("stone_deposits")
			_deposit = deposits[0] if deposits.size() > 0 else null
			for t in get_nodes_in_group("interactable"):
				t.regrow_time = 10000.0
			_game_time.set_auto_advance(false)
			_game_time.set_durations(10.0, 10.0)
			_enter(TestPhase.INIT_DAY)
		TestPhase.INIT_DAY:
			_check(_game_time != null, "GameTime autoload exists")
			_check(_player != null, "Player exists")
			_check(_camera != null, "World Camera2D exists")
			_check(_hud != null, "HUD exists")
			_check(_daytime_label != null, "DayTimeLabel exists")
			_check(_miner != null, "miner worker exists")
			_check(_lumberjack != null, "lumberjack worker exists")
			_check(_deposit != null, "stone deposit exists")
			_check(_game_time.get_phase() == _game_time.Phase.DAY, "game starts in DAY")
			_check(_game_time.get_day_number() == 1, "day number starts at 1")
			_check(not _controller.is_night_mode(), "camera controller starts in DAY (camera pan mode)")
			_check(_zoom_near(_controller.day_zoom), "camera starts at day_zoom (%.2f)" % _camera.zoom.x)
			_check(_camera.zoom.x == _camera.zoom.y, "camera zoom uniform")
			_check(_label_matches("DAY 1"), "HUD label starts with DAY 1 (text=%s)" % (_daytime_label.text if _daytime_label else "null"))
			_enter(TestPhase.DAY_START)
		TestPhase.DAY_START:
			if not _step_done:
				_step_done = true
				_controller.global_position = Vector2.ZERO
				_player.global_position = Vector2.ZERO
				_start_x = _controller.global_position.x
				_hold_move("move_right")
			if _elapsed() >= MOVE_WAIT_FRAMES:
				_release_move("move_right")
				_check(_controller.global_position.x > _start_x, "DAY: camera pans (WASD = camera pan)")
				_check(_player.global_position == Vector2.ZERO, "DAY: player stays stationary")
				_player.global_position = Vector2.ZERO
				_enter(TestPhase.TO_NIGHT)
		TestPhase.TO_NIGHT:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "DAY -> NIGHT transition")
				_check(_game_time.get_day_number() == 1, "day number stays 1 during NIGHT")
				_check(_controller.is_night_mode(), "NIGHT: camera controller tactical mode")
				_enter(TestPhase.NIGHT_CHECK)
		TestPhase.NIGHT_CHECK:
			if not _step_done:
				_step_done = true
				_controller.global_position = Vector2.ZERO
				_player.global_position = Vector2.ZERO
				_start_x = _controller.global_position.x
				_hold_move("move_right")
			if _elapsed() >= MOVE_WAIT_FRAMES:
				_release_move("move_right")
				_check(_controller.global_position.x > _start_x, "NIGHT: tactical camera pans (WASD = tactical camera pan)")
				_check(_player.global_position == Vector2.ZERO, "NIGHT: player entity stays stationary")
				_enter(TestPhase.NIGHT_ZOOM)
		TestPhase.NIGHT_ZOOM:
			if _elapsed() >= ZOOM_WAIT_FRAMES:
				_check(_zoom_near(_controller.night_zoom), "NIGHT: camera converges to night_zoom (%.2f)" % _camera.zoom.x)
				_enter(TestPhase.DAY2)
		TestPhase.DAY2:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "NIGHT -> DAY transition")
				_check(_game_time.get_day_number() == 2, "day number increments to 2 (day=%d)" % _game_time.get_day_number())
				_check(not _controller.is_night_mode(), "DAY: camera controller day mode restored")
				_check(_label_matches("DAY 2"), "HUD label reflects DAY 2 (text=%s)" % (_daytime_label.text if _daytime_label else "null"))
				_enter(TestPhase.DAY2_CHECK)
		TestPhase.DAY2_CHECK:
			if not _step_done:
				_step_done = true
				_controller.global_position = Vector2.ZERO
				_player.global_position = Vector2.ZERO
				_start_x = _controller.global_position.x
				_hold_move("move_right")
			if _elapsed() >= MOVE_WAIT_FRAMES:
				_release_move("move_right")
				_check(_controller.global_position.x > _start_x, "DAY again: camera pans (control restored)")
				_check(_player.global_position == Vector2.ZERO, "DAY again: player stays stationary")
				_player.global_position = Vector2.ZERO
				_enter(TestPhase.DAY2_ZOOM)
		TestPhase.DAY2_ZOOM:
			if _elapsed() >= ZOOM_WAIT_FRAMES:
				_check(_zoom_near(_controller.day_zoom), "DAY again: camera returns to day_zoom (%.2f)" % _camera.zoom.x)
				_enter(TestPhase.PRODUCE_ASSIGN)
		TestPhase.PRODUCE_ASSIGN:
			if _frame % 2 == 0:
				return false
			_resources._amounts["wood"] = 50
			_placement._set_building_type("lumberyard")
			_placement._try_place_at(Vector2(300, 260))
			_check(get_nodes_in_group("lumberyards").size() == 1, "DAY: lumberyard built on valid clearing position")
			_lumberyard = get_nodes_in_group("lumberyards")[0] if get_nodes_in_group("lumberyards").size() > 0 else null
			_check(_lumberyard != null and _lumberyard.get_slot_capacity() == 2, "lumberyard slot capacity is 2")

			_placement._set_building_type("quarry")
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "DAY: quarry built on valid deposit")
			_quarry = get_nodes_in_group("quarries")[0] if get_nodes_in_group("quarries").size() > 0 else null
			_check(_quarry != null and _quarry.get_deposit() == _deposit, "quarry linked to deposit")
			_check(_quarry.get_slot_capacity() == 2, "quarry slot capacity is 2")

			var qres: Dictionary = _quarry.handle_worker_interaction()
			_check(qres.get("action") == "assign" and qres.get("success") == true, "quarry assigns miner (%s)" % str(qres))
			_check(_miner.get_workplace() == _quarry, "miner workplace is the quarry")
			var lres: Dictionary = _lumberyard.handle_worker_interaction()
			_check(lres.get("action") == "assign" and lres.get("success") == true, "lumberyard assigns lumberjack (%s)" % str(lres))
			_check(_lumberjack.get_workplace() == _lumberyard, "lumberjack workplace is the lumberyard")
			_check(not _quarry.assign_worker(_miner), "duplicate miner assignment rejected")
			_check(not _lumberyard.assign_worker(_lumberjack), "duplicate lumberjack assignment rejected")

			_wood_before = _resources.get_amount("wood")
			_stone_before = _resources.get_amount("stone")
			_enter(TestPhase.TO_NIGHT2)
		TestPhase.TO_NIGHT2:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "transitioned into NIGHT (cycle 2)")
				_check(_game_time.get_day_number() == 2, "day number stays 2 during NIGHT (cycle 2)")
				_check(_controller.is_night_mode(), "NIGHT: tactical camera mode active (cycle 2)")
				_check(is_instance_valid(_lumberjack.get_workplace()), "lumberjack workplace ref stable across transition")
				_check(is_instance_valid(_miner.get_workplace()), "miner workplace ref stable across transition")
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						t.regrow_time = 0.2
						t._regrow()
						break
				_wood_before = _resources.get_amount("wood")
				_stone_before = _resources.get_amount("stone")
				_enter(TestPhase.NIGHT2_CHECK)
		TestPhase.NIGHT2_CHECK:
			var stone: int = _resources.get_amount("stone")
			var wood: int = _resources.get_amount("wood")
			if stone >= _stone_before + 3 and wood > _wood_before:
				_check(stone >= _stone_before + 3, "NIGHT: miner keeps producing (no stop policy, +%d)" % (stone - _stone_before))
				_check(wood > _wood_before, "NIGHT: lumberjack keeps producing (no stop policy, +%d)" % (wood - _wood_before))
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "production continued during NIGHT")
				_check(is_instance_valid(_lumberjack.get_workplace()), "lumberjack workplace stable during NIGHT")
				_check(is_instance_valid(_miner.get_workplace()), "miner workplace stable during NIGHT")
				_check(_lumberjack.state >= 0 and _lumberjack.state <= 5, "lumberjack FSM state valid (state=%d)" % _lumberjack.state)
				_check(_miner.state >= 0 and _miner.state <= 2, "miner FSM state valid (state=%d)" % _miner.state)
				_check(_lumberyard.get_filled_slots() == 1, "lumberyard assignment retained during NIGHT")
				_check(_quarry.get_filled_slots() == 1, "quarry assignment retained during NIGHT")
				_enter(TestPhase.TO_DAY3)
			elif _elapsed() >= 4000:
				_check(false, "NIGHT production within timeout (stone=%d wood=%d)" % [stone, wood])
				_finish()
				return true
		TestPhase.TO_DAY3:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "NIGHT -> DAY transition (cycle 3)")
				_check(_game_time.get_day_number() == 3, "day number increments to 3 (day=%d)" % _game_time.get_day_number())
				_check(not _controller.is_night_mode(), "DAY: camera controller day mode restored (cycle 3)")
				_check(_label_matches("DAY 3"), "HUD label reflects DAY 3 (text=%s)" % (_daytime_label.text if _daytime_label else "null"))
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						t.regrow_time = 0.2
						t._regrow()
						break
				_wood_before = _resources.get_amount("wood")
				_stone_before = _resources.get_amount("stone")
				_enter(TestPhase.DAY3_CHECK)
		TestPhase.DAY3_CHECK:
			var stone: int = _resources.get_amount("stone")
			var wood: int = _resources.get_amount("wood")
			if stone >= _stone_before + 3 and wood > _wood_before:
				_check(stone >= _stone_before + 3, "DAY return: miner resumes production (+%d)" % (stone - _stone_before))
				_check(wood > _wood_before, "DAY return: lumberjack resumes production (+%d)" % (wood - _wood_before))
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "production happened during DAY")
				_check(not _controller.is_night_mode(), "camera controller day mode during DAY production")
				_check(is_instance_valid(_lumberjack.get_workplace()), "lumberjack workplace stable across full cycle")
				_check(is_instance_valid(_miner.get_workplace()), "miner workplace stable across full cycle")
				_enter(TestPhase.UI_SYNC)
			elif _elapsed() >= 4000:
				_check(false, "DAY return production within timeout (stone=%d wood=%d)" % [stone, wood])
				_finish()
				return true
		TestPhase.UI_SYNC:
			if not _step_done:
				_step_done = true
				_game_time.advance(5.0)
			if _elapsed() >= 400:
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "still DAY after partial advance (UI sync)")
				_check(_label_matches("DAY 3"), "DayTimeLabel shows DAY 3 (text=%s)" % (_daytime_label.text if _daytime_label else "null"))
				var wood_label: Label = _hud.get_node("WoodLabel") as Label
				var stone_label: Label = _hud.get_node("StoneLabel") as Label
				_check(wood_label != null and wood_label.text.begins_with("Wood:"), "Wood HUD label intact (text=%s)" % (wood_label.text if wood_label else "null"))
				_check(stone_label != null and stone_label.text.begins_with("Stone:"), "Stone HUD label intact (text=%s)" % (stone_label.text if stone_label else "null"))
				_enter(TestPhase.SMOKE)
		TestPhase.SMOKE:
			_check(main.get_node("Player") != null, "player exists")
			_check(main.get_node("HUD") != null, "HUD exists")
			var floor_node: TileMapLayer = main.get_node("World/Floor") as TileMapLayer
			_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")
			_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack system intact")
			_check(get_nodes_in_group("miners").size() >= 1, "miner system intact")
			_check(get_nodes_in_group("lumberyards").size() >= 1, "lumberyard built during integration")
			_check(get_nodes_in_group("quarries").size() >= 1, "quarry built during integration")
			_check(_game_time.get_phase() == _game_time.Phase.DAY, "final state is DAY")
			_check(not _controller.is_night_mode(), "final state camera controller day mode")
			_enter(TestPhase.DONE)
		TestPhase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0105_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
