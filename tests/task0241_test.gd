extends SceneTree

## TASK-024-1 Threat State 자동 검증.
## ThreatSystem autoload의 순수 상태 동작을 검증한다.
##   - deterministic growth: GameTime in-game 경과에 비례해 성장.
##   - clamp: current가 [0, max]를 벗어나지 않음.
##   - pause/time scale 일관: Pause(0) 중에는 성장 멈춤.
##   - repeated DAY/NIGHT 안정: 여러 phase 전환 후에도 안전(음수/초과 없음).
##   - reduce: 0 미만으로 내려가지 않음.
##   - UI signal: threat_changed 발행.
##   - snapshot: to_snapshot/from_snapshot round-trip.
## autoload 전역 식별자는 -s 스탠드얼론에서 미등록이므로 root.get_node_or_null로 조회한다.

enum Phase {
	SETUP,
	GROWTH,
	CLAMP,
	PAUSE,
	REDUCE,
	SNAPSHOT,
	DAY_NIGHT,
	SIGNAL,
	DONE,
}

const LONG_DURATION := 100000.0

var _frame := 0
var _sub := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _threat: Node = null
var _game_time: Node = null
var _signal_count := 0
var _signal_current := 0.0
var _day_cycles := 0
var _snap_data: Dictionary = {}


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


## sub-step을 진행하고 n 프레임 대기.
func _wait_frames(n: int) -> void:
	_wait = n
	_sub += 1


