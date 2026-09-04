extends SceneTree

## TASK-028-1 Threat API Audit / Contract 자동 검증.
## Dungeon clear(TASK-028-2)가 연결할 **authoritative API**를 고정한다.
##   - 현재 Threat owner: 기존 ThreatSystem(Wave)을 재사용한 WaveManager가 authoritative owner.
##     신규 ThreatManager를 만들지 않았다(기존 owner 재사용).
##   - increase API: WaveManager.add_threat / ThreatSystem.add.
##   - reduce API: WaveManager.reduce_threat -> ThreatSystem.reduce 재사용.
##   - delay API: WaveManager.delay_wave.
##   - Wave schedule 연결: WaveManager.is_wave_night()가 기존 NIGHT enemy spawn
##     (FirstEncounterSpawner3D)을 gate한다.
##   - HUD signal: threat_changed / schedule_changed / wave_triggered 발행.
##   - duplicate application guard: apply_dungeon_clear는 run당 1회, 동일 run_id 중복 호출은 무시.
##   - config + DESIGN_TUNING: dungeon_clear_reduce_amount / dungeon_clear_delay_nights는
##     export config로 분리(감소량/지연량만 미정).
## autoload 전역 식별자는 -s 스탠드얼론에서 미등록이므로 root.get_node_or_null로 조회한다.

enum Phase {
	SETUP,
	OWNER,
	INCREASE,
	REDUCE,
	DELAY,
	SIGNAL,
	DUPLICATE_GUARD,
	SPAWNER_GATE,
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

var _spawner: Node = null
var _world_stub: Node = null

var _signal_counts := {
	"threat_changed": 0,
	"schedule_changed": 0,
	"wave_triggered": 0,
}


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
	print("TASK0281_RESULT=" + ("FAIL" if _failed else "PASS"))
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
		Phase.OWNER:
			_owner()
		Phase.INCREASE:
			_increase()
		Phase.REDUCE:
			_reduce()
		Phase.DELAY:
			_delay()
		Phase.SIGNAL:
			_signal()
		Phase.DUPLICATE_GUARD:
			_duplicate_guard()
		Phase.SPAWNER_GATE:
			_spawner_gate()
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0281_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
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
		_wave.base_wave_interval = 1
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
		_wave.dungeon_clear_reduce_amount = 25.0
		_wave.dungeon_clear_delay_nights = 1
		_wait = 3
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_enter(Phase.OWNER)


## -- OWNER: WaveManager가 authoritative owner이며 신규 ThreatManager를 만들지 않았다 --
func _owner() -> void:
	if _sub == 0:
		_check(_wave.has_method("add_threat"), "owner: WaveManager has increase API (add_threat)")
		_check(_wave.has_method("reduce_threat"), "owner: WaveManager has reduce API (reduce_threat)")
		_check(_wave.has_method("delay_wave"), "owner: WaveManager has delay API (delay_wave)")
		_check(_wave.has_method("is_wave_night"), "owner: WaveManager owns wave schedule (is_wave_night)")
		_check(_wave.has_method("get_ratio"), "owner: WaveManager delegates threat ratio (get_ratio)")
		_check(root.get_node_or_null("ThreatManager") == null,
			"owner: no duplicate ThreatManager autoload created")
		_check(_wave.get("dungeon_clear_reduce_amount") != null,
			"owner: dungeon_clear_reduce_amount is config")
		_check(_wave.get("dungeon_clear_delay_nights") != null,
			"owner: dungeon_clear_delay_nights is config")
		_enter(Phase.INCREASE)


## -- INCREASE: add_threat가 Threat를 증가시키고 schedule_changed를 발행한다 --
func _increase() -> void:
	if _sub == 0:
		_threat.reset()
		_wave.reset()
		_wave.add_threat(30.0)
		_check(is_equal_approx(_threat.get_current(), 30.0),
			"increase: add_threat raises threat (%.2f)" % _threat.get_current())
		_check(_wave.get_ratio() > 0.0,
			"increase: get_ratio reflects raised threat (%.2f)" % _wave.get_ratio())
		_enter(Phase.REDUCE)


## -- REDUCE: reduce_threat가 ThreatSystem.reduce를 재사용해 실제 감소한다 --
func _reduce() -> void:
	if _sub == 0:
		_threat.reset()
		_wave.reset()
		_wave.add_threat(60.0)
		_check(is_equal_approx(_threat.get_current(), 60.0),
			"reduce: threat raised to 60 (%.2f)" % _threat.get_current())
		_wave.reduce_threat(25.0)
		_check(is_equal_approx(_threat.get_current(), 35.0),
			"reduce: reduce_threat delegates to ThreatSystem.reduce (%.2f)"
			% _threat.get_current())
		_wave.reduce_threat(999.0)
		_check(_threat.get_current() == 0.0,
			"reduce: reduce clamps at 0 (%.2f)" % _threat.get_current())
		_enter(Phase.DELAY)


## -- DELAY: delay_wave가 다음 wave timing을 실제로 뒤로 미룬다 --
func _delay() -> void:
	if _sub == 0:
		_wave.base_wave_interval = 1
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
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
			"delay: base interval 1 -> next wave in 1 night (%d)"
			% _wave.get_nights_until_wave())
		_toggle_phase()  # NIGHT 1 -> DAY 2
		_wave.delay_wave(2)
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		_check(_wave.get_nights_until_wave() == 3,
			"delay: delay_wave(2) pushes next wave to 3 nights (1+2, %d)"
			% _wave.get_nights_until_wave())
		_toggle_phase()  # DAY 2 -> NIGHT 2
		_wait_frames(2)
		_sub = 3
	elif _sub == 3:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"delay: NIGHT 2 no wave after delay")
		_toggle_phase()  # NIGHT 2 -> DAY 3
		_wait_frames(2)
		_sub = 4
	elif _sub == 4:
		if not _waited():
			return
		_enter(Phase.SIGNAL)


