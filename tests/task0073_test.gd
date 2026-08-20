extends SceneTree

enum Phase {
	SETUP, NO_AUTOSTART, ASSIGN, WORKPOINT, UNASSIGN, REASSIGN, LUMBERYARD_REGRESSION, DONE
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _failed := false
var _world: Node = null
var _placement: Node = null
var _resources: Node = null
var _deposit: Node = null
var _quarry: Node = null
var _miner: Node = null
var _lumberjack: Node = null
var _miner_start_pos := Vector2.ZERO
var _no_move_frames := 0
var _stone_before := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: Phase) -> void:
	_phase = new_phase
	_phase_start = _frame


func _elapsed() -> int:
	return _frame - _phase_start


func _process(_delta: float) -> bool:
	_frame += 1
	var main: Node = root.get_node("Main")
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			_world = main.get_node("World")
			_placement = main.get_node("BuildingPlacement")
			_resources = root.get_node("VillageResources")
			_miner = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_lumberjack = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_miner.position = Vector2(500, 140)
			_lumberjack.position = Vector2(300, 200)
			_world.add_child(_miner)
			_world.add_child(_lumberjack)
			var deposits := get_nodes_in_group("stone_deposits")
			_deposit = deposits[0] if deposits.size() > 0 else null

			_check(_miner != null, "miner exists in world")
			_check(get_nodes_in_group("miners").size() == 1, "exactly 1 miner in world (got %d)" % get_nodes_in_group("miners").size())
			if _miner == null or _deposit == null:
				_finish()
				return true
			_miner_start_pos = _miner.global_position
			_check(not _miner.is_assigned(), "miner starts unassigned")
			_check(_miner.state == 0, "miner starts IDLE (state=%d)" % _miner.state)
			_check(not _miner.is_gathering(), "miner not gathering at start")

			_placement._set_building_type("quarry")
			_resources._amounts["wood"] = 20
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "quarry built on deposit")
			_check(_deposit.is_occupied(), "deposit occupied by quarry")
			_quarry = get_nodes_in_group("quarries")[0]
			_check(_quarry.get_slot_capacity() == 2, "quarry slot capacity is 2")
			_check(_quarry.get_filled_slots() == 0, "quarry starts with 0 workers")
			_check(_quarry.get_interact_prompt() == "Workers: 0/2 - Assign Miner", "quarry prompt Workers: 0/2 - Assign Miner (got '%s')" % _quarry.get_interact_prompt())
			var interact: Node = _quarry.get_node("Interact")
			_check(interact.prompt == "Workers: 0/2 - Assign Miner", "quarry interact prompt syncs (got '%s')" % interact.prompt)
			_check(interact.collision_layer == 8, "quarry interact area on layer 8")
			_stone_before = _resources.get_amount("stone")
			_no_move_frames = 0
			_enter(Phase.NO_AUTOSTART)
		Phase.NO_AUTOSTART:
			if _miner.global_position.distance_to(_miner_start_pos) < 2.0:
				_no_move_frames += 1
			if _elapsed() >= 150:
				_check(_no_move_frames >= 140, "miner does not auto-start after Quarry built (still frames=%d)" % _no_move_frames)
				_check(_miner.state == 0, "miner stays IDLE after Quarry built (state=%d)" % _miner.state)
				_check(not _miner.is_assigned(), "miner has no workplace before assign")
				_check(_quarry.get_filled_slots() == 0, "quarry still 0/1 after build only")
				_check(_resources.get_amount("stone") == _stone_before, "no stone produced by unassigned miner")
				_enter(Phase.ASSIGN)
		Phase.ASSIGN:
			if _frame % 2 == 0:
				return false
			_stone_before = _resources.get_amount("stone")
			var res: Dictionary = _quarry.handle_worker_interaction()
			_check(res.get("action") == "assign" and res.get("success") == true, "quarry interaction assigns miner (%s)" % str(res))
			_check(_quarry.get_filled_slots() == 1, "quarry filled becomes 1 after assign (got %d)" % _quarry.get_filled_slots())
			_check(_quarry.has_worker(_miner), "quarry has worker")
			_check(_miner.get_workplace() == _quarry, "miner workplace is exactly the quarry")
			_check(_miner.get_workplace().is_in_group("quarries"), "miner workplace is a Quarry")
			_check(_miner.is_assigned(), "miner is_assigned true")
			_check(_miner.state == 1, "miner enters MOVE_TO_WORK after assign (TASK-007-4, state=%d)" % _miner.state)
			_check(_resources.get_amount("stone") == _stone_before, "no stone produced right after assign (production requires arriving at WorkPoint)")
			_check(_quarry.get_interact_prompt() == "Workers: 1/2 - Assign Miner", "quarry prompt Workers: 1/2 - Assign Miner (got '%s')" % _quarry.get_interact_prompt())
			var interact: Node = _quarry.get_node("Interact")
			_check(interact.prompt == "Workers: 1/2 - Assign Miner", "quarry interact prompt updates to 1/2 (got '%s')" % interact.prompt)
			_check(not _quarry.assign_worker(_miner), "duplicate assign rejected")
			var second_quarry: Node = (load("res://scenes/quarry.tscn") as PackedScene).instantiate()
			_world.add_child(second_quarry)
			_check(not second_quarry.assign_worker(_miner), "second quarry rejects already-assigned miner")
			_check(second_quarry.get_filled_slots() == 0, "second quarry stays empty")
			_check(_quarry._pick_available_worker() == null, "quarry finds no other assignable miner while slot full")
			second_quarry.queue_free()
			_enter(Phase.WORKPOINT)
		Phase.WORKPOINT:
			if _frame % 2 == 0:
				return false
			var mining_point: Node = _quarry.get_node_or_null("MiningPoint")
			var work_point: Node = _quarry.get_node_or_null("WorkPoint")
			_check(mining_point != null, "quarry has MiningPoint marker")
			_check(work_point != null, "quarry has WorkPoint marker")
			if mining_point != null:
				_check(mining_point is Marker2D, "MiningPoint is a Marker2D")
			_enter(Phase.UNASSIGN)
		Phase.UNASSIGN:
			if _frame % 2 == 0:
				return false
			var ok: bool = _quarry.unassign_worker(_miner)
			_check(ok, "unassign succeeds")
			_check(_quarry.get_filled_slots() == 0, "quarry filled back to 0 after unassign (got %d)" % _quarry.get_filled_slots())
			_check(_quarry.get_interact_prompt() == "Workers: 0/2 - Assign Miner", "quarry prompt back to Assign Miner (got '%s')" % _quarry.get_interact_prompt())
			_check(not _miner.is_assigned(), "miner workplace released after unassign")
			_check(_miner.state == 0, "miner IDLE after unassign (state=%d)" % _miner.state)
			_check(not _miner.is_gathering(), "miner not gathering after unassign")
			_enter(Phase.REASSIGN)
		Phase.REASSIGN:
			if _frame % 2 == 0:
				return false
			_check(_quarry.assign_worker(_miner), "reassign after unassign succeeds")
			_check(_quarry.get_filled_slots() == 1, "quarry filled 1 after reassign (got %d)" % _quarry.get_filled_slots())
			_check(_miner.get_workplace() == _quarry, "miner workplace is the quarry again after reassign")
			_enter(Phase.LUMBERYARD_REGRESSION)
		Phase.LUMBERYARD_REGRESSION:
			if _frame % 2 == 0:
				return false
			var picked: Node = _quarry._pick_available_worker()
			_check(picked == null, "quarry does not pick assigned miner as available")
			_quarry.unassign_worker(_miner)
			_placement._set_building_type("lumberyard")
			_resources._amounts["wood"] = 10
			var ly_count := get_nodes_in_group("lumberyards").size()
			var spot := Vector2(500, 300)
			if _placement._is_valid_position(spot):
				_placement._try_place_at(spot)
				var ljs := get_nodes_in_group("lumberyards")
				_check(ljs.size() == ly_count + 1, "lumberyard placement still works after quarry mode (count=%d)" % ljs.size())
				if ljs.size() > 0:
					var ly: Node = ljs[0]
					var ly_pick: Node = ly._pick_available_worker()
					_check(ly_pick == _lumberjack, "lumberyard picks the lumberjack, not the miner")
					var ly_res: Dictionary = ly.handle_worker_interaction()
					_check(ly_res.get("success") == true, "lumberyard assign works (regression)")
					_check(_lumberjack.get_workplace() == ly, "lumberjack workplace is the lumberyard (regression)")
					_check(not _miner.is_assigned(), "miner unaffected by lumberyard flow")
			else:
				print("SKIP: lumberyard spot (%s) collides in test world, skipping lumberyard regression check" % str(spot))
			_enter(Phase.DONE)
		Phase.DONE:
			print("TASK0073_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 25000:
		print("TASK0073_RESULT=TIMEOUT phase=%s miner_state=%d stone=%d" % [str(_phase), _miner.state if _miner != null else -1, _resources.get_amount("stone")])
		quit()
		return true
	return false


func _finish() -> void:
	print("TASK0073_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)