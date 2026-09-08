extends Node

## TASK-027-1 최소 DungeonManager(autoload).
## DungeonDefinition / DungeonRewardTable 데이터 기반 정의를 등록하고, Dungeon
## instance를 생성/조회/state 전환하는 persistent owner다.
## Runtime Combat Actor reference를 저장하지 않는다. Encounter 실행/Combat Actor는
## TASK-027-3/027-4에서 이 instance 데이터를 읽어 Runtime에 별도로 생성한다.
## 첫 vertical slice는 Dungeon 1종만 등록한다. 확정되지 않은 procedural dungeon
## generator는 구현하지 않는다.
##
## state 전환 정책:
##   DISCOVERED -> READY
##   READY      -> IN_PROGRESS
##   IN_PROGRESS-> CLEARED / FAILED
##   CLEARED    -> READY (재진입)
##   FAILED     -> READY (재진입)
## CLEARED 전환 1회마다 completion_count를 정확히 1회 증가한다.
## threat_reward 값은 clear 시 Threat 감소/지연 hook이며 실제 적용은 TASK-028에서 한다.
##
## V3-005 Food Preparation & Expedition Effect Contract
## - Dungeon run start 및 complete 시 VillageResources의 food 사용량 결정
## - Food preparation-only role은 유지
## - Potion runtime auto-consume behavior 은 그대로 유지

const PROTOTYPE_REWARD_TABLES := [
	{
		"reward_table_id": "ne_ruins_clear",
		"entries": [
			{"type": "material", "id": "arcane_dust", "amount": 3},
			{"type": "potion_material", "id": "ghost_essence", "amount": 1},
		],
	},
]

const PROTOTYPE_DEFINITIONS := [
	{
		"dungeon_id": "ne_ruins",
		"region_id": "ne_dungeon",
		"display_name": "NE Ruins",
		"tier": 1,
		"encounter_ids": ["enc_ruins_gate"],
		"reward_table_id": "ne_ruins_clear",
		"one_shot": false,
		"threat_reward": 2,
		"metadata": {
			"required_party_min": 2,
			"required_party_max": 4,
			"risk": 3,
		},
	},
]

const ALLOWED_TRANSITIONS := {
	DungeonDefinition.DungeonState.DISCOVERED: [
		DungeonDefinition.DungeonState.READY,
	],
	DungeonDefinition.DungeonState.READY: [
		DungeonDefinition.DungeonState.IN_PROGRESS,
	],
	DungeonDefinition.DungeonState.IN_PROGRESS: [
		DungeonDefinition.DungeonState.CLEARED,
		DungeonDefinition.DungeonState.FAILED,
	],
	DungeonDefinition.DungeonState.CLEARED: [
		DungeonDefinition.DungeonState.READY,
	],
	DungeonDefinition.DungeonState.FAILED: [
		DungeonDefinition.DungeonState.READY,
	],
}

var _definitions: Dictionary = {}
var _instances: Dictionary = {}
var _reward_tables: Dictionary = {}


func _ready() -> void:
	_register_prototype_data()


## --- 데이터 기반 정의 등록 ---

func register_definition(definition: DungeonDefinition) -> bool:
	if definition == null or definition.dungeon_id.is_empty():
		return false
	if _definitions.has(definition.dungeon_id):
		return false
	_definitions[definition.dungeon_id] = definition
	return true


func get_definition(dungeon_id: String) -> DungeonDefinition:
	return _definitions.get(dungeon_id)


func get_definition_ids() -> Array:
	return _definitions.keys()


func register_reward_table(table: DungeonRewardTable) -> bool:
	if table == null or table.reward_table_id.is_empty():
		return false
	if _reward_tables.has(table.reward_table_id):
		return false
	_reward_tables[table.reward_table_id] = table
	return true


func get_reward_table(reward_table_id: String) -> DungeonRewardTable:
	return _reward_tables.get(reward_table_id)


func get_reward_table_ids() -> Array:
	return _reward_tables.keys()


## --- instance 생성 / 조회 ---

## 데이터 기반 정의를 snapshot으로 복사해 새 Dungeon instance를 생성한다.
## 중복 dungeon_id 또는 미등록 dungeon_id는 null을 반환한다.
func create_dungeon(dungeon_id: String) -> DungeonDefinition:
	if dungeon_id.is_empty() or _instances.has(dungeon_id):
		return null
	var definition: DungeonDefinition = _definitions.get(dungeon_id)
	if definition == null:
		return null
	var instance := DungeonDefinition.from_snapshot(definition.to_snapshot())
	instance.state = DungeonDefinition.DungeonState.DISCOVERED
	instance.completion_count = 0
	_instances[dungeon_id] = instance
	return instance


func get_dungeon(dungeon_id: String) -> DungeonDefinition:
	return _instances.get(dungeon_id)


