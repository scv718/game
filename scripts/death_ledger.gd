extends Node

## TASK-016-2 최소 DeathLedger 전역 서비스.
## 사망 snapshot(DeathRecord.to_snapshot() 등)으로 DeathRecord를 생성/조회하고 상태
## (PENDING/ACTIVE/RESOLVED)를 변경한다. Autoload로 등록되어 SceneTree가 유지되는 한
## record를 보관하므로 Day/Night 전환 후에도 record가 유지된다.
## DeathLedger는 Ghost를 spawn하지 않으며 Portal/Wave를 제어하지 않는다.
## SaveGame 시스템은 구현하지 않는다. 중복 기록 차단 / Ghost 재귀 기록 방지 전용
## guard는 TASK-016-4에서 구현한다.

signal record_added(record_id: String)
signal record_status_changed(record_id: String, status: int)
signal record_resolved(record_id: String)

## record_id -> DeathRecord. Actor reference가 아닌 snapshot 데이터만 보관한다.
var _records: Dictionary = {}
var _next_id := 1


## TASK-016-2: 사망 snapshot으로 record를 생성해 Ledger에 추가하고 record_added를
## 발행한다. snapshot은 순수 데이터 Dictionary이며, record_id가 없으면 자동 생성하고
## eligible_day가 0이하이면 death_day + 1로 계산한다(NIGHT Day N 사망 → 최소 Day N+1).
## 생성된 record의 복사본을 반환한다. 중복 source 차단은 TASK-016-4에서 처리한다.
func record_death(snapshot: Dictionary) -> DeathRecord:
	var record := DeathRecord.from_snapshot(snapshot)
	if record.record_id == "":
		record.record_id = _generate_record_id()
	if record.eligible_day <= 0:
		record.eligible_day = record.death_day + 1
	_records[record.record_id] = record
	record_added.emit(record.record_id)
	return _copy_record(record)


## record_id로 record 조회. 없으면 null. 내부 상태 우회 변경 방지를 위해 복사본 반환.
func get_record(record_id: String) -> DeathRecord:
	if not _records.has(record_id):
		return null
	return _copy_record(_records[record_id])


## 전체 record 목록(복사본). 조회 결과를 외부에서 수정해도 Ledger 내부 상태는 변하지
## 않는다.
func get_all_records() -> Array[DeathRecord]:
	var out: Array[DeathRecord] = []
	for record in _records.values():
		out.append(_copy_record(record))
	return out


func get_pending_records() -> Array[DeathRecord]:
	return _get_records_by_status(DeathRecord.Status.PENDING)


func get_active_records() -> Array[DeathRecord]:
	return _get_records_by_status(DeathRecord.Status.ACTIVE)


func get_resolved_records() -> Array[DeathRecord]:
	return _get_records_by_status(DeathRecord.Status.RESOLVED)


## TASK-016-2: PENDING → ACTIVE. 이미 ACTIVE면 true(멱등), RESOLVED record는 되돌릴 수
## 없으므로 false. 존재하지 않는 record도 false(안전 no-op).
func mark_active(record_id: String) -> bool:
	var record := _get_internal(record_id)
	if record == null:
		return false
	if record.status == DeathRecord.Status.RESOLVED:
		return false
	if record.status == DeathRecord.Status.ACTIVE:
		return true
	if not record.set_status(DeathRecord.Status.ACTIVE):
		return false
	record_status_changed.emit(record_id, record.status)
	return true


## TASK-016-2: ACTIVE → PENDING. 이미 PENDING이면 true(멱등), RESOLVED record는 되돌릴
## 수 없으므로 false. 존재하지 않는 record도 false(안전 no-op).
func mark_pending(record_id: String) -> bool:
	var record := _get_internal(record_id)
	if record == null:
		return false
	if record.status == DeathRecord.Status.RESOLVED:
		return false
	if record.status == DeathRecord.Status.PENDING:
		return true
	if not record.set_status(DeathRecord.Status.PENDING):
		return false
	record_status_changed.emit(record_id, record.status)
	return true


## TASK-016-2: PENDING/ACTIVE → RESOLVED로 영구 종료하고 resolved_day를 기록한다.
## 이미 RESOLVED면 true(멱등)이며 resolved_day를 변경하지 않는다.
## 존재하지 않는 record는 false(안전 no-op).
func resolve(record_id: String, day: int) -> bool:
	var record := _get_internal(record_id)
	if record == null:
		return false
	if record.status == DeathRecord.Status.RESOLVED:
		return true
	if not record.set_status(DeathRecord.Status.RESOLVED):
		return false
	record.resolved_day = day
	record_status_changed.emit(record_id, record.status)
	record_resolved.emit(record_id)
	return true


## source_uid와 일치하는 record가 하나라도 존재하는지. display_name이 아니라
## source_uid 기준이다(같은 이름의 다른 개체는 서로 다른 record).
func has_record_for_source(source_uid: String) -> bool:
	for record in _records.values():
		if record.source_uid == source_uid:
			return true
	return false


## 내부 record 조회(복사본 없이 실제 인스턴스). 상태 변경 API 내부에서만 사용.
func _get_internal(record_id: String) -> DeathRecord:
	if not _records.has(record_id):
		return null
	return _records[record_id]


## 외부 반환용 복사본. snapshot round-trip으로 mutable 상태가 공유되지 않게 한다.
func _copy_record(record: DeathRecord) -> DeathRecord:
	return DeathRecord.from_snapshot(record.to_snapshot())


func _get_records_by_status(status: int) -> Array[DeathRecord]:
	var out: Array[DeathRecord] = []
	for record in _records.values():
		if record.status == status:
			out.append(_copy_record(record))
	return out


## 중복되지 않는 record_id를 생성한다.
func _generate_record_id() -> String:
	var id := "death_%d" % _next_id
	_next_id += 1
	return id