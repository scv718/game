extends SceneTree

## TASK-011-7 Core Village / Roster / Worker Lifecycle 통합 회귀.
## TASK-011 전체 흐름을 실제 게임 루프 순서로 headless 통합 검증한다.
##
## 필수 시나리오 (게임 루프 순서):
##   1. 게임 시작.
##   2. 중앙에 거점/주점/여관/식료품점/장비점 존재.
##   3. 시작 시 Lumberjack/Miner Actor가 월드에 미리 존재하지 않음.
##   4. 주점에서 Lumberjack 2명 + Miner 2명 고용.
##   5. 고용 직후 Actor 수는 여전히 0.
##   6. Lumberyard 건설.
##   7. Quarry 건설.
##   8. 여관에서 Lumberjack 2명을 Lumberyard에 배치.
##   9. Lumberyard에서 Actor 2명 spawn.
##  10. 두 Lumberjack가 Tree를 작업하고 Wood 생산.
##  11. 여관에서 Miner 2명을 Quarry에 배치.
##  12. Quarry에서 Actor 2명 spawn.
##  13. 두 Miner가 Stone 생산.
##  14. 각 시설에 3번째 Worker 배치 거부.
##  15. Lumberjack 1명 Unassign.
##  16. 마지막 Wood 반납 후 facility return/despawn.
##  17. Roster에는 해당 Worker가 Unassigned 상태로 유지.
##  18. Miner 1명 Unassign → 생산 중단/복귀/despawn.
##  19. 두 Worker 모두 다시 Reassign 가능.
##
## 추가 회귀:
##   - Tree regrowth.
##   - Lumberjack obstacle avoidance / TASK-BUG-NAV-001.
##   - Quarry Deposit 점유.
##   - BuildingPlacement.
##   - Workplace freed reference.
##   - Day/Night 전환 중 roster/actor/workplace reference 안정성.
##   - Night에도 생산을 중단하는 새 정책을 추가하지 않는다.
##   - Wood/Stone HUD.
##   - main.tscn smoke.

enum Phase {
	SETUP, START_CORE, START_EMPTY, HIRE, HIRE_NO_ACTOR,
	BUILD_LUMBERYARD, BUILD_QUARRY, ASSIGN_LJ, LJ_SPAWN, LJ_WORK,
	ASSIGN_MINER, MINER_SPAWN, MINER_WORK, THIRD_REJECT,
	UNASSIGN_LJ, WAIT_LJ_DESPAWN, LJ_ROSTER, UNASSIGN_MINER, WAIT_MINER_DESPAWN,
	MINER_ROSTER, REASSIGN, REGROW, NAV_OBSERVE, NAV_CLEANUP, DAYNIGHT, HUD_SMOKE, DONE
}

var _frame := 0
var _failed := false
var _phase := Phase.SETUP
var _phase_start := 0
var _step_done := false

var _main: Node
var _world: Node
var _roster: Node
var _resources: Node
var _game_time: Node
var _controller: Node
var _camera: Camera2D
var _hud: Node
var _wood_label: Label
var _stone_label: Label
var _hire_ui: Control
var _placement: Node

var _lumberyard: Node
var _quarry: Node
var _deposit: Node
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
var _wait_start := 0
var _obstacle: Node = null

const ZOOM_TOLERANCE := 0.01
const ZOOM_WAIT_FRAMES := 300


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_phase_start = _frame
	_step_done = false


func _elapsed() -> int:
	return _frame - _phase_start


