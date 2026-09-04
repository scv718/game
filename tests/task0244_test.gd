extends SceneTree

## TASK-024-4 Threat / Wave Regression (vertical slice).
## Threat → Wave pressure 전체 흐름을 하나의 연속 시나리오로 회귀 검증한다.
##   - DAY progression: 날짜가 진행되고(GameTime.day_number) Threat가 누적된다.
##   - threat increase: in-game 시간 경과에 비례해 Threat current가 증가한다.
##   - NIGHT: phase 전환과 함께 wave schedule이 NIGHT 단위로 처리된다.
##   - wave trigger: schedule/threshold trigger 모두 실제로 wave를 만든다.
##   - delay/reduce: delay_wave()/reduce_threat()가 다음 wave timing을 바꾼다.
##   - next wave: 지연/감소 후에도 다음 wave가 실제로 trigger된다.
##   - pause/1x/2x: Threat 성장이 전술 시간 배율과 일관된다(0=멈춤, 2x=2배).
##   - persistence: save/load 시스템은 아직 없으므로, 향후 저장을 위한 순수
##     데이터 스냅샷(to_snapshot/from_snapshot) round-trip이 상태를 보존한다.
##   - Gate/Tactical/Ghost 회귀는 별도 rerun(task3dbld0013 / task3dcmb0012 /
##     task0166)으로 실행해 test_results에 기록한다.
## autoload 전역 식별자는 -s 스탠드얼론에서 미등록이므로 root.get_node_or_null로 조회한다.

enum Phase {
	SETUP,
	DAY_PROGRESS,
	WAVE_TRIGGER,
	DELAY_REDUCE,
	NEXT_WAVE,
	TIME_SCALE,
	PERSISTENCE,
	DONE,
}

const LONG_DURATION := 100000.0
## 공차: Threat 성장이 프레임 타이밍에 따라 소수점에서 어긋날 수 있어 ±0.6 허용.
const GROWTH_EPS := 0.6

var _frame := 0
var _sub := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP

