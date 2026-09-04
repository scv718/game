extends SceneTree

## TASK-028-2 Dungeon Clear Threat Reduction 자동 검증.
##  - CLEARED 확정 시 run당 정확히 1회 Threat reduce/delay 적용.
##  - RETREAT/FAILED에는 clear reduction 적용 금지.
##  - 동일 Dungeon clear event 재수신으로 duplicate 감소 금지.
##  - Threat HUD 갱신 신호(threat_changed / schedule_changed)가 즉시 발행.
##  - 다음 Wave schedule이 실제로 변경(지연)된다.
##
## 이 검증은 실제 Dungeon runtime(TASK-027)이 아직 없으므로 WaveManager가 제공하는
## authoritative result contract(report_dungeon_result)을 통해 run 결과를 보고한다.
## TASK-028-1이 고정한 apply_dungeon_clear가 내부 감소/지연과 duplicate guard를
## 담당하며, TASK-028-2는 outcome gate(CLEARED만 통과)와 HUD 신호를 검증한다.
##
## autoload 전역 식별자는 -s 스탠드얼론에서 미등록이므로 root.get_node_or_null로 조회한다.

enum Phase {
	SETUP,
	CLEAR_ONCE,
	RETREAT_NO_REDUCE,
	FAILED_NO_REDUCE,
	DUPLICATE_GUARD,
	HUD_SIGNAL,
	SCHEDULE_CHANGED,
	DONE,
}

const LONG_DURATION := 100000.0

var _frame := 0
var _sub := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP

var _threat: Node = null
var _wave: Node = null
var _game_time: Node = null

