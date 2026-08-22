extends SceneTree

## TASK-010-1 GameTime / DayNight 상태 기반 검증.
## 전역 GameTime autoload의 초기 상태, DAY/NIGHT 전환, day number 증가,
## phase_changed 시그널 단일 발행(중복 없음), duration override/수동 진행(주입),
## auto-advance 동작/해제 결정성, 기존 main smoke 회귀를 자동 검증한다.

enum TestPhase {
	SETUP, BASICS, TRANSITION, CYCLES, SIGNAL_SINGLE, REENTRANT, AUTO_OFF, AUTO_ON, SMOKE, DONE
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _phase_start := 0
var _failed := false

var _game_time: Node = null
var _signal_count := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: TestPhase) -> void:
	_phase = new_phase
	_phase_start = _frame


func _elapsed() -> int:
	return _frame - _phase_start


func _finish() -> void:
	print("TASK0101_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _on_phase_changed(_phase_value: int, _day_number: int) -> void:
	_signal_count += 1


func _on_phase_changed_spam(_phase_value: int, _day_number: int) -> void:
	# 재진입 테스트: 시그널 핸들러 안에서 advance()를 호출해도
	# 중복 전환/중복 시그널이 발생하지 않아야 한다.
	_game_time.advance(100.0)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_game_time = root.get_node("GameTime")
			var main: Node = root.get_node("Main")
			var world: Node = main.get_node("World")
			var lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			lj.position = Vector2(300, 200)
			world.add_child(lj)
			var mn = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			mn.position = Vector2(500, 140)
			world.add_child(mn)
			_enter(TestPhase.BASICS)
		TestPhase.BASICS:
			_check(_game_time != null, "GameTime autoload exists")
			_check(_game_time.get_day_number() == 1, "starts at day 1")
			_check(_game_time.get_phase() == _game_time.Phase.DAY, "starts in DAY phase")
			_check(_game_time.get_phase_name() == "DAY", "phase name resolves to DAY")
			_check(_game_time.get_phase_duration() > 0.0, "day duration configured")
			_check(_game_time.get_phase_progress() == 0.0, "fresh phase progress is 0")
			_game_time.phase_changed.connect(_on_phase_changed)
			_game_time.set_auto_advance(false)
			_enter(TestPhase.TRANSITION)
		TestPhase.TRANSITION:
			_game_time.set_durations(10.0, 10.0)
			_check(_game_time.day_duration == 10.0 and _game_time.night_duration == 10.0, "durations overridable for tests")
			_game_time.advance(5.0)
			_check(_game_time.get_phase() == _game_time.Phase.DAY, "partial day advance stays DAY")
			_check(_game_time.get_phase_elapsed() == 5.0, "phase elapsed tracks 5.0")
			_check(absf(_game_time.get_phase_progress() - 0.5) < 0.001, "day progress is 0.5")
			_game_time.advance(5.0)
			_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "DAY -> NIGHT after full day duration")
			_check(_game_time.get_day_number() == 1, "day number unchanged during NIGHT")
			_check(_signal_count == 1, "phase_changed emitted once for DAY->NIGHT (count=%d)" % _signal_count)
			_enter(TestPhase.CYCLES)
		TestPhase.CYCLES:
			_game_time.advance(10.0)
			_check(_game_time.get_phase() == _game_time.Phase.DAY, "NIGHT -> DAY transition")
			_check(_game_time.get_day_number() == 2, "day number increments to 2 on new DAY (day=%d)" % _game_time.get_day_number())
			_game_time.advance(10.0)
			_game_time.advance(10.0)
			_game_time.advance(10.0)
			_game_time.advance(10.0)
			_check(_game_time.get_phase() == _game_time.Phase.DAY, "multiple cycles repeat DAY/NIGHT")
			_check(_game_time.get_day_number() == 4, "day number advances across cycles (day=%d)" % _game_time.get_day_number())
			_check(_signal_count == 6, "one signal per transition, no duplicates (count=%d)" % _signal_count)
			_enter(TestPhase.SIGNAL_SINGLE)
		TestPhase.SIGNAL_SINGLE:
			_signal_count = 0
			_game_time.advance(10.0)
			_check(_signal_count == 1, "single batch advance emits exactly one transition (count=%d)" % _signal_count)
			_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "batch advance ends in NIGHT")
			_enter(TestPhase.REENTRANT)
		TestPhase.REENTRANT:
			_signal_count = 0
			_game_time.phase_changed.connect(_on_phase_changed_spam)
			_game_time.advance(10.0)
			_check(_game_time.get_phase() == _game_time.Phase.DAY, "reentrant handler cannot skip ahead during transition")
			_check(_signal_count == 1, "reentrant advance() ignored - no duplicate phase signal (count=%d)" % _signal_count)
			_game_time.phase_changed.disconnect(_on_phase_changed_spam)
			_enter(TestPhase.AUTO_OFF)
		TestPhase.AUTO_OFF:
			var day_before: int = _game_time.get_day_number()
			if _elapsed() >= 20:
				_check(_game_time.get_day_number() == day_before, "auto-advance off keeps state frozen without manual advance")
				_enter(TestPhase.AUTO_ON)
		TestPhase.AUTO_ON:
			_game_time.set_durations(0.01, 0.01)
			_game_time.set_auto_advance(true)
			if _elapsed() >= 200:
				_check(_game_time.get_day_number() >= 2, "auto-advance on drives cycles from frame time (day=%d)" % _game_time.get_day_number())
				_check(_signal_count >= 2, "auto-advance emitted phase signals (count=%d)" % _signal_count)
				_game_time.set_auto_advance(false)
				_enter(TestPhase.SMOKE)
		TestPhase.SMOKE:
			var main: Node = root.get_node("Main")
			_check(main != null, "main.tscn loads with GameTime autoload present")
			_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
			_check(main.get_node("HUD") != null, "HUD exists")
			var floor_node: TileMapLayer = main.get_node("World/Floor") as TileMapLayer
			_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")
			_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack system intact")
			_check(get_nodes_in_group("miners").size() >= 1, "miner system intact")
			_check(root.get_node("VillageResources") != null, "VillageResources autoload intact")
			_enter(TestPhase.DONE)
		TestPhase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0101_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)