func has_dungeon(dungeon_id: String) -> bool:
	return _instances.has(dungeon_id)


func get_dungeons() -> Array:
	return _instances.values()


## terminal(CLEARED/FAILED)이 아닌 instance 목록.
func get_active_dungeons() -> Array:
	var active: Array = []
	for dungeon in _instances.values():
		if dungeon.state != DungeonDefinition.DungeonState.CLEARED \
			and dungeon.state != DungeonDefinition.DungeonState.FAILED:
			active.append(dungeon)
	return active


## --- state 전환 ---

func set_dungeon_state(dungeon_id: String, new_state: int) -> bool:
	var dungeon: DungeonDefinition = _instances.get(dungeon_id)
	if dungeon == null:
		return false
	if not _can_transition(dungeon.state, new_state):
		return false
	if new_state == DungeonDefinition.DungeonState.CLEARED:
		dungeon.completion_count += 1
	dungeon.set_state(new_state)
	return true


func mark_ready(dungeon_id: String) -> bool:
	return set_dungeon_state(dungeon_id, DungeonDefinition.DungeonState.READY)


func start_run(dungeon_id: String) -> bool:
	# V3-005: Consume food from VillageResources when dungeon run begins
	var vr := get_node_or_null("/root/VillageResources")
	if vr != null and vr.has_method("get_food_count"):
		var prep := DungeonPreparationManager.get_preparation(dungeon_id)
		if prep != null:
			var food_id := prep.get_food_slot()
			if not food_id.is_empty():
				# Consume one unit of the selected food
				vr.remove_food(food_id, 1)
	
	return set_dungeon_state(dungeon_id, DungeonDefinition.DungeonState.IN_PROGRESS)


func complete_run(dungeon_id: String) -> bool:
	# V3-005: Return food to VillageResources when dungeon run completes
	var vr := get_node_or_null("/root/VillageResources")
	if vr != null and vr.has_method("get_food_count"):
		var prep := DungeonPreparationManager.get_preparation(dungeon_id)
		if prep != null:
			var food_id := prep.get_food_slot()
			if not food_id.is_empty():
				# Return one unit of the selected food (this is not a direct consumption but 
				# an effect of completing the expedition, so we just return it to stock)
				vr.add_food(food_id, 1)
	
	return set_dungeon_state(dungeon_id, DungeonDefinition.DungeonState.CLEARED)


func fail_run(dungeon_id: String) -> bool:
	return set_dungeon_state(dungeon_id, DungeonDefinition.DungeonState.FAILED)


## 존재하지 않거나 생성되지 않은 dungeon은 -1을 반환한다.
func get_dungeon_state(dungeon_id: String) -> int:
	var dungeon: DungeonDefinition = _instances.get(dungeon_id)
	if dungeon == null:
		return -1
	return dungeon.state


func get_completion_count(dungeon_id: String) -> int:
	var dungeon: DungeonDefinition = _instances.get(dungeon_id)
	if dungeon == null:
		return 0
	return dungeon.completion_count


func get_threat_reward(dungeon_id: String) -> int:
	var dungeon: DungeonDefinition = _instances.get(dungeon_id)
	if dungeon != null:
		return dungeon.threat_reward
	var definition: DungeonDefinition = _definitions.get(dungeon_id)
	if definition == null:
		return 0
	return definition.threat_reward


func get_reward_table_for_dungeon(dungeon_id: String) -> DungeonRewardTable:
	var dungeon: DungeonDefinition = _instances.get(dungeon_id)
	if dungeon == null:
		return null
	return _reward_tables.get(dungeon.reward_table_id)


func _can_transition(from_state: int, to_state: int) -> bool:
	var allowed: Array = ALLOWED_TRANSITIONS.get(from_state, [])
	return allowed.has(to_state)


## 첫 vertical slice 데이터 등록. 값은 prototype이며 밸런스 수치는 DESIGN_TUNING.
func _register_prototype_data() -> void:
	for table_data in PROTOTYPE_REWARD_TABLES:
		var table := DungeonRewardTable.new(str(table_data.get("reward_table_id", "")))
		table.set_entries(table_data.get("entries", []))
		register_reward_table(table)

	for def_data in PROTOTYPE_DEFINITIONS:
		var definition := DungeonDefinition.new(str(def_data.get("dungeon_id", "")))
		definition.region_id = str(def_data.get("region_id", ""))
		definition.display_name = str(def_data.get("display_name", ""))
		definition.tier = int(def_data.get("tier", 1))
		definition.set_encounter_ids(def_data.get("encounter_ids", []))
		definition.reward_table_id = str(def_data.get("reward_table_id", ""))
		definition.one_shot = bool(def_data.get("one_shot", false))
		definition.threat_reward = int(def_data.get("threat_reward", 0))
		definition.set_metadata(def_data.get("metadata", {}))
		register_definition(definition)