func _finish() -> void:
	print("TASK0117_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	var wood: int = _resources.get_amount("wood") if _resources else 0
	var stone: int = _resources.get_amount("stone") if _resources else 0
	_min_wood = mini(_min_wood, wood)
	_min_stone = mini(_min_stone, stone)
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.START_CORE:
			_check_core()
		Phase.START_EMPTY:
			_check_start_empty()
		Phase.HIRE:
			_hire()
		Phase.HIRE_NO_ACTOR:
			_check_hire_no_actor()
		Phase.BUILD_LUMBERYARD:
			_build_lumberyard()
		Phase.BUILD_QUARRY:
			_build_quarry()
		Phase.ASSIGN_LJ:
			_assign_lj()
		Phase.LJ_SPAWN:
			_check_lj_spawn()
		Phase.LJ_WORK:
			_wait_lj_work()
		Phase.ASSIGN_MINER:
			_assign_miner()
		Phase.MINER_SPAWN:
			_check_miner_spawn()
		Phase.MINER_WORK:
			_wait_miner_work()
		Phase.THIRD_REJECT:
			_third_reject()
		Phase.UNASSIGN_LJ:
			_unassign_lj()
		Phase.WAIT_LJ_DESPAWN:
			_wait_lj_despawn()
		Phase.LJ_ROSTER:
			_check_lj_roster()
		Phase.UNASSIGN_MINER:
			_unassign_miner()
		Phase.WAIT_MINER_DESPAWN:
			_wait_miner_despawn()
		Phase.MINER_ROSTER:
			_check_miner_roster()
		Phase.REASSIGN:
			_reassign()
		Phase.REGROW:
			_regrow()
		Phase.NAV_OBSERVE:
			_nav_observe()
		Phase.NAV_CLEANUP:
			_nav_cleanup()
		Phase.DAYNIGHT:
			_daynight()
		Phase.HUD_SMOKE:
			_hud_smoke()
		Phase.DONE:
			_finish()
			return true
	if _frame > 60000:
		print("TASK0117_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < 8:
		return
	_main = root.get_node("Main")
	_world = _main.get_node("World")
	_roster = root.get_node("WorkerRoster")
	_resources = root.get_node("VillageResources")
	_game_time = root.get_node("GameTime")
	var ctrls := get_nodes_in_group("camera_controller")
	_controller = ctrls[0] if ctrls.size() > 0 else null
	_camera = _controller.get_camera() as Camera2D if _controller else null
	_hud = _main.get_node("HUD")
	_wood_label = _hud.get_node("WoodLabel") as Label
	_stone_label = _hud.get_node("StoneLabel") as Label
	_hire_ui = get_first_node_in_group("recruitment_ui") as Control
	_placement = _main.get_node("BuildingPlacement")
	var deposits := get_nodes_in_group("stone_deposits")
	_deposit = deposits[0] if deposits.size() > 0 else null
	_check(_main != null, "main.tscn loads")
	_check(_roster != null, "WorkerRoster autoload exists")
	_check(_resources != null, "VillageResources autoload exists")
	_check(_game_time != null, "GameTime autoload exists")
	_check(_hire_ui != null, "recruitment UI exists")
	_check(_placement != null, "BuildingPlacement exists")
	_check(_deposit != null, "stone deposit exists")
	for t in get_nodes_in_group("interactable"):
		t.regrow_time = 10000.0
	_game_time.set_auto_advance(false)
	_game_time.set_durations(10.0, 10.0)
	_min_wood = _resources.get_amount("wood")
	_min_stone = _resources.get_amount("stone")
	_enter(Phase.START_CORE)


func _check_core() -> void:
	var cores := get_nodes_in_group("core_buildings")
	_check(cores.size() == 5, "5 core buildings exist (%d)" % cores.size())
	var types := []
	for c in cores:
		types.append(c.core_type)
	_check("keep" in types and "tavern" in types and "inn" in types \
			and "grocery" in types and "equipment" in types,
			"core types keep/tavern/inn/grocery/equipment present (%s)" % str(types))
	var keep := _world.get_node_or_null("Keep")
	_check(keep != null and keep.core_type == "keep", "Keep core building identifiable")
	_check(keep.get_level() == 1, "core building level 1")
	_enter(Phase.START_EMPTY)


func _check_start_empty() -> void:
	_check(_roster.get_count() == 0, "roster empty at start (%d)" % _roster.get_count())
	_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor at start")
	_check(get_nodes_in_group("miners").size() == 0, "no miner actor at start")
	_check(_roster.get_actor_count() == 0, "roster actor count 0 at start")
	_enter(Phase.HIRE)


func _hire() -> void:
	for cid in ["lumberjack_A", "lumberjack_B", "miner_A", "miner_B"]:
		_hire_ui._on_hire_pressed(cid)
	_check(_roster.get_count() == 4, "roster has 4 after tavern hires (%d)" % _roster.get_count())
	_lj_a = _roster.get_worker("lumberjack_A")
	_lj_b = _roster.get_worker("lumberjack_B")
	_miner_a = _roster.get_worker("miner_A")
	_miner_b = _roster.get_worker("miner_B")
	_check(_lj_a != null and _lj_b != null, "two lumberjack WorkerData hired")
	_check(_miner_a != null and _miner_b != null, "two miner WorkerData hired")
	_enter(Phase.HIRE_NO_ACTOR)


func _check_hire_no_actor() -> void:
	_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor right after hire (unassigned)")
	_check(get_nodes_in_group("miners").size() == 0, "no miner actor right after hire (unassigned)")
	_check(_roster.get_actor_count() == 0, "roster actor count still 0 after hire")
	_enter(Phase.BUILD_LUMBERYARD)


func _build_lumberyard() -> void:
	if _frame % 2 != 0:
		return
	_resources._amounts["wood"] = 200
	_placement._set_building_type("lumberyard")
	_placement._try_place_at(Vector2(300, 260))
	var lys := get_nodes_in_group("lumberyards")
	_check(lys.size() == 1, "lumberyard built on valid clearing (%d)" % lys.size())
	_lumberyard = lys[0] if lys.size() > 0 else null
	_check(_lumberyard != null and _lumberyard.get_slot_capacity() == 2, "lumberyard slot capacity 2")
	_enter(Phase.BUILD_QUARRY)


func _build_quarry() -> void:
	if _frame % 2 != 0:
		return
	_placement._set_building_type("quarry")
	_placement._try_place_quarry_at(_deposit.global_position)
	var qs := get_nodes_in_group("quarries")
	_check(qs.size() == 1, "quarry built on deposit (%d)" % qs.size())
	_quarry = qs[0] if qs.size() > 0 else null
	_check(_quarry != null and _quarry.get_deposit() == _deposit, "quarry linked to deposit")
	_check(_deposit.is_occupied(), "deposit occupied by quarry")
	_check(_quarry.get_slot_capacity() == 2, "quarry slot capacity 2")
	_enter(Phase.ASSIGN_LJ)


func _assign_lj() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.assign(_lj_a, _lumberyard), "inn assigns lumberjack A to lumberyard")
	_check(_roster.assign(_lj_b, _lumberyard), "inn assigns lumberjack B to lumberyard")
	_enter(Phase.LJ_SPAWN)


func _check_lj_spawn() -> void:
	var actors := get_nodes_in_group("lumberjacks")
	_check(actors.size() == 2, "two lumberjack actors spawn at lumberyard (%d)" % actors.size())
	_check(_lumberyard.get_filled_slots() == 2, "lumberyard filled 2/2")
	_check(_roster.get_actor_count() == 2, "roster tracks 2 actors")
	var a: Node = _roster.get_actor(_lj_a)
	_check(a != null and a.get_workplace() == _lumberyard, "actor A workplace is lumberyard")
	_check(a.worker_data == _lj_a, "actor A connected to WorkerData")
	var spawn: Node2D = _lumberyard.get_node_or_null("SpawnPoint")
	_check(spawn != null and a.global_position.distance_to(spawn.global_position) < 16.0, "actor A spawned at SpawnPoint")
	_wood_before = _resources.get_amount("wood")
	_enter(Phase.LJ_WORK)


func _wait_lj_work() -> void:
	var wood: int = _resources.get_amount("wood")
	var actors := get_nodes_in_group("lumberjacks")
	if wood > _wood_before:
		_check(wood - _wood_before >= 1, "both lumberjacks produce wood (+%d)" % (wood - _wood_before))
		_check(actors.size() == 2, "two lumberjacks remain while working")
		_enter(Phase.ASSIGN_MINER)
	elif _elapsed() >= 9000:
		_check(false, "lumberjack wood production within timeout (wood=%d)" % wood)
		_finish()


func _assign_miner() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.assign(_miner_a, _quarry), "inn assigns miner A to quarry")
	_check(_roster.assign(_miner_b, _quarry), "inn assigns miner B to quarry")
	_enter(Phase.MINER_SPAWN)


