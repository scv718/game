extends RefCounted
class_name DungeonDefinition

## TASK-027-1 최소 DungeonDefinition / Persistent Instance Data.
## 발견된 던전의 영속 데이터를 Runtime Combat Actor와 분리해 보관하는 순수 데이터 클래스.
## Node/Actor/NodePath/Callable/SceneTree reference를 저장하지 않으며, Encounter는
## encounter_ids(String) 목록으로, 보상은 reward_table_id(String)로만 참조한다.
## 상태 전환 정책(DISCOVERED/READY/IN_PROGRESS/CLEARED/FAILED)은 TASK-027-1
## DungeonManager가 담당하고, 실제 Dungeon Runtime/Combat Actor 생성은 TASK-027-3부터
## 이 데이터를 읽어 별도로 처리한다.
## 첫 vertical slice에서는 Dungeon 1종만 사용하며, procedural dungeon generator는
## 구현하지 않는다.

enum DungeonState { DISCOVERED, READY, IN_PROGRESS, CLEARED, FAILED }

const STATE_NAMES := {
	DungeonState.DISCOVERED: "DISCOVERED",
	DungeonState.READY: "READY",
	DungeonState.IN_PROGRESS: "IN_PROGRESS",
	DungeonState.CLEARED: "CLEARED",
	DungeonState.FAILED: "FAILED",
}

var dungeon_id: String = ""
var region_id: String = ""
var display_name: String = ""
var state: DungeonState = DungeonState.DISCOVERED
## difficulty/tier. 밸런스 확정 전까지는 정수 등급으로만 두고 수치는 DESIGN_TUNING.
var tier: int = 1
var encounter_ids: Array = []
var reward_table_id: String = ""
## clear 횟수. 1회성 여부는 one_shot hook으로 분리해 두었다.
var completion_count: int = 0
## 1회성 여부 hook. true면 첫 clear 이후 재진입을 허용하지 않는 의도로 사용할 수 있다.
## 실제 재진입 정책은 이후 태스크에서 정의한다.
var one_shot := false
## clear 시 Threat 감소/지연 hook. 0이면 보상 없음. 실제 적용은 TASK-028에서 한다.
var threat_reward: int = 0
var metadata: Dictionary = {}


func _init(p_dungeon_id: String = "") -> void:
	dungeon_id = p_dungeon_id


func get_state_name() -> String:
	return STATE_NAMES.get(state, "?")


## 상태 변경. 존재하지 않는 enum 값은 거부하고 false를 반환한다.
## 실제 전환 정책(잘못된 상태 도약 등)은 TASK-027-1 DungeonManager가 담당한다.
func set_state(value: int) -> bool:
	if value < DungeonState.DISCOVERED or value > DungeonState.FAILED:
		return false
	state = value
	return true


func get_state() -> DungeonState:
	return state


## encounter_ids는 mutable object이므로 복사본으로 저장/반환해 외부 수정을 격리한다.
func set_encounter_ids(ids: Array) -> void:
	encounter_ids = ids.duplicate(true)


func get_encounter_ids() -> Array:
	return encounter_ids.duplicate(true)


func add_encounter_id(encounter_id: String) -> bool:
	if encounter_id.is_empty() or encounter_ids.has(encounter_id):
		return false
	encounter_ids.append(encounter_id)
	return true


func has_encounter(encounter_id: String) -> bool:
	return encounter_ids.has(encounter_id)


## metadata는 mutable object이므로 복사본으로 저장/반환해 원본 Dictionary 수정이
## 내부 상태에 반영되지 않게 한다.
func set_metadata(value: Dictionary) -> void:
	metadata = value.duplicate(true)


func get_metadata() -> Dictionary:
	return metadata.duplicate(true)


## 순수 snapshot(Dictionary)으로 직렬화한다. 모든 값은 기본 타입이며 Node/Actor
## reference를 포함하지 않는다. 컨테이너는 복사본으로 포함한다.
func to_snapshot() -> Dictionary:
	return {
		"dungeon_id": dungeon_id,
		"region_id": region_id,
		"display_name": display_name,
		"state": state,
		"tier": tier,
		"encounter_ids": encounter_ids.duplicate(true),
		"reward_table_id": reward_table_id,
		"completion_count": completion_count,
		"one_shot": one_shot,
		"threat_reward": threat_reward,
		"metadata": metadata.duplicate(true),
	}


## snapshot(Dictionary)으로부터 dungeon을 복원한다. 컨테이너는 복사본으로 참조해
## 원본을 수정해도 dungeon 내부 상태가 바뀌지 않게 한다.
static func from_snapshot(snapshot: Dictionary) -> DungeonDefinition:
	var dungeon := DungeonDefinition.new(str(snapshot.get("dungeon_id", "")))
	dungeon.region_id = str(snapshot.get("region_id", ""))
	dungeon.display_name = str(snapshot.get("display_name", ""))
	dungeon.state = int(snapshot.get("state", DungeonState.DISCOVERED))
	dungeon.tier = int(snapshot.get("tier", 1))
	var encounters: Variant = snapshot.get("encounter_ids", [])
	if typeof(encounters) == TYPE_ARRAY:
		dungeon.encounter_ids = (encounters as Array).duplicate(true)
	dungeon.reward_table_id = str(snapshot.get("reward_table_id", ""))
	dungeon.completion_count = int(snapshot.get("completion_count", 0))
	dungeon.one_shot = bool(snapshot.get("one_shot", false))
	dungeon.threat_reward = int(snapshot.get("threat_reward", 0))
	var meta: Variant = snapshot.get("metadata", {})
	if typeof(meta) == TYPE_DICTIONARY:
		dungeon.metadata = (meta as Dictionary).duplicate(true)
	return dungeon
