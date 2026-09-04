extends RefCounted
class_name GhostReturnCandidate

## TASK-017-1 최소 Ghost Return Candidate.
## DeathLedger의 DeathRecord(1회성, source_uid dedup, ghost death 제외)를 기반으로
## Ghost Return 후보 상태를 snapshot한다. Actor/Node reference, NodePath/Callable,
## SceneTree reference를 저장하지 않으며 원본 Actor가 despawn/free되어도 후보가 유지된다.
##
## - 원본 entity category(source_kind) / source death(death_day/phase/position) /
##   combat identity(level/max_hp/attack_damage/attack_interval/move_speed)를 추적.
## - consumed(1회 return) 불변식: consume()는 이미 consumed면 false, 최초 1회만 true.
## - cleanup/despawn은 DeathRecord를 만들지 않으므로 후보가 되지 않는다.
## - Ghost death는 DeathRecord를 만들지 않으므로 후보가 되지 않는다(DeathLedger가 차단).
## 실제 Ghost spawn과 consume 순서는 TASK-017-2에서 처리한다.

enum CandidateState { PENDING, CONSUMED }

var record_id: String = ""
var source_uid: String = ""
var source_kind: int = DeathRecord.SourceKind.MERCENARY
var is_ghost := false
var display_name: String = ""
var class_or_type: String = ""
var level: int = 1
var max_hp: int = 0
var attack_damage: int = 0
var attack_interval: float = 1.0
var move_speed: float = 0.0
var death_day: int = 1
var death_phase: int = DeathRecord.DeathPhase.NIGHT
var death_position := Vector2.ZERO

var _consumed := false


func _init(p_record_id: String = "") -> void:
	record_id = p_record_id


## 1회 return 불변식. 이미 consumed된 candidate는 다시 consume할 수 없다.
func consume() -> bool:
	if _consumed:
		return false
	_consumed = true
	return true


func is_consumed() -> bool:
	return _consumed


func get_state() -> CandidateState:
	return CandidateState.CONSUMED if _consumed else CandidateState.PENDING


func get_source_kind_name() -> String:
	return DeathRecord.SOURCE_KIND_NAMES.get(source_kind, "?")


func get_death_phase_name() -> String:
	return DeathRecord.DEATH_PHASE_NAMES.get(death_phase, "?")


## 순수 snapshot(Dictionary)으로 직렬화. 기본 타입/Vector2만 포함하며 Node reference 없음.
func to_snapshot() -> Dictionary:
	return {
		"record_id": record_id,
		"source_uid": source_uid,
		"source_kind": source_kind,
		"is_ghost": is_ghost,
		"display_name": display_name,
		"class_or_type": class_or_type,
		"level": level,
		"max_hp": max_hp,
		"attack_damage": attack_damage,
		"attack_interval": attack_interval,
		"move_speed": move_speed,
		"death_day": death_day,
		"death_phase": death_phase,
		"death_position": death_position,
		"consumed": _consumed,
	}


static func from_snapshot(snapshot: Dictionary) -> GhostReturnCandidate:
	var cand := GhostReturnCandidate.new(str(snapshot.get("record_id", "")))
	cand.source_uid = str(snapshot.get("source_uid", ""))
	cand.source_kind = int(snapshot.get("source_kind", DeathRecord.SourceKind.MERCENARY))
	cand.is_ghost = bool(snapshot.get("is_ghost", false))
	cand.display_name = str(snapshot.get("display_name", ""))
	cand.class_or_type = str(snapshot.get("class_or_type", ""))
	cand.level = int(snapshot.get("level", 1))
	cand.max_hp = int(snapshot.get("max_hp", 0))
	cand.attack_damage = int(snapshot.get("attack_damage", 0))
	cand.attack_interval = float(snapshot.get("attack_interval", 1.0))
	cand.move_speed = float(snapshot.get("move_speed", 0.0))
	cand.death_day = int(snapshot.get("death_day", 1))
	cand.death_phase = int(snapshot.get("death_phase", DeathRecord.DeathPhase.NIGHT))
	cand.death_position = Vector2(snapshot.get("death_position", Vector2.ZERO))
	cand._consumed = bool(snapshot.get("consumed", false))
	return cand


## DeathRecord(source-of-truth)로부터 후보 snapshot을 만든다. consume 상태는 초기 false.
static func from_record(record: DeathRecord) -> GhostReturnCandidate:
	if record == null:
		return null
	var cand := GhostReturnCandidate.new(record.record_id)
	cand.source_uid = record.source_uid
	cand.source_kind = record.source_kind
	cand.is_ghost = record.is_ghost
	cand.display_name = record.display_name
	cand.class_or_type = record.class_or_type
	cand.level = record.level
	cand.max_hp = record.max_hp
	cand.attack_damage = record.attack_damage
	cand.attack_interval = record.attack_interval
	cand.move_speed = record.move_speed
	cand.death_day = record.death_day
	cand.death_phase = record.death_phase
	cand.death_position = record.death_position
	return cand
