extends RefCounted
class_name DeathRecord

## TASK-016-1 최소 DeathRecord Data Model.
## 실제 lethal 전투에서 사망한 존재의 정체성과 Ghost Return에 필요한 정보를
## Actor 생명주기와 독립된 snapshot으로 저장하는 순수 데이터 클래스.
## Actor/Node reference, NodePath/Callable/SceneTree reference, temporary combat
## state를 저장하지 않는다. 사망 시점 값을 copy/snapshot해 원본 Actor가
## despawn/free되어도 record는 유지된다.
## 상태 전환(PENDING/ACTIVE/RESOLVED)과 record 생성/조회는 TASK-016-2 DeathLedger가
## 담당하고, 실제 Ghost Return은 TASK-017에서 구현한다.

enum SourceKind { MERCENARY, ENEMY }

## 사망 시점 phase. GameTime.Phase와 동일한 값(DAY=0, NIGHT=1)을 사용하되
## DeathRecord가 GameTime autoload에 의존하지 않도록 자체 enum으로 가진다.
enum DeathPhase { DAY, NIGHT }

enum Status { PENDING, ACTIVE, RESOLVED }

const SOURCE_KIND_NAMES := {
	SourceKind.MERCENARY: "MERCENARY",
	SourceKind.ENEMY: "ENEMY",
}

const DEATH_PHASE_NAMES := {
	DeathPhase.DAY: "DAY",
	DeathPhase.NIGHT: "NIGHT",
}

const STATUS_NAMES := {
	Status.PENDING: "PENDING",
	Status.ACTIVE: "ACTIVE",
	Status.RESOLVED: "RESOLVED",
}

var record_id: String = ""
var source_uid: String = ""
var source_kind: SourceKind = SourceKind.MERCENARY
var display_name: String = ""
var class_or_type: String = ""
var level: int = 1
var max_hp: int = 0
var attack_damage: int = 0
var attack_interval: float = 1.0
var move_speed: float = 0.0
var death_day: int = 1
var death_phase: DeathPhase = DeathPhase.NIGHT
var death_position := Vector2.ZERO
var status: Status = Status.PENDING
var eligible_day: int = 0
var resolved_day: int = 0
var metadata: Dictionary = {}


func _init(p_record_id: String = "") -> void:
	record_id = p_record_id


func get_source_kind_name() -> String:
	return SOURCE_KIND_NAMES.get(source_kind, "?")


func get_death_phase_name() -> String:
	return DEATH_PHASE_NAMES.get(death_phase, "?")


func get_status_name() -> String:
	return STATUS_NAMES.get(status, "?")


## TASK-016-1: 상태 변경. 존재하지 않는 enum 값은 거부하고 false를 반환한다.
## 실제 전환 정책(RESOLVED 보호 등)은 TASK-016-2 DeathLedger가 담당한다.
func set_status(value: int) -> bool:
	if value < Status.PENDING or value > Status.RESOLVED:
		return false
	status = value
	return true


func get_status() -> Status:
	return status


## metadata는 mutable object이므로 외부에서 원본 Dictionary를 수정해도 record 내부
## 상태가 바뀌지 않게 복사본으로 저장한다.
func set_metadata(value: Dictionary) -> void:
	metadata = value.duplicate(true)


## metadata를 외부에 넘길 때에도 복사본을 반환해 record 내부 상태를 우회 변경할 수
## 없게 한다.
func get_metadata() -> Dictionary:
	return metadata.duplicate(true)


## TASK-016-1: 순수 snapshot(Dictionary)으로 직렬화한다. 모든 값은 기본 타입/
## Vector2이며 Node reference를 포함하지 않는다. metadata는 복사본으로 포함한다.
func to_snapshot() -> Dictionary:
	return {
		"record_id": record_id,
		"source_uid": source_uid,
		"source_kind": source_kind,
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
		"status": status,
		"eligible_day": eligible_day,
		"resolved_day": resolved_day,
		"metadata": metadata.duplicate(true),
	}


## snapshot(Dictionary)으로부터 record를 복원한다. metadata는 복사본으로 참조해
## 원본 Dictionary를 수정해도 record 내부 상태가 바뀌지 않게 한다.
static func from_snapshot(snapshot: Dictionary) -> DeathRecord:
	var record := DeathRecord.new(str(snapshot.get("record_id", "")))
	record.source_uid = str(snapshot.get("source_uid", ""))
	record.source_kind = int(snapshot.get("source_kind", SourceKind.MERCENARY))
	record.display_name = str(snapshot.get("display_name", ""))
	record.class_or_type = str(snapshot.get("class_or_type", ""))
	record.level = int(snapshot.get("level", 1))
	record.max_hp = int(snapshot.get("max_hp", 0))
	record.attack_damage = int(snapshot.get("attack_damage", 0))
	record.attack_interval = float(snapshot.get("attack_interval", 1.0))
	record.move_speed = float(snapshot.get("move_speed", 0.0))
	record.death_day = int(snapshot.get("death_day", 1))
	record.death_phase = int(snapshot.get("death_phase", DeathPhase.NIGHT))
	record.death_position = Vector2(snapshot.get("death_position", Vector2.ZERO))
	record.status = int(snapshot.get("status", Status.PENDING))
	record.eligible_day = int(snapshot.get("eligible_day", 0))
	record.resolved_day = int(snapshot.get("resolved_day", 0))
	var source: Variant = snapshot.get("metadata", {})
	if typeof(source) == TYPE_DICTIONARY:
		record.metadata = (source as Dictionary).duplicate(true)
	return record