## -- SIGNAL: HUD가 구독하는 신호가 실제 발행된다 --
func _signal() -> void:
	if _sub == 0:
		_signal_counts["threat_changed"] = 0
		_signal_counts["schedule_changed"] = 0
		_signal_counts["wave_triggered"] = 0
		_threat.threat_changed.connect(_on_threat_changed)
		_wave.schedule_changed.connect(_on_wave_schedule_changed)
		_wave.wave_triggered.connect(_on_wave_triggered)
		_threat.reset()
		_wave.reset()
		_wave.add_threat(10.0)
		_check(_signal_counts["threat_changed"] >= 1,
			"signal: add_threat emits threat_changed (%d)" % _signal_counts["threat_changed"])
		_check(_signal_counts["schedule_changed"] >= 1,
			"signal: add_threat emits schedule_changed (%d)" % _signal_counts["schedule_changed"])
		_toggle_phase()  # DAY -> NIGHT 1 (wave trigger)
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		_check(_signal_counts["wave_triggered"] >= 1,
			"signal: wave night emits wave_triggered (%d)" % _signal_counts["wave_triggered"])
		_toggle_phase()  # NIGHT 1 -> DAY 2
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		_threat.threat_changed.disconnect(_on_threat_changed)
		_wave.schedule_changed.disconnect(_on_wave_schedule_changed)
		_wave.wave_triggered.disconnect(_on_wave_triggered)
		_enter(Phase.DUPLICATE_GUARD)