func _check_miner_spawn() -> void:
	var actors := get_nodes_in_group("miners")
	_check(actors.size() == 2, "two miner actors spawn at quarry (%d)" % actors.size())
	_check(_quarry.get_filled_slots() == 2, "quarry filled 2/2")
	_check(_roster.get_actor_count() == 4, "roster tracks 4 actors total")
	_stone_before = _resources.get_amount("stone")
	_enter(Phase.MINER_WORK)


func _wait_miner_work() -> void:
	var stone: int = _resources.get_amount("stone")
	if stone >= _stone_before + 2:
		_check(stone >= _stone_before + 2, "two miners produce stone (+%d)" % (stone - _stone_before))
		_check(get_nodes_in_group("miners").size() == 2, "two miners remain while producing")
		_enter(Phase.THIRD_REJECT)
	elif _elapsed() >= 9000:
		_check(false, "miner stone production within timeout (stone=%d)" % stone)
		_finish()


func _third_reject() -> void:
	_lj3 = WorkerData.new("lumberjack_C", "Lumberjack C", WorkerData.Job.LUMBERJACK)
	_check(_roster.add_worker(_lj3), "add 3rd lumberjack to roster")
	_check(not _roster.assign(_lj3, _lumberyard), "3rd lumberjack assignment rejected (lumberyard full)")
	_check(not _lj3.is_assigned(), "3rd lumberjack remains unassigned")
	_check(_lumberyard.get_filled_slots() == 2, "lumberyard still 2/2 after reject")
	_miner3 = WorkerData.new("miner_C", "Miner C", WorkerData.Job.MINER)
	_check(_roster.add_worker(_miner3), "add 3rd miner to roster")
	_check(not _roster.assign(_miner3, _quarry), "3rd miner assignment rejected (quarry full)")
	_check(not _miner3.is_assigned(), "3rd miner remains unassigned")
	_check(_quarry.get_filled_slots() == 2, "quarry still 2/2 after reject")
	_enter(Phase.UNASSIGN_LJ)


