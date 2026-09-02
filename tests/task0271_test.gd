extends SceneTree

## TASK-027-1 Dungeon Definition / Persistent Instance Data 검증.
## - DungeonManager autoload와 데이터 기반 정의/보상 테이블 등록 (Dungeon 1종).
## - DungeonDefinition 순수 데이터: 필드/state 이름/복사 보호/snapshot 순수성.
## - DungeonRewardTable data-driven 최소 구조.
## - create_dungeon 데이터 기반 생성/조회/중복 차단.
## - state 전환(DISCOVERED/READY/IN_PROGRESS/CLEARED/FAILED)과 completion_count 1회 증가.
## - Runtime Combat Actor reference 부재 (snapshot 순수성).
## - 기존 월드 회귀(floor/core buildings/no player) + Exploration region 유지.

const DUNGEON_ID := "ne_ruins"
const REGION_ID := "ne_dungeon"
const REWARD_TABLE_ID := "ne_ruins_clear"

var _frame := 0
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 1000:
		print("TASK0271_RESULT=TIMEOUT")
		quit()
		return true
	if _frame != 20:
		return false

	_run_checks()

	print("TASK0271_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _run_checks() -> void:
	var manager: Node = root.get_node_or_null("DungeonManager")
	_check(manager != null, "DungeonManager autoload registered")

	var main: Node = root.get_node("Main")
	_check(main != null, "main.tscn loads")

	# --- 데이터 기반 정의 등록 (Dungeon 1종) ---
	var definition: DungeonDefinition = manager.get_definition(DUNGEON_ID)
	_check(definition != null, "data-driven definition '%s' registered" % DUNGEON_ID)
	_check(manager.get_definition_ids() == [DUNGEON_ID], \
		"exactly one prototype dungeon definition registered")
	_check(definition.region_id == REGION_ID, "region_id linked to NE dungeon region")
	_check(definition.display_name == "NE Ruins", "display_name set")
	_check(definition.tier == 1, "tier defaults to 1")
	_check(definition.get_encounter_ids() == ["enc_ruins_gate"], \
		"encounter_ids data-driven")
	_check(definition.reward_table_id == REWARD_TABLE_ID, "reward_table_id referenced")
	_check(definition.one_shot == false, "one_shot hook default false")
	_check(definition.threat_reward == 2, "threat_reward hook set (2)")
	_check(definition.get_state() == DungeonDefinition.DungeonState.DISCOVERED \
		and definition.get_state_name() == "DISCOVERED", "definition starts DISCOVERED")
	_check(int(definition.get_metadata()["required_party_min"]) == 2, \
		"metadata party min carried")

	var reward_table: DungeonRewardTable = manager.get_reward_table(REWARD_TABLE_ID)
	_check(reward_table != null, "data-driven reward table '%s' registered" % REWARD_TABLE_ID)
	_check(manager.get_reward_table_ids() == [REWARD_TABLE_ID], \
		"exactly one prototype reward table registered")
	_check(reward_table.get_entry_count() == 2, "reward table has 2 entries")
	_check(String(reward_table.get_entries()[0]["type"]) == "material" \
		and String(reward_table.get_entries()[0]["id"]) == "arcane_dust" \
		and int(reward_table.get_entries()[0]["amount"]) == 3, \
		"entry[0] type/id/amount readable")

	# --- DungeonDefinition 순수 데이터 검증 (Manager와 독립) ---
	var pure := DungeonDefinition.new("pure_test")
	_check(pure.get_class() == "RefCounted", "DungeonDefinition is pure RefCounted data")
	_check(pure.dungeon_id == "pure_test", "dungeon_id retained")
	_check(pure.get_state_name() == "DISCOVERED", "default state name 'DISCOVERED'")
	_check(pure.set_state(-1) == false and pure.set_state(99) == false, \
		"invalid state enum rejected")
	_check(pure.get_state() == DungeonDefinition.DungeonState.DISCOVERED, \
		"state unchanged after rejected set")
	_check(pure.add_encounter_id("") == false, "empty encounter_id rejected")
	_check(pure.add_encounter_id("enc_a") and pure.add_encounter_id("enc_a") == false, \
		"duplicate encounter_id rejected")
	var ext_encounters := ["enc_x"]
	pure.set_encounter_ids(ext_encounters)
	ext_encounters.append("MUTATED")
	_check(not pure.has_encounter("MUTATED"), \
		"set_encounter_ids stores a copy (external mutation isolated)")
	var fetched: Array = pure.get_encounter_ids()
	fetched.append("MUTATED")
	_check(not pure.has_encounter("MUTATED"), \
		"get_encounter_ids returns a copy (internal state protected)")
	var ext_meta := {"risk": 3}
	pure.set_metadata(ext_meta)
	ext_meta["risk"] = 999
	_check(int(pure.get_metadata()["risk"]) == 3, "set_metadata stores a copy")
	var fetched_meta: Dictionary = pure.get_metadata()
	fetched_meta["injected"] = true
	_check(pure.get_metadata().has("injected") == false, \
		"get_metadata returns a copy (internal state protected)")

	# --- DungeonRewardTable data-driven 최소 구조 ---
	var pure_table := DungeonRewardTable.new("pure_table")
	_check(pure_table.add_entry({"type": "material", "id": "wood", "amount": 5}), \
		"valid entry accepted")
	_check(pure_table.add_entry({"type": "material", "id": "no_amount"}) \
		and int(pure_table.get_entries()[1]["amount"]) == 0, \
		"missing amount defaults to 0")
	_check(pure_table.add_entry({"id": "missing_type"}) == false, \
		"entry without type rejected")
	_check(pure_table.add_entry({"type": "x"}) == false, \
		"entry without id rejected")
	_check(pure_table.add_entry("not_a_dict") == false, "non-dictionary entry rejected")
	var ext_entries := [{"type": "a", "id": "b", "amount": 1}]
	pure_table.set_entries(ext_entries)
	ext_entries.append({"type": "a", "id": "MUTATED", "amount": 1})
	_check(pure_table.get_entry_count() == 1, \
		"set_entries stores a copy (external mutation isolated)")

	# --- snapshot 순수성 (Actor/Node reference 없음) ---
	var snap := pure.to_snapshot()
	_check(_snapshot_is_pure(snap), "DungeonDefinition snapshot is pure save-safe")
	var restored := DungeonDefinition.from_snapshot(snap)
	_check(restored.dungeon_id == pure.dungeon_id \
		and restored.get_state() == pure.get_state() \
		and restored.get_encounter_ids() == pure.get_encounter_ids(), \
		"DungeonDefinition snapshot round-trip restores fields")
	snap["injected"] = true
	_check(pure.to_snapshot().has("injected") == false, \
		"to_snapshot returns an independent copy")
	var table_snap := pure_table.to_snapshot()
	_check(_snapshot_is_pure(table_snap), "DungeonRewardTable snapshot is pure save-safe")
	var table_restored := DungeonRewardTable.from_snapshot(table_snap)
	_check(table_restored.reward_table_id == pure_table.reward_table_id \
		and table_restored.get_entry_count() == pure_table.get_entry_count(), \
		"DungeonRewardTable snapshot round-trip restores fields")

	# --- create_dungeon: 데이터 기반 생성/조회/중복 차단 ---
	_check(manager.has_dungeon(DUNGEON_ID) == false, "no instance before create")
	var instance: DungeonDefinition = manager.create_dungeon(DUNGEON_ID)
	_check(instance != null, "create_dungeon instantiates from definition")
	_check(manager.create_dungeon(DUNGEON_ID) == null, \
		"duplicate create_dungeon rejected")
	_check(manager.create_dungeon("unknown_dungeon") == null, \
		"create_dungeon for unknown id rejected")
	_check(manager.get_dungeon(DUNGEON_ID) == instance, "get_dungeon returns instance")
	_check(instance.get_state() == DungeonDefinition.DungeonState.DISCOVERED, \
		"instance starts DISCOVERED")
	_check(instance.completion_count == 0, "instance completion_count starts 0")
	_check(instance.get_encounter_ids() == ["enc_ruins_gate"], \
		"instance carries encounter_ids from definition")
	_check(instance.reward_table_id == REWARD_TABLE_ID, "instance carries reward_table_id")
	_check(manager.get_dungeons() == [instance], "get_dungeons returns instance list")
	_check(manager.get_active_dungeons() == [instance], \
		"instance is active before terminal state")
	_check(manager.get_dungeon_state(DUNGEON_ID) == DungeonDefinition.DungeonState.DISCOVERED, \
		"get_dungeon_state returns DISCOVERED")
	_check(manager.get_threat_reward(DUNGEON_ID) == 2, \
		"get_threat_reward returns instance hook")
	_check(manager.get_reward_table_for_dungeon(DUNGEON_ID) == reward_table, \
		"reward table resolved through instance reward_table_id")
	_check(manager.get_dungeon_state("missing") == -1, "unknown dungeon state is -1")
	_check(manager.get_completion_count("missing") == 0, \
		"unknown dungeon completion_count is 0")

	# --- state 전환 정책 ---
	_check(manager.set_dungeon_state(DUNGEON_ID, DungeonDefinition.DungeonState.IN_PROGRESS) == false, \
		"DISCOVERED -> IN_PROGRESS rejected")
	_check(manager.set_dungeon_state(DUNGEON_ID, DungeonDefinition.DungeonState.CLEARED) == false, \
		"DISCOVERED -> CLEARED rejected")
	_check(manager.set_dungeon_state(DUNGEON_ID, -1) == false, \
		"invalid state rejected at manager level")
	_check(manager.mark_ready(DUNGEON_ID), "DISCOVERED -> READY accepted")
	_check(instance.get_state_name() == "READY", "instance state is READY")
	_check(manager.mark_ready(DUNGEON_ID) == false, "READY -> READY rejected")
	_check(manager.complete_run(DUNGEON_ID) == false, "READY -> CLEARED rejected")
	_check(manager.start_run(DUNGEON_ID), "READY -> IN_PROGRESS accepted")
	_check(manager.start_run(DUNGEON_ID) == false, "IN_PROGRESS -> IN_PROGRESS rejected")
	_check(manager.complete_run(DUNGEON_ID), "IN_PROGRESS -> CLEARED accepted")
	_check(instance.get_state_name() == "CLEARED", "instance state is CLEARED")
	_check(manager.get_completion_count(DUNGEON_ID) == 1, \
		"completion_count incremented exactly once on clear")
	_check(manager.complete_run(DUNGEON_ID) == false, "CLEARED -> CLEARED rejected")
	_check(manager.get_completion_count(DUNGEON_ID) == 1, \
		"repeated complete does not duplicate completion_count")
	_check(manager.get_active_dungeons().is_empty(), \
		"CLEARED instance no longer active")
	_check(manager.mark_ready(DUNGEON_ID), "CLEARED -> READY re-entry accepted")
	_check(manager.start_run(DUNGEON_ID), "re-entry READY -> IN_PROGRESS accepted")
	_check(manager.fail_run(DUNGEON_ID), "IN_PROGRESS -> FAILED accepted")
	_check(instance.get_state_name() == "FAILED", "instance state is FAILED")
	_check(manager.fail_run(DUNGEON_ID) == false, "FAILED -> FAILED rejected")
	_check(manager.mark_ready(DUNGEON_ID), "FAILED -> READY re-entry accepted")
	_check(manager.start_run(DUNGEON_ID), "second re-entry READY -> IN_PROGRESS accepted")
	_check(manager.complete_run(DUNGEON_ID), "second clear accepted")
	_check(manager.get_completion_count(DUNGEON_ID) == 2, \
		"second clear increments completion_count again")
	_check(manager.get_reward_table_for_dungeon(DUNGEON_ID) == reward_table, \
		"reward table still resolved after repeated runs")

	# --- instance 전환 후에도 데이터 기반 정의(템플릿)는 무손상 ---
	var template: DungeonDefinition = manager.get_definition(DUNGEON_ID)
	_check(template.get_state() == DungeonDefinition.DungeonState.DISCOVERED \
		and template.completion_count == 0, \
		"data-driven definition template unchanged by instance transitions")

	# --- 회귀: 기존 월드 구조 + Exploration 유지 ---
	var floor_node: TileMapLayer = main.get_node("World").get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() >= 128 * 128, \
		"TASK-012 world floor intact (>=128x128 cells)")
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
	var explorer: Node = root.get_node_or_null("ExplorationManager")
	_check(explorer != null and explorer.get_region(REGION_ID) != null, \
		"ExplorationManager/NE dungeon region preserved")


func _snapshot_is_pure(snap: Dictionary) -> bool:
	var valid_types := [
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
		TYPE_VECTOR2, TYPE_RECT2, TYPE_DICTIONARY, TYPE_ARRAY,
	]
	for key in snap.keys():
		if typeof(snap[key]) not in valid_types:
			return false
	return true


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)