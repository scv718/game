extends SceneTree

## TASK-049-1 Asset / License Audit + Audio Bus 테스트.
##
## 요구사항 대응:
##   - 기존 audio/vfx asset 확인 → runtime 검증이 아닌 문서 항목. INTEGRATION_NOTE_AUDIO.md
##     존재 여부를 여기서 고정한다.
##   - 신규 asset 출처/라이선스 기록 → 위 문서 + default_bus_layout(코드 리소스).
##   - Bus: Master / Music / SFX / Ambient / UI → 버스 존재/순서/재생 라우팅 검증.
##   - volume setting hook → db/linear get/set + 일괄 설정 + reset + persist/restore.
##   - playback foundation → event-driven one-shot 재생 + 자동 해제 + 유지형 재생.
##
## 완료조건(bus/playback foundation PASS) 대응:
##   - AudioManager autoload 존재.
##   - 5버스 존재·순서 일치, default_bus_layout.tres 로드 가능.
##   - volume hook이 AudioServer 실제 버스에 반영.
##   - one-shot 재생이 finished 시 자동 해제(duplicate/freed emitter 없음).
##   - per-frame playback 없음은 이 계층에 폴링이 없다는 정적 사실로 문서에 기록.

enum Phase {
	SETUP, PLAYBACK_WAIT, PLAYBACK_CHECK, PLAYBACK_FREE_WAIT, PERSIST_WAIT, PERSIST_CHECK, DONE,
}

