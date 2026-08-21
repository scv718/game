extends Node

## TASK-010-1 최소 Day/Night 시간 상태 기반.
## 전역(autoload)에서 조회 가능한 DAY/NIGHT phase와 day number를 관리한다.
## 낮 직접 운영 ↔ 밤 지휘 모드의 시간 기반이 되는 최소 상태만 제공하며,
## 전투/적/용병 등 실제 게임 기능은 포함하지 않는다.
##
## 프로토타입 시간값(day_duration/night_duration)은 export로 조정 가능하며
## 게임 설계의 최종 밸런스가 아니다. 자동 테스트에서는 매우 짧은 duration 또는
## set_auto_advance(false) + advance() 직접 호출로 시간을 빠르게 진행할 수 있다.

enum Phase {
	DAY,
	NIGHT,
}

## TASK-015-6 전술 시간 배율 상수. Pause=0, 1x=1.0, 2x=2.0.
const TIME_SCALE_PAUSE := 0.0
const TIME_SCALE_1X := 1.0
const TIME_SCALE_2X := 2.0

signal phase_changed(phase: Phase, day_number: int)

@export var day_duration := 60.0
@export var night_duration := 30.0

var _day_number := 1
var _phase: Phase = Phase.DAY
var _elapsed := 0.0
var _auto_advance := true
var _transitioning := false
## TASK-015-6: 전술 시간 배율. Pause=0 / 1x / 2x. advance()에 곱해 적용되며
## DAY phase에 진입하면 항상 1x로 복원된다.
var _time_scale := TIME_SCALE_1X


func _process(delta: float) -> void:
	if _auto_advance:
		advance(delta)


func get_day_number() -> int:
	return _day_number


func get_phase() -> Phase:
	return _phase


func get_phase_name() -> String:
	return "DAY" if _phase == Phase.DAY else "NIGHT"


func get_phase_elapsed() -> float:
	return _elapsed


func get_phase_duration() -> float:
	if _phase == Phase.DAY:
		return day_duration
	return night_duration


func get_phase_progress() -> float:
	var duration := get_phase_duration()
	if duration <= 0.0:
		return 1.0
	return clampf(_elapsed / duration, 0.0, 1.0)


## 시간을 주어진 초만큼 진행한다. phase 경계를 넘으면 전환하고 phase_changed를
## 정확히 전환 횟수만큼 발행한다. 재진입 시(시그널 핸들러가 advance 호출) 무시해
## 중복 전환/중복 시그널을 방지한다.
## TASK-015-6: 전술 시간 배율(_time_scale)을 경과 시간에 곱해 적용한다.
## Pause(0)면 아무것도 진행되지 않고, 2x면 2배로 진행된다. DAY phase에 진입하면
## 전술 시간을 1x로 복원한다.
func advance(seconds: float) -> void:
	if seconds <= 0.0 or _transitioning:
		return
	_elapsed += seconds * _time_scale
	var duration := get_phase_duration()
	if _elapsed < duration:
		return
	_transitioning = true
	while _elapsed >= duration:
		_elapsed -= duration
		if _phase == Phase.DAY:
			_phase = Phase.NIGHT
		else:
			_phase = Phase.DAY
			_day_number += 1
			_time_scale = TIME_SCALE_1X
		phase_changed.emit(_phase, _day_number)
		duration = get_phase_duration()
	_transitioning = false


## TASK-015-6: 전술 시간 배율을 설정한다. Pause=0 / 1x=1.0 / 2x=2.0.
## SceneTree.paused를 사용하지 않으므로 Pause 중에도 UI 입력(명령 버튼)이
## 그대로 동작한다. DAY 진입 시 1x 복원은 advance()가 처리한다.
func set_time_scale(scale: float) -> void:
	_time_scale = clampf(scale, TIME_SCALE_PAUSE, TIME_SCALE_2X)


func get_time_scale() -> float:
	return _time_scale


func set_durations(day: float, night: float) -> void:
	day_duration = day
	night_duration = night


func set_auto_advance(enabled: bool) -> void:
	_auto_advance = enabled