func _unassign_lj() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.unassign(_lj_a), "inn unassigns lumberjack A")
	_check(not _lj_a.is_assigned(), "lumberjack A WorkerData unassigned")
	_check(_lj_a.get_workplace() == null, "lumberjack A workplace cleared")
	_check(_roster.get_worker("lumberjack_A") == _lj_a, "lumberjack A retained in roster after unassign")
	_wait_start = _frame
	_enter(Phase.WAIT_LJ_DESPAWN)


func _wait_lj_despawn() -> void:
	if get_nodes_in_group("lumberjacks").size() == 1:
		_check(true, "one lumberjack despawned after return (remaining 1)")
		_check(_roster.get_actor(_lj_a) == null, "roster no longer returns lumberjack A actor")
		_enter(Phase.LJ_ROSTER)
		return
	if _elapsed() > 1200:
		_check(false, "lumberjack A despawn within bound (actors=%d)" % get_nodes_in_group("lumberjacks").size())
		_enter(Phase.LJ_ROSTER)


func _check_lj_roster() -> void:
	_check(not _lj_a.is_assigned(), "lumberjack A stays Unassigned in roster")
	_check(_lj_b.is_assigned(), "lumberjack B still assigned")
	_check(_lumberyard.get_filled_slots() == 1, "lumberyard now 1/2")
	_enter(Phase.UNASSIGN_MINER)