const EXPECTED_BUSES := ["Master", "Music", "SFX", "Ambient", "UI"]

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _audio: Node = null
var _one_shot: AudioStreamPlayer = null
var _loop: AudioStreamPlayer = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _make_silent_wav(seconds: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var bytes := 22050.0 * seconds
	wav.data = PackedByteArray()
	wav.data.resize(int(bytes) * 2)
	return wav


func _finish() -> void:
	if _audio != null and is_instance_valid(_audio):
		_audio.stop_all()
		_audio.reset_volumes()
		_audio.save_volumes()
	print("TASK0491_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.PLAYBACK_WAIT:
			_playback_wait()
		Phase.PLAYBACK_CHECK:
			_playback_check()
		Phase.PLAYBACK_FREE_WAIT:
			_playback_free_wait()
		Phase.PERSIST_WAIT:
			_persist_wait()
		Phase.PERSIST_CHECK:
			_persist_check()
		Phase.DONE:
			_finish()
			return true
	if _frame > 2000:
		print("TASK0491_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < 8:
		return
	_audio = root.get_node_or_null("AudioManager")
	_check(_audio != null, "AudioManager autoload available to the runtime")
	if _audio == null:
		_finish()
		return
	_audio.reset_volumes()

	_check_bus_foundation()
	_check_volume_hooks()
	_check_audit_doc()

	_one_shot = _audio.play_sfx(_make_silent_wav(0.2))
	_check(_one_shot != null, "play_sfx returns a player")
	if _one_shot != null:
		_check(String(_one_shot.bus) == "SFX", "one-shot plays on the SFX bus")
		_check(_one_shot.playing, "one-shot starts playing immediately (event-driven)")
	_check(_audio.get_active_playback_count() == 1,
		"one-shot is tracked as active playback (no per-frame spawn loop)")

	_loop = _audio.play_ambient(_make_silent_wav(5.0))
	_check(_loop != null, "play_ambient returns a persistent player")
	if _loop != null:
		_check(String(_loop.bus) == "Ambient", "ambient plays on the Ambient bus")
	_check(_audio.get_active_playback_count() == 2,
		"persistent loop is tracked separately from one-shots")
	_wait = 0
	_enter(Phase.PLAYBACK_WAIT)


func _check_bus_foundation() -> void:
	var layout := load("res://audio/default_bus_layout.tres")
	_check(layout != null and layout is AudioBusLayout,
		"audio/default_bus_layout.tres loads as AudioBusLayout")
	var buses: PackedStringArray = _audio.get_buses()
	_check(buses.size() >= EXPECTED_BUSES.size(),
		"at least 5 audio buses present (got %d)" % buses.size())
	for i in EXPECTED_BUSES.size():
		_check(buses.size() > i and buses[i] == EXPECTED_BUSES[i],
			"bus %d is '%s' (got '%s')" % [i, EXPECTED_BUSES[i],
			(buses[i] if buses.size() > i else "<missing>")])
	_check(_audio.bus_exists("Music") and _audio.bus_exists("SFX")
		and _audio.bus_exists("Ambient") and _audio.bus_exists("UI"),
		"all four non-master buses exist")
	_check(not _audio.bus_exists("NotABus"), "unknown bus is safely rejected")
	# set_bus_layout 경로 회귀: layout 리소스를 실제 AudioServer에 적용 가능해야 한다.
	if layout != null:
		AudioServer.set_bus_layout(layout)
		_check(AudioServer.get_bus_name(1) == &"Music",
			"default_bus_layout applies to AudioServer")


func _check_volume_hooks() -> void:
	_audio.reset_volumes()
	for bus_name in EXPECTED_BUSES:
		_check(is_equal_approx(_audio.get_volume_db(bus_name), 0.0),
			"'%s' defaults to 0 db" % bus_name)
	_check(is_equal_approx(_audio.get_volume_linear("Master"), 1.0),
		"master defaults to linear 1.0")
	_audio.set_volume_db("SFX", -12.0)
	_check(is_equal_approx(_audio.get_volume_db("SFX"), -12.0),
		"set_volume_db reflects on the SFX bus")
	_check(is_equal_approx(_audio.get_volume_linear("SFX"), db_to_linear(-12.0)),
		"linear getter matches db setter")
	_audio.set_volume_linear("UI", 0.5)
	_check(is_equal_approx(_audio.get_volume_linear("UI"), 0.5),
		"set_volume_linear reflects on the UI bus")
	_check(is_equal_approx(_audio.get_volume_db("UI"), linear_to_db(0.5)),
		"db getter matches linear setter")
	_audio.set_volume_db("Music", 99.0)
	_check(_audio.get_volume_db("Music") <= 0.0, "volume clamps to non-positive db")
	_audio.set_volumes({"SFX": -6.0, "Unknown": -3.0})
	_check(is_equal_approx(_audio.get_volume_db("SFX"), -6.0),
		"set_volumes batch applies known bus")
	_check(not is_equal_approx(_audio.get_volume_db("SFX"), -3.0),
		"set_volumes ignores unknown bus")
	_audio.reset_volumes()
	_check(is_equal_approx(_audio.get_volume_db("SFX"), 0.0),
		"reset_volumes restores defaults")


func _check_audit_doc() -> void:
	var doc := FileAccess.file_exists("res://auto_dev/INTEGRATION_NOTE_AUDIO.md")
	_check(doc, "audio/license audit document exists")
	var layout_doc := FileAccess.file_exists("res://audio/default_bus_layout.tres")
	_check(layout_doc, "bus layout manifest is a tracked project asset")


## -- PLAYBACK_WAIT: headless에서도 AudioStreamPlayer가 재생을 진행해
## 0.2초 무음 스트림이 자연 종료(finished)하면 one-shot player가 자동 해제된다.
func _playback_wait() -> void:
	_wait += 1
	if is_instance_valid(_one_shot) and _wait < 600:
		return
	_check(not is_instance_valid(_one_shot),
		"one-shot auto-releases on natural finished")
	_check(_audio.get_active_playback_count() == 1,
		"only the persistent loop stays active after the one-shot ends")
	_enter(Phase.PLAYBACK_CHECK)


func _playback_check() -> void:
	_audio.stop_loops()
	_check(_audio.get_active_playback_count() == 0,
		"stop_loops releases persistent playback")
	_wait = 0
	_enter(Phase.PLAYBACK_FREE_WAIT)


func _playback_free_wait() -> void:
	_wait += 1
	if _wait < 3:
		return
	_check(not is_instance_valid(_loop),
		"stopped loop leaves no orphan emitter behind")
	_enter(Phase.PERSIST_WAIT)


func _persist_wait() -> void:
	_wait += 1
	if _wait < 2:
		return
	_wait = 0
	_audio.set_volume_db("SFX", -6.0)
	_audio.save_volumes()
	_audio.reset_volumes()
	_check(is_equal_approx(_audio.get_volume_db("SFX"), 0.0),
		"reset clears the persisted value in memory")
	_enter(Phase.PERSIST_CHECK)


func _persist_check() -> void:
	_audio.load_volumes()
	_check(is_equal_approx(_audio.get_volume_db("SFX"), -6.0),
		"volume setting hook restores persisted value from user://")
	_enter(Phase.DONE)