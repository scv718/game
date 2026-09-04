extends SceneTree

## TASK-024-2 Wave Trigger / Delay Contract 자동 검증.
## WaveManager autoload + 기존 NIGHT enemy spawn(FirstEncounterSpawner3D) 연결을 검증한다.
##   - schedule trigger: base_wave_interval(NIGHT)마다 wave가 trigger되고 그 사이 NIGHT은
##     wave night가 아니다.
##   - threshold trigger: threat ratio가 wave_threshold_ratio 이상이면 스케줄과 무관하게
##     해당 NIGHT을 강제 wave로 당긴다.
##   - Threat 영향(최소 규칙): ratio가 높을수록 다음 wave 간격이 줄어든다.
##   - delay/reduce 호출: delay_wave()는 다음 wave를 뒤로, reduce_threat()는 ratio를 낮춰
##     다음 wave timing을 실제로 변화시킨다.
##   - duplicate trigger 없음: 동일 NIGHT wave 처리는 정확히 1회다.
##   - spawner 연결: WaveManager.is_wave_night()가 true인 NIGHT에만 FirstEncounterSpawner3D가
##     spawn하고, false인 NIGHT에는 spawn하지 않는다.
## autoload 전역 식별자는 -s 스탠드얼론에서 미등록이므로 root.get_node_or_null로 조회한다.

enum Phase {
	SETUP,
	SCHEDULE,
	THRESHOLD,
	DELAY,
	REDUCE,
	DUPLICATE,
	SPAWNER_CONNECT,
	DONE,
}

const LONG_DURATION := 100000.0

var _frame := 0
var _sub := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _wave: Node = null
var _threat: Node = null
var _game_time: Node = null

var _spawner: Node = null
var _world_stub: Node = null

## SCHEDULE phase에서 예상 wave_index.
var _schedule_wave_seq := 0


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
	print("TASK0242_RESULT=" + ("FAIL" if _failed else "PASS"))
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
		Phase.SCHEDULE:
			_schedule()
		Phase.THRESHOLD:
			_threshold()
		Phase.DELAY:
			_delay()
		Phase.REDUCE:
			_reduce()
		Phase.DUPLICATE:
			_duplicate()
		Phase.SPAWNER_CONNECT:
			_spawner_connect()
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0242_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
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
		_wait = 3
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_enter(Phase.SCHEDULE)


## -- SCHEDULE: schedule trigger + Threat 없는 간격 검증 --
func _schedule() -> void:
	if _sub == 0:
		_wave.base_wave_interval = 2
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.5
		_wave.wave_threshold_ratio = 1.0
		_wave.reset()
		_threat.reset()
		# DAY 시작 → NIGHT 1
		_toggle_phase()
		_wait_frames(2)
		_check_wave_seq(1)
	elif _sub == 1:
		if not _waited():
			return
		_check(_wave.is_wave_night(), "schedule: NIGHT 1 is a wave night")
		_check(_wave.get_wave_index() == 1,
			"schedule: wave_index increments to 1 (%d)" % _wave.get_wave_index())
		# NIGHT 1 다음 간격은 ratio 0에서 base 2
		_check(_wave.get_nights_until_wave() == 2,
			"schedule: next wave in 2 nights at zero threat (%d)"
			% _wave.get_nights_until_wave())
		_toggle_phase()  # NIGHT 1 → DAY 2
		_toggle_phase()  # DAY 2 → NIGHT 2
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"schedule: NIGHT 2 is NOT a wave night")
		_check(_wave.get_wave_index() == 1,
			"schedule: no duplicate trigger on NIGHT 2 (%d)"
			% _wave.get_wave_index())
		_toggle_phase()  # NIGHT 2 → DAY 3
		_toggle_phase()  # DAY 3 → NIGHT 3
		_wait_frames(2)
		_sub = 3
	elif _sub == 3:
		if not _waited():
			return
		_check(_wave.is_wave_night(),
			"schedule: NIGHT 3 is a wave night again")
		_check(_wave.get_wave_index() == 2,
			"schedule: wave_index increments to 2 (%d)" % _wave.get_wave_index())
		_toggle_phase()  # NIGHT 3 → DAY 4 (초기화)
		_wait_frames(2)
		_sub = 4
	elif _sub == 4:
		if not _waited():
			return
		_enter(Phase.THRESHOLD)


func _check_wave_seq(expected: int) -> void:
	_schedule_wave_seq = expected


