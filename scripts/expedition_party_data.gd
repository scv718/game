extends RefCounted
class_name ExpeditionPartyData

## TASK-026-2 최소 ExpeditionPartyData.
## Runtime Actor와 분리된 Expedition persistent 데이터 클래스.
## 월드 Actor/Node reference를 저장하지 않으며, member는 MercenaryRoster의
## stable String identity id로만 참조한다(MercenaryData.id와 동일 관례).
## 모든 필드는 기본 타입/Array/Dictionary만으로 구성되어 Save/Load snapshot에
## 그대로 사용할 수 있다. 상태 진행 자체(시간 기반 전환)는 TASK-026-3 runtime
## owner가 다루며, 본 데이터는 상태/결과를 보관하는 책임만 진다.
## 범용 Party Framework를 만들지 않고 Expedition 고유 최소 필드만 보유한다.

enum Status { READY, OUTBOUND, EXPLORING, RETURNING, COMPLETED }

const STATUS_NAMES := {
	Status.READY: "READY",
	Status.OUTBOUND: "OUTBOUND",
	Status.EXPLORING: "EXPLORING",
	Status.RETURNING: "RETURNING",
	Status.COMPLETED: "COMPLETED",
}

var expedition_id: String = ""
var destination_region_id: String = ""
var status: Status = Status.READY
## 출발 시점(GameTime.get_day_number() / day 내 경과 초).
var departure_day: int = 0
var departure_time: float = 0.0
## 각 구간 소요 시간(초). 진행 규칙 자체는 TASK-026-3 owner가 다룬다.
var outbound_duration: float = 0.0
var exploration_duration: float = 0.0
var return_duration: float = 0.0
## 현재 status 시작 시점(초). runtime owner가 구간 진행 기준으로 사용한다.
var phase_started_at: float = 0.0
## 현재 구간 진행도(0.0~1.0). runtime owner가 갱신한다.
var progress: float = 0.0

## 편성 member identity id 목록(String). 외부에서 원본을 수정해도 내부가 바뀌지
## 않도록 복사본으로만 보관하며, 순서는 추가 순서대로 deterministic하게 유지한다.
var _member_identity_ids: Array = []
var _result: Dictionary = {}
var _discovered_feature_ids: Array = []
var _metadata: Dictionary = {}


func _init(p_expedition_id: String = "", p_destination_region_id: String = "") -> void:
	expedition_id = p_expedition_id
	destination_region_id = p_destination_region_id


func get_status_name() -> String:
	return STATUS_NAMES.get(status, "?")


## 상태 변경. 존재하지 않는 enum 값은 거부하고 false를 반환한다.
func set_status(value: int) -> bool:
	if value < Status.READY or value > Status.COMPLETED:
		return false
	status = value
	return true


func get_status() -> Status:
	return status


## READY/COMPLETED가 아닌 진행 중(파견/탐사/귀환) 상태인지.
func is_active() -> bool:
	return status != Status.READY and status != Status.COMPLETED


## member 추가. 빈 id와 중복은 거부한다. 순서는 append 순서대로 유지한다.
func add_member(identity_id: String) -> bool:
	if identity_id.is_empty() or _member_identity_ids.has(identity_id):
		return false
	_member_identity_ids.append(identity_id)
	return true


func remove_member(identity_id: String) -> bool:
	if not _member_identity_ids.has(identity_id):
		return false
	_member_identity_ids.erase(identity_id)
	return true


func has_member(identity_id: String) -> bool:
	return _member_identity_ids.has(identity_id)


func get_member_count() -> int:
	return _member_identity_ids.size()


## 외부에서 원본 Array를 수정해도 내부 상태가 바뀌지 않게 복사본으로 저장한다.
## 빈 id와 중복은 제거하고 기존 순서를 유지해 deterministic하게 만든다.
func set_member_ids(ids: Array) -> void:
	var cleaned: Array = []
	for id in ids:
		var sid := str(id)
		if sid.is_empty() or cleaned.has(sid):
			continue
		cleaned.append(sid)
	_member_identity_ids = cleaned