## -- DUPLICATE_GUARD: apply_dungeon_clear는 run당 정확히 1회, 동일 run_id 중복 무시 --
func _duplicate_guard() -> void:
	if _sub == 0:
		_wave.reset()
		_threat.reset()
		_wave.dungeon_clear_reduce_amount = 25.0
		_wave.dungeon_clear_delay_nights = 1
		_wave.base_wave_interval = 1
		_wave.wave_threshold_ratio = 1.0
		_wave.threat_schedule_factor = 0.0
		_wave.add_threat(60.0)
		_toggle_phase()  # NIGHT 1 (wave trigger -> next in 1)
		_wait_frames(2)
		_sub = 1
	elif _sub == 1:
		if not _waited():
			return
		_toggle_phase()  # NIGHT 1 -> DAY 2
		_wait_frames(2)
		_sub = 2
	elif _sub == 2:
		if not _waited():
			return
		var nights_before: int = _wave.get_nights_until_wave()
		var current_before: float = _threat.get_current()
		# empty id는 no-op이어야 한다.
		_wave.apply_dungeon_clear("")
		_check(not _wave.is_dungeon_clear_applied(""),
			"guard: empty run id is not marked applied")
		# 첫 적용: reduce + delay가 실제로 반영된다.
		_wave.apply_dungeon_clear("dungeon_run_1")
		_check(_wave.is_dungeon_clear_applied("dungeon_run_1"),
			"guard: first clear marks run applied")
		_check(_threat.get_current() < current_before,
			"guard: first clear reduces threat (%.2f -> %.2f)"
			% [current_before, _threat.get_current()])
		_check(_wave.get_nights_until_wave() > nights_before,
			"guard: first clear delays next wave (%d -> %d)"
			% [nights_before, _wave.get_nights_until_wave()])
		# 동일 run_id 재호출: 감소/지연이 또 적용되면 안 된다.
		var current_after: float = _threat.get_current()
		var nights_after: int = _wave.get_nights_until_wave()
		_wave.apply_dungeon_clear("dungeon_run_1")
		_check(is_equal_approx(_threat.get_current(), current_after),
			"guard: duplicate clear does not reduce again (%.2f)" % _threat.get_current())
		_check(_wave.get_nights_until_wave() == nights_after,
			"guard: duplicate clear does not delay again (%d)" % _wave.get_nights_until_wave())
		_sub = 3
	elif _sub == 3:
		_enter(Phase.SPAWNER_GATE)


## -- SPAWNER_GATE: WaveManager.is_wave_night()가 FirstEncounterSpawner3D를 gate한다 --
func _spawner_gate() -> void:
	if _sub == 0:
		if not _waited():
			return
		_wave.reset()
		_threat.reset()
		_wave.base_wave_interval = 2
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.0
		_wave.wave_threshold_ratio = 1.0
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
		_toggle_phase()  # DAY 1 -> NIGHT 1 (wave night)
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
		_toggle_phase()  # NIGHT 1 -> DAY 2 (despawn)
		_wait_frames(2)
		_sub = 3
	elif _sub == 3:
		if not _waited():
			return
		_check(not _spawner.is_night_active() and _spawner.get_enemy_count() == 0,
			"spawner: DAY despawns the encounter")
		_toggle_phase()  # DAY 2 -> NIGHT 2 (NOT a wave night)
		_wait_frames(2)
		_sub = 4
	elif _sub == 4:
		if not _waited():
			return
		_check(not _wave.is_wave_night(),
			"spawner: NIGHT 2 is not a wave night")
		_check(not _spawner.is_night_active() and _spawner.get_enemy_count() == 0,
			"spawner: no spawn on non-wave NIGHT 2")
		_toggle_phase()  # NIGHT 2 -> DAY 3
		_wait_frames(2)
		_sub = 5
	elif _sub == 5:
		if not _waited():
			return
		if is_instance_valid(_spawner):
			_spawner.free()
		if is_instance_valid(_world_stub):
			_world_stub.free()
		_wait_frames(2)
		_sub = 6
	elif _sub == 6:
		if not _waited():
			return
		_enter(Phase.DONE)


func _on_threat_changed(_current: float, _max: float) -> void:
	_signal_counts["threat_changed"] += 1


func _on_wave_schedule_changed(_nights: int, _index: int) -> void:
	_signal_counts["schedule_changed"] += 1


func _on_wave_triggered(_index: int, _night: int) -> void:
	_signal_counts["wave_triggered"] += 1