## -- THRESHOLD: threat ratio가 임계 이상이면 강제 wave --
func _threshold() -> void:
	if _sub == 0:
		_wave.base_wave_interval = 4
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.5
		_wave.wave_threshold_ratio = 0.5
		_wave.reset()
		_threat.reset()
		_toggle_phase()  # NIGHT 1
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		_check(_wave.is_wave_night(), "threshold: NIGHT 1 wave (schedule start)")
		_check(_wave.get_wave_index() == 1,
			"threshold: wave_index 1 on NIGHT 1 (%d)" % _wave.get_wave_index())
		# threat ratio 0.6으로 올려 임계(0.5) 초과. 다음 NIGHT은 강제 wave여야 한다.
		_threat.add(60.0)
		_check(_threat.get_ratio() >= 0.5,
			"threshold: threat ratio raised above threshold (%.2f)" % _threat.get_ratio())
		_toggle_phase()  # NIGHT 1 → DAY 2
		_toggle_phase()  # DAY 2 → NIGHT 2
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		_check(_wave.is_wave_night(),
			"threshold: NIGHT 2 forced wave despite schedule gap")
		_check(_wave.get_wave_index() == 2,
			"threshold: threshold trigger increments wave (2, %d)"
			% _wave.get_wave_index())
		_toggle_phase()  # NIGHT 2 → DAY 3
		_wait_frames(2)
		_sub = 3
	elif _sub == 3:
		if not _waited():
			return
		_enter(Phase.DELAY)


## -- DELAY: delay_wave()가 다음 wave timing을 뒤로 미는지 --
func _delay() -> void:
	if _sub == 0:
		_wave.base_wave_interval = 1
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
		_wave.max_delay_nights = 5
		_wave.reset()
		_threat.reset()
		_toggle_phase()  # NIGHT 1 (wave)
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		_check(_wave.get_wave_index() == 1,
			"delay: NIGHT 1 wave triggered (%d)" % _wave.get_wave_index())
		_check(_wave.get_nights_until_wave() == 1,
			"delay: base interval 1 means next wave in 1 night (%d)"
			% _wave.get_nights_until_wave())
		# DAY로 돌아온 뒤 delay 3 → 다음 wave 3 NIGHT 뒤로 밀린다.
		_toggle_phase()  # NIGHT 1 → DAY 2
		_wave.delay_wave(3)
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		_check(_wave.get_nights_until_wave() == 4,
			"delay: delay_wave(3) pushes next wave to 4 nights (1+3, %d)"
			% _wave.get_nights_until_wave())
		# NIGHT 2는 wave night가 아니어야 한다.
		_toggle_phase()  # DAY 2 → NIGHT 2
		_wait_frames(2)
		_sub = 3
	elif _sub == 3:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"delay: NIGHT 2 no wave after delay")
		_check(_wave.get_wave_index() == 1,
			"delay: no extra trigger on delayed NIGHT 2 (%d)"
			% _wave.get_wave_index())
		# 뒤로 밀린 wave가 실제로 돌아오는지: NIGHT 5에서 trigger.
		_toggle_phase()  # NIGHT 2 → DAY 3
		_toggle_phase()  # DAY 3 → NIGHT 3
		_toggle_phase()  # NIGHT 3 → DAY 4
		_toggle_phase()  # DAY 4 → NIGHT 4
		_wait_frames(2)
		_sub = 4
	elif _sub == 4:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"delay: NIGHT 4 still no wave (%d nights left)"
			% _wave.get_nights_until_wave())
		_toggle_phase()  # NIGHT 4 → DAY 5
		_toggle_phase()  # DAY 5 → NIGHT 5
		_wait_frames(2)
		_sub = 5
	elif _sub == 5:
		if not _waited():
			return
		_check(_wave.is_wave_night(),
			"delay: delayed wave finally triggers on NIGHT 5")
		_check(_wave.get_wave_index() == 2,
			"delay: delayed wave increments index (2, %d)" % _wave.get_wave_index())
		_toggle_phase()  # NIGHT 5 → DAY 6
		_wait_frames(2)
		_sub = 6
	elif _sub == 6:
		if not _waited():
			return
		_enter(Phase.REDUCE)


## -- REDUCE: reduce_threat()가 ratio를 낮춰 다음 wave timing을 바꾸는지 --
func _reduce() -> void:
	if _sub == 0:
		_wave.base_wave_interval = 4
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.5
		_wave.wave_threshold_ratio = 0.5
		_wave.reset()
		_threat.reset()
		# threat ratio 0.6 (임계 초과) 상태에서 NIGHT 1 강제 wave.
		_threat.add(60.0)
		_toggle_phase()  # NIGHT 1
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		_check(_wave.is_wave_night(), "reduce: NIGHT 1 forced wave")
		_check(_wave.get_wave_index() == 1,
			"reduce: wave_index 1 (%d)" % _wave.get_wave_index())
		# ratio 0.6에서 다음 간격: round(4*(1-0.6*0.5)) = round(2.8) = 3
		_check(_wave.get_nights_until_wave() == 3,
			"reduce: high threat shortens next interval to 3 nights (%d)"
			% _wave.get_nights_until_wave())
		_toggle_phase()  # NIGHT 1 → DAY 2
		# reduce 60 → ratio 0. 임계 해제 + 다음 간격이 base 4로 늘어난다.
		_wave.reduce_threat(60.0)
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		_check(is_equal_approx(_threat.get_ratio(), 0.0),
			"reduce: reduce_threat lowers ratio to 0 (%.2f)" % _threat.get_ratio())
		# NIGHT 2는 더 이상 강제 wave가 아니어야 한다.
		_toggle_phase()  # DAY 2 → NIGHT 2
		_wait_frames(2)
		_sub = 3
	elif _sub == 3:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"reduce: NIGHT 2 no forced wave after reduce")
		_check(_wave.get_wave_index() == 1,
			"reduce: no extra trigger after reduce (%d)" % _wave.get_wave_index())
		_toggle_phase()  # NIGHT 2 → DAY 3
		_wait_frames(2)
		_sub = 4
	elif _sub == 4:
		if not _waited():
			return
		_enter(Phase.DUPLICATE)