var _game_time: Node = null
var _threat: Node = null
var _wave: Node = null


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
	print("TASK0244_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


## DAY라면 NIGHT로, NIGHT라면 DAY로 한 번 전환한다.
func _toggle_phase() -> void:
	if _game_time.get_phase() == GameTime.Phase.DAY:
		_game_time.advance(_game_time.day_duration)
	else:
		_game_time.advance(_game_time.night_duration)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= GROWTH_EPS


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.DAY_PROGRESS:
			_day_progress()
		Phase.WAVE_TRIGGER:
			_wave_trigger()
		Phase.DELAY_REDUCE:
			_delay_reduce()
		Phase.NEXT_WAVE:
			_next_wave()
		Phase.TIME_SCALE:
			_time_scale()
		Phase.PERSISTENCE:
			_persistence()
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0244_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
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
		_game_time = root.get_node_or_null("GameTime")
		_threat = root.get_node_or_null("ThreatSystem")
		_wave = root.get_node_or_null("WaveManager")
		_check(_game_time != null, "GameTime autoload available")
		_check(_threat != null, "ThreatSystem autoload available")
		_check(_wave != null, "WaveManager autoload available")
		if _game_time == null or _threat == null or _wave == null:
			_finish()
			return
		_game_time.set_auto_advance(false)
		_game_time.set_time_scale(1.0)
		_game_time.set_durations(5.0, 5.0)
		_threat.growth_per_second = 1.0
		_threat.max_threat = 1000.0
		_threat.set_auto_grow(true)
		_threat.reset()
		_wave.base_wave_interval = 1
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
		_wave.reset()
		_wait = 3
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_enter(Phase.DAY_PROGRESS)


## -- DAY_PROGRESS: 짧은 DAY/NIGHT 사이클로 날짜 진행 + Threat 누적 --
## DAY(5s) + NIGHT(5s)를 3일간 진행한다. 매 NIGHT은 base interval 1로 wave다.
## Threat은 in-game 경과에 비례해 1.0/s로 자란다.
func _day_progress() -> void:
	if _sub == 0:
		_threat.reset()
		_wave.reset()
		# DAY 1 진행 5초 → NIGHT 1 (wave)
		_toggle_phase()
		_wait_frames(2)
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_check(_game_time.get_phase() == GameTime.Phase.NIGHT,
			"day: NIGHT 1 reached (phase=%s)" % _game_time.get_phase_name())
		_check(_wave.is_wave_night(),
			"day: NIGHT 1 is a wave night")
		_check(_wave.get_wave_index() == 1,
			"day: first wave triggered (index=%d)" % _wave.get_wave_index())
		_check(_near(_threat.get_current(), 5.0),
			"day: threat grew through DAY 1 (%.2f)" % _threat.get_current())
		_toggle_phase()  # NIGHT 1 → DAY 2
		_wait_frames(2)
		_sub = 2
		return
	if _sub == 2:
		if not _waited():
			return
		_check(_game_time.get_phase() == GameTime.Phase.DAY,
			"day: back to DAY (phase=%s)" % _game_time.get_phase_name())
		_check(_game_time.get_day_number() == 2,
			"day: day_number progressed to 2 (got %d)" % _game_time.get_day_number())
		_check(_threat.get_current() > 5.0,
			"day: threat keeps rising through NIGHT (%.2f)" % _threat.get_current())
		_toggle_phase()  # DAY 2 → NIGHT 2 (wave)
		_wait_frames(2)
		_sub = 3
		return
	if _sub == 3:
		if not _waited():
			return
		_check(_wave.get_wave_index() == 2,
			"day: NIGHT 2 triggered next wave (index=%d)" % _wave.get_wave_index())
		_check(_wave.is_wave_night(),
			"day: NIGHT 2 is a wave night")
		_toggle_phase()  # NIGHT 2 → DAY 3
		_wait_frames(2)
		_sub = 4
		return
	if _sub == 4:
		if not _waited():
			return
		_check(_game_time.get_day_number() == 3,
			"day: day_number progressed to 3 (got %d)" % _game_time.get_day_number())
		_check(_threat.get_current() > 10.0,
			"day: threat accumulates across DAY/NIGHT cycles (%.2f)"
			% _threat.get_current())
		_check(_threat.get_current() <= _threat.get_max(),
			"day: threat stays within max (%.2f)" % _threat.get_current())
		_game_time.set_durations(LONG_DURATION, LONG_DURATION)
		_enter(Phase.WAVE_TRIGGER)


## -- WAVE_TRIGGER: schedule + threshold trigger + next wave timing 검증 --
## Threat ratio가 threshold를 넘으면 스케줄과 무관하게 강제 wave가 되고,
## 감소시키면 강제가 풀리고 다음 wave 간격이 길어진다.
func _wave_trigger() -> void:
	if _sub == 0:
		_threat.set_auto_grow(false)
		_threat.max_threat = 100.0
		_wave.base_wave_interval = 4
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.5
		_wave.wave_threshold_ratio = 0.5
		_wave.reset()
		_threat.reset()
		# ratio 0.6 → 다음 NIGHT은 강제 wave.
		_threat.add(60.0)
		_check(_threat.get_ratio() >= 0.5,
			"trigger: threat ratio raised above threshold (%.2f)" % _threat.get_ratio())
		_toggle_phase()  # NIGHT 1
		_wait_frames(2)
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_check(_wave.is_wave_night(),
			"trigger: NIGHT 1 forced wave despite schedule")
		_check(_wave.get_wave_index() == 1,
			"trigger: threshold trigger increments wave (index=%d)"
			% _wave.get_wave_index())
		# ratio 0.6에서 다음 간격: round(4*(1-0.6*0.5)) = round(2.8) = 3
		_check(_wave.get_nights_until_wave() == 3,
			"trigger: high threat shortens next interval to 3 nights (got %d)"
			% _wave.get_nights_until_wave())
		_toggle_phase()  # NIGHT 1 → DAY 2
		_wait_frames(2)
		_sub = 2
		return
	if _sub == 2:
		if not _waited():
			return
		# threshold 미달이면 다음 NIGHT은 강제 wave가 아니다.
		_wave.reduce_threat(60.0)
		_check(is_equal_approx(_threat.get_ratio(), 0.0),
			"trigger: reduce_threat lowers ratio to 0 (%.2f)" % _threat.get_ratio())
		_toggle_phase()  # DAY 2 → NIGHT 2
		_wait_frames(2)
		_sub = 3
		return
	if _sub == 3:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"trigger: no forced wave after threat reduced")
		_check(_wave.get_wave_index() == 1,
			"trigger: no extra trigger after reduce (index=%d)" % _wave.get_wave_index())
		_toggle_phase()  # NIGHT 2 → DAY 3
		_wait_frames(2)
		_sub = 4
		return
	if _sub == 4:
		if not _waited():
			return
		_enter(Phase.DELAY_REDUCE)


## -- DELAY_REDUCE: delay_wave()가 다음 wave를 뒤로 미는지 --
func _delay_reduce() -> void:
	if _sub == 0:
		_wave.base_wave_interval = 1
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
		_wave.max_delay_nights = 5
		_wave.reset()
		_threat.reset()
		_toggle_phase()  # NIGHT 3 (wave, schedule start)
		_wait_frames(2)
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_check(_wave.get_wave_index() == 1,
			"delay: first wave after reset triggered (index=%d)" % _wave.get_wave_index())
		_check(_wave.get_nights_until_wave() == 1,
			"delay: base interval 1 means next wave in 1 night (got %d)"
			% _wave.get_nights_until_wave())
		_toggle_phase()  # NIGHT → DAY
		_wave.delay_wave(2)
		_wait_frames(2)
		_sub = 2
		return
	if _sub == 2:
		if not _waited():
			return
		_check(_wave.get_nights_until_wave() == 3,
			"delay: delay_wave(2) pushes next wave to 3 nights (1+2, got %d)"
			% _wave.get_nights_until_wave())
		_toggle_phase()  # DAY → NIGHT
		_wait_frames(2)
		_sub = 3
		return
	if _sub == 3:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"delay: next NIGHT no wave after delay")
		_check(_wave.get_wave_index() == 1,
			"delay: no extra trigger on delayed NIGHT (index=%d)"
			% _wave.get_wave_index())
		_toggle_phase()  # NIGHT → DAY
		_wait_frames(2)
		_sub = 4
		return
	if _sub == 4:
		if not _waited():
			return
		_enter(Phase.NEXT_WAVE)


