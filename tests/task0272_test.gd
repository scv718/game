extends SceneTree

## TASK-027-2 Dungeon Preparation / Validation 검증.
## - DungeonPreparation pure data: member 편성/중복 거부/snapshot 순수성 + Food/Potion/
##   Equipment 선택 hook(기존 설계에 필수 규칙이 없어 차단하지 않음).
## - DungeonPreparationService: dead/unavailable(expedition/active run)/duplicate member,
##   party min/max, dungeon 상태, party empty 등을 명확한 사유로 검증.
## - DungeonPreparationManager: create/clear preparation, add_member 즉시 거부,
##   validate, depart(valid party 출발 가능, invalid 출발 차단, 재진입 포함).
## - member availability: depart(IN_PROGRESS) 후 unavailable, run 종료(CLEARED) 후 복구.
## - DungeonPreparationUI: no-dungeon 표시, 위험도/보상 공개값, invalid 사유 명확 표시,
##   valid일 때만 Depart 활성화.
## - 회귀: TASK-027-1 dungeon 데이터/state 유지 + 기존 월드(floor/core/no player).

const DUNGEON_ID := "ne_ruins"

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
		print("TASK0272_RESULT=TIMEOUT")
		quit()
		return true
	if _frame != 20:
		return false
	_run_checks()
	print("TASK0272_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _has_issue(report: Dictionary, code: int) -> bool:
	for issue in report.get("issues", []):
		if int(issue.get("code", -1)) == code:
			return true
	return false


func _run_checks() -> void:
	var manager: Node = root.get_node_or_null("DungeonPreparationManager")
	_check(manager != null, "DungeonPreparationManager autoload registered")
	var dungeon_manager: Node = root.get_node_or_null("DungeonManager")
	_check(dungeon_manager != null, "DungeonManager autoload registered")
	var roster: Node = root.get_node_or_null("MercenaryRoster")
	_check(roster != null, "MercenaryRoster autoload registered")
	var main: Node = root.get_node("Main")
	_check(main != null, "main.tscn loads")

	var ui: Control = get_nodes_in_group("dungeon_preparation_ui")[0] as Control
	_check(ui != null and ui.visible == false, "preparation UI starts hidden")

	# --- UI no-dungeon 표시 (instance 없이 열기) ---
	ui.open()
	_check(ui.is_open() and ui._dungeon_info_label.text.contains("No dungeon discovered"), \
		"UI handles no-dungeon state")
	ui.close()

	# --- dungeon instance 확보 (TASK-027-1 재사용) ---
	var dungeon: DungeonDefinition = dungeon_manager.create_dungeon(DUNGEON_ID)
	_check(dungeon != null, "dungeon instance created")
	_check(int(dungeon.get_metadata()["required_party_min"]) == 2, "dungeon metadata party min 2")
	_check(int(dungeon.get_metadata()["required_party_max"]) == 4, "dungeon metadata party max 4")
	_check(int(dungeon.get_metadata()["risk"]) == 3, "dungeon metadata risk 3")

	# --- roster 용병 준비 ---
	var m_a := MercenaryData.new("merc_A", "Merc A", MercenaryData.MercClass.SWORDSMAN)
	var m_b := MercenaryData.new("merc_B", "Merc B", MercenaryData.MercClass.SWORDSMAN)
	var m_c := MercenaryData.new("merc_C", "Merc C", MercenaryData.MercClass.SWORDSMAN)
	var m_d := MercenaryData.new("merc_D", "Merc D", MercenaryData.MercClass.SWORDSMAN)
	var m_dead := MercenaryData.new("merc_dead", "Merc Dead", MercenaryData.MercClass.SWORDSMAN)
	_check(roster.add_mercenary(m_a), "roster add merc_A")
	_check(roster.add_mercenary(m_b), "roster add merc_B")
	_check(roster.add_mercenary(m_c), "roster add merc_C")
	_check(roster.add_mercenary(m_d), "roster add merc_D")
	_check(roster.add_mercenary(m_dead), "roster add merc_dead")
	m_dead.alive = false

	# --- DungeonPreparation pure data ---
	var pure := DungeonPreparation.new("pure_dungeon")
	_check(pure.get_class() == "RefCounted", "DungeonPreparation is pure RefCounted data")
	_check(pure.dungeon_id == "pure_dungeon", "dungeon_id retained")
	_check(pure.add_member("m1") and pure.add_member("m1") == false, "duplicate member rejected")
	_check(pure.add_member("") == false, "empty member id rejected")
	_check(pure.get_member_count() == 1 and pure.has_member("m1"), "member added")
	_check(pure.remove_member("m1") and pure.get_member_count() == 0, "member removed")
	_check(pure.remove_member("m1") == false, "removing missing member rejected")
	var ext_members := ["x"]
	pure.set_member_ids(ext_members)
	ext_members.append("MUTATED")
	_check(pure.get_member_count() == 1, "set_member_ids stores a copy")
	var fetched: Array = pure.get_member_ids()
	fetched.append("MUTATED")
	_check(not pure.has_member("MUTATED"), "get_member_ids returns a copy")
	# Food/Potion/Equipment 선택 hook (기존 설계에 필수 규칙이 없음)
	pure.set_food_slot("cooked_stew")
	_check(pure.get_food_slot() == "cooked_stew", "food slot hook set")
	pure.set_food_slot("")
	_check(pure.get_food_slot() == "", "food slot empty allowed (no mandatory rule)")
	pure.set_potion_slots(["hp_potion"])
	var fetched_potions: Array = pure.get_potion_slots()
	fetched_potions.append("MUTATED")
	_check(pure.get_potion_slots() == ["hp_potion"], "potion slots copy-protected")
	pure.set_potion_slots([])
	_check(pure.get_potion_slots().is_empty(), "empty potion slots allowed")
	pure.set_equipment_summary(["sword"])
	_check(pure.get_equipment_summary() == ["sword"], "equipment summary hook set")
	pure.set_equipment_summary([])
	_check(pure.get_equipment_summary().is_empty(), "empty equipment summary allowed")
	pure.add_member("m1")
	pure.set_food_slot("food")
	var snap: Dictionary = pure.to_snapshot()
	_check(_snapshot_is_pure(snap), "DungeonPreparation snapshot is pure save-safe")
	var restored := DungeonPreparation.from_snapshot(snap)
	_check(restored.dungeon_id == pure.dungeon_id \
		and restored.get_member_ids() == pure.get_member_ids() \
		and restored.get_food_slot() == pure.get_food_slot(), \
		"DungeonPreparation snapshot round-trip restores fields")

	# --- DungeonPreparationService 직접 검증 ---
	var prep := DungeonPreparation.new(DUNGEON_ID)
	var r_empty: Dictionary = DungeonPreparationService.validate(prep, dungeon, roster)
	_check(not r_empty["valid"] \
		and _has_issue(r_empty, DungeonPreparationService.IssueCode.PARTY_EMPTY), \
		"empty party invalid with clear reason")
	_check(r_empty["can_depart"] == false, "empty party cannot depart")
	prep.add_member("merc_A")
	var r_small: Dictionary = DungeonPreparationService.validate(prep, dungeon, roster)
	_check(not r_small["valid"] \
		and _has_issue(r_small, DungeonPreparationService.IssueCode.PARTY_TOO_SMALL), \
		"party below min rejected with clear reason")
	prep.add_member("merc_B")
	var r_ok: Dictionary = DungeonPreparationService.validate(prep, dungeon, roster)
	_check(r_ok["valid"] and r_ok["can_depart"], "valid 2-member party passes")
	_check(r_ok["valid"], "empty Food/Potion/Equipment does not block (design has no mandatory rule)")

	var prep_dead := DungeonPreparation.new(DUNGEON_ID)
	prep_dead.add_member("merc_dead")
	prep_dead.add_member("merc_A")
	var r_dead: Dictionary = DungeonPreparationService.validate(prep_dead, dungeon, roster)
	_check(not r_dead["valid"] \
		and _has_issue(r_dead, DungeonPreparationService.IssueCode.MEMBER_DEAD), \
		"dead member rejected with clear reason")

	var prep_missing := DungeonPreparation.new(DUNGEON_ID)
	prep_missing.add_member("merc_nonexistent")
	prep_missing.add_member("merc_A")
	var r_missing: Dictionary = DungeonPreparationService.validate(prep_missing, dungeon, roster)
	_check(not r_missing["valid"] \
		and _has_issue(r_missing, DungeonPreparationService.IssueCode.MEMBER_MISSING), \
		"member not in roster rejected with clear reason")

	# unavailable(expedition/active run)은 unavailable_ids로 거부한다.
	var prep_unavail := DungeonPreparation.new(DUNGEON_ID)
	prep_unavail.add_member("merc_C")
	prep_unavail.add_member("merc_A")
	var r_unavail: Dictionary = DungeonPreparationService.validate(
		prep_unavail, dungeon, roster, {"merc_C": "expedition_1"})
	_check(not r_unavail["valid"] \
		and _has_issue(r_unavail, DungeonPreparationService.IssueCode.MEMBER_UNAVAILABLE), \
		"member on expedition/active run rejected with clear reason")

	var prep_dup := DungeonPreparation.new(DUNGEON_ID)
	prep_dup.set_member_ids(["merc_A", "merc_A", "merc_B"])
	var r_dup: Dictionary = DungeonPreparationService.validate(prep_dup, dungeon, roster)
	_check(not r_dup["valid"] \
		and _has_issue(r_dup, DungeonPreparationService.IssueCode.MEMBER_DUPLICATE), \
		"duplicate member rejected with clear reason")

	var prep_large := DungeonPreparation.new(DUNGEON_ID)
	prep_large.set_member_ids(["merc_A", "merc_B", "merc_C", "merc_D", "merc_dead"])
	var r_large: Dictionary = DungeonPreparationService.validate(prep_large, dungeon, roster)
	_check(not r_large["valid"] \
		and _has_issue(r_large, DungeonPreparationService.IssueCode.PARTY_TOO_LARGE), \
		"party above max rejected with clear reason")

	# dungeon 상태: IN_PROGRESS / CLEARED는 준비 불가
	dungeon_manager.mark_ready(DUNGEON_ID)
	dungeon_manager.start_run(DUNGEON_ID)
	var r_inprogress: Dictionary = DungeonPreparationService.validate(prep, dungeon, roster)
	_check(not r_inprogress["valid"] \
		and _has_issue(r_inprogress, DungeonPreparationService.IssueCode.DUNGEON_NOT_PREPARABLE), \
		"IN_PROGRESS dungeon not preparable")
	dungeon_manager.complete_run(DUNGEON_ID)
	var r_cleared: Dictionary = DungeonPreparationService.validate(prep, dungeon, roster)
	_check(not r_cleared["valid"] \
		and _has_issue(r_cleared, DungeonPreparationService.IssueCode.DUNGEON_NOT_PREPARABLE), \
		"CLEARED dungeon not preparable")
	# 재진입 준비를 위해 CLEARED -> READY
	dungeon_manager.mark_ready(DUNGEON_ID)
	var r_ready: Dictionary = DungeonPreparationService.validate(prep, dungeon, roster)
	_check(r_ready["valid"] and r_ready["can_depart"], \
		"READY dungeon with valid party can depart")

	# --- DungeonPreparationManager 흐름 ---
	_check(manager.create_preparation(DUNGEON_ID), "create_preparation ok")
	_check(manager.create_preparation(DUNGEON_ID) == false, "duplicate preparation rejected")
	_check(manager.has_preparation(DUNGEON_ID) \
		and manager.get_preparation(DUNGEON_ID) != null, "preparation queryable")
	# invalid 파티(1명, min 2)는 depart 차단
	_check(manager.add_member(DUNGEON_ID, "merc_A")["ok"], "add_member merc_A ok")
	_check(manager.add_member(DUNGEON_ID, "merc_A")["ok"] == false, "duplicate add_member rejected")
	_check(str(manager.add_member(DUNGEON_ID, "merc_dead")["reason"]).contains("dead"), \
		"dead member add rejected with reason")
	var r_invalid: Dictionary = manager.validate(DUNGEON_ID)
	_check(not r_invalid["valid"], "manager validate invalid for 1-member party")
	var dep_invalid: Dictionary = manager.depart(DUNGEON_ID)
	_check(dep_invalid["ok"] == false, "invalid party depart blocked")
	_check(dungeon_manager.get_dungeon_state(DUNGEON_ID) == DungeonDefinition.DungeonState.READY, \
		"state unchanged after blocked depart")
	# valid 파티 완성 -> depart 성공
	_check(manager.add_member(DUNGEON_ID, "merc_B")["ok"], "add_member merc_B ok")
	var r_valid: Dictionary = manager.validate(DUNGEON_ID)
	_check(r_valid["valid"], "manager validate valid for 2-member party")
	var dep_ok: Dictionary = manager.depart(DUNGEON_ID)
	_check(dep_ok["ok"], "valid party departs")
	_check(dungeon_manager.get_dungeon_state(DUNGEON_ID) == DungeonDefinition.DungeonState.IN_PROGRESS, \
		"dungeon state IN_PROGRESS after depart")
	# depart된 member는 unavailable(active run/expedition 거부)
	var unavailable: Dictionary = manager.get_unavailable_member_ids()
	_check(unavailable.has("merc_A") and unavailable.has("merc_B"), \
		"departed members marked unavailable")
	_check(manager.add_member(DUNGEON_ID, "merc_A")["ok"] == false \
		and str(manager.add_member(DUNGEON_ID, "merc_A")["reason"]).contains("unavailable"), \
		"departed member add rejected as unavailable")
	# IN_PROGRESS 상태이므로 중복 depart 차단
	_check(manager.depart(DUNGEON_ID)["ok"] == false, "duplicate depart blocked during run")
	# run 종료(CLEARED) -> member availability 복구
	dungeon_manager.complete_run(DUNGEON_ID)
	_check(manager.get_unavailable_member_ids().is_empty(), \
		"members available again after run ends (CLEARED)")
	# 재진입: 종료된 run을 READY로 다시 연 뒤, clear 후 재편성 -> depart 성공
	dungeon_manager.mark_ready(DUNGEON_ID)
	manager.clear_preparation(DUNGEON_ID)
	_check(manager.has_preparation(DUNGEON_ID) == false, "clear_preparation ok")
	_check(manager.create_preparation(DUNGEON_ID), "re-create preparation for re-entry")
	_check(manager.add_member(DUNGEON_ID, "merc_A")["ok"], "re-entry add member A")
	_check(manager.add_member(DUNGEON_ID, "merc_C")["ok"], "re-entry add member C")
	var dep_reentry: Dictionary = manager.depart(DUNGEON_ID)
	_check(dep_reentry["ok"], "re-entry valid party departs")
	_check(dungeon_manager.get_dungeon_state(DUNGEON_ID) == DungeonDefinition.DungeonState.IN_PROGRESS, \
		"re-entry dungeon IN_PROGRESS")

	# --- UI: 위험도/보상/검증 표시 + Depart 동작 ---
	dungeon_manager.complete_run(DUNGEON_ID)
	dungeon_manager.mark_ready(DUNGEON_ID)
	manager.clear_preparation(DUNGEON_ID)
	manager.create_preparation(DUNGEON_ID)
	manager.add_member(DUNGEON_ID, "merc_A")
	ui.open_dungeon(DUNGEON_ID)
	_check(ui.is_open() and ui.visible, "preparation UI opens for dungeon")
	_check(ui._risk_label.text.contains("3"), "dungeon risk displayed")
	_check(ui._reward_label.text.contains("arcane_dust"), \
		"expected reward displayed (public values)")
	_check(ui._depart_button.disabled, "depart disabled for invalid (too small) party")
	_check(ui._status_label.text.contains("at least 2"), \
		"invalid party reason clearly displayed in UI")
	_check(ui._food_line.text == "", "food slot starts empty (optional)")
	ui._on_food_submitted("cooked_stew")
	_check(manager.get_preparation(DUNGEON_ID).get_food_slot() == "cooked_stew", \
		"food slot set via UI hook")
	manager.add_member(DUNGEON_ID, "merc_B")
	ui._refresh()
	_check(not ui._depart_button.disabled, "depart enabled once party valid")
	_check(ui._status_label.text.begins_with("VALID"), "UI status shows VALID")
	ui._on_depart_pressed()
	_check(dungeon_manager.get_dungeon_state(DUNGEON_ID) == DungeonDefinition.DungeonState.IN_PROGRESS, \
		"UI depart transitions dungeon to IN_PROGRESS")
	_check(ui._depart_button.text == "DEPARTED", "UI shows DEPARTED after departure")

	# --- 회귀 ---
	var reward_table: DungeonRewardTable = dungeon_manager.get_reward_table("ne_ruins_clear")
	_check(reward_table != null, "TASK-027-1 reward table preserved")
	_check(dungeon_manager.get_definition(DUNGEON_ID) != null, "TASK-027-1 definition preserved")
	var floor_node: TileMapLayer = main.get_node("World").get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() >= 128 * 128, \
		"TASK-012 world floor intact (>=128x128 cells)")
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")


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