## -- DUPLICATE: 동일 NIGHT wave 처리는 정확히 1회 --
func _duplicate() -> void:
	if _sub == 0:
		_wave.base_wave_interval = 1
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
		_wave.reset()
		_threat.reset()
		# 동일 NIGHT(day 1)을 두 번 직접 처리해도 wave_index는 1회만 증가해야 한다.
		_wave._process_night(1)
		var first: int = _wave.get_wave_index()
		_wave._process_night(1)
		var second: int = _wave.get_wave_index()
		_check(first == 1 and second == 1,
			"duplicate: same NIGHT processed once (first=%d second=%d)" % [first, second])
		# 직접 호출 가드가 _last_processed_night를 소비했으므로 reset 후 정상 흐름 검증.
		_wave.reset()
		_wait_frames(2)
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_toggle_phase()  # DAY 1 → NIGHT 1
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		var n1: int = _wave.get_wave_index()
		_check(n1 == 1,
			"duplicate: GameTime NIGHT 1 adds exactly one wave (%d)" % n1)
		_toggle_phase()  # NIGHT 1 → DAY 2
		_toggle_phase()  # DAY 2 → NIGHT 2
		_wait_frames(2)
		_sub = 3
	elif _sub == 3:
		if not _waited():
			return
		var n2: int = _wave.get_wave_index()
		_check(n2 == 2,
			"duplicate: NIGHT 2 adds exactly one wave (%d)" % n2)
		_toggle_phase()  # NIGHT 2 → DAY 3
		_wait_frames(2)
		_sub = 4
	elif _sub == 4:
		if not _waited():
			return
		_enter(Phase.SPAWNER_CONNECT)


## -- SPAWNER_CONNECT: WaveManager gate에 따라 FirstEncounterSpawner3D spawn/비-spawn --
func _spawner_connect() -> void:
	if _sub == 0:
		if not _waited():
			return
		_wave.base_wave_interval = 2
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
		_wave.reset()
		_threat.reset()
		_world_stub = Node3D.new()
		_world_stub.name = "WorldStub"
		_world_stub.add_to_group("world3d")
		root.add_child(_world_stub)
		_spawner = load("res://scripts/first_encounter_spawner_3d.gd").new()
		_spawner.name = "FirstEncounterSpawner3D"
		root.add_child(_spawner)
		_spawner.set_count(1)
		_wait_frames(4)
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_check(_spawner != null and is_instance_valid(_spawner),
			"spawner: FirstEncounterSpawner3D instantiates")
		_toggle_phase()  # DAY 1 → NIGHT 1 (wave night)
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		_check(_spawner.is_night_active(),
			"spawner: spawns on wave NIGHT 1")
		_check(_spawner.get_enemy_count() == 1,
			"spawner: exactly 1 enemy spawned on wave night (%d)"
			% _spawner.get_enemy_count())
		_toggle_phase()  # NIGHT 1 → DAY 2 (despawn)
		_wait_frames(2)
		_sub = 3
	elif _sub == 3:
		if not _waited():
			return
		_check(not _spawner.is_night_active() and _spawner.get_enemy_count() == 0,
			"spawner: DAY despawns the encounter")
		_toggle_phase()  # DAY 2 → NIGHT 2 (NOT a wave night)
		_wait_frames(2)
		_sub = 4
	elif _sub == 4:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"spawner: NIGHT 2 is not a wave night")
		_check(not _spawner.is_night_active() and _spawner.get_enemy_count() == 0,
			"spawner: no spawn on non-wave NIGHT 2")
		_toggle_phase()  # NIGHT 2 → DAY 3
		_toggle_phase()  # DAY 3 → NIGHT 3 (wave night)
		_wait_frames(2)
		_sub = 5
	elif _sub == 5:
		if not _waited():
			return
		_check(_spawner.is_night_active(),
			"spawner: spawns again on wave NIGHT 3")
		_check(_spawner.get_enemy_count() == 1,
			"spawner: wave NIGHT 3 has exactly 1 enemy (%d)"
			% _spawner.get_enemy_count())
		# 정리
		_toggle_phase()  # NIGHT 3 → DAY 4
		_wait_frames(2)
		_sub = 6
	elif _sub == 6:
		if not _waited():
			return
		if is_instance_valid(_spawner):
			_spawner.free()
		if is_instance_valid(_world_stub):
			_world_stub.free()
		_wait_frames(2)
		_sub = 7
	elif _sub == 7:
		if not _waited():
			return
		_enter(Phase.DONE)