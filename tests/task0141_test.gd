extends SceneTree

## TASK-014-1 MercenaryData / MercenaryRoster + 주점 고용 검증.
## 주점 상호작용으로 고용 UI가 열리고, 고정 Mercenary 후보 1명을 고용하면
## MercenaryData가 MercenaryRoster에 정확히 1회 추가되며,
## 중복 고용이 거부되고, 고용 직후 월드 전투 Actor가 생성되지 않는지 자동 검증한다.
## 여관에서 보유/대기 상태 최소 표시를 확인한다.
## 기존 시스템(smoke, 5개 핵심 건물, Worker Roster, 고용 UI) 회귀도 함께 확인한다.

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

	# Roster autoload 존재 (Worker/Mercenary 분리)
	var worker_roster: Node = root.get_node("WorkerRoster")
	_check(worker_roster != null, "WorkerRoster autoload exists")
	var roster: Node = root.get_node("MercenaryRoster")
	_check(roster != null, "MercenaryRoster autoload exists")
	_check(roster != worker_roster, "MercenaryRoster separate from WorkerRoster")

	# 주점/상호작용 존재
	var world: Node = main.get_node("World")
	var tavern: Node = world.get_node("Tavern")
	_check(tavern != null, "tavern exists")
	_check(tavern.get("core_type") == "tavern", "tavern core_type is tavern")
	var interact: Node = tavern.get_node("Interact")
	_check(interact != null, "tavern interactable exists")
	_check(interact.has_method("interact"), "tavern interactable has interact")

	# 고용 UI 존재/초기 상태
	var ui: Control = get_first_node_in_group("recruitment_ui")
	_check(ui != null, "recruitment UI exists in group")
	_check(ui.visible == false, "recruitment UI hidden initially")

	# 기존 Worker 후보 4명 유지 (회귀)
	var seen := {}
	for c in ui.CANDIDATES:
		seen[c.id] = c
	_check(seen.size() == 4, "4 worker candidates intact (%d)" % seen.size())

	# TASK-014-1: 고정 Mercenary 후보 1명
	var m_seen := {}
	for c in ui.MERCENARY_CANDIDATES:
		m_seen[c.id] = c
	_check(m_seen.size() == 1, "1 mercenary candidate defined (%d)" % m_seen.size())
	_check(m_seen.has("mercenary_A"), "mercenary_A candidate")
	_check(m_seen["mercenary_A"].merc_class == MercenaryData.MercClass.SWORDSMAN, "mercenary candidate class SWORDSMAN")

	# 초기 Roster 빈 상태 (Worker/Mercenary 각각)
	_check(worker_roster.get_count() == 0, "worker roster starts empty (%d)" % worker_roster.get_count())
	_check(roster.get_count() == 0, "mercenary roster starts empty (%d)" % roster.get_count())

	# 주점 상호작용 시 UI 열림
	interact.interact(null)
	_check(ui.visible, "tavern interact opens recruitment UI")

	# 고용: Mercenary A → MercenaryRoster 정확히 1회 추가
	var merc_actors_before: int = get_nodes_in_group("mercenaries").size()
	ui._on_mercenary_hire_pressed("mercenary_A")
	_check(roster.get_count() == 1, "mercenary roster grew to 1 after hire (%d)" % roster.get_count())
	var m: MercenaryData = roster.get_mercenary("mercenary_A")
	_check(m != null, "Mercenary A in mercenary roster")
	_check(m.display_name == "Mercenary A", "Mercenary A display name")
	_check(m.get_class_name() == "SWORDSMAN", "Mercenary A class name SWORDSMAN")
	_check(m.level == 1, "Mercenary A level 1 prototype")
	_check(m.max_hp > 0 and m.attack_damage > 0 and m.attack_interval > 0.0 and m.move_speed > 0.0, "combat stats minimum present (hp=%d dmg=%d)" % [m.max_hp, m.attack_damage])
	_check(m.alive == true, "Mercenary A starts alive")
	_check(m.get_defense_zone() == MercenaryData.DefenseZone.NONE, "Mercenary A defense zone NONE initially")
	_check(m.get_defense_name() == "NONE", "Mercenary A defense name NONE")

	# 중복 고용 거부
	ui._on_mercenary_hire_pressed("mercenary_A")
	_check(roster.get_count() == 1, "duplicate mercenary hire rejected (roster stays 1)")

	# 고용 직후 월드 전투 Actor 미생성 (Mercenary group 0, 월드 구성 유지)
	var merc_actors_after: int = get_nodes_in_group("mercenaries").size()
	_check(merc_actors_after == merc_actors_before, "no mercenary combat actor spawned on hire (%d -> %d)" % [merc_actors_before, merc_actors_after])

	# Roster 조회 API
	_check(roster.get_mercenaries().size() == 1, "get_mercenaries returns 1")
	_check(roster.get_alive().size() == 1, "get_alive returns hired mercenary")
	_check(roster.get_alive_count() == 1, "get_alive_count is 1")
	_check(roster.get_mercenary("missing") == null, "get_mercenary unknown id returns null")
	_check(not roster.remove_mercenary(null), "remove_mercenary(null) rejected")
	_check(not roster.add_mercenary(null), "add_mercenary(null) rejected")

	# Worker 고용은 Mercenary Roster에 영향을 주지 않음 (분리)
	ui._on_hire_pressed("lumberjack_A")
	_check(worker_roster.get_count() == 1, "worker hire works (roster=%d)" % worker_roster.get_count())
	_check(roster.get_count() == 1, "mercenary roster unaffected by worker hire (%d)" % roster.get_count())

	# 여관에서 보유/대기 상태 최소 표시
	var inn: Node = world.get_node("Inn")
	_check(inn != null, "inn exists")
	var inn_interact: Node = inn.get_node("Interact")
	_check(inn_interact != null, "inn interactable exists")
	var roster_ui: Control = get_first_node_in_group("inn_roster_ui")
	_check(roster_ui != null, "inn roster UI exists in group")
	_check(roster_ui.visible == false, "inn roster UI hidden initially")
	inn_interact.interact(null)
	_check(roster_ui.visible, "inn interact opens roster UI")
	roster_ui._refresh_mercenaries()
	_check(roster_ui._mercenary_list.get_child_count() >= 1, "mercenary list has content")
	var m_info := _find_mercenary_row_text(roster_ui._mercenary_list, "Mercenary A")
	_check(m_info != "" and "대기" in m_info, "mercenary row shows owned/standby status (got '%s')" % m_info)
	_check("NONE" in m_info, "mercenary row shows defense zone NONE (got '%s')" % m_info)

	# 여관 닫기 / 고용 UI 닫기
	roster_ui.close()
	_check(not roster_ui.visible, "roster UI closes")
	ui.close()
	_check(not ui.visible, "recruitment UI closes")

	# 회귀: 5개 핵심 건물 / 기존 Worker 시스템 유지
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	_check(get_nodes_in_group("lumberjacks").size() == 0, "no worker actor spawned by roster data (lumberjacks=%d)" % get_nodes_in_group("lumberjacks").size())
	_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned by roster data (miners=%d)" % get_nodes_in_group("miners").size())
	var floor_node: TileMapLayer = world.get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")

	print("TASK0141_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _find_mercenary_row_text(list: Node, name_prefix: String) -> String:
	for child in list.get_children():
		var text := _find_label_text(child, name_prefix)
		if text != "":
			return text
	return ""


func _find_label_text(node: Node, name_prefix: String) -> String:
	if node is Label and str(node.text).begins_with(name_prefix):
		return str(node.text)
	for sub in node.get_children():
		var text := _find_label_text(sub, name_prefix)
		if text != "":
			return text
	return ""


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)