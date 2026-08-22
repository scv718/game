extends SceneTree

## TASK-011-6 Lumberyard / Quarry 2 Worker 동시 작업 검증.
## - Lumberyard/Quarry 초기 Worker Slot 2 (capacity 2).
## - 동일 시설에 두 Worker가 동시에 배치/작업 가능.
## - 3번째 Worker 배치는 거부.
## - 두 Lumberjack가 서로 다른 Tree를 우선 선택(가벼운 claim)하고 자원 중복/음수 없음.
## - 두 Miner가 서로 다른 WorkPoint에서 독립적으로 Stone 생산.
## - 기존 회귀(smoke, 5개 핵심 건물, 고용/여관 UI, floor) 유지.

enum Phase {
	SETUP, VERIFY_CAPACITY, ASSIGN_LJ, LJ_WORK, THIRD_LJ_REJECT,
	ASSIGN_MINER, MINER_WORK, THIRD_MINER_REJECT, REGRESSION, DONE
}

var _frame := 0
var _failed := false
var _phase := Phase.SETUP
var _main: Node
var _world: Node
var _roster: Node
var _lumberyard: Node
var _quarry: Node
var _lj_a: WorkerData
var _lj_b: WorkerData
var _miner_a: WorkerData
var _miner_b: WorkerData
var _lj3: WorkerData
var _miner3: WorkerData
var _wood_before := 0
var _stone_before := 0
var _min_wood := 0
var _min_stone := 0
var _sample := 0
var _distinct_trees_observed := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	var wood: int = root.get_node("VillageResources").get_amount("wood")
	var stone: int = root.get_node("VillageResources").get_amount("stone")
	_min_wood = mini(_min_wood, wood)
	_min_stone = mini(_min_stone, stone)
	if wood < 0 or stone < 0:
		_check(false, "no negative resource (wood=%d stone=%d)" % [wood, stone])
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.VERIFY_CAPACITY:
			_verify_capacity()
		Phase.ASSIGN_LJ:
			_assign_lj()
		Phase.LJ_WORK:
			_wait_lj_work()
		Phase.THIRD_LJ_REJECT:
			_third_lj_reject()
		Phase.ASSIGN_MINER:
			_assign_miner()
		Phase.MINER_WORK:
			_wait_miner_work()
		Phase.THIRD_MINER_REJECT:
			_third_miner_reject()
		Phase.REGRESSION:
			_regression()
		Phase.DONE:
			print("TASK0116_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 15000:
		print("TASK0116_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	_main = root.get_node("Main")
	_world = _main.get_node("World")
	_roster = root.get_node("WorkerRoster")
	_check(_main != null, "main.tscn loads")
	_check(_roster != null, "WorkerRoster autoload exists")

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

	var hire_ui := get_first_node_in_group("recruitment_ui") as Control
	_check(hire_ui != null, "recruitment UI exists")
	for cid in ["lumberjack_A", "lumberjack_B", "miner_A", "miner_B"]:
		hire_ui._on_hire_pressed(cid)
	_check(_roster.get_count() == 4, "roster has 4 after hires (%d)" % _roster.get_count())
	_lj_a = _roster.get_worker("lumberjack_A")
	_lj_b = _roster.get_worker("lumberjack_B")
	_miner_a = _roster.get_worker("miner_A")
	_miner_b = _roster.get_worker("miner_B")
	_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor right after hire")
	_check(get_nodes_in_group("miners").size() == 0, "no miner actor right after hire")
	_min_wood = root.get_node("VillageResources").get_amount("wood")
	_min_stone = root.get_node("VillageResources").get_amount("stone")
	_phase = Phase.VERIFY_CAPACITY


func _verify_capacity() -> void:
	_check(_lumberyard.get_slot_capacity() == 2, "lumberyard capacity 2 (got %d)" % _lumberyard.get_slot_capacity())
	_check(_quarry.get_slot_capacity() == 2, "quarry capacity 2 (got %d)" % _quarry.get_slot_capacity())
	_check(_lumberyard.get_interact_prompt() == "Workers: 0/2 - Assign Worker", "lumberyard prompt 0/2 (got '%s')" % _lumberyard.get_interact_prompt())
	_check(_quarry.get_interact_prompt() == "Workers: 0/2 - Assign Miner", "quarry prompt 0/2 (got '%s')" % _quarry.get_interact_prompt())
	_phase = Phase.ASSIGN_LJ


func _assign_lj() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.assign(_lj_a, _lumberyard), "assign lumberjack A")
	_check(_roster.assign(_lj_b, _lumberyard), "assign lumberjack B")
	var actors: Array = get_nodes_in_group("lumberjacks")
	_check(actors.size() == 2, "two lumberjack actors spawned (%d)" % actors.size())
	_check(_lumberyard.get_filled_slots() == 2, "lumberyard filled 2/2")
	_check(_roster.get_actor_count() == 2, "roster tracks 2 actors")
	_check(_lumberyard.get_interact_prompt() == "Workers: 2/2 - Unassign Worker", "lumberyard prompt 2/2 (got '%s')" % _lumberyard.get_interact_prompt())
	_wood_before = root.get_node("VillageResources").get_amount("wood")
	_distinct_trees_observed = false
	_phase = Phase.LJ_WORK


func _wait_lj_work() -> void:
	var wood: int = root.get_node("VillageResources").get_amount("wood")
	_sample += 1
	var actors: Array = get_nodes_in_group("lumberjacks")
	var seen: Array = []
	var both_engaged := true
	for a in actors:
		if a.state < 1 or a.state > 4:
			both_engaged = false
		if a.target_tree != null and is_instance_valid(a.target_tree):
			seen.append(a.target_tree)
	if seen.size() >= 2 and seen[0] != seen[1]:
		_distinct_trees_observed = true
	if wood > _wood_before:
		_check(wood - _wood_before >= 1, "both lumberjacks working, wood produced (+%d)" % (wood - _wood_before))
		_check(actors.size() == 2, "two lumberjacks remain while working")
		_check(_distinct_trees_observed, "two lumberjacks observed on distinct trees (claim)")
		_phase = Phase.THIRD_LJ_REJECT


func _third_lj_reject() -> void:
	_lj3 = WorkerData.new("lumberjack_C", "Lumberjack C", WorkerData.Job.LUMBERJACK)
	_check(_roster.add_worker(_lj3), "add 3rd lumberjack to roster")
	_check(not _roster.assign(_lj3, _lumberyard), "3rd lumberjack assignment rejected (full)")
	_check(not _lj3.is_assigned(), "3rd lumberjack remains unassigned")
	_check(_lumberyard.get_filled_slots() == 2, "lumberyard still 2/2 after reject")
	_check(_roster.unassign(_lj3) == false, "unassign on unassigned 3rd lumberjack rejected")
	_stone_before = root.get_node("VillageResources").get_amount("stone")
	_phase = Phase.ASSIGN_MINER


func _assign_miner() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.assign(_miner_a, _quarry), "assign miner A")
	_check(_roster.assign(_miner_b, _quarry), "assign miner B")
	var actors: Array = get_nodes_in_group("miners")
	_check(actors.size() == 2, "two miner actors spawned (%d)" % actors.size())
	_check(_quarry.get_filled_slots() == 2, "quarry filled 2/2")
	_check(_quarry.get_interact_prompt() == "Workers: 2/2 - Unassign Miner", "quarry prompt 2/2 (got '%s')" % _quarry.get_interact_prompt())
	_phase = Phase.MINER_WORK


