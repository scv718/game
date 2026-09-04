extends Node

## TASK-049-1 Asset / License Audit + Audio Bus.
## 전역(autoload) AudioManager. Runtime 전체가 공유하는 최소 오디오 기반을 제공한다.
##
## - Bus foundation: Master / Music / SFX / Ambient / UI 다섯 버스를 보장한다.
##   project 설정 `audio/default_bus_layout.tres`(audio/default_bus_layout.tres)가
##   기본 레이아웃이며, 이 스크립트는 startup 시 누락된 버스를 idempotent하게
##   복구한다(설정 파일 누락/일부 누락에도 foundation이 깨지지 않게).
## - volume setting hook: 설정 화면/저장 시스템이 부를 수 있는 최소 API.
##   db(-80..0)와 linear(0..1) 두 표현을 제공하고 `user://audio_settings.cfg`로
##   최소 persist/restore를 지원한다. 게임 Save/Load 시스템(TASK-046)이 생기면
##   이 ConfigFile을 그 시스템으로 대체/흡수하면 된다.
## - playback foundation: event-driven one-shot 재생(SFX/UI)과 유지형 재생
##   (Music/Ambient)만 제공한다. per-frame playback 금지(태스크 TASK-049-2)는
##   이 계층이 아니라 호출 측 정책이므로 이 파일에는 per-frame 폴링이 없다.
##
## 이 autoload는 신규 audio 도메인 전용 진입점이다. 기존 게임 로직에는 연결하지
## 않는다(연결은 TASK-049-2 Gameplay SFX가 수행).

## 버스 순서 단일 소스. Master는 AudioServer가 항상 index 0으로 보장한다.
const BUS_ORDER := ["Master", "Music", "SFX", "Ambient", "UI"]

## volume setting hook의 기본 볼륨(db).
const DEFAULT_VOLUME_DB := 0.0

## linear volume slider의 하한(0.0은 완전 무음으로 해석).
const MIN_VOLUME_LINEAR := 0.0
const MAX_VOLUME_LINEAR := 1.0

## 최소 볼륨(db). 그 이하 linear는 무음으로 간주한다(-inf 대비 안전 처리).
const MIN_VOLUME_DB := -80.0

const SETTINGS_PATH := "user://audio_settings.cfg"
const SETTINGS_SECTION := "audio"

## volume_changed: set_volume_db()/set_volume_linear() 호출마다 emit.
signal volume_changed(bus_name: String, volume_db: float)

## one-shot(완료 시 자동 free) 재생 중인 player.
var _one_shots: Array[AudioStreamPlayer] = []
## 유지형(Music/Ambient) 재생 중인 player. stop_loops()/stop_all()로 해제.
var _loops: Array[AudioStreamPlayer] = []


func _ready() -> void:
	add_to_group("audio_manager")
	_ensure_buses()
	load_volumes()


## 버스 레이아웃 보장. default_bus_layout.tres가 정상 반영된 경우 아무것도
## 하지 않고, 누락 버스만 Master 다음 순서로 추가한다. 재호출해도 안전하다.
func _ensure_buses() -> void:
	if AudioServer.get_bus_name(0) != &"Master":
		AudioServer.set_bus_name(0, &"Master")
	var existing := {}
	for i in AudioServer.bus_count:
		existing[AudioServer.get_bus_name(i)] = true
	for bus_name in BUS_ORDER:
		if bus_name == "Master" or existing.has(bus_name):
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		existing[bus_name] = true


## -- 버스 조회 --

func get_bus_index(bus_name: String) -> int:
	for i in AudioServer.bus_count:
		if String(AudioServer.get_bus_name(i)) == bus_name:
			return i
	return -1


func bus_exists(bus_name: String) -> bool:
	return get_bus_index(bus_name) >= 0


func get_buses() -> PackedStringArray:
	var out := PackedStringArray()
	for i in AudioServer.bus_count:
		out.append(String(AudioServer.get_bus_name(i)))
	return out


## -- volume setting hook --

func get_volume_db(bus_name: String) -> float:
	var idx := get_bus_index(bus_name)
	if idx < 0:
		push_error("AudioManager: unknown bus '%s'" % bus_name)
		return NAN
	return AudioServer.get_bus_volume_db(idx)


func set_volume_db(bus_name: String, volume_db: float) -> void:
	var idx := get_bus_index(bus_name)
	if idx < 0:
		push_error("AudioManager: unknown bus '%s'" % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, clampf(volume_db, MIN_VOLUME_DB, 0.0))
	volume_changed.emit(bus_name, volume_db)


