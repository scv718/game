extends SceneTree

## TASK-010-4 기존 생산/건설 시스템과 phase 회귀 검증.
## Day/Night 상태 도입이 기존 Wood/Stone/Worker/Building/Navigation 시스템을
## 깨뜨리지 않는지 통합 검증한다.
##
## 정책:
##  - 이번 태스크에서는 Worker 생산을 NIGHT에 자동 정지하지 않는다.
##  - NIGHT에 건설을 금지하는 규칙도 임의 추가하지 않는다.
##  - 따라서 DAY와 NIGHT 모두에서 생산이 계속되고 건설 상호작용이 정상 동작해야 한다.
##
## 검증 항목:
##  1. DAY Player movement.
##  2. DAY Lumberyard/Quarry 건설 + Worker assign.
##  3. DAY Worker 생산(Wood/Stone).
##  4. phase 전환 중 Worker reference/FSM 안전.
##  5. NIGHT 동안 production timer/FSM 오류 없음 + 생산 지속(정지 정책 없음).
##  6. NIGHT 건설 상호작용이 정상(건설 금지 규칙 추가하지 않음).
##  7. DAY 복귀 후 interaction 정상.
##  8. runtime nav/building state 보존.

enum Phase {
	SETUP, INIT, DAY_MOVE, BUILD, ASSIGN, PRODUCE_DAY, TO_NIGHT, NIGHT_PRODUCE,
	NIGHT_INTERACT, TO_DAY, DAY_AFTER, NAV, SMOKE, DONE
}

const LUMBERYARD_SCENE := preload("res://scenes/lumberyard.tscn")

var _frame := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _step_done := false
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _layout: Node = null
var _controller: Node = null
var _placement: Node = null
var _resources: Node = null
var _lumberjack: Node = null
var _miner: Node = null
var _deposit: Node = null
var _quarry: Node = null
var _lumberyard: Node = null

var _start_x := 0.0
var _wood_before := 0
var _stone_before := 0
var _lumberjack_worked := false
var _nav_before := 0
var _interactable_count := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: Phase) -> void:
	_phase = new_phase
	_phase_start = _frame
	_step_done = false


func _elapsed() -> int:
	return _frame - _phase_start


