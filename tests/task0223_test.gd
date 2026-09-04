extends SceneTree

## TASK-022-3 Inn Upgrade UI / Visual.
## 여관 업그레이드가 UI(여관 Roster)에서 이해 가능하게 드러나는지, 그리고 3D
## 건물 visual이 레벨에 따라 prop/visual variation으로 반영되는지 결정적으로 검증한다.
##
## 검증 항목:
##  1. inn_roster_ui에 업그레이드 섹션 노드(레벨/용량/비용/불가 사유) 존재.
##  2. UI가 InnCapacity 레벨/용량을 반영 표시(초기 Lv.1, 주민/용병 capacity).
##  3. 업그레이드 비용이 데이터 테이블에서 표시됨(초기 레벨 2 cost).
##  4. 업그레이드 버튼 → InnCapacity.upgrade() 반영, UI 갱신.
##  5. 최대 레벨에서 불가 사유 표시 + 버튼 비활성.
##  6. 3D visual variation: 여관은 레벨 상승 시 prop(InnProps)가 증가.
##  7. 비여관(주점 등)은 prop variation 없음.
##  8. 회귀: 기존 Roster UI(배치/용병) 무결성 유지.

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const SETTLE_FRAMES := 10

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
	if _frame != SETTLE_FRAMES:
		return false
	_run_checks()
	print("TASK0223_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _initialize() -> void:
	var scene: Node = load(MAIN_SCENE_PATH).instantiate()
	root.add_child(scene)


func _inn_node() -> Node:
	for b in get_nodes_in_group("core_buildings_3d"):
		if b.get_core_type() == "inn":
			return b
	return null


func _props_count(inn: Node) -> int:
	var root := inn.get_node_or_null("Visual/InnProps")
	if root == null:
		return 0
	return root.get_child_count()


func _run_checks() -> void:
	var inn_cap: Node = root.get_node("InnCapacity")
	var worker_roster: Node = root.get_node("WorkerRoster")
	var merc_roster: Node = root.get_node("MercenaryRoster")
	_check(inn_cap != null, "InnCapacity autoload available")
	if inn_cap == null:
		return

	var inn_uis := get_nodes_in_group("inn_roster_ui")
	_check(inn_uis.size() == 1, "single inn roster UI (no duplicate)")
	var ui: Control = inn_uis[0] if inn_uis.size() > 0 else null
	if ui == null:
		return

	# 1. 업그레이드 섹션 노드 존재.
	for node_name in ["InnLevelLabel", "CapacityLabel", "UpgradeButton",
			"UpgradeCostLabel", "UpgradeReasonLabel"]:
		_check(ui.has_node("%" + node_name), "inn upgrade UI node '%s' present" % node_name)

	# 2. 초기 레벨/용량 표시 (Lv.1).
	var level_label: Label = ui.get_node("%InnLevelLabel")
	var cap_label: Label = ui.get_node("%CapacityLabel")
	_check(level_label.text.contains("Lv.1"), "UI shows inn level 1 ('%s')" % level_label.text)
	_check(cap_label.text.contains(str(inn_cap.get_worker_capacity()))
			and cap_label.text.contains(str(inn_cap.get_mercenary_capacity())),
		"UI shows worker/mercenary capacity ('%s')" % cap_label.text)

	# 3. 업그레이드 비용 표시 (level 1 -> 2 cost).
	var cost_label: Label = ui.get_node("%UpgradeCostLabel")
	var expected_cost: int = int(inn_cap.INN_LEVELS[1].cost)
	_check(cost_label.text.contains(str(expected_cost)),
		"UI shows upgrade cost from data table ('%s')" % cost_label.text)

	# 4. 업그레이드 버튼 → InnCapacity.upgrade 반영.
	var btn: Button = ui.get_node("%UpgradeButton")
	_check(not btn.disabled, "upgrade button enabled below max level")
	var before_level: int = inn_cap.get_level()
	btn.pressed.emit()
	_check(inn_cap.get_level() == before_level + 1,
		"upgrade button drives InnCapacity.upgrade (%d -> %d)"
			% [before_level, inn_cap.get_level()])
	_check(level_label.text.contains("Lv.%d" % inn_cap.get_level()),
		"UI refreshes level after upgrade ('%s')" % level_label.text)
	_check(cap_label.text.contains(str(inn_cap.get_worker_capacity())),
		"UI refreshes worker capacity after upgrade ('%s')" % cap_label.text)

	# 5. 최대 레벨까지 업그레이드 후 불가 사유 + 비활성.
	while inn_cap.can_upgrade():
		inn_cap.upgrade()
	_check(not inn_cap.can_upgrade(), "reached inn max level")
	ui._refresh_inn_upgrade()
	_check(btn.disabled, "upgrade button disabled at max level")
	var reason_label: Label = ui.get_node("%UpgradeReasonLabel")
	_check(not reason_label.text.is_empty(), "invalid reason shown at max level ('%s')"
		% reason_label.text)
	_check(cost_label.text.contains("-"), "no upgrade cost shown at max level ('%s')"
		% cost_label.text)

	# 6. 3D visual variation: 여관 레벨별 prop 증가.
	var inn := _inn_node()
	_check(inn != null, "inn building present")
	if inn != null:
		var base_props: int = _props_count(inn)
		_check(base_props > 0, "inn level>=2 shows upgrade props (%d)" % base_props)

	# 7. 비여관은 prop variation 없음.
	var tavern: Node = null
	for b in get_nodes_in_group("core_buildings_3d"):
		if b.get_core_type() == "tavern":
			tavern = b
	if tavern != null:
		_check(tavern.get_node_or_null("Visual/InnProps") == null,
			"tavern has no inn upgrade props")

	# 8. 회귀: Roster UI 메서드/노드 무결성.
	_check(ui.has_method("_refresh_mercenaries"), "inn roster mercenary section intact")
	_check(ui.get_node("%FacilityList") != null, "facility list intact")
	_check(ui.get_node("%WorkerList") != null, "worker list intact")
	_check(ui.get_node("%MercenaryList") != null, "mercenary list intact")
	_check(worker_roster.has_method("add_worker"), "worker roster API intact")
	_check(merc_roster.has_method("add_mercenary"), "mercenary roster API intact")