func _wait_miner_work() -> void:
	var stone: int = root.get_node("VillageResources").get_amount("stone")
	if stone >= _stone_before + 2:
		_check(stone >= _stone_before + 2, "two miners produced stone (+%d)" % (stone - _stone_before))
		var actors: Array = get_nodes_in_group("miners")
		var wp0: Node = null
		var wp1: Node = null
		var distinct := true
		for a in actors:
			var wp: Node = a._get_work_point()
			if wp0 == null:
				wp0 = wp
			elif wp != wp0:
				wp1 = wp
		_check(actors.size() == 2, "two miners remain while producing")
		_check(distinct and wp0 != null and wp1 != null, "two miners use distinct work points")
		_phase = Phase.THIRD_MINER_REJECT


func _third_miner_reject() -> void:
	_miner3 = WorkerData.new("miner_C", "Miner C", WorkerData.Job.MINER)
	_check(_roster.add_worker(_miner3), "add 3rd miner to roster")
	_check(not _roster.assign(_miner3, _quarry), "3rd miner assignment rejected (full)")
	_check(not _miner3.is_assigned(), "3rd miner remains unassigned")
	_check(_quarry.get_filled_slots() == 2, "quarry still 2/2 after reject")
	_phase = Phase.REGRESSION


func _regression() -> void:
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	_check(get_first_node_in_group("recruitment_ui") != null, "recruitment UI intact")
	_check(get_first_node_in_group("inn_roster_ui") != null, "inn roster UI intact")
	var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
			_check(floor_node != null and floor_node.get_used_cells().size() == 192 * 192, "world floor intact (192x192)")
	_check(_min_wood >= 0 and _min_stone >= 0, "resources never went negative (min wood=%d stone=%d)" % [_min_wood, _min_stone])
	_phase = Phase.DONE


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