func get_member_ids() -> Array:
	return _member_identity_ids.duplicate(true)


## 결과 데이터(mutable object)는 복사본으로만 저장한다. reward 등은 이후 태스크.
func set_result(value: Dictionary) -> void:
	_result = value.duplicate(true)


func get_result() -> Dictionary:
	return _result.duplicate(true)


## 발견 feature 추가. 빈 id와 중복은 거부한다.
func add_discovered_feature(feature_id: String) -> bool:
	if feature_id.is_empty() or _discovered_feature_ids.has(feature_id):
		return false
	_discovered_feature_ids.append(feature_id)
	return true


func has_discovered_feature(feature_id: String) -> bool:
	return _discovered_feature_ids.has(feature_id)


func set_discovered_feature_ids(ids: Array) -> void:
	_discovered_feature_ids = ids.duplicate(true)


func get_discovered_feature_ids() -> Array:
	return _discovered_feature_ids.duplicate(true)


## metadata는 mutable object이므로 복사본으로 저장한다.
func set_metadata(value: Dictionary) -> void:
	_metadata = value.duplicate(true)


func get_metadata() -> Dictionary:
	return _metadata.duplicate(true)


## 순수 snapshot(Dictionary)으로 직렬화한다. 모든 값은 기본 타입/Array/Dictionary이며
## Node/Actor reference를 포함하지 않는다. 컨테이너는 복사본으로 포함한다.
func to_snapshot() -> Dictionary:
	return {
		"expedition_id": expedition_id,
		"destination_region_id": destination_region_id,
		"status": status,
		"departure_day": departure_day,
		"departure_time": departure_time,
		"outbound_duration": outbound_duration,
		"exploration_duration": exploration_duration,
		"return_duration": return_duration,
		"phase_started_at": phase_started_at,
		"progress": progress,
		"member_identity_ids": _member_identity_ids.duplicate(true),
		"result": _result.duplicate(true),
		"discovered_feature_ids": _discovered_feature_ids.duplicate(true),
		"metadata": _metadata.duplicate(true),
	}


## snapshot(Dictionary)으로부터 expedition을 복원한다. 컨테이너는 복사본으로 참조해
## 원본을 수정해도 내부 상태가 바뀌지 않게 한다. 존재하지 않는 status는 거부한다.
static func from_snapshot(snapshot: Dictionary) -> ExpeditionPartyData:
	var exp := ExpeditionPartyData.new(
		str(snapshot.get("expedition_id", "")),
		str(snapshot.get("destination_region_id", "")))
	var new_status := int(snapshot.get("status", Status.READY))
	if new_status < Status.READY or new_status > Status.COMPLETED:
		new_status = Status.READY
	exp.status = new_status
	exp.departure_day = int(snapshot.get("departure_day", 0))
	exp.departure_time = float(snapshot.get("departure_time", 0.0))
	exp.outbound_duration = float(snapshot.get("outbound_duration", 0.0))
	exp.exploration_duration = float(snapshot.get("exploration_duration", 0.0))
	exp.return_duration = float(snapshot.get("return_duration", 0.0))
	exp.phase_started_at = float(snapshot.get("phase_started_at", 0.0))
	exp.progress = clampf(float(snapshot.get("progress", 0.0)), 0.0, 1.0)
	var members: Variant = snapshot.get("member_identity_ids", [])
	if typeof(members) == TYPE_ARRAY:
		exp.set_member_ids(members as Array)
	var result: Variant = snapshot.get("result", {})
	if typeof(result) == TYPE_DICTIONARY:
		exp._result = (result as Dictionary).duplicate(true)
	var features: Variant = snapshot.get("discovered_feature_ids", [])
	if typeof(features) == TYPE_ARRAY:
		exp._discovered_feature_ids = (features as Array).duplicate(true)
	var meta: Variant = snapshot.get("metadata", {})
	if typeof(meta) == TYPE_DICTIONARY:
		exp._metadata = (meta as Dictionary).duplicate(true)
	return exp
