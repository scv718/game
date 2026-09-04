extends Node

## TASK-017-1 최소 Ghost Return Candidate 관리자(autoload: GhostReturn).
## DeathLedger(autoload)의 record_added 신호를 받아 lethal death record를
## GhostReturnCandidate로 등록하고, 1회 return 불변식(consume)을 관리한다.
## DeathLedger가 이미 다음을 보장하므로 candidate 중복/비대상이 원천 차단된다:
##   - 같은 source_uid duplicate death → 신규 record 없음 → candidate 추가 안 함.
##   - cleanup/despawn → record 없음 → candidate 안 됨.
##   - Ghost death → 신규 record 없음 → candidate 안 됨(재귀 방지).
## Ghost를 spawn하지 않으며 Portal/Wave를 제어하지 않는다. TASK-017-2에서
## eligible candidate를 consume하고 NIGHT spawn한다. save/load 시스템은 현재 없으므로
## autoload 유지 기간 동안 candidate/consumed 상태가 보존된다.
## 별도 거대 event sourcing 시스템은 만들지 않는다.

signal candidate_added(candidate: GhostReturnCandidate)
signal candidate_consumed(record_id: String)

## record_id -> GhostReturnCandidate. 내부 소유본만 보관한다.
var _candidates: Dictionary = {}


func _ready() -> void:
	var ledger: Node = get_node_or_null("/root/DeathLedger")
	if ledger != null:
		if not ledger.record_added.is_connected(_on_record_added):
			ledger.record_added.connect(_on_record_added)


## DeathLedger.record_added 수신. 신규 record만 시그널이 발생하므로 duplicate/ghost/
## cleanup은 이 경로에 도달하지 않는다. 방어적으로 is_ghost/중복은 다시 검사한다.
func _on_record_added(record_id: String) -> void:
	var ledger: Node = get_node_or_null("/root/DeathLedger")
	if ledger == null:
		return
	var record: DeathRecord = ledger.get_record(record_id)
	if record == null:
		return
	register(record)


## DeathRecord를 후보로 등록한다.
## - record_id가 이미 있으면 기존 후보를 그대로 반환(중복 후보 없음).
## - ghost death record는 신규 후보를 만들지 않는다(재귀 방지).
## - 등록 성공 시 candidate_added를 1회 발행한다. 반환값은 복사본.
func register(record: DeathRecord) -> GhostReturnCandidate:
	if record == null or record.record_id == "":
		return null
	if record.is_ghost:
		return get_candidate(record.record_id)
	if _candidates.has(record.record_id):
		return get_candidate(record.record_id)
	var cand: GhostReturnCandidate = GhostReturnCandidate.from_record(record)
	if cand == null:
		return null
	_candidates[record.record_id] = cand
	candidate_added.emit(_copy_candidate(cand))
	return _copy_candidate(cand)


## record_id로 후보 조회. 없으면 null. 내부 상태 우회 변경 방지를 위해 복사본 반환.
func get_candidate(record_id: String) -> GhostReturnCandidate:
	if not _candidates.has(record_id):
		return null
	return _copy_candidate(_candidates[record_id])


## 전체 후보 목록(복사본).
func get_all_candidates() -> Array[GhostReturnCandidate]:
	var out: Array[GhostReturnCandidate] = []
	for cand in _candidates.values():
		out.append(_copy_candidate(cand))
	return out


## 아직 consume되지 않은(return 가능한) 후보 목록(복사본).
func get_eligible_candidates() -> Array[GhostReturnCandidate]:
	var out: Array[GhostReturnCandidate] = []
	for cand in _candidates.values():
		if not cand.is_consumed():
			out.append(_copy_candidate(cand))
	return out


func get_candidate_count() -> int:
	return _candidates.size()


func is_consumed(record_id: String) -> bool:
	if not _candidates.has(record_id):
		return false
	return _candidates[record_id].is_consumed()


## 1회 return 불변식. 이미 consumed된 candidate는 false(재사용 없음).
## 존재하지 않는 candidate도 false(안전 no-op).
func consume(record_id: String) -> bool:
	if not _candidates.has(record_id):
		return false
	var cand: GhostReturnCandidate = _candidates[record_id]
	if not cand.consume():
		return false
	candidate_consumed.emit(record_id)
	return true


## 외부 반환용 복사본. snapshot round-trip으로 mutable 상태(consumed)가 공유되지 않게 한다.
func _copy_candidate(cand: GhostReturnCandidate) -> GhostReturnCandidate:
	return GhostReturnCandidate.from_snapshot(cand.to_snapshot())