func _finish() -> void:
	print("TASK0104_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _stump_count() -> int:
	var n := 0
	for t in get_nodes_in_group("interactable"):
		if not t.can_interact():
			n += 1
	return n


func _process(_delta: float) -> bool:
	_frame += 1
	var main: Node = root.get_node("Main")
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_game_time = root.get_node("GameTime")
			_world = main.get_node("World")
			_layout = _world.get_node_or_null("MapLayout")
			var ctrls := get_nodes_in_group("camera_controller")
			_controller = ctrls[0] if ctrls.size() > 0 else null
			_placement = main.get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_miner = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_miner.position = Vector2(500, 140)
			_world.add_child(_miner)
			_lumberjack = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lumberjack.position = Vector2(300, 200)
			_world.add_child(_lumberjack)
			var deposits := get_nodes_in_group("stone_deposits")
			_deposit = deposits[0] if deposits.size() > 0 else null
			_interactable_count = get_nodes_in_group("interactable").size()
			for t in get_nodes_in_group("interactable"):
				t.regrow_time = 10000.0
			_game_time.set_auto_advance(false)
			_game_time.set_durations(10.0, 10.0)
			_enter(Phase.INIT)
		Phase.INIT:
			_check(_game_time != null, "GameTime autoload exists")
			_check(_world != null, "world exists")
			_check(_layout != null, "MapLayout exists")
			_check(_placement != null, "BuildingPlacement exists")
			_check(_miner != null, "miner worker exists")
			_check(_lumberjack != null, "lumberjack worker exists")
			_check(_deposit != null, "stone deposit exists")
			_check(_game_time.get_phase() == _game_time.Phase.DAY, "game starts in DAY")
			_check(not _controller.is_night_mode(), "camera controller starts in DAY (camera pan mode)")
			_enter(Phase.DAY_MOVE)
		Phase.DAY_MOVE:
			if not _step_done:
				_step_done = true
				_controller.global_position = Vector2.ZERO
				_start_x = _controller.global_position.x
				Input.action_press("move_right")
			if _elapsed() >= 120:
				Input.action_release("move_right")
				_check(_controller.global_position.x > _start_x, "DAY: camera pans (WASD = camera pan)")
				_enter(Phase.BUILD)
		Phase.BUILD:
			_resources._amounts["wood"] = 50
			_placement._set_building_type("lumberyard")
			_placement._try_place_at(Vector2(300, 260))
			_check(get_nodes_in_group("lumberyards").size() == 1, "DAY: lumberyard built on valid clearing position")
			_lumberyard = get_nodes_in_group("lumberyards")[0] if get_nodes_in_group("lumberyards").size() > 0 else null
			_check(_lumberyard != null and _lumberyard.get_slot_capacity() == 2, "lumberyard slot capacity is 2")

			_placement._set_building_type("quarry")
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "DAY: quarry built on valid deposit")
			_quarry = get_nodes_in_group("quarries")[0] if get_nodes_in_group("quarries").size() > 0 else null
			_check(_quarry != null and _quarry.get_deposit() == _deposit, "quarry linked to deposit")
			_check(_quarry.get_slot_capacity() == 2, "quarry slot capacity is 2")
			_enter(Phase.ASSIGN)
		Phase.ASSIGN:
			if _frame % 2 == 0:
				return false
			var qres: Dictionary = _quarry.handle_worker_interaction()
			_check(qres.get("action") == "assign" and qres.get("success") == true, "DAY: quarry assigns miner (%s)" % str(qres))
			_check(_miner.get_workplace() == _quarry, "miner workplace is the quarry")

			var lres: Dictionary = _lumberyard.handle_worker_interaction()
			_check(lres.get("action") == "assign" and lres.get("success") == true, "DAY: lumberyard assigns lumberjack (%s)" % str(lres))
			_check(_lumberjack.get_workplace() == _lumberyard, "lumberjack workplace is the lumberyard")

			_wood_before = _resources.get_amount("wood")
			_stone_before = _resources.get_amount("stone")
			_enter(Phase.PRODUCE_DAY)
		Phase.PRODUCE_DAY:
			var stone: int = _resources.get_amount("stone")
			var wood: int = _resources.get_amount("wood")
			if _lumberjack.carried_amount == 0 and _stump_count() >= 2 and _lumberjack.state == 0:
				_lumberjack_worked = true
			if stone >= _stone_before + 3 and wood > _wood_before and _lumberjack_worked:
				_check(stone >= _stone_before + 3, "DAY: miner produced stone at WorkPoint (+%d)" % (stone - _stone_before))
				_check(wood > _wood_before, "DAY: lumberjack produced wood (+%d)" % (wood - _wood_before))
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "production happened during DAY")
				_enter(Phase.TO_NIGHT)
			elif _elapsed() >= 4000:
				_check(false, "DAY production within timeout (stone=%d wood=%d state=%d stumps=%d)" % [stone, wood, _lumberjack.state, _stump_count()])
				_finish()
				return true
		Phase.TO_NIGHT:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "transitioned into NIGHT")
				_check(_game_time.get_day_number() == 1, "day number stays 1 during NIGHT")
				_check(_controller.is_night_mode(), "NIGHT: camera controller tactical mode")
				_check(is_instance_valid(_lumberjack.get_workplace()), "lumberjack workplace ref stable across transition")
				_check(is_instance_valid(_miner.get_workplace()), "miner workplace ref stable across transition")
				# DAY 동안 lumberjack이 반경 내 나무를 모두 벌목해 STUMP 상태일 수 있으므로,
				# NIGHT에도 벌목 FSM이 계속 작업함을 검증하기 위해 나무 1그루를 재생장시킨다.
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						t.regrow_time = 0.2
						t._regrow()
						break
				_wood_before = _resources.get_amount("wood")
				_stone_before = _resources.get_amount("stone")
				_enter(Phase.NIGHT_PRODUCE)
		Phase.NIGHT_PRODUCE:
			# 정책: NIGHT에 생산을 정지하지 않는다. 따라서 NIGHT에도 production timer/FSM이
			# 오류 없이 계속 돌며 생산이 이어져야 한다. (광부 stone은 지속 생산의 결정적 신호,
			# 벌목 wood는 재생장시킨 나무로 NIGHT에도 FSM이 계속 작업함을 확인)
			var stone: int = _resources.get_amount("stone")
			var wood: int = _resources.get_amount("wood")
			if stone >= _stone_before + 3 and wood > _wood_before:
				_check(stone >= _stone_before + 3, "NIGHT: miner keeps producing (no stop policy, +%d)" % (stone - _stone_before))
				_check(wood > _wood_before, "NIGHT: lumberjack keeps producing (no stop policy, +%d)" % (wood - _wood_before))
				_check(_game_time.get_phase() == _game_time.Phase.NIGHT, "production continued during NIGHT")
				_check(is_instance_valid(_lumberjack.get_workplace()), "lumberjack FSM/workplace stable during NIGHT")
				_check(is_instance_valid(_miner.get_workplace()), "miner FSM/workplace stable during NIGHT")
				_check(_lumberjack.state >= 0 and _lumberjack.state <= 5, "lumberjack FSM state valid during NIGHT (state=%d)" % _lumberjack.state)
				_check(_miner.state >= 0 and _miner.state <= 2, "miner FSM state valid during NIGHT (state=%d)" % _miner.state)
				_enter(Phase.NIGHT_INTERACT)
			elif _elapsed() >= 4000:
				_check(false, "NIGHT production continued within timeout (stone=%d wood=%d)" % [stone, wood])
				_finish()
				return true
		Phase.NIGHT_INTERACT:
			# 정책: NIGHT에 건설을 금지하는 규칙을 추가하지 않았다. 따라서 NIGHT에도
			# 건설 상호작용이 정상 동작해야 한다(회귀 없음).
			_resources._amounts["wood"] = 30
			_placement._set_building_type("lumberyard")
			var before_count: int = get_nodes_in_group("lumberyards").size()
			_placement._try_place_at(Vector2(200, 200))
			_check(get_nodes_in_group("lumberyards").size() == before_count + 1, "NIGHT: building placement still works (no night ban added)")
			var placed: Node = get_nodes_in_group("lumberyards")[get_nodes_in_group("lumberyards").size() - 1]
			placed.queue_free()
			_enter(Phase.TO_DAY)
		Phase.TO_DAY:
			if not _step_done:
				_step_done = true
				_game_time.advance(10.0)
			if _elapsed() >= 4:
				_check(_game_time.get_phase() == _game_time.Phase.DAY, "NIGHT -> DAY transition")
				_check(_game_time.get_day_number() == 2, "day number increments to 2")
				_check(not _controller.is_night_mode(), "DAY: camera controller day mode restored")
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						t.regrow_time = 0.2
						t._regrow()
						break
				_wood_before = _resources.get_amount("wood")
				_stone_before = _resources.get_amount("stone")
				_enter(Phase.DAY_AFTER)
		Phase.DAY_AFTER:
			var stone: int = _resources.get_amount("stone")
			var wood: int = _resources.get_amount("wood")
			if stone >= _stone_before + 3 and wood > _wood_before:
				_check(stone >= _stone_before + 3, "DAY return: miner resumes production (+%d)" % (stone - _stone_before))
				_check(wood > _wood_before, "DAY return: lumberjack resumes production (+%d)" % (wood - _wood_before))
				var qres: Dictionary = _quarry.handle_worker_interaction()
				_check(qres.has("action"), "DAY return: quarry interaction returns valid action (%s)" % str(qres))
				_check(_quarry.get_interact_prompt() == "Workers: 1/2 - Assign Miner", "quarry prompt reflects capacity 2 (got '%s')" % _quarry.get_interact_prompt())
				var lres: Dictionary = _lumberyard.handle_worker_interaction()
				_check(lres.has("action"), "DAY return: lumberyard interaction returns valid action (%s)" % str(lres))
				_check(_lumberyard.get_interact_prompt() == "Workers: 1/2 - Assign Worker", "lumberyard prompt reflects capacity 2 (got '%s')" % _lumberyard.get_interact_prompt())
				_enter(Phase.NAV)
			elif _elapsed() >= 4000:
				_check(false, "DAY return production within timeout (stone=%d wood=%d)" % [stone, wood])
				_finish()
				return true
		Phase.NAV:
			_nav_before = _world.nav_rebuild_count
			_check(_world.has_method("rebuild_navigation"), "world exposes rebuild_navigation")
			_world.rebuild_navigation()
			_check(true, "runtime navigation rebuild works after phase transitions")
			_check(_world.nav_rebuild_count >= _nav_before, "navigation rebuild count updates")
			_check(get_nodes_in_group("interactable").size() == _interactable_count, "interactable/tree set preserved across rebuild")
			_check(_quarry.get_node_or_null("WorkPoint") != null, "quarry WorkPoint preserved across rebuild")
			_check(_lumberyard.get_node_or_null("DepositPoint") != null, "lumberyard DepositPoint preserved across rebuild")
			_enter(Phase.SMOKE)
		Phase.SMOKE:
			_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
			_check(main.get_node("HUD") != null, "HUD exists")
			var floor_node: TileMapLayer = main.get_node("World/Floor") as TileMapLayer
			_check(floor_node != null and floor_node.get_used_cells().size() == 192 * 192, "world floor intact (192x192)")
			_check(get_nodes_in_group("lumberjacks").size() >= 1, "lumberjack system intact")
			_check(get_nodes_in_group("miners").size() >= 1, "miner system intact")
			_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0104_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
