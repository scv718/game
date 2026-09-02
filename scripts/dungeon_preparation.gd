extends RefCounted
class_name DungeonPreparation

## TASK-027-2 최소 DungeonPreparation(준비 데이터).
## Dungeon 출발 전 파티와 준비 자원 구성을 Runtime Actor와 분리해 보관하는 순수
## 데이터 클래스. Node/Actor/NodePath/Callable/SceneTree reference를 저장하지 않는다.
##
## member_ids는 순서를 유지한 채 파티 멤버(용병 identity id) 목록을 보관한다.
## Food/Supply, Potion, Equipment는 아직 런타임 시스템이 없는 data hook이다.
##  - food_slot_id: 용병 파티 공용 Food/Supply 슬롯(설계상 Food는 출발 전 장기 준비).
##  - potion_slot_ids: 파티 공용 Potion 슬롯 목록(설계상 전투 중 조건부 자동 사용).
##  - equipment_summary: 장비 요약 항목(String) 목록.
## 기존 설계에 필수 Food/Potion/Equipment 규칙이 없으므로 이 hook들은 모두 선택
## (미지정 허용)이며, 검증에서 차단하지 않는다. 신규 Food/Potion/Equipment 규칙은
## 발명하지 않는다. 실제 소비/효과 적용은 TASK-027-5부터 이 데이터를 읽어 별도 처리한다.

var dungeon_id: String = ""
## 순서 보장 파티 멤버 identity id 목록. 중복은 add_member에서 거부한다.
var member_ids: Array = []
## Food/Supply 슬롯 id. 미지정("") 허용.
var food_slot_id: String = ""
## Potion 슬롯 id 목록. 빈 배열 허용.
var potion_slot_ids: Array = []
## 장비 요약 항목 목록. 빈 배열 허용.
var equipment_summary: Array = []
var metadata: Dictionary = {}


func _init(p_dungeon_id: String = "") -> void:
	dungeon_id = p_dungeon_id


## --- 멤버 ---

func get_member_ids() -> Array:
	return member_ids.duplicate(true)


## 외부에서 원본 Array를 수정해도 내부 상태가 바뀌지 않게 복사본으로 저장한다.
func set_member_ids(ids: Array) -> void:
	member_ids = ids.duplicate(true)


func add_member(member_id: String) -> bool:
	if member_id.is_empty() or member_ids.has(member_id):
		return false
	member_ids.append(member_id)
	return true


func remove_member(member_id: String) -> bool:
	if not member_ids.has(member_id):
		return false
	member_ids.erase(member_id)
	return true


func clear_members() -> void:
	member_ids.clear()


func has_member(member_id: String) -> bool:
	return member_ids.has(member_id)


func get_member_count() -> int:
	return member_ids.size()


## --- Food/Supply ---

func set_food_slot(food_id: String) -> void:
	food_slot_id = food_id


func get_food_slot() -> String:
	return food_slot_id


## --- Potion ---

func set_potion_slots(ids: Array) -> void:
	potion_slot_ids = ids.duplicate(true)


func get_potion_slots() -> Array:
	return potion_slot_ids.duplicate(true)


func add_potion_slot(potion_id: String) -> bool:
	if potion_id.is_empty() or potion_slot_ids.has(potion_id):
		return false
	potion_slot_ids.append(potion_id)
	return true


## --- Equipment summary ---

func set_equipment_summary(values: Array) -> void:
	equipment_summary = values.duplicate(true)


func get_equipment_summary() -> Array:
	return equipment_summary.duplicate(true)


## --- metadata ---

func set_metadata(value: Dictionary) -> void:
	metadata = value.duplicate(true)


func get_metadata() -> Dictionary:
	return metadata.duplicate(true)


## 순수 snapshot(Dictionary)으로 직렬화한다. 모든 값은 기본 타입이며 Node/Actor
## reference를 포함하지 않는다. 컨테이너는 복사본으로 포함한다.
func to_snapshot() -> Dictionary:
	return {
		"dungeon_id": dungeon_id,
		"member_ids": member_ids.duplicate(true),
		"food_slot_id": food_slot_id,
		"potion_slot_ids": potion_slot_ids.duplicate(true),
		"equipment_summary": equipment_summary.duplicate(true),
		"metadata": metadata.duplicate(true),
	}


## snapshot(Dictionary)으로부터 preparation을 복원한다. 컨테이너는 복사본으로
## 참조해 원본을 수정해도 preparation 내부 상태가 바뀌지 않게 한다.
static func from_snapshot(snapshot: Dictionary) -> DungeonPreparation:
	var prep := DungeonPreparation.new(str(snapshot.get("dungeon_id", "")))
	var members: Variant = snapshot.get("member_ids", [])
	if typeof(members) == TYPE_ARRAY:
		prep.member_ids = (members as Array).duplicate(true)
	prep.food_slot_id = str(snapshot.get("food_slot_id", ""))
	var potions: Variant = snapshot.get("potion_slot_ids", [])
	if typeof(potions) == TYPE_ARRAY:
		prep.potion_slot_ids = (potions as Array).duplicate(true)
	var equipment: Variant = snapshot.get("equipment_summary", [])
	if typeof(equipment) == TYPE_ARRAY:
		prep.equipment_summary = (equipment as Array).duplicate(true)
	var meta: Variant = snapshot.get("metadata", {})
	if typeof(meta) == TYPE_DICTIONARY:
		prep.metadata = (meta as Dictionary).duplicate(true)
	return prep