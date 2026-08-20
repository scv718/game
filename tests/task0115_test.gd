extends SceneTree

## TASK-011-5 시설 배치 시 Worker Actor Spawn / Unassign Despawn 검증.
## - 시작 상태: Roster가 비면 생산직 Worker Actor 수 0.
## - WorkerData 배치(assign) 시 해당 시설 SpawnPoint에서 직업별 Actor가 spawn되고 기존 FSM 수행.
## - 배치 해제(unassign) 시 WorkerData는 Roster에 유지되고 Actor만 시설 복귀 후 despawn.
## - despawn 후 다시 배치(reassign) 가능.
## - freed workplace 안전 정리.
## - 기존 회귀(smoke, 5개 핵심 건물, 고용/여관 UI, floor) 유지.

enum Phase {
	SETUP, START_EMPTY, HIRE_AND_BUILD, ASSIGN_LJ_SPAWN, LJ_WORK,
	UNASSIGN_LJ, WAIT_LJ_DESPAWN, REASSIGN_LJ, ASSIGN_MINER_SPAWN, MINER_WORK,
	UNASSIGN_MINER, WAIT_MINER_DESPAWN, FREED_CLEANUP, REGRESSION, DONE
}

var _frame := 0
var _failed := false
var _phase := Phase.SETUP
var _main: Node
var _world: Node
var _roster: Node
var _hire_ui: Control
var _lumberyard: Node
var _quarry: Node
var _lj_a: WorkerData
var _lj_b: WorkerData
var _miner_a: WorkerData
var _miner_b: WorkerData
var _wood_before := 0
var _wait_start := 0


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
		Phase.START_EMPTY:
			_check_start_empty()
		Phase.HIRE_AND_BUILD:
			_hire_and_build()
		Phase.ASSIGN_LJ_SPAWN:
			_assign_lj_spawn()
		Phase.LJ_WORK:
			_wait_lj_work()
		Phase.UNASSIGN_LJ:
			_unassign_lj()
		Phase.WAIT_LJ_DESPAWN:
			_wait_lj_despawn()
		Phase.REASSIGN_LJ:
			_reassign_lj()
		Phase.ASSIGN_MINER_SPAWN:
			_assign_miner_spawn()
		Phase.MINER_WORK:
			_wait_miner_work()
		Phase.UNASSIGN_MINER:
			_unassign_miner()
		Phase.WAIT_MINER_DESPAWN:
			_wait_miner_despawn()
		Phase.FREED_CLEANUP:
			_freed_cleanup()
		Phase.REGRESSION:
			_regression()
		Phase.DONE:
			print("TASK0115_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 15000:
		print("TASK0115_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	_main = root.get_node("Main")
	_world = _main.get_node("World")
	_roster = root.get_node("WorkerRoster")
	_hire_ui = get_first_node_in_group("recruitment_ui") as Control
	_check(_main != null, "main.tscn loads")
	_check(_roster != null, "WorkerRoster autoload exists")
	_check(_hire_ui != null, "recruitment UI exists")

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
	_phase = Phase.START_EMPTY


func _check_start_empty() -> void:
	_check(_roster.get_count() == 0, "roster empty at start (%d)" % _roster.get_count())
	_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor at start (%d)" % get_nodes_in_group("lumberjacks").size())
	_check(get_nodes_in_group("miners").size() == 0, "no miner actor at start (%d)" % get_nodes_in_group("miners").size())
	_check(_roster.get_actor_count() == 0, "roster actor count 0 at start")
	_phase = Phase.HIRE_AND_BUILD


func _hire_and_build() -> void:
	for cid in ["lumberjack_A", "lumberjack_B", "miner_A", "miner_B"]:
		_hire_ui._on_hire_pressed(cid)
	_check(_roster.get_count() == 4, "roster has 4 after hires (%d)" % _roster.get_count())
	_lj_a = _roster.get_worker("lumberjack_A")
	_lj_b = _roster.get_worker("lumberjack_B")
	_miner_a = _roster.get_worker("miner_A")
	_miner_b = _roster.get_worker("miner_B")
	_check(get_nodes_in_group("lumberjacks").size() == 0, "no actor right after hire (unassigned)")
	_check(get_nodes_in_group("miners").size() == 0, "no miner actor right after hire (unassigned)")
	_check(_lumberyard.get_node_or_null("SpawnPoint") != null, "lumberyard has SpawnPoint")
	_check(_quarry.get_node_or_null("SpawnPoint") != null, "quarry has SpawnPoint")
	_phase = Phase.ASSIGN_LJ_SPAWN


func _assign_lj_spawn() -> void:
	_check(_roster.assign(_lj_a, _lumberyard), "assign lumberjack A to lumberyard")
	var actors_before: int = get_nodes_in_group("lumberjacks").size()
	_check(actors_before == 1, "lumberjack actor spawned on assign (%d)" % actors_before)
	var actor: Node = _roster.get_actor(_lj_a)
	_check(actor != null and is_instance_valid(actor), "roster returns spawned lumberjack actor")
	if actor != null:
		_check(actor.has_method("begin_despawn"), "spawned actor is a despawn-capable worker")
		_check(actor.get_workplace() == _lumberyard, "spawned actor workplace is lumberyard")
		_check(actor.worker_data == _lj_a, "spawned actor connected to WorkerData")
		var spawn: Node2D = _lumberyard.get_node_or_null("SpawnPoint")
		_check(spawn != null and actor.global_position.distance_to(spawn.global_position) < 2.0, "actor spawned at facility SpawnPoint")
	_check(_lumberyard.get_filled_slots() == 1, "lumberyard filled slots 1 after spawn")
	if actor != null:
		_check(_lumberyard.has_worker(actor), "lumberyard tracks spawned worker")
	_wood_before = root.get_node("VillageResources").get_amount("wood")
	_phase = Phase.LJ_WORK


func _wait_lj_work() -> void:
	var wood: int = root.get_node("VillageResources").get_amount("wood")
	if wood > _wood_before:
		_check(wood - _wood_before >= 1, "lumberjack produces wood (+%d)" % (wood - _wood_before))
		_check(_lj_a.is_assigned(), "worker data still assigned while working")
		_phase = Phase.UNASSIGN_LJ


func _unassign_lj() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.unassign(_lj_a), "unassign lumberjack A")
	_check(not _lj_a.is_assigned(), "worker data unassigned after unassign")
	_check(_lj_a.get_workplace() == null, "worker data workplace cleared")
	_check(_roster.get_worker("lumberjack_A") == _lj_a, "worker data retained in roster after unassign")
	_wait_start = _frame
	_phase = Phase.WAIT_LJ_DESPAWN


func _wait_lj_despawn() -> void:
	var actors_now: int = get_nodes_in_group("lumberjacks").size()
	if actors_now == 0:
		_check(true, "lumberjack actor despawned after return")
		_check(_roster.get_actor(_lj_a) == null, "roster no longer returns actor after despawn")
		_phase = Phase.REASSIGN_LJ
		return
	if _frame - _wait_start > 900:
		_check(false, "lumberjack actor did not despawn within bound (actors=%d)" % actors_now)
		_phase = Phase.REASSIGN_LJ


func _reassign_lj() -> void:
	_check(_roster.assign(_lj_a, _lumberyard), "reassign lumberjack A after despawn")
	_check(_roster.get_actor(_lj_a) != null, "lumberjack actor respawned on reassign")
	_phase = Phase.ASSIGN_MINER_SPAWN


func _assign_miner_spawn() -> void:
	_check(_roster.assign(_miner_a, _quarry), "assign miner A to quarry")
	var actors_before: int = get_nodes_in_group("miners").size()
	_check(actors_before == 1, "miner actor spawned on assign (%d)" % actors_before)
	var actor: Node = _roster.get_actor(_miner_a)
	_check(actor != null and actor.has_method("begin_despawn"), "spawned actor is a despawn-capable worker")
	if actor != null:
		_check(actor.get_workplace() == _quarry, "spawned miner workplace is quarry")
		_check(actor.worker_data == _miner_a, "spawned miner connected to WorkerData")
		_check(actor.get_node_or_null("NavigationAgent2D") != null, "spawned miner has nav agent (worker actor)")
	_check(_quarry.get_node_or_null("SpawnPoint") != null, "quarry has SpawnPoint")
	_check(_quarry.get_filled_slots() == 1, "quarry filled slots 1 after spawn")
	_phase = Phase.MINER_WORK


func _wait_miner_work() -> void:
	var stone: int = root.get_node("VillageResources").get_amount("stone")
	if stone >= 1:
		_check(stone >= 1, "miner produces stone (%d)" % stone)
		_phase = Phase.UNASSIGN_MINER


func _unassign_miner() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.unassign(_miner_a), "unassign miner A")
	_check(not _miner_a.is_assigned(), "miner data unassigned after unassign")
	_check(_roster.get_worker("miner_A") == _miner_a, "miner data retained in roster")
	_wait_start = _frame
	_phase = Phase.WAIT_MINER_DESPAWN