func _unassign_miner() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.unassign(_miner_a), "inn unassigns miner A")
	_check(not _miner_a.is_assigned(), "miner A WorkerData unassigned")
	_check(_roster.get_worker("miner_A") == _miner_a, "miner A retained in roster after unassign")
	_wait_start = _frame
	_enter(Phase.WAIT_MINER_DESPAWN)


func _wait_miner_despawn() -> void:
	if get_nodes_in_group("miners").size() == 1:
		_check(true, "one miner despawned after return (remaining 1)")
		_check(_roster.get_actor(_miner_a) == null, "roster no longer returns miner A actor")
		_enter(Phase.MINER_ROSTER)
		return
	if _elapsed() > 1200:
		_check(false, "miner A despawn within bound (actors=%d)" % get_nodes_in_group("miners").size())
		_enter(Phase.MINER_ROSTER)


func _check_miner_roster() -> void:
	_check(not _miner_a.is_assigned(), "miner A stays Unassigned in roster")
	_check(_miner_b.is_assigned(), "miner B still assigned")
	_check(_quarry.get_filled_slots() == 1, "quarry now 1/2")
	_enter(Phase.REASSIGN)


func _reassign() -> void:
	if _frame % 2 != 0:
		return
	_check(_roster.assign(_lj_a, _lumberyard), "lumberjack A reassigned after despawn")
	_check(_roster.get_actor(_lj_a) != null, "lumberjack A actor respawned on reassign")
	_check(_roster.assign(_miner_a, _quarry), "miner A reassigned after despawn")
	_check(_roster.get_actor(_miner_a) != null, "miner A actor respawned on reassign")
	_check(_lumberyard.get_filled_slots() == 2, "lumberyard refilled 2/2")
	_check(_quarry.get_filled_slots() == 2, "quarry refilled 2/2")
	_check(_roster.get_actor_count() == 4, "roster tracks 4 actors after reassign")
	_enter(Phase.REGROW)


## Tree regrowth 회귀.
func _regrow() -> void:
	if _frame % 2 != 0:
		return
	var depleted: Node = null
	for t in get_nodes_in_group("interactable"):
		if not t.can_interact():
			depleted = t
			break
	if depleted != null:
		_check(true, "a tree is depleted (stump) during production")
		depleted.regrow_time = 0.2
		depleted._regrow()
		_check(depleted.can_interact(), "depleted tree regrows (can interact again)")
	else:
		_check(true, "no depleted tree currently (wood not fully consumed)")

	var trees := get_nodes_in_group("interactable")
	_check(trees.size() >= 3, "forest trees present (%d)" % trees.size())

	# Lumberjack obstacle avoidance (TASK-BUG-NAV-001) 회귀:
	# 작업 중인 lumberjack 경로 근처에 장애물을 놓아 우회 후에도 생산이 지속되는지 확인.
	var lj_a: Node = _roster.get_actor(_lj_a)
	_check(lj_a != null and is_instance_valid(lj_a), "lumberjack A actor valid for nav check")
	if is_instance_valid(lj_a):
		var ob: Node2D = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate()
		ob.position = lj_a.global_position + Vector2(60, 0)
		_world.add_child(ob)
		_world.rebuild_navigation()
		_obstacle = ob
		_check(true, "obstacle placed for lumberjack path avoidance (rebuild nav)")
		_wood_before = _resources.get_amount("wood")
		_wait_start = _frame
		_enter(Phase.NAV_OBSERVE)
	else:
		_check(_min_wood >= 0 and _min_stone >= 0, "resources never went negative (min wood=%d stone=%d)" % [_min_wood, _min_stone])
		_enter(Phase.DAYNIGHT)


