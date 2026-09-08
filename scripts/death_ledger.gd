extends Node

## TASK-016-2 최소 DeathLedger 전역 서비스.
## 사망 snapshot(DeathRecord.to_snapshot() 등)으로 DeathRecord를 생성/조회하고 상태
## (PENDING/ACTIVE/RESOLVED)를 변경한다. Autoload로 등록되어 SceneTree가 유지되는 한
## record를 보관하므로 Day/Night 전환 후에도 record가 유지된다.
## DeathLedger는 Ghost를 spawn하지 않으며 Portal/Wave를 제어하지 않는다.
## SaveGame 시스템은 구현하지 않는다. TASK-016-4에서 source_uid 기준 중복 기록
## 차단과 Ghost(재귀) 사망의 신규 record 생성을 차단하는 가드를 구현한다.
## TASK-025-1에서 entity category 기반 eligibility(ELIGIBLE_CATEGORIES)로
## unsupported category를 안전하게 skip하도록 일반화한다.
## TASK-028-1: Ghost Identity Preservation. Mercenary의 원래 loadout을 포함한
## 사망 정보를 저장하여 Ghost가 원본 상태를 재현할 수 있도록 한다.

signal record_added(record_id: String)
signal record_status_changed(record_id: String, status: int)
signal record_resolved(record_id: String)

## TASK-025-1: Ghost Return/사망 기록에 eligible한 entity category 집합.
## entity category 기반 eligibility를 적용한다. 실제 구현된 eligible category만
## 기록 대상이 된다. 여기에 없는 category는 사망 snapshot이라도 안전하게 skip해
## record를 만들지 않는다. 새 category가 실제로 구현되면 여기에 추가하면 된다
## (animal/NPC 등 미구현 category를 억지로 만들지 않음).
const ELIGIBLE_CATEGORIES := {
	"MERCENARY": true,
	"ENEMY": true,
}

## record_id -> DeathRecord. Actor reference가 아닌 snapshot 데이터만 보관한다.
var _records: Dictionary = {}
var _next_id := 1

## TASK-028-1: Ghost Identity Preservation.
## 원래 mercenary에서 loadout/effect 정보를 저장할 수 있는 필드.
## 특정 사망 기록(record)에 대한 원본 정보 저장용.
var _original_mercenary_data: Dictionary = {}


## TASK-016-2: 사망 snapshot으로 record를 생성해 Ledger에 추가하고 record_added를
## 발행한다. snapshot은 순수 데이터 Dictionary이며, record_id가 없으면 자동 생성하고
## eligible_day가 0이하이면 death_day + 1로 계산한다(NIGHT Day N 사망 → 최소 Day N+1).
## 생성된 record의 복사본을 반환한다.
## TASK-016-4 duplicate guard: 같은 source_uid의 record가 이미 존재하면 신규 record를
## 만들지 않고 기존 record 복사본을 반환한다(동일 실제 죽음 = 정확히 1 record).
## display_name이 아니라 source_uid 기준이므로 이름이 같은 다른 개체는 각각 기록된다.
## TASK-016-4 recursive guard: is_ghost가 true인(Ghost) 사망 snapshot은 신규 record를
## 절대 만들지 않는다. 기존 record가 있으면 그 복사본을, 없으면 null을 반환한다.
## Ghost death의 기존 record RESOLVED 처리는 TASK-017에서 구현한다.
## TASK-025-1 eligibility: entity category가 eligible set에 없으면(unsupported category)
## 신규 record를 만들지 않고 null을 반환한다. identity snapshot / source·death context /
## one-return invariant(duplicate+recursive guard)는 유지된다.
## TASK-028-1: Ghost Identity Preservation. Mercenary 사망 정보 저장 시 원래 loadout/
## effect 구조를 추가로 저장한다. 사망 기록을 만들 때 mercenary data를 별도 필드에
## 저장하고, Ghost 생성 시 복구하여 사용할 수 있도록 한다.
func record_death(snapshot: Dictionary) -> DeathRecord:
	var record := DeathRecord.from_snapshot(snapshot)
	if not is_eligible_category(record.get_category()):
		return null
	if record.is_ghost:
		return _find_record_copy_by_source(record.source_uid)
	if has_record_for_source(record.source_uid):
		return _find_record_copy_by_source(record.source_uid)
	if record.record_id == "":
		record.record_id = _generate_record_id()
	if record.eligible_day <= 0:
		record.eligible_day = record.death_day + 1
	
	## TASK-028-1: Mercenary 사망 시 원본 loadout/effect 정보 저장
	if record.get_category() == "MERCENARY" and snapshot.has("original_mercenary_data"):
		_original_mercenary_data[record.record_id] = snapshot["original_mercenary_data"]
	
	_records[record.record_id] = record
	record_added.emit(record.record_id)
	return _copy_record(record)


## TASK-025-1: 주어진 entity category가 Ghost Return/사망 기록에 eligible한지 판정한다.
## unsupported category는 false이며 DeathLedger가 이 기록을 안전하게 skip한다.
func is_eligible_category(category: String) -> bool:
	return ELIGIBLE_CATEGORIES.has(category)


## record_id로 record 조회. 없으면 null. 내부 상태 우회 변경 방지를 위해 복사본 반환.
func get_record(record_id: String) -> DeathRecord:
	if not _records.has(record_id):
		return null
	return _copy_record(_records[record_id])


## TASK-026-1: party member id로 사망 snapshot을 만들고 record_death에서 record를 추가한다.
## 사망은 dungeon에서 발생한 것으로 간주하고 category는 "MERCENARY"로 기록하며,
## death day 정보를 저장한다. 복사본이 반환되므로 Ledger 내부 상태는 변경되지 않는다.
func report_death(member_id: String, source: String) -> DeathRecord:
	var snapshot := {
		"source_uid": member_id,
		"display_name": "Mercenary",
		"category": "MERCENARY",
		"death_day": GameTime.get_day(),
		"death_source": source
	}
	return record_death(snapshot)


## TASK-028-1: Ghost Identity Preservation.
## 주어진 record_id의 원래 mercenary 데이터를 반환한다.
## record_id가 없거나 mercenary 데이터가 없으면 null을 반환한다.
func get_original_mercenary_data(record_id: String) -> Dictionary:
	if not _original_mercenary_data.has(record_id):
		return {}
	return _original_mercenary_data[record_id]


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


## TASK-016-4: source_uid와 일치하는 record의 복사본을 반환한다(없으면 null).
## duplicate/ghost guard에서 기존 record를 재반환할 때 사용한다.
func _find_record_copy_by_source(source_uid: String) -> DeathRecord:
	for record in _records.values():
		if record.source_uid == source_uid:
			return _copy_record(record)
	return null


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

## TASK-012: Add faction reputation management
func add_faction_reputation(faction_id: String, amount: int) -> void:
	# This function is a placeholder that can be extended to store and manage faction reputations
	pass

func get_faction_reputation(faction_id: String) -> int:
	# This function is a placeholder that can be extended to retrieve faction reputations
	return 0

## TASK-012: Return total death count
func get_death_count() -> int:
	return _next_id - 1


## TASK-012: Get a specific death record by ID
func get_death_record(record_id: String) -> DeathRecord:
	if not _records.has(record_id):
		return null
	return _copy_record(_records[record_id])