func _waited() -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	return true


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
		_game_time.set_time_scale(1.0)
	print("TASK0241_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.GROWTH:
			_growth()
		Phase.CLAMP:
			_clamp()
		Phase.PAUSE:
			_pause()
		Phase.REDUCE:
			_reduce()
		Phase.SNAPSHOT:
			_snapshot()
		Phase.DAY_NIGHT:
			_day_night()
		Phase.SIGNAL:
			_signal()
		Phase.DONE:
			_finish()
			return true
	if _frame > 20000:
		print("TASK0241_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _initialize() -> void:
	pass


## -- SETUP: autoload 조회 + 테스트 설정 --
func _setup() -> void:
	if _sub == 0:
		if _frame < 6:
			return
		_threat = root.get_node_or_null("ThreatSystem")
		_game_time = root.get_node_or_null("GameTime")
		_check(_threat != null, "ThreatSystem autoload available")
		_check(_game_time != null, "GameTime autoload available")
		if _threat == null or _game_time == null:
			_finish()
			return
		_game_time.set_auto_advance(false)
		_game_time.set_durations(LONG_DURATION, LONG_DURATION)
		_game_time.set_time_scale(1.0)
		_threat.set_auto_grow(true)
		_threat.reset()
		_threat.growth_per_second = 1.0
		_threat.max_threat = 1000.0
		# ThreatSystem._process가 _last_* 스냅샷을 현재 phase로 초기화할 프레임을 준다.
		_wait = 3
		_sub = 1
		return
	if _sub == 1:
		if _wait > 0:
			_wait -= 1
			return
		_enter(Phase.GROWTH)


## -- GROWTH: deterministic growth 검증 --
func _growth() -> void:
	if _sub == 0:
		if not _waited():
			return
		var before: float = _threat.get_current()
		_game_time.advance(5.0)
		_wait_frames(2)
		_check_growth1(before)
	elif _sub == 1:
		if not _waited():
			return
		var grown: float = _threat.get_current() - _check_growth1_from
		_check(grown > 4.99 and grown < 5.01,
			"deterministic growth adds growth_per_second * elapsed (%.2f)" % grown)
		var before2: float = _threat.get_current()
		_game_time.advance(3.0)
		_wait_frames(2)
		_check_growth2_before = before2
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		var grown2: float = _threat.get_current() - _check_growth2_before
		_check(grown2 > 2.99 and grown2 < 3.01,
			"growth continues deterministically across advances (%.2f)" % grown2)
		_enter(Phase.CLAMP)


var _check_growth1_from := 0.0
var _check_growth2_before := 0.0


func _check_growth1(before: float) -> void:
	_check_growth1_from = before


## -- CLAMP: current가 max를 넘지 않음 --
func _clamp() -> void:
	if _sub == 0:
		_threat.reset()
		_threat.max_threat = 10.0
		_threat.growth_per_second = 100.0
		_game_time.advance(1000.0)
		_wait_frames(2)
		return
	if _sub == 1:
		if not _waited():
			return
		_check(_threat.get_current() <= _threat.get_max(),
			"current clamps at max (%.2f)" % _threat.get_current())
		_check(is_equal_approx(_threat.get_current(), _threat.get_max()),
			"current reaches max exactly under heavy growth")
		_check(_threat.get_ratio() <= 1.0 and _threat.get_ratio() >= 0.0,
			"ratio stays in [0,1] (%.2f)" % _threat.get_ratio())
		_enter(Phase.PAUSE)


## -- PAUSE: time scale 0에서 성장 멈춤 --
func _pause() -> void:
	if _sub == 0:
		_threat.reset()
		_threat.growth_per_second = 1.0
		_threat.max_threat = 1000.0
		_game_time.set_time_scale(0.0)
		_game_time.advance(10.0)
		_wait_frames(2)
		return
	if _sub == 1:
		if not _waited():
			return
		_check(_threat.get_current() == 0.0,
			"no growth while paused (time scale 0): %.2f" % _threat.get_current())
		_game_time.set_time_scale(2.0)
		var before: float = _threat.get_current()
		_game_time.advance(4.0)
		_wait_frames(2)
		_pause_2x_before = before
		_sub = 2
		return
	if _sub == 2:
		if not _waited():
			return
		var grown: float = _threat.get_current() - _pause_2x_before
		# 2x 배율: 4 in-game 초가 8초 경과로 취급되어 +8 성장.
		_check(grown > 7.9 and grown < 8.1,
			"growth respects time scale (2x => %.2f)" % grown)
		_game_time.set_time_scale(1.0)
		_enter(Phase.REDUCE)


var _pause_2x_before := 0.0


## -- REDUCE: 감소가 0 미만으로 내려가지 않음 --
func _reduce() -> void:
	if _sub == 0:
		_threat.reset()
		_threat.add(50.0)
		_check(is_equal_approx(_threat.get_current(), 50.0),
			"add() raises current (%.2f)" % _threat.get_current())
		_threat.reduce(30.0)
		_check(is_equal_approx(_threat.get_current(), 20.0),
			"reduce() lowers current (%.2f)" % _threat.get_current())
		_threat.reduce(999.0)
		_check(_threat.get_current() == 0.0,
			"reduce clamps at 0 (%.2f)" % _threat.get_current())
		_sub = 1
		return
	if _sub == 1:
		_enter(Phase.SNAPSHOT)


## -- SNAPSHOT: to_snapshot/from_snapshot round-trip --
func _snapshot() -> void:
	if _sub == 0:
		_threat.reset()
		_threat.add(37.5)
		_snap_data = _threat.to_snapshot()
		_check(_snap_data.get("current", 0.0) == 37.5, "to_snapshot captures current")
		_check(_snap_data.get("max", 0.0) == _threat.get_max(), "to_snapshot captures max")
		_threat.reset()
		_check(_threat.get_current() == 0.0, "reset zeroes current")
		_threat.from_snapshot(_snap_data)
		_check(is_equal_approx(_threat.get_current(), 37.5),
			"from_snapshot restores current (%.2f)" % _threat.get_current())
		_enter(Phase.DAY_NIGHT)


## -- DAY_NIGHT: 반복 phase 전환 후에도 안정 --
func _day_night() -> void:
	if _day_cycles == 0 and _sub == 0:
		_threat.reset()
		_threat.max_threat = 50.0
		_threat.growth_per_second = 1.0
		_game_time.set_durations(2.0, 1.0)
		# DAY(2초) + NIGHT(1초)를 진행해 한 날을 넘긴다.
		_game_time.advance(1.0)
		_wait = 2
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		var c: float = _threat.get_current()
		_check(c >= 0.0 and c <= _threat.get_max(),
			"DAY/NIGHT cycle %d keeps current in [0,max] (%.2f)" % [_day_cycles, c])
		_day_cycles += 1
		if _day_cycles >= 3:
			_check(_threat.get_current() >= 0.0,
				"threat never negative after repeated cycles (%.2f)" % _threat.get_current())
			_game_time.set_durations(LONG_DURATION, LONG_DURATION)
			_enter(Phase.SIGNAL)
			return
		_game_time.advance(1.0)
		_wait = 2
		_sub = 1


## -- SIGNAL: threat_changed 발행 확인 --
func _signal() -> void:
	if _sub == 0:
		_threat.threat_changed.connect(_on_threat_changed)
		_signal_count = 0
		_threat.add(5.0)
		_check(_signal_count == 1,
			"threat_changed emitted once on add (count=%d)" % _signal_count)
		_check(is_equal_approx(_signal_current, _threat.get_current()),
			"signal carries the new current value")
		_enter(Phase.DONE)


func _on_threat_changed(current: float, _max: float) -> void:
	_signal_count += 1
	_signal_current = current

