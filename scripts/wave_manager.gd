extends Node

## TASK-024-2 Wave Trigger / Delay Contract 전역 서비스 (autoload).
## Threat(ThreatSystem)와 기존 NIGHT enemy spawn(FirstEncounterSpawner3D) 사이에서
## Wave가 "언제 일어나는지"를 결정하는 스케줄 계층이다.
##
## 핵심 계약:
##   - Wave schedule: NIGHT 단위 countdown(_nights_until_wave)으로 다음 wave를 예약한다.
##     0 이하가 되면 해당 NIGHT은 wave night다. (기본 base_wave_interval=1 이면 매 NIGHT wave)
##   - schedule trigger: countdown이 0에 도달하면 wave가 trigger된다.
##   - threshold trigger: threat ratio가 wave_threshold_ratio 이상이면 해당 NIGHT을
##     강제 wave로 당긴다(스케줄과 무관).
##   - Threat 영향(최소 규칙): threat ratio가 높을수록 다음 wave 간격이
##     min_wave_interval까지 줄어든다. 대규모 scaling table은 만들지 않는다.
##   - reduce/delay 외부 API: reduce_threat()는 ThreatSystem.reduce를 재사용하고,
##     delay_wave()는 다음 wave를 뒤로 미룬다. 향후 Dungeon clear(TASK-028)가 이 API를
##     호출할 수 있다. Dungeon placeholder gameplay는 구현하지 않는다.
##   - 동일 NIGHT duplicate wave trigger 없음: _last_processed_night 가드로 1 NIGHT에
##     정확히 1회만 wave를 처리한다(스케줄 trigger + spawner gate 이중 방어).
##
## 정확한 배율/임계값은 아직 최종 밸런스가 아니므로 export로 조정 가능하게 두고
## DESIGN_TUNING으로 표시한다.

signal wave_triggered(wave_index: int, night_number: int)
signal schedule_changed(nights_until_wave: int, wave_index: int)
## TASK-028-2: Dungeon 시스템이 run 결과를 보고했을 때 발행되는 신호.
## outcome이 CLEARED일 때만 Threat 감소/지연이 적용된다. HUD는 이 신호를 구독해
## "던전 공략이 wave 대비에 연결됨"을 즉시 반영할 수 있다.
signal dungeon_run_result(outcome: String, dungeon_run_id: String)

## 기본 wave 간격(밤 수). 1이면 매 NIGHT wave(기존 spawner 동작과 동일). (DESIGN_TUNING)
@export var base_wave_interval := 1
## 최소 간격. Threat가 아무리 높아도 이보다 촘촘하지 않다. (DESIGN_TUNING)
@export var min_wave_interval := 1
## threat ratio 1.0일 때 간격이 얼마나 줄어드는지(0..1). 0이면 Threat가 간격에 영향 없음.
## 1이면 max threat에서 간격이 0에 수렴(min_wave_interval로 clamp). (DESIGN_TUNING)
@export var threat_schedule_factor := 0.5
## 이 ratio 이상이면 스케줄과 무관하게 해당 NIGHT을 강제 wave로 trigger한다. (DESIGN_TUNING)
@export var wave_threshold_ratio := 1.0
## delay_wave()가 한 번에 추가할 수 있는 상한(밤 수). 무한 밀림 방지. (DESIGN_TUNING)
@export var max_delay_nights := 5

## TASK-028-1: Dungeon clear가 호출할 감소량. ThreatSystem.reduce를 통해
## 다음 wave timing(간격/강제 threshold)에 실제로 반영된다. (DESIGN_TUNING)
@export var dungeon_clear_reduce_amount := 25.0
## TASK-028-1: Dungeon clear가 호출할 지연량(밤 수). max_delay_nights 상한을 따른다. (DESIGN_TUNING)
@export var dungeon_clear_delay_nights := 1

## TASK-028-2: Dungeon run 결과 outcome 상수. `CLEARED`만 Threat 감소/지연을 유발하고
## RETREAT/FAILED는 적용하지 않는다. (그 밖의 outcome도 적용되지 않는다.)
const DUNGEON_CLEARED := "CLEARED"
const DUNGEON_RETREAT := "RETREAT"
const DUNGEON_FAILED := "FAILED"

var _wave_index := 0
var _nights_until_wave := 0
var _is_wave_night := false
var _wave_triggered_this_night := false
var _last_processed_night := -1
## TASK-028-1: 이미 Dungeon clear 보상을 적용한 run ID 목록. duplicate reduction 방지.
var _applied_dungeon_clears: Array[String] = []


func _ready() -> void:
	GameTime.phase_changed.connect(_on_phase_changed)


## GameTime phase 전환. NIGHT이면 wave 스케줄을 처리하고, DAY 복귀 시 per-NIGHT 가드를
## 풀어 다음 NIGHT이 다시 wave를 판정할 수 있게 한다.
func _on_phase_changed(phase: int, day_number: int) -> void:
	if phase == GameTime.Phase.NIGHT:
		_process_night(day_number)
	else:
		_wave_triggered_this_night = false
		_is_wave_night = false


## NIGHT 진입 시 wave 스케줄 처리. 동일 NIGHT 중복 처리를 _last_processed_night로 막는다.
func _process_night(day_number: int) -> void:
	if day_number == _last_processed_night or _wave_triggered_this_night:
		return
	_last_processed_night = day_number
	_wave_triggered_this_night = true

	_nights_until_wave -= 1
	var forced := ThreatSystem.get_ratio() >= wave_threshold_ratio
	if _nights_until_wave <= 0 or forced:
		_is_wave_night = true
		_trigger_wave(day_number)
	else:
		_is_wave_night = false
	schedule_changed.emit(_nights_until_wave, _wave_index)