## -- NEXT_WAVE: 지연된 wave가 실제로 돌아오는지 --
func _next_wave() -> void:
	if _sub == 0:
		# DAY 5에서 NIGHT 5 → NIGHT 6까지 진행: 남은 2 NIGHT 뒤 wave.
		_toggle_phase()  # DAY 5 → NIGHT 5
		_wait_frames(2)
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"next: NIGHT 5 still not a wave night")
		_toggle_phase()  # NIGHT 5 → DAY 6
		_toggle_phase()  # DAY 6 → NIGHT 6
		_wait_frames(2)
		_sub = 2
		return
	if _sub == 2:
		if not _waited():
			return
		_check(_wave.is_wave_night(),
			"next: delayed wave finally triggers on next wave night")
		_check(_wave.get_wave_index() == 2,
			"next: next wave increments index (got %d)" % _wave.get_wave_index())
		_toggle_phase()  # NIGHT → DAY
		_wait_frames(2)
		_sub = 3
		return
	if _sub == 3:
		if not _waited():
			return
		_enter(Phase.TIME_SCALE)


## -- TIME_SCALE: pause(0)/1x/2x와 Threat 성장 일관성 --
func _time_scale() -> void:
	if _sub == 0:
		_game_time.set_durations(LONG_DURATION, LONG_DURATION)
		_game_time.set_time_scale(1.0)
		_threat.set_auto_grow(true)
		_threat.growth_per_second = 1.0
		_threat.max_threat = 1000.0
		_threat.reset()
		_wait = 3
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		# Pause(0): in-game 시간이 흐르지 않으므로 Threat 성장도 멈춘다.
		_game_time.set_time_scale(0.0)
		var before: float = _threat.get_current()
		_game_time.advance(10.0)
		_wait_frames(2)
		_ts_pause_before = before
		_sub = 2
		return
	if _sub == 2:
		if not _waited():
			return
		_check(is_equal_approx(_threat.get_current(), _ts_pause_before),
			"scale: no growth while paused (%.2f == %.2f)"
			% [_threat.get_current(), _ts_pause_before])
		# 2x: 4 in-game 초가 8초 경과로 취급되어 +8 성장.
		_game_time.set_time_scale(2.0)
		var before2: float = _threat.get_current()
		_game_time.advance(4.0)
		_wait_frames(2)
		_ts_2x_before = before2
		_sub = 3
		return
	if _sub == 3:
		if not _waited():
			return
		var grown: float = _threat.get_current() - _ts_2x_before
		_check(_near(grown, 8.0),
			"scale: growth respects 2x time scale (grown=%.2f)" % grown)
		# 1x 복귀: 3 in-game 초 → +3 성장.
		_game_time.set_time_scale(1.0)
		var before3: float = _threat.get_current()
		_game_time.advance(3.0)
		_wait_frames(2)
		_ts_1x_before = before3
		_sub = 4
		return
	if _sub == 4:
		if not _waited():
			return
		var grown1: float = _threat.get_current() - _ts_1x_before
		_check(_near(grown1, 3.0),
			"scale: growth returns to 1x rate (grown=%.2f)" % grown1)
		_game_time.set_time_scale(1.0)
		_enter(Phase.PERSISTENCE)


var _ts_pause_before := 0.0
var _ts_2x_before := 0.0
var _ts_1x_before := 0.0


## -- PERSISTENCE: save/load는 아직 없으므로 snapshot round-trip이 상태를 보존 --
func _persistence() -> void:
	if _sub == 0:
		# Threat snapshot round-trip.
		_threat.set_auto_grow(false)
		_threat.reset()
		_threat.add(37.5)
		var snap: Dictionary = _threat.to_snapshot()
		_check(snap.get("current", 0.0) == 37.5,
			"persist: threat to_snapshot captures current")
		_threat.reset()
		_check(_threat.get_current() == 0.0, "persist: reset zeroes threat")
		_threat.from_snapshot(snap)
		_check(is_equal_approx(_threat.get_current(), 37.5),
			"persist: threat from_snapshot restores current (%.2f)"
			% _threat.get_current())
		# Wave snapshot round-trip.
		_wave.reset()
		_wave.delay_wave(3)
		var wsnap: Dictionary = _wave.to_snapshot()
		_check(wsnap.get("nights_until_wave", 0) == 3,
			"persist: wave to_snapshot captures schedule")
		_wave.reset()
		_check(_wave.get_nights_until_wave() == 0,
			"persist: wave reset clears schedule")
		_wave.from_snapshot(wsnap)
		_check(_wave.get_nights_until_wave() == 3,
			"persist: wave from_snapshot restores schedule (got %d)"
			% _wave.get_nights_until_wave())
		_sub = 1
		return
	if _sub == 1:
		_enter(Phase.DONE)