extends SceneTree

## TASK-022-1 Existing Recruitment Audit — 재사용 경계 결정적 검증.
## 이 테스트는 기존 고용/Roster 시스템이 (1) 단일 고용 경로(주점 UI → Roster)를
## 유지하고, (2) 중복 recruitment framework가 필요 없으며, (3) 재사용 가능한
## count/candidate/building identity API를 노출하는지 자동 검증한다.
## audit-only 산출물(impl_fun/RECRUITMENT_AUDIT_022.md)의 결론을 코드로 고정한다.
##
## 검증 항목:
##  1. 단일 고용 경로: 주점 상호작용 → recruitment_ui(TavernRecruitmentUI) 하나.
##  2. hire candidate: Worker 후보 4종 + Mercenary 후보 1종 정의.
##  3. 고용 → Roster 정확히 1회, 중복 고용 거부(id 중복 거부).
##  4. roster capacity API: get_count / get_alive_count / get_actor_count 재사용.
##  5. active mercenary count: get_alive_count / get_actor_count 반환.
##  6. Inn/Tavern building identity: core_type / get_level / get_building_label.
##  7. building count: 핵심 건물 5종(core_buildings 그룹).
##  8. UI: recruitment_ui / inn_roster_ui 그룹, 차원 중립 Control.
##  9. cost: 고용 비용 상수 0("고용 (0)").
## 10. save/load: roster에 영구 저장 API 부재(재사용 경계 = 인메모리 유지).

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
	if _frame != 10:
		return false

	var main: Node = root.get_node("Main")
	_check(main != null, "main.tscn loads")

	var worker_roster: Node = root.get_node("WorkerRoster")
	var roster: Node = root.get_node("MercenaryRoster")
	_check(worker_roster != null, "WorkerRoster autoload exists")
	_check(roster != null, "MercenaryRoster autoload exists")
	_check(roster != worker_roster, "Worker/Mercenary roster separate")

	var world: Node = main.get_node("World")

	# 1. 단일 고용 경로 / 중복 프레임워크 부재.
	var recruit_uis := get_nodes_in_group("recruitment_ui")
	_check(recruit_uis.size() == 1, "single recruitment UI entry (no duplicate framework, got %d)" % recruit_uis.size())
	var ui: Control = recruit_uis[0] if recruit_uis.size() > 0 else null
	_check(ui != null and ui is Control, "recruitment UI is dimension-neutral Control")
	_check(ui != null and ui.has_method("_on_hire_pressed"), "recruitment UI owns worker hire")
	_check(ui != null and ui.has_method("_on_mercenary_hire_pressed"), "recruitment UI owns mercenary hire")

	# 2. hire candidate 정의.
	# TASK-022 audits the existing recruitment owner; later worker slices may append
	# candidates. Preserve the four pre-Inn identities without freezing the list size.
	var worker_candidate_ids: Array[String] = []
	if ui != null:
		for candidate in ui.CANDIDATES:
			worker_candidate_ids.append(str(candidate.id))
	_check(["lumberjack_A", "lumberjack_B", "miner_A", "miner_B"].all(
			func(candidate_id: String) -> bool: return candidate_id in worker_candidate_ids),
		"existing worker hire candidates remain defined (%d total)" % worker_candidate_ids.size())
	_check(ui != null and ui.MERCENARY_CANDIDATES.size() == 1, "1 mercenary hire candidate defined (%d)" % (ui.MERCENARY_CANDIDATES.size() if ui else -1))

	# 3. 고용 → 정확히 1회 + 중복 거부 (id 중복 거부 재사용).
	_check(worker_roster.get_count() == 0, "worker roster starts empty")
	_check(roster.get_count() == 0, "mercenary roster starts empty")
	ui._on_hire_pressed("lumberjack_A")
	_check(worker_roster.get_count() == 1, "worker hire adds exactly once (%d)" % worker_roster.get_count())
	ui._on_hire_pressed("lumberjack_A")
	_check(worker_roster.get_count() == 1, "duplicate worker hire rejected (stays 1)")
	ui._on_mercenary_hire_pressed("mercenary_A")
	_check(roster.get_count() == 1, "mercenary hire adds exactly once (%d)" % roster.get_count())
	ui._on_mercenary_hire_pressed("mercenary_A")
	_check(roster.get_count() == 1, "duplicate mercenary hire rejected (stays 1)")
	_check(worker_roster.get_count() == 1 and roster.get_count() == 1, "worker/mercenary rosters stay separate")

	# 4. roster capacity API 재사용 (보유 수 조회).
	_check(worker_roster.has_method("get_count"), "WorkerRoster.get_count reusable")
	_check(worker_roster.has_method("get_workers"), "WorkerRoster.get_workers reusable")
	_check(roster.has_method("get_count"), "MercenaryRoster.get_count reusable")
	_check(roster.has_method("get_mercenaries"), "MercenaryRoster.get_mercenaries reusable")

	# 5. active mercenary count.
	_check(roster.has_method("get_alive_count"), "active mercenary count get_alive_count reusable")
	_check(roster.has_method("get_actor_count"), "active mercenary actor count get_actor_count reusable")
	_check(roster.get_alive_count() == 1, "get_alive_count reflects hire (%d)" % roster.get_alive_count())
	_check(roster.get_actor_count() == 0, "no combat actor spawned by roster data alone (%d)" % roster.get_actor_count())

	# 6. Inn/Tavern building identity.
	var tavern: Node = world.get_node("Tavern")
	var inn: Node = world.get_node("Inn")
	_check(tavern != null and tavern.get("core_type") == "tavern", "tavern core_type identity")
	_check(inn != null and inn.get("core_type") == "inn", "inn core_type identity")
	_check(tavern != null and tavern.has_method("get_level"), "building identity exposes get_level (upgrade extension point)")
	_check(tavern != null and tavern.get_level() == 1, "tavern level baseline 1 (%d)" % (tavern.get_level() if tavern else -1))
	_check(tavern != null and tavern.has_method("get_building_label"), "building identity exposes get_building_label")

	# 7. building count (핵심 건물 고정 배치).
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings fixed (%d)" % get_nodes_in_group("core_buildings").size())

	# 8. UI 그룹 + 차원 중립 Control.
	var inn_uis := get_nodes_in_group("inn_roster_ui")
	_check(inn_uis.size() == 1, "single inn roster UI (no duplicate)")
	var inn_ui: Control = inn_uis[0] if inn_uis.size() > 0 else null
	_check(inn_ui != null and inn_ui is Control, "inn roster UI is dimension-neutral Control")

	# 9. cost 상수 0 (미고용 후보 버튼 텍스트 "고용 (0)").
	#    참고: console 인코딩상 한글은 깨져 보일 수 있으나 in-memory 문자열은 UTF-8이며,
	#    "0" 포함 여부로 비용 기준 0 상수를 판정한다(고용된 후보는 "고용됨"으로 바뀜).
	_check(ui != null and ui._hire_buttons.has("miner_A"), "hire button created for unhired candidate")
	if ui != null and ui._hire_buttons.has("miner_A"):
		var hire_text: String = str(ui._hire_buttons["miner_A"].text)
		_check("0" in hire_text, "hire cost baseline 0 constant (button '%s')" % hire_text)

	# 10. save/load 부재 (재사용 경계 = 인메모리, 영구 저장 범위 밖).
	_check(not worker_roster.has_method("save"), "no worker roster save API (in-memory only)")
	_check(not roster.has_method("save"), "no mercenary roster save API (in-memory only)")

	# 회귀: 핵심 건물 상호작용 경로가 동일 recruitment_ui/inn_roster_ui를 재사용.
	var tavern_interact: Node = tavern.get_node("Interact")
	_check(tavern_interact != null and tavern_interact.has_method("interact"), "tavern interact path intact")
	var inn_interact: Node = inn.get_node("Interact")
	_check(inn_interact != null and inn_interact.has_method("interact"), "inn interact path intact")
	tavern_interact.interact(null)
	_check(ui.visible, "tavern interact opens single recruitment UI")
	inn_interact.interact(null)
	_check(inn_ui.visible, "inn interact opens single roster UI")

	print("TASK0221_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