## wave를 1회 trigger하고 다음 wave 간격을 Threat 기반으로 재예약한다.
func _trigger_wave(day_number: int) -> void:
	_wave_index += 1
	_nights_until_wave = _effective_interval()
	wave_triggered.emit(_wave_index, day_number)


## Threat가 간격에 주는 최소 규칙: ratio가 높을수록 간격이 min_wave_interval까지 줄어든다.
## 문서에 확정 배율이 없으므로 대규모 scaling table을 만들지 않고 export 조합만 사용한다.
func _effective_interval() -> int:
	var ratio := ThreatSystem.get_ratio()
	var interval := float(base_wave_interval) * (1.0 - ratio * threat_schedule_factor)
	return maxi(min_wave_interval, int(round(interval)))


## 현재 NIGHT이 wave night인지. 기존 NIGHT enemy spawn(FirstEncounterSpawner3D)이
## 이 값을 조회해 wave night에만 spawn하도록 gate한다.
func is_wave_night() -> bool:
	return _is_wave_night


func get_wave_index() -> int:
	return _wave_index


func get_nights_until_wave() -> int:
	return _nights_until_wave


## Threat ratio 위임(get_ratio). HUD/호출부가 ThreatSystem을 직접 모르게 한다.
func get_ratio() -> float:
	return ThreatSystem.get_ratio()


## 외부 Threat 증가. 향후 이벤트/Dungeon reward 등이 사용 가능하다. (TASK-028-1 contract)
func add_threat(amount: float) -> void:
	ThreatSystem.add(amount)
	schedule_changed.emit(_nights_until_wave, _wave_index)


## 외부 Threat 감소 API. 기존 ThreatSystem.reduce를 재사용한다(중복 owner 금지).
## Threat가 낮아지면 threshold trigger가 해제되고 다음 wave 간격이 길어져
## "다음 wave timing 변화"가 실제 스케줄에 반영된다.
func reduce_threat(amount: float) -> void:
	ThreatSystem.reduce(amount)
	schedule_changed.emit(_nights_until_wave, _wave_index)


## 외부 wave 지연 API. 다음 wave를 nights만큼 뒤로 미룬다. cap은 max_delay_nights.
func delay_wave(nights: int) -> void:
	if nights <= 0:
		return
	var cap := base_wave_interval + max_delay_nights
	_nights_until_wave = mini(_nights_until_wave + nights, cap)
	schedule_changed.emit(_nights_until_wave, _wave_index)


## TASK-028-1: Dungeon clear가 연결할 **authoritative API**.
## `CLEARED` 확정 시 run당 정확히 1회 호출해야 한다. 내부적으로 config로 분리한
## 감소량(dungeon_clear_reduce_amount)/지연량(dungeon_clear_delay_nights)을
## 기존 reduce_threat/delay_wave를 통해 적용한다. 같은 dungeon_run_id로 중복 호출되면
## 두 번째는 무시되어 duplicate reduction을 방지한다(RETREAT/FAILED에는 적용 금지).
## 실제 Dungeon run 수명 주기는 TASK-028-2에서 다룬다.
func apply_dungeon_clear(dungeon_run_id: String) -> void:
	if dungeon_run_id.is_empty():
		return
	if dungeon_run_id in _applied_dungeon_clears:
		return
	_applied_dungeon_clears.append(dungeon_run_id)
	reduce_threat(dungeon_clear_reduce_amount)
	delay_wave(dungeon_clear_delay_nights)


## TASK-028-1: 동일 Dungeon clear의 duplicate application guard가 활성 상태인지.
func is_dungeon_clear_applied(dungeon_run_id: String) -> bool:
	return dungeon_run_id in _applied_dungeon_clears


## TASK-028-2: Dungeon run이 끝났을 때 호출하는 **result contract**.
## outcome이 DUNGEON_CLEARED일 때만 run당 정확히 1회 Threat 감소/지연을
## apply_dungeon_clear()로 반영하고, RETREAT/FAILED 및 그 외 outcome에는 적용하지
## 않는다. 같은 dungeon_run_id의 CLEARED 재수신은 apply_dungeon_clear의 duplicate
## guard가 차단해 감소/지연이 중복되지 않는다.
## 실제 Dungeon runtime(TASK-027)이 이 메서드를 호출할 수 있는 authoritative bridge다.
func report_dungeon_result(outcome: String, dungeon_run_id: String) -> void:
	if outcome == DUNGEON_CLEARED:
		apply_dungeon_clear(dungeon_run_id)
	dungeon_run_result.emit(outcome, dungeon_run_id)


## 테스트/리셋용. 초기 상태로 되돌린다.
func reset() -> void:
	_wave_index = 0
	_nights_until_wave = 0
	_is_wave_night = false
	_wave_triggered_this_night = false
	_last_processed_night = -1
	_applied_dungeon_clears.clear()
	schedule_changed.emit(_nights_until_wave, _wave_index)


## 향후 저장 확장용 순수 데이터 스냅샷. Node/Actor reference를 담지 않는다.
func to_snapshot() -> Dictionary:
	return {
		"wave_index": _wave_index,
		"nights_until_wave": _nights_until_wave,
		"applied_dungeon_clears": _applied_dungeon_clears.duplicate(),
	}


## 스냅샷 복원(향후 persistence용). 현재 저장 시스템이 없어 실제 사용처는 아직 없다.
func from_snapshot(snapshot: Dictionary) -> void:
	_wave_index = int(snapshot.get("wave_index", 0))
	_nights_until_wave = int(snapshot.get("nights_until_wave", 0))
	var applied: Array = snapshot.get("applied_dungeon_clears", [])
	_applied_dungeon_clears.clear()
	for id in applied:
		_applied_dungeon_clears.append(str(id))
	schedule_changed.emit(_nights_until_wave, _wave_index)