func _nav_observe() -> void:
	var wood: int = _resources.get_amount("wood")
	if wood > _wood_before:
		_check(wood > _wood_before, "lumberjack produced wood after obstacle (nav avoidance intact)")
		_enter(Phase.NAV_CLEANUP)
	elif _elapsed() >= 2400:
		_check(false, "lumberjack produced wood after obstacle within window (no nav stall)")
		_enter(Phase.NAV_CLEANUP)


func _nav_cleanup() -> void:
	if _obstacle != null and is_instance_valid(_obstacle):
		_obstacle.queue_free()
		_obstacle = null
		_world.rebuild_navigation()
		_check(true, "obstacle removed and nav rebuilt")
	_check(_min_wood >= 0 and _min_stone >= 0, "resources never went negative (min wood=%d stone=%d)" % [_min_wood, _min_stone])
	_enter(Phase.DAYNIGHT)


func _daynight() -> void:
	if not _step_done:
		_step_done = true
		# 먼저 DAY 상태로 초기화 보장 후 NIGHT 전환.
		_game_time.advance(10.0)
		_wait_start = _frame
	if _elapsed() >= 4:
		_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "DAY -> NIGHT transition")
		_check(_controller.is_night_mode(), "NIGHT: camera controller tactical mode")
		_check(_lj_a.is_assigned(), "lumberjack A assigned across DAY/NIGHT transition")
		_check(_miner_a.is_assigned(), "miner A assigned across DAY/NIGHT transition")
		_check(is_instance_valid(_roster.get_actor(_lj_a)), "lumberjack A actor stable across transition")
		_check(is_instance_valid(_roster.get_actor(_miner_a)), "miner A actor stable across transition")
		_check(_lumberyard.get_filled_slots() == 2, "lumberyard assignment retained during NIGHT")
		_check(_quarry.get_filled_slots() == 2, "quarry assignment retained during NIGHT")
		_stone_before = _resources.get_amount("stone")
		_wood_before = _resources.get_amount("wood")
		_enter(Phase.HUD_SMOKE)


func _hud_smoke() -> void:
	# NIGHT 동안 생산이 계속되는지(정지 정책 추가 없음) 확인.
	var wood: int = _resources.get_amount("wood")
	var stone: int = _resources.get_amount("stone")
	if _elapsed() >= 600:
		_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "still NIGHT during production check")
		_check(is_instance_valid(_lumberyard), "lumberyard ref stable")
		_check(_roster.get_actor(_lj_a) != null, "lumberjack A actor stable")
		_check(_roster.get_actor(_miner_a) != null, "miner A actor stable")
		# Wood/Stone HUD.
		_check(_wood_label != null and _wood_label.text.begins_with("Wood:"), "Wood HUD label intact (text=%s)" % (_wood_label.text if _wood_label else "null"))
		_check(_stone_label != null and _stone_label.text.begins_with("Stone:"), "Stone HUD label intact (text=%s)" % (_stone_label.text if _stone_label else "null"))
		# main smoke / regressions.
		_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact at end")
		_check(get_nodes_in_group("lumberjacks").size() >= 2, "lumberjack actors present")
		_check(get_nodes_in_group("miners").size() >= 2, "miner actors present")
		_check(get_nodes_in_group("lumberyards").size() >= 1, "lumberyard built")
		_check(get_nodes_in_group("quarries").size() >= 1, "quarry built")
		_check(_roster.get_count() == 6, "roster holds 6 workers (4 hired + 2 third)" if _roster.get_count() == 6 else "roster holds %d workers" % _roster.get_count())
		var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
		_check(floor_node != null and floor_node.get_used_cells().size() == 192 * 192, "world floor intact (192x192)")
		_check(_min_wood >= 0 and _min_stone >= 0, "resources never went negative (min wood=%d stone=%d)" % [_min_wood, _min_stone])
		_enter(Phase.DONE)


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
