extends SceneTree

## TASK-011-4 여관 Roster / 시설 배치 UI 검증.
## 여관 상호작용으로 Roster 관리 UI가 열리고, 고용된 Worker를 직업에 맞는
## 생산시설에 배치/해제할 수 있으며, slot 상태(0/N...)와 가득 참/중복 배치 거부,
## 직업 불일치 배치 거부가 정상 동작하는지 자동 검증한다.
## 기존 회귀(smoke, 5개 핵심 건물, Roster, 고용 UI)도 함께 확인한다.

enum Phase { SETUP, VERIFY, DONE }

var _frame := 0
var _failed := false
var _phase := Phase.SETUP
var _main: Node
var _world: Node
var _roster: Node
var _roster_ui: Control
var _hire_ui: Control
var _inn_interact: Node
var _lumberyard: Node
var _quarry: Node


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
			return false
		Phase.VERIFY:
			_verify()
			return false
		Phase.DONE:
			print("TASK0114_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	return false


func _setup() -> void:
	_main = root.get_node("Main")
	_world = _main.get_node("World")
	_roster = root.get_node("WorkerRoster")
	_check(_main != null, "main.tscn loads")

	# 여관 존재/상호작용
	var inn: Node = _world.get_node("Inn")
	_check(inn != null, "inn exists")
	_check(inn.get("core_type") == "inn", "inn core_type is inn")
	_inn_interact = inn.get_node("Interact")
	_check(_inn_interact != null, "inn interactable exists")
	_check(_inn_interact.has_method("interact"), "inn interactable has interact")

	# 여관 Roster UI 존재/초기 숨김
	_roster_ui = get_first_node_in_group("inn_roster_ui") as Control
	_check(_roster_ui != null, "inn roster UI exists in group")
	_check(_roster_ui.visible == false, "inn roster UI hidden initially")

	# 생산시설 씬 인스턴스화해 월드에 추가 (기존 task0062 방식)
	var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
	var qy_scene: PackedScene = load("res://scenes/quarry.tscn")
	_lumberyard = ly_scene.instantiate()
	_quarry = qy_scene.instantiate()
	_lumberyard.name = "Lumberyard1"
	_quarry.name = "Quarry1"
	_lumberyard.position = Vector2(300, 260)
	_quarry.position = Vector2(-300, 260)
	_world.add_child(_lumberyard)
	_world.add_child(_quarry)
	_phase = Phase.VERIFY


func _verify() -> void:
	_check(get_nodes_in_group("lumberyards").size() == 1, "lumberyard registered in group")
	_check(get_nodes_in_group("quarries").size() == 1, "quarry registered in group")
	var lumberyard: Node = get_first_node_in_group("lumberyards")
	var quarry: Node = get_first_node_in_group("quarries")
	_check(is_instance_valid(lumberyard), "lumberyard exists")
	_check(is_instance_valid(quarry), "quarry exists")
	var ly_cap: int = lumberyard.get_slot_capacity()
	var qy_cap: int = quarry.get_slot_capacity()
	_check(ly_cap >= 1, "lumberyard has capacity (%d)" % ly_cap)
	_check(qy_cap >= 1, "quarry has capacity (%d)" % qy_cap)

	# 여관 상호작용 시 UI 열림
	_inn_interact.interact(null)
	_check(_roster_ui.visible, "inn interact opens roster UI")

	# 빈 Roster 상태
	_check(_roster.get_count() == 0, "roster empty before hires (count=%d)" % _roster.get_count())

	# 고용 UI 사용해 4명 고용
	_hire_ui = get_first_node_in_group("recruitment_ui") as Control
	_check(_hire_ui != null, "recruitment UI exists")
	for cid in ["lumberjack_A", "lumberjack_B", "miner_A", "miner_B"]:
		_hire_ui._on_hire_pressed(cid)
	_check(_roster.get_count() == 4, "roster has 4 after hires (count=%d)" % _roster.get_count())

	# Roster UI 재갱신
	_roster_ui.open()

	# 직업별 배치 대상 시설 검증
	var lj_targets: Array = _roster_ui._get_facilities_for_job(WorkerData.Job.LUMBERJACK)
	_check(lj_targets.size() == 1 and lj_targets[0] == lumberyard, "lumberjack only targets lumberyard")
	var miner_targets: Array = _roster_ui._get_facilities_for_job(WorkerData.Job.MINER)
	_check(miner_targets.size() == 1 and miner_targets[0] == quarry, "miner only targets quarry")

	# 배치: Lumberjack A → Lumberyard
	var lj_a: WorkerData = _roster.get_worker("lumberjack_A")
	var lj_b: WorkerData = _roster.get_worker("lumberjack_B")
	var miner_a: WorkerData = _roster.get_worker("miner_A")
	var miner_b: WorkerData = _roster.get_worker("miner_B")
	_check(not lj_a.is_assigned(), "lumberjack A unassigned initially")
	_check(_roster.assign(lj_a, lumberyard), "assign lumberjack A to lumberyard")
	_check(lj_a.is_assigned(), "lumberjack A assigned")
	_check(lj_a.get_workplace() == lumberyard, "lumberjack A workplace is lumberyard")
	_check(lj_a.get_workplace_id() == "Lumberyard1", "lumberjack A workplace id resolves")
	_check(_roster.get_workers_for_workplace(lumberyard).size() == 1, "lumberyard filled count 1")

	# 중복 배치 거부: 이미 배치된 lj_a 재배치 불가
	_check(_roster_ui._pick_target(lj_a) == null, "assigned worker has no assign target (duplicate reject)")
	_check(not _roster.assign(lj_a, lumberyard), "roster rejects re-assign of assigned worker")

	# 직업 불일치: Miner를 Lumberyard에 직접 배치하더라도 worker.job 기반 대상은 quarry
	_check(_roster_ui._pick_target(miner_a) == quarry, "miner A pick target is quarry")

	# slot 상태 동기화 (Workers #N 표시 기반)
	var ly_filled: int = _roster.get_workers_for_workplace(lumberyard).size()
	_check(ly_filled <= ly_cap, "lumberyard filled (%d) within capacity (%d)" % [ly_filled, ly_cap])

	# 두 번째 Lumberjack 배치: capacity 2 → 2/2로 가득 참.
	_check(_roster_ui._pick_target(lj_b) == lumberyard, "lumberyard has room for lumberjack B (capacity 2)")
	_check(_roster.assign(lj_b, lumberyard), "assign lumberjack B to lumberyard")
	_check(lj_b.is_assigned(), "lumberjack B assigned")
	var ly_filled2: int = _roster.get_workers_for_workplace(lumberyard).size()
	_check(ly_filled2 == 2, "lumberyard filled count 2")
	_check(lumberyard.get_available_slots() == 0, "full lumberyard has 0 available slots")
	_check(not lumberyard.has_available_slot(), "full lumberyard has no available slot")

	# Miner 배치 → Quarry
	var miner_target: Node = _roster_ui._pick_target(miner_a)
	_check(miner_target == quarry, "miner pick target quarry")
	_check(_roster.assign(miner_a, quarry), "assign miner A to quarry")
	_check(miner_a.get_workplace() == quarry, "miner A workplace is quarry")
	var qy_filled: int = _roster.get_workers_for_workplace(quarry).size()
	_check(qy_filled <= qy_cap, "quarry filled (%d) within capacity (%d)" % [qy_filled, qy_cap])

	# 해제: lj_a unassign
	var ly_filled_before: int = _roster.get_workers_for_workplace(lumberyard).size()
	_check(_roster.unassign(lj_a), "unassign lumberjack A")
	_check(not lj_a.is_assigned(), "lumberjack A unassigned after unassign")
	_check(lj_a.get_workplace() == null, "lumberjack A workplace cleared")
	var ly_after: int = _roster.get_workers_for_workplace(lumberyard).size()
	_check(ly_after == ly_filled_before - 1, "workplace list reflects unassign (filled %d -> %d)" % [ly_filled_before, ly_after])

	# 상태 텍스트 검증
	var unassigned_worker: WorkerData = miner_b
	_check(_roster_ui._status_text(unassigned_worker) == "Unassigned", "unassigned status text is Unassigned (got '%s')" % _roster_ui._status_text(unassigned_worker))
	var assigned_worker: WorkerData = miner_a
	_check(_roster_ui._status_text(assigned_worker) == "Quarry Quarry1", "assigned status text is Quarry (got '%s')" % _roster_ui._status_text(assigned_worker))

	# UI 닫기
	_roster_ui.close()
	_check(not _roster_ui.visible, "roster UI closes")

	# 회귀: 5개 핵심 건물 / 기존 시스템 / 고용 UI 유지
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	_check(get_first_node_in_group("recruitment_ui") != null, "recruitment UI intact")
	# TASK-011-5: Roster 배치로 Worker Actor가 시설에 spawn된다.
	_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack actor spawned on assign (%d)" % get_nodes_in_group("lumberjacks").size())
	_check(get_nodes_in_group("miners").size() >= 1, "miner actor spawned on assign (%d)" % get_nodes_in_group("miners").size())
	var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")

	_phase = Phase.DONE


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