func _wait_miner_despawn() -> void:
	var miners_now: int = get_nodes_in_group("miners").size()
	if miners_now == 0:
		_check(true, "miner actor despawned after return")
		_check(_roster.get_actor(_miner_a) == null, "roster no longer returns miner actor after despawn")
		_phase = Phase.FREED_CLEANUP
		return
	if _frame - _wait_start > 900:
		_check(false, "miner actor did not despawn within bound (actors=%d)" % miners_now)
		_phase = Phase.FREED_CLEANUP


func _freed_cleanup() -> void:
	_check(_lj_a.is_assigned(), "lumberjack A assigned before building deletion")
	var actor: Node = _roster.get_actor(_lj_a)
	_check(actor != null, "lumberjack actor exists before building deletion")
	_lumberyard.free()
	_roster.cleanup_freed_workplaces()
	_check(not _lj_a.is_assigned(), "worker unassigned after building deletion cleanup")
	_phase = Phase.REGRESSION


func _regression() -> void:
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	_check(get_first_node_in_group("recruitment_ui") != null, "recruitment UI intact")
	_check(get_first_node_in_group("inn_roster_ui") != null, "inn roster UI intact")
	var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")
	_check(_roster.get_worker("lumberjack_B") != null, "unassigned worker B retained")
	_check(not _lj_b.is_assigned(), "worker B unassigned")
	_phase = Phase.DONE


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
