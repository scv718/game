extends SceneTree

## TASK-010-2 Day/Time HUD 검증.
## HUD의 DayTimeLabel이 GameTime 상태(phase/day number/progress)와 동기화되는지,
## 기존 Wood/Stone HUD가 그대로 동작하는지, main smoke 회귀가 없는지 자동 검증한다.
## progress 퍼센트 갱신은 HUD의 0.25s 주기 타이머 기반이므로, 프레임 수가 아닌
## 충분한 대기 프레임 후 검사한다.

enum TestPhase {
	SETUP, INIT, PROGRESS, NIGHT, DAY2, NIGHT_PROGRESS, WOOD_STONE, SMOKE, DONE
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _game_time: Node = null
var _hud: Node = null
var _daytime_label: Label = null
var _wood_label: Label = null
var _stone_label: Label = null

const TIMER_WAIT_FRAMES := 400


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
	print("TASK0102_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_game_time = root.get_node("GameTime")
			var main: Node = root.get_node("Main")
			_hud = main.get_node("HUD")
			_daytime_label = _hud.get_node("DayTimeLabel") as Label
			_wood_label = _hud.get_node("WoodLabel") as Label
			_stone_label = _hud.get_node("StoneLabel") as Label
			var world: Node = main.get_node("World")
			var lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			lj.position = Vector2(300, 200)
			world.add_child(lj)
			var mn = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			mn.position = Vector2(500, 140)
			world.add_child(mn)
			_enter(TestPhase.INIT)
		TestPhase.INIT:
			_check(_game_time != null, "GameTime autoload exists")
			_check(_hud != null, "HUD exists in main")
			_check(_daytime_label != null, "DayTimeLabel exists in HUD")
			_check(_wood_label != null, "WoodLabel exists in HUD")
			_check(_stone_label != null, "StoneLabel exists in HUD")
			_check(_daytime_label.text.begins_with("DAY 1"), "initial label shows DAY 1 (text=%s)" % _daytime_label.text)
			_game_time.set_auto_advance(false)
			_game_time.set_durations(10.0, 10.0)
			_enter(TestPhase.PROGRESS)
		TestPhase.PROGRESS:
			if not _step_done:
				_step_done = true
				_game_time.advance(5.0)
			if _elapsed() >= TIMER_WAIT_FRAMES:
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "still DAY after partial advance")
				_check(_daytime_label.text == "DAY 1  50%", "label syncs progress percent (text=%s)" % _daytime_label.text)
				_enter(TestPhase.NIGHT)
		TestPhase.NIGHT:
			if not _step_done:
				_step_done = true
				_game_time.advance(5.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "advanced into NIGHT")
				_check(_game_time.get_day_number() == 1, "day number stays 1 during NIGHT")
				_check(_daytime_label.text.begins_with("NIGHT 1"), "label reflects NIGHT on phase change (text=%s)" % _daytime_label.text)
				_enter(TestPhase.DAY2)
		TestPhase.DAY2:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "NIGHT -> DAY transition")
				_check(_game_time.get_day_number() == 2, "day number increments to 2")
				_check(_daytime_label.text.begins_with("DAY 2"), "label reflects new day number (text=%s)" % _daytime_label.text)
				_enter(TestPhase.NIGHT_PROGRESS)
		TestPhase.NIGHT_PROGRESS:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
				_game_time.advance(5.0)
			if _elapsed() >= TIMER_WAIT_FRAMES:
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "advanced into NIGHT on day 2")
				_check(_game_time.get_day_number() == 2, "day number stays 2 during NIGHT on day 2")
				_check(_daytime_label.text == "NIGHT 2  50%", "label syncs night progress percent (text=%s)" % _daytime_label.text)
				_enter(TestPhase.WOOD_STONE)
		TestPhase.WOOD_STONE:
			if not _step_done:
				_step_done = true
				root.get_node("VillageResources").add("wood", 3)
				root.get_node("VillageResources").add("stone", 5)
			if _elapsed() >= 4:
				_check(_wood_label.text == "Wood: 3", "Wood HUD label still works (text=%s)" % _wood_label.text)
				_check(_stone_label.text == "Stone: 5", "Stone HUD label still works (text=%s)" % _stone_label.text)
				_check(_daytime_label.text.begins_with("NIGHT 2"), "DayTimeLabel unaffected by resource updates")
				_enter(TestPhase.SMOKE)
		TestPhase.SMOKE:
			var main: Node = root.get_node("Main")
			_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
			_check(main.get_node("HUD") != null, "HUD exists")
			var floor_node: TileMapLayer = main.get_node("World/Floor") as TileMapLayer
			_check(floor_node != null and floor_node.get_used_cells().size() == 192 * 192, "world floor intact (192x192)")
			_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack system intact")
			_check(get_nodes_in_group("miners").size() >= 1, "miner system intact")
			_enter(TestPhase.DONE)
		TestPhase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0102_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)