## linear(0..1) volume setting hook. 0 = 무음, 1 = 0db.
func get_volume_linear(bus_name: String) -> float:
	var db := get_volume_db(bus_name)
	if is_nan(db):
		return NAN
	return db_to_linear(db)


func set_volume_linear(bus_name: String, linear: float) -> void:
	set_volume_db(bus_name, linear_to_db(clampf(linear, MIN_VOLUME_LINEAR, MAX_VOLUME_LINEAR)))


## 일괄 설정(설정 화면/저장 시스템용). 알려진 버스만 반영하고 미지 버스는 무시한다.
func set_volumes(volumes: Dictionary) -> void:
	for bus_name in volumes:
		if bus_exists(String(bus_name)):
			set_volume_db(String(bus_name), float(volumes[bus_name]))


func get_volumes() -> Dictionary:
	var out := {}
	for bus_name in BUS_ORDER:
		out[bus_name] = get_volume_db(bus_name)
	return out


func reset_volumes() -> void:
	for bus_name in BUS_ORDER:
		set_volume_db(bus_name, DEFAULT_VOLUME_DB)


func save_volumes() -> void:
	var cfg := ConfigFile.new()
	for bus_name in BUS_ORDER:
		cfg.set_value(SETTINGS_SECTION, bus_name, get_volume_db(bus_name))
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("AudioManager: failed to save volume settings (%s)" % error_string(err))


func load_volumes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for bus_name in BUS_ORDER:
		if cfg.has_section_key(SETTINGS_SECTION, bus_name):
			set_volume_db(bus_name, float(cfg.get_value(SETTINGS_SECTION, bus_name)))


## -- playback foundation --

## 이벤트 기반 재생의 단일 진입점. 버스가 없으면 Master로 폴백하고 오류를
## 기록한다(오류 은폐 금지, 큐 운영 규칙 준수). one_shot=true면 재생 완료 시
## player가 자동으로 해제된다. 반환된 player는 호출 측이 volume/pitch를
## 사전 설정하고 finished 연결에 쓸 수 있다.
func play_on_bus(
	bus_name: String,
	stream: AudioStream,
	volume_db := 0.0,
	pitch_scale := 1.0,
	one_shot := true
) -> AudioStreamPlayer:
	var idx := get_bus_index(bus_name)
	if idx < 0:
		push_error("AudioManager: cannot play on unknown bus '%s'" % bus_name)
		idx = 0
	if stream == null:
		push_error("AudioManager: cannot play a null stream on '%s'" % bus_name)
		return null
	var player := AudioStreamPlayer.new()
	player.name = "Playback_%s_%d" % [bus_name, _one_shots.size() + _loops.size()]
	player.stream = stream
	player.bus = AudioServer.get_bus_name(idx)
	player.volume_db = clampf(volume_db, MIN_VOLUME_DB, 0.0)
	player.pitch_scale = pitch_scale
	add_child(player)
	if one_shot:
		_one_shots.append(player)
		player.finished.connect(_on_one_shot_finished.bind(player))
	else:
		_loops.append(player)
	player.play()
	return player


func play_sfx(stream: AudioStream, volume_db := 0.0, pitch_scale := 1.0) -> AudioStreamPlayer:
	return play_on_bus("SFX", stream, volume_db, pitch_scale, true)


func play_ui(stream: AudioStream, volume_db := 0.0, pitch_scale := 1.0) -> AudioStreamPlayer:
	return play_on_bus("UI", stream, volume_db, pitch_scale, true)


## 유지형 재생(Music/Ambient). 반환 player를 보관하고 stop_loops()/stop_all()로
## 해제한다. one-shot이 아니므로 finished 시 자동 해제되지 않는다.
func play_music(stream: AudioStream, volume_db := 0.0) -> AudioStreamPlayer:
	return play_on_bus("Music", stream, volume_db, 1.0, false)


func play_ambient(stream: AudioStream, volume_db := 0.0) -> AudioStreamPlayer:
	return play_on_bus("Ambient", stream, volume_db, 1.0, false)


func stop_loops() -> void:
	for player in _loops:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_loops.clear()


func stop_one_shots() -> void:
	for player in _one_shots:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_one_shots.clear()


func stop_all() -> void:
	stop_loops()
	stop_one_shots()


## 활성 재생 개수(진단/테스트용).
func get_active_playback_count() -> int:
	return _one_shots.size() + _loops.size()


func _on_one_shot_finished(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player):
		_one_shots.erase(player)
		return
	player.finished.disconnect(_on_one_shot_finished.bind(player))
	_one_shots.erase(player)
	player.queue_free()