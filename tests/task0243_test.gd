extends SceneTree

## TASK-024-3 Threat HUD 자동 검증.
## HUD(ui/hud.tscn)의 Threat 게이지 / 증가 방향 / 다음 wave countdown을 검증한다.
##   - gauge: ThreatSystem ratio가 ThreatGauge/ThreatLabel에 그대로 반영된다.
##   - 방향: 시간 경과 성장 중(▲), 상한 도달(!), Pause/auto_grow off(빈 칸).
##   - countdown: WaveLabel이 WaveManager.get_nights_until_wave() 기반으로 실제
##     schedule과 일치한다(DAY/NIGHT 전환 각 지점에서 state와 라벨이 일치).
##   - threshold: ratio가 wave_threshold_ratio 이상이면 schedule countdown 대신
##     "WAVE NEXT NIGHT" 임박 표시가 우선되고, 실제로 그 NIGHT에 wave가 trigger된다.
##   - reduce: reduce_threat()로 ratio가 낮아지면 임박 표시가 countdown으로 복귀한다.
##   - DAY/NIGHT 유지: phase 전환 후에도 HUD 시그널 연결이 살아 있어 갱신된다.
## autoload 전역 식별자는 -s 스탠드얼론에서 미등록이므로 root.get_node_or_null로 조회한다.

enum Phase {
	SETUP,
	GAUGE,
	DIRECTION,
	COUNTDOWN,
	THRESHOLD,
	REDUCE,
	KEEP,
	DONE,
}

const LONG_DURATION := 100000.0

var _frame := 0
var _sub := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP

var _game_time: Node = null
var _threat: Node = null
var _wave: Node = null
var _hud: Node = null
var _threat_gauge: ProgressBar = null
var _threat_label: Label = null
var _threat_direction_label: Label = null
var _wave_label: Label = null


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


## DAY라면 NIGHT로, NIGHT라면 DAY로 한 번 전환한다.
func _toggle_phase() -> void:
	if _game_time.get_phase() == GameTime.Phase.DAY:
		_game_time.advance(_game_time.day_duration)
	else:
		_game_time.advance(_game_time.night_duration)


## WaveLabel이 현재 WaveManager/ThreatSystem state에서 기대되는 텍스트와 일치하는지.
func _expected_wave_text() -> String:
	var phase: int = _game_time.get_phase()
	var nights: int = _wave.get_nights_until_wave()
	var forced: bool = _threat.get_ratio() >= _wave.wave_threshold_ratio
	if phase == GameTime.Phase.NIGHT and _wave.is_wave_night():
		return "WAVE NOW"
	if forced or nights <= 0:
		return "WAVE NEXT NIGHT"
	if nights == 1:
		return "Wave in 1 night"
	return "Wave in %d nights" % nights


func _check_wave_label(msg: String) -> void:
	var expected := _expected_wave_text()
	_check(_wave_label.text == expected,
		"%s (got '%s', expected '%s')" % [msg, _wave_label.text, expected])


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
		_game_time.set_time_scale(1.0)
	if _hud != null and is_instance_valid(_hud):
		_hud.free()
	print("TASK0243_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.GAUGE:
			_gauge()
		Phase.DIRECTION:
			_direction()
		Phase.COUNTDOWN:
			_countdown()
		Phase.THRESHOLD:
			_threshold()
		Phase.REDUCE:
			_reduce()
		Phase.KEEP:
			_keep()
		Phase.DONE:
			_finish()
			return true
	if _frame > 20000:
		print("TASK0243_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _initialize() -> void:
	pass


## -- SETUP: autoload 조회 + HUD 인스턴스화 --
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
		_game_time.set_durations(LONG_DURATION, LONG_DURATION)
		_game_time.set_time_scale(1.0)
		_threat.set_auto_grow(true)
		_threat.max_threat = 100.0
		_threat.reset()
		_wave.reset()
		var hud_scene: PackedScene = load("res://ui/hud.tscn")
		_check(hud_scene != null, "hud.tscn loads")
		if hud_scene == null:
			_finish()
			return
		_hud = hud_scene.instantiate()
		_hud.name = "HUD"
		root.add_child(_hud)
		_wait = 3
		_sub = 1
		return
	if _sub == 1:
		if not _waited():
			return
		_threat_gauge = _hud.get_node_or_null("%ThreatGauge") as ProgressBar
		_threat_label = _hud.get_node_or_null("%ThreatLabel") as Label
		_threat_direction_label = _hud.get_node_or_null("%ThreatDirectionLabel") as Label
		_wave_label = _hud.get_node_or_null("%WaveLabel") as Label
		_check(_threat_gauge != null, "HUD has ThreatGauge")
		_check(_threat_label != null, "HUD has ThreatLabel")
		_check(_threat_direction_label != null, "HUD has ThreatDirectionLabel")
		_check(_wave_label != null, "HUD has WaveLabel")
		_check(_hud.get_node_or_null("StatusPanel") != null, "HUD StatusPanel intact")
		if _threat_gauge == null or _threat_label == null \
				or _threat_direction_label == null or _wave_label == null:
			_finish()
			return
		_check(is_equal_approx(_threat_gauge.value, 0.0),
			"gauge starts at 0 (%.1f)" % _threat_gauge.value)
		_check(_threat_label.text == "Threat 0%",
			"label starts at 0%% (got '%s')" % _threat_label.text)
		_check(_threat_direction_label.text == "▲",
			"direction shows ▲ while growing (got '%s')" % _threat_direction_label.text)
		_enter(Phase.GAUGE)


## -- GAUGE: threat 증가가 게이지/라벨에 즉시 반영 --
func _gauge() -> void:
	if _sub == 0:
		_threat.add(30.0)
		_check(is_equal_approx(_threat_gauge.value, 30.0),
			"gauge reflects threat current (%.1f)" % _threat_gauge.value)
		_check(_threat_label.text == "Threat 30%",
			"label reflects threat (got '%s')" % _threat_label.text)
		_sub = 1
		return
	if _sub == 1:
		_enter(Phase.DIRECTION)


## -- DIRECTION: 성장/상한/Pause/auto_grow off에 따른 방향 표시 --
func _direction() -> void:
	if _sub == 0:
		_game_time.set_time_scale(0.0)
		_hud._refresh_threat()
		_check(_threat_direction_label.text == "",
			"direction hides while paused (got '%s')" % _threat_direction_label.text)
		_game_time.set_time_scale(1.0)
		_hud._refresh_threat()
		_check(_threat_direction_label.text == "▲",
			"direction ▲ again after resume (got '%s')" % _threat_direction_label.text)
		_threat.set_auto_grow(false)
		_hud._refresh_threat()
		_check(_threat_direction_label.text == "",
			"direction hides when auto_grow off (got '%s')" % _threat_direction_label.text)
		_threat.add(70.0)
		_check(is_equal_approx(_threat.get_ratio(), 1.0),
			"threat reached max before peak check (%.2f)" % _threat.get_ratio())
		_hud._refresh_threat()
		_check(_threat_direction_label.text == "!",
			"direction shows ! at max threat (got '%s')" % _threat_direction_label.text)
		_threat.reset()
		_threat.set_auto_grow(true)
		_threat.max_threat = 100.0
		_enter(Phase.COUNTDOWN)


## -- COUNTDOWN: WaveLabel이 실제 schedule과 일치 (DAY/NIGHT 전환 추적) --
func _countdown() -> void:
	if _sub == 0:
		_threat.set_auto_grow(false)
		_wave.base_wave_interval = 2
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.5
		_wave.wave_threshold_ratio = 1.0
		_wave.reset()
		_threat.reset()
		_check_wave_label("countdown: DAY 1 initial (first night is wave)")
		_toggle_phase()  # DAY 1 → NIGHT 1 (wave)
		_check(_wave.is_wave_night(), "countdown: NIGHT 1 is a wave night")
		_check_wave_label("countdown: NIGHT 1 wave in progress")
		_toggle_phase()  # NIGHT 1 → DAY 2
		_check_wave_label("countdown: DAY 2 shows reset interval (2 nights)")
		_toggle_phase()  # DAY 2 → NIGHT 2 (not wave)
		_check(not _wave.is_wave_night(), "countdown: NIGHT 2 is NOT a wave night")
		_check_wave_label("countdown: NIGHT 2 shows 1 night left")
		_toggle_phase()  # NIGHT 2 → DAY 3
		_check_wave_label("countdown: DAY 3 keeps 1 night left")
		_toggle_phase()  # DAY 3 → NIGHT 3 (wave)
		_check(_wave.is_wave_night(), "countdown: NIGHT 3 is a wave night again")
		_check_wave_label("countdown: NIGHT 3 wave in progress")
		_toggle_phase()  # NIGHT 3 → DAY 4
		_sub = 1
		return
	if _sub == 1:
		_enter(Phase.THRESHOLD)


## -- THRESHOLD: threshold 강제 wave가 HUD 임박 표시와 실제 trigger 모두 일치 --
func _threshold() -> void:
	if _sub == 0:
		_wave.base_wave_interval = 4
		_wave.min_wave_interval = 1
		_wave.threat_schedule_factor = 0.5
		_wave.wave_threshold_ratio = 0.5
		_wave.reset()
		_threat.reset()
		_toggle_phase()  # DAY 1 → NIGHT 1 (wave, schedule start)
		_check(_wave.is_wave_night(), "threshold: NIGHT 1 wave (schedule start)")
		_check_wave_label("threshold: NIGHT 1 wave in progress")
		_toggle_phase()  # NIGHT 1 → DAY 2
		_check_wave_label("threshold: DAY 2 scheduled countdown (4 nights)")
		_threat.add(60.0)
		_check(_threat.get_ratio() >= 0.5,
			"threshold: ratio raised above threshold (%.2f)" % _threat.get_ratio())
		_check_wave_label("threshold: forced display overrides countdown")
		_toggle_phase()  # DAY 2 → NIGHT 2 (forced wave)
		_check(_wave.is_wave_night(), "threshold: NIGHT 2 forced wave despite schedule")
		_check_wave_label("threshold: NIGHT 2 wave in progress")
		_toggle_phase()  # NIGHT 2 → DAY 3
		_sub = 1
		return
	if _sub == 1:
		_enter(Phase.REDUCE)


## -- REDUCE: reduce_threat() 후 임박 표시가 countdown으로 복귀 --
func _reduce() -> void:
	if _sub == 0:
		_check_wave_label("reduce: still forced on DAY 3")
		_wave.reduce_threat(60.0)
		_check(is_equal_approx(_threat.get_ratio(), 0.0),
			"reduce: ratio back to 0 (%.2f)" % _threat.get_ratio())
		_check_wave_label("reduce: countdown restored after reduce")
		_toggle_phase()  # DAY 3 → NIGHT 3
		_check(not _wave.is_wave_night(), "reduce: NIGHT 3 no forced wave after reduce")
		_check_wave_label("reduce: NIGHT 3 shows remaining countdown")
		_toggle_phase()  # NIGHT 3 → DAY 4
		_sub = 1
		return
	if _sub == 1:
		_enter(Phase.KEEP)


## -- KEEP: DAY/NIGHT 전환 후에도 HUD 시그널 연결 유지 --
func _keep() -> void:
	if _sub == 0:
		var before: float = _threat_gauge.value
		_threat.add(10.0)
		_check(_threat_gauge.value > before,
			"gauge still updates after phase transitions (%.1f -> %.1f)"
			% [before, _threat_gauge.value])
		_toggle_phase()  # DAY 4 → NIGHT 4
		_check_wave_label("keep: HUD tracks schedule after long transitions")
		_enter(Phase.DONE)