extends RefCounted
class_name DungeonRewardTable

## TASK-027-1 최소 DungeonRewardTable (data-driven).
## Dungeon clear 보상 테이블의 최소 구조. 각 entry는
##   { "type": String, "id": String, "amount": int }
## 형태의 Dictionary며, 실제 지급 규칙/1회 보장/retreat·fail 정책은 TASK-027-7에서
## 이 데이터를 읽어 처리한다.
## Node/Actor reference를 저장하지 않는 순수 데이터 클래스다. 범용 Reward/Loot
## Framework를 도입하지 않는 최소 확장 지점이다.

var reward_table_id: String = ""
var entries: Array = []
var metadata: Dictionary = {}


func _init(p_reward_table_id: String = "") -> void:
	reward_table_id = p_reward_table_id


## entries는 mutable object이므로 복사본으로 저장/반환해 외부 수정을 격리한다.
func set_entries(values: Array) -> void:
	entries = values.duplicate(true)


func get_entries() -> Array:
	return entries.duplicate(true)


## 단일 entry 추가. Dictionary가 아니거나 "type"/"id" 키가 없으면 거부하고 false를
## 반환한다. amount가 없으면 0으로 보정한다.
func add_entry(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	var copy := (entry as Dictionary).duplicate(true)
	if not copy.has("type") or not copy.has("id"):
		return false
	if not copy.has("amount"):
		copy["amount"] = 0
	entries.append(copy)
	return true


func get_entry_count() -> int:
	return entries.size()


## metadata는 mutable object이므로 복사본으로 저장/반환한다.
func set_metadata(value: Dictionary) -> void:
	metadata = value.duplicate(true)


func get_metadata() -> Dictionary:
	return metadata.duplicate(true)


## 순수 snapshot(Dictionary)으로 직렬화한다. Node/Actor reference를 포함하지 않는다.
func to_snapshot() -> Dictionary:
	return {
		"reward_table_id": reward_table_id,
		"entries": entries.duplicate(true),
		"metadata": metadata.duplicate(true),
	}


## snapshot(Dictionary)으로부터 table을 복원한다. 컨테이너는 복사본으로 참조한다.
static func from_snapshot(snapshot: Dictionary) -> DungeonRewardTable:
	var table := DungeonRewardTable.new(str(snapshot.get("reward_table_id", "")))
	var values: Variant = snapshot.get("entries", [])
	if typeof(values) == TYPE_ARRAY:
		table.entries = (values as Array).duplicate(true)
	var meta: Variant = snapshot.get("metadata", {})
	if typeof(meta) == TYPE_DICTIONARY:
		table.metadata = (meta as Dictionary).duplicate(true)
	return table