var _hud_signal_threat := 0
var _hud_signal_schedule := 0
var _signal_dungeon_outcomes: Array[String] = []


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
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
		_game_time.set_time_scale(1.0)
	print("TASK0282_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


## DAY라면 NIGHT로, NIGHT라면 DAY로 한 번 전환한다.
func _toggle_phase() -> void:
	if _game_time.get_phase() == GameTime.Phase.DAY:
		_game_time.advance(_game_time.day_duration)
	else:
		_game_time.advance(_game_time.night_duration)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CLEAR_ONCE:
			_clear_once()
		Phase.RETREAT_NO_REDUCE:
			_retreat_no_reduce()
		Phase.FAILED_NO_REDUCE:
			_failed_no_reduce()
		Phase.DUPLICATE_GUARD:
			_duplicate_guard()
		Phase.HUD_SIGNAL:
			_hud_signal()
		Phase.SCHEDULE_CHANGED:
			_schedule_changed()
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0282_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


## -- SETUP: autoload 조회 + 테스트 설정 --
func _setup() -> void:
	if _sub == 0:
		if _frame < 6:
			return
		_wave = root.get_node_or_null("WaveManager")
		_threat = root.get_node_or_null("ThreatSystem")
		_game_time = root.get_node_or_null("GameTime")
		_check(_wave != null, "WaveManager autoload available")
		_check(_threat != null, "ThreatSystem autoload available")
		_check(_game_time != null, "GameTime autoload available")
		if _wave == null or _threat == null or _game_time == null:
			_finish()
			return
		_game_time.set_auto_advance(false)
		_game_time.set_durations(LONG_DURATION, LONG_DURATION)
		_game_time.set_time_scale(1.0)
		_threat.set_auto_grow(false)
		_threat.max_threat = 100.0
		_threat.reset()
		_wave.reset()
		_wave.base_wave_interval = 1
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
		_wave.dungeon_clear_reduce_amount = 25.0
		_wave.dungeon_clear_delay_nights = 1
		_wave.dungeon_run_result.connect(_on_dungeon_run_result)
		_wait = 3
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_enter(Phase.CLEAR_ONCE)


## -- CLEAR_ONCE: CLEARED 확정 시 run당 정확히 1회 reduce/delay --
func _clear_once() -> void:
	if _sub == 0:
		_threat.reset()
		_wave.reset()
		_threat.set_auto_grow(false)
		_threat.add(60.0)
		_check(is_equal_approx(_threat.get_current(), 60.0),
			"clear: threat set to 60 (%.2f)" % _threat.get_current())
		# 첫 NIGHT wave trigger 후 base interval 1 -> next wave in 1 night.
		_toggle_phase()
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		_check(_wave.get_wave_index() == 1,
			"clear: baseline wave triggered (%d)" % _wave.get_wave_index())
		var nights_before: int = _wave.get_nights_until_wave()
		var current_before: float = _threat.get_current()
		_wave.report_dungeon_result(_wave.DUNGEON_CLEARED, "dungeon_run_a")
		_check(is_equal_approx(_threat.get_current(), current_before - 25.0),
			"clear: CLEARED reduces threat by config (%.2f -> %.2f)"
			% [current_before, _threat.get_current()])
		_check(_wave.get_nights_until_wave() > nights_before,
			"clear: CLEARED delays next wave (%d -> %d)"
			% [nights_before, _wave.get_nights_until_wave()])
		_check(_wave.is_dungeon_clear_applied("dungeon_run_a"),
			"clear: run a marked applied")
		_enter(Phase.RETREAT_NO_REDUCE)


## -- RETREAT_NO_REDUCE: RETREAT에는 clear reduction 적용 금지 --
func _retreat_no_reduce() -> void:
	if _sub == 0:
		_threat.reset()
		_wave.reset()
		_threat.add(50.0)
		_toggle_phase()
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		var nights_before: int = _wave.get_nights_until_wave()
		var current_before: float = _threat.get_current()
		_wave.report_dungeon_result(_wave.DUNGEON_RETREAT, "dungeon_run_b")
		_check(is_equal_approx(_threat.get_current(), current_before),
			"retreat: RETREAT does not reduce threat (%.2f)" % _threat.get_current())
		_check(_wave.get_nights_until_wave() == nights_before,
			"retreat: RETREAT does not delay wave (%d)" % _wave.get_nights_until_wave())
		_check(not _wave.is_dungeon_clear_applied("dungeon_run_b"),
			"retreat: run b not marked clear-applied")
		_enter(Phase.FAILED_NO_REDUCE)


## -- FAILED_NO_REDUCE: FAILED에는 clear reduction 적용 금지 --
func _failed_no_reduce() -> void:
	if _sub == 0:
		_threat.reset()
		_wave.reset()
		_threat.add(50.0)
		_toggle_phase()
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		var nights_before: int = _wave.get_nights_until_wave()
		var current_before: float = _threat.get_current()
		_wave.report_dungeon_result(_wave.DUNGEON_FAILED, "dungeon_run_c")
		_check(is_equal_approx(_threat.get_current(), current_before),
			"failed: FAILED does not reduce threat (%.2f)" % _threat.get_current())
		_check(_wave.get_nights_until_wave() == nights_before,
			"failed: FAILED does not delay wave (%d)" % _wave.get_nights_until_wave())
		_check(not _wave.is_dungeon_clear_applied("dungeon_run_c"),
			"failed: run c not marked clear-applied")
		_enter(Phase.DUPLICATE_GUARD)


## -- DUPLICATE_GUARD: 동일 run CLEARED 재수신으로 duplicate 감소 금지 --
func _duplicate_guard() -> void:
	if _sub == 0:
		_threat.reset()
		_wave.reset()
		_threat.add(60.0)
		_wave.report_dungeon_result(_wave.DUNGEON_CLEARED, "dungeon_run_d")
		var current_after_first: float = _threat.get_current()
		var nights_after_first: int = _wave.get_nights_until_wave()
		_check(_wave.is_dungeon_clear_applied("dungeon_run_d"),
			"dup: first CLEARED applied")
		_wave.report_dungeon_result(_wave.DUNGEON_CLEARED, "dungeon_run_d")
		_check(is_equal_approx(_threat.get_current(), current_after_first),
			"dup: duplicate CLEARED does not reduce again (%.2f)" % _threat.get_current())
		_check(_wave.get_nights_until_wave() == nights_after_first,
			"dup: duplicate CLEARED does not delay again (%d)" % _wave.get_nights_until_wave())
		_sub = 1
	elif _sub == 1:
		_enter(Phase.HUD_SIGNAL)


## -- HUD_SIGNAL: Threat HUD가 구독하는 threat_changed / schedule_changed 즉시 발행 --
func _hud_signal() -> void:
	if _sub == 0:
		_hud_signal_threat = 0
		_hud_signal_schedule = 0
		_threat.threat_changed.connect(_on_threat_changed)
		_wave.schedule_changed.connect(_on_wave_schedule_changed)
		_threat.reset()
		_wave.reset()
		_threat.add(50.0)
		_wave.report_dungeon_result(_wave.DUNGEON_CLEARED, "dungeon_run_e")
		_check(_hud_signal_threat >= 1,
			"hud: CLEARED emits threat_changed (%d)" % _hud_signal_threat)
		_check(_hud_signal_schedule >= 1,
			"hud: CLEARED emits schedule_changed (%d)" % _hud_signal_schedule)
		_threat.threat_changed.disconnect(_on_threat_changed)
		_wave.schedule_changed.disconnect(_on_wave_schedule_changed)
		_enter(Phase.SCHEDULE_CHANGED)


## -- SCHEDULE_CHANGED: 다음 Wave schedule이 실제로 변경(지연)되는지 기간 검증 --
func _schedule_changed() -> void:
	if _sub == 0:
		_threat.reset()
		_wave.reset()
		_wave.base_wave_interval = 1
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
		_wave.threat_schedule_factor = 0.0
		_wave.dungeon_clear_delay_nights = 1
		_threat.add(20.0)
		_wave.report_dungeon_result(_wave.DUNGEON_CLEARED, "dungeon_run_f")
		_check(_wave.get_nights_until_wave() >= 1,
			"schedule: next wave delayed to at least 1 night (%d)"
			% _wave.get_nights_until_wave())
		# NIGHT 진입 시, 지연(delay 1) 덕분에 이번 NIGHT은 wave night가 아니다.
		_toggle_phase()
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"schedule: the next NIGHT is not a wave night after clear delay")
		_check(_wave.get_wave_index() == 0,
			"schedule: no wave triggered on the delayed night (%d)" % _wave.get_wave_index())
		_sub = 2
	elif _sub == 2:
		_enter(Phase.DONE)


func _on_threat_changed(_current: float, _max: float) -> void:
	_hud_signal_threat += 1


func _on_wave_schedule_changed(_nights: int, _index: int) -> void:
	_hud_signal_schedule += 1


func _on_dungeon_run_result(outcome: String, _id: String) -> void:
	_signal_dungeon_outcomes.append(outcome)

