extends Node

## TASK-024-1 Threat State 전역 서비스 (autoload).
## Threat는 장기적인 Wave 압력을 표현하는 누적 게이지다. 현재 값(_current)은
## 0에서 max_threat 사이로 clamp되며, GameTime의 경과 시간(DAY/NIGHT 진행)에 비례해
## 성장한다. GameTime.advance()가 이미 전술 시간 배율(_time_scale)을 곱하므로
## Threat 성장도 동일하게 Pause(0) 중에는 멈추고 1x/2x에 따라 배율이 일치한다.
##
## 정확한 성장률(growth_per_second)과 상한(max_threat)은 아직 최종 밸런스가
## 아니므로 export로 조정 가능하게 두고 DESIGN_TUNING으로 표시한다.
##
## save/load 시스템은 아직 프로젝트에 없으므로 실제 persistence는 구현하지
## 않는다. 대신 향후 저장 확장을 위해 to_snapshot()/from_snapshot()을 제공한다.
## (요구사항: "save/load가 있으면 persistence" - 현재는 없음.)
##
## UI는 threat_changed 신호를 구독해 게이지를 그린다. (TASK-024-3에서 HUD 연결)

signal threat_changed(current: float, max_threat: float)

## 성장률: in-game 초당 증가량. 최종 밸런스 확정 전까지 조정용 export. (DESIGN_TUNING)
@export var growth_per_second := 0.5
## Threat 상한. (DESIGN_TUNING)
@export var max_threat := 100.0

var _current := 0.0
## 테스트에서 직접 제어할 때 성장을 끄는 플래그.
var _auto_grow := true

## GameTime의 in-game 경과 추적용 직전 스냅샷.
var _last_elapsed := 0.0
var _last_phase := -1
var _last_duration := 0.0


func _ready() -> void:
	GameTime.phase_changed.connect(_on_phase_changed)
	_last_phase = GameTime.get_phase()
	_last_elapsed = GameTime.get_phase_elapsed()
	_last_duration = GameTime.get_phase_duration()


## 매 프레임 GameTime의 in-game 경과 시간 변화만큼 Threat를 성장시킨다.
## GameTime.advance()가 시간 배율을 이미 반영하므로 Pause 중에는 delta가 0이어서
## 성장이 멈춘다. phase 전환(GameTime이 phase_elapsed를 리셋) 시에는 이전 phase의
## 남은 구간과 새 phase 진행분을 더해 연속 성장을 유지한다.
func _process(_delta: float) -> void:
	if not _auto_grow:
		return
	var elapsed := GameTime.get_phase_elapsed()
	var phase := GameTime.get_phase()
	var growth_seconds := 0.0
	if phase == _last_phase:
		growth_seconds = elapsed - _last_elapsed
	else:
		# 전환 직후: 이전 phase는 _last_elapsed에서 _last_duration까지 진행했고,
		# 새 phase는 0에서 elapsed까지 진행했다.
		growth_seconds = (_last_duration - _last_elapsed) + elapsed
	_last_elapsed = elapsed
	_last_phase = phase
	_last_duration = GameTime.get_phase_duration()
	if growth_seconds > 0.0:
		_add(growth_seconds * growth_per_second)


## 매 DAY 시작(새 날 진입) 시 기본 성장. GameTime이 DAY로 전환될 때 발행된다.
func _on_phase_changed(phase: int, _day_number: int) -> void:
	if phase == GameTime.Phase.DAY:
		_last_elapsed = GameTime.get_phase_elapsed()


func get_current() -> float:
	return _current


func get_max() -> float:
	return max_threat


## 0..1 진행률. HUD 게이지 비율용.
func get_ratio() -> float:
	if max_threat <= 0.0:
		return 0.0
	return clampf(_current / max_threat, 0.0, 1.0)


## 외부 증가(테스트/이벤트). clamp를 적용하고 변경 시 신호를 발행한다.
func add(amount: float) -> void:
	if amount <= 0.0:
		return
	_add(amount)


## 외부 감소(예: 향후 Dungeon clear). 0 미만으로 내려가지 않게 clamp한다.
func reduce(amount: float) -> void:
	if amount <= 0.0:
		return
	_current = maxf(0.0, _current - amount)
	threat_changed.emit(_current, max_threat)


## 성장 자동 적용 on/off. 테스트에서 직접 제어할 때 사용한다.
func set_auto_grow(enabled: bool) -> void:
	_auto_grow = enabled


## 자동 성장(시간 경과)이 켜져 있는지. HUD가 "다음 위험 증가 방향"(▲) 표시에 사용한다.
func is_auto_growing() -> bool:
	return _auto_grow


func reset() -> void:
	_current = 0.0
	threat_changed.emit(_current, max_threat)


## 향후 저장 확장용 순수 데이터 스냅샷. Node/Actor reference를 담지 않는다.
func to_snapshot() -> Dictionary:
	return {
		"current": _current,
		"max": max_threat,
	}


## 스냅샷 복원(향후 persistence용). 현재 저장 시스템이 없어 실제 사용처는 아직 없다.
func from_snapshot(snapshot: Dictionary) -> void:
	_current = clampf(float(snapshot.get("current", 0.0)), 0.0, max_threat)
	threat_changed.emit(_current, max_threat)


func _add(amount: float) -> void:
	if amount <= 0.0:
		return
	_current = clampf(_current + amount, 0.0, max_threat)
	threat_changed.emit(_current, max_threat)
