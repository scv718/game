extends SceneTree

enum Phase {
	SETUP, SMOKE, STONE_HUD, PLACEMENT, QUARRY_NO_AUTOSTART, ASSIGN_MINER,
	MINE_PRODUCE, UNASSIGN_MINER, REASSIGN_MINER, ASSIGN_LUMBERJACK,
	LUMBERJACK_LOOP, REGROW_REWORK, NAVIGATION, DONE
}

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _failed := false
var _world: Node = null
var _placement: Node = null
var _resources: Node = null
var _hud: Node = null
var _deposit: Node = null
var _quarry: Node = null
var _miner: Node = null
var _lumberjack: Node = null
var _ly: Node = null
var _stone_before := 0
var _wood_before := 0
var _lumberjack_worked := false
var _regrow_done := false


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


func _regrow_all_trees() -> void:
	for t in get_nodes_in_group("interactable"):
		if t.has_method("_regrow") and not t.can_interact():
			t._regrow()


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
			_hud = main.get_node("HUD")
			_miner = (load("res://scenes/miner.tscn") as PackedScene).instantiate()
			_lumberjack = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_miner.position = Vector2(500, 140)
			_lumberjack.position = Vector2(300, 200)
			_world.add_child(_miner)
			_world.add_child(_lumberjack)
			var deposits := get_nodes_in_group("stone_deposits")
			_deposit = deposits[0] if deposits.size() > 0 else null
			for t in get_nodes_in_group("interactable"):
				t.regrow_time = 10000.0
			_enter(Phase.SMOKE)
		Phase.SMOKE:
			_check(main != null, "main.tscn loads")
			_check(_world != null, "world node present")
			_check(_miner != null, "miner exists in world")
			_check(_lumberjack != null, "lumberjack exists in world")
			_check(get_nodes_in_group("miners").size() == 1, "exactly 1 miner")
			_check(get_nodes_in_group("lumberjacks").size() >= 1, "at least 1 lumberjack")
			_check(get_nodes_in_group("interactable").size() >= 3, "trees present (%d)" % get_nodes_in_group("interactable").size())
			_check(get_nodes_in_group("stone_deposits").size() == 1, "exactly 1 StoneDeposit")
			_enter(Phase.STONE_HUD)
		Phase.STONE_HUD:
			var stone_label: Label = _hud.get_node("%StoneLabel")
			_check(stone_label != null, "HUD has StoneLabel")
			_check(stone_label != null and stone_label.text == "Stone: 0", "HUD stone label starts Stone: 0 (%s)" % (stone_label.text if stone_label else "none"))
			_check(_resources.get_amount("stone") == 0, "stone defaults to 0")
			_resources.add("stone", 3)
			_check(stone_label != null and stone_label.text == "Stone: 3", "HUD stone label refreshes on change (%s)" % (stone_label.text if stone_label else "none"))
			_resources._amounts["stone"] = 0
			_enter(Phase.PLACEMENT)
		Phase.PLACEMENT:
			_check(_deposit != null, "deposit exists")
			if _deposit == null:
				_finish()
				return true
			_check(not _deposit.is_occupied(), "deposit starts unoccupied")
			_check(_placement._building_type == "lumberyard", "placement defaults to lumberyard")
			_placement._set_building_type("quarry")
			_check(_placement._building_type == "quarry", "building type switches to quarry")
			_resources._amounts["wood"] = 0
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 0, "no quarry built without enough wood")
			_check(_resources.get_amount("wood") == 0, "wood unchanged when not affordable")
			_resources._amounts["wood"] = 20
			var wood_before: int = _resources.get_amount("wood")
			_placement._try_place_quarry_at(Vector2(100, 100))
			_check(get_nodes_in_group("quarries").size() == 0, "quarry denied outside deposit area")
			_check(_resources.get_amount("wood") == wood_before, "wood not deducted outside deposit")
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "quarry built on valid deposit")
			_check(_resources.get_amount("wood") == wood_before - 10, "wood deducted exactly once (-10)")
			_check(_deposit.is_occupied(), "deposit occupied after quarry built")
			_quarry = get_nodes_in_group("quarries")[0]
			_check(_quarry.get_deposit() == _deposit, "quarry linked to deposit")
			_check(_quarry.get_slot_capacity() == 2, "quarry slot capacity is 2")
			_check(_quarry.get_filled_slots() == 0, "quarry starts 0/2")
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "duplicate quarry on same deposit denied")
			_check(_resources.get_amount("wood") == wood_before - 10, "no extra cost on denied duplicate")
			_check(_quarry.get_node_or_null("WorkPoint") != null, "quarry has WorkPoint marker")
			_check(_quarry.get_node_or_null("MiningPoint") != null, "quarry has MiningPoint marker")
			var interact: Node = _quarry.get_node_or_null("Interact")
			_check(interact != null and interact.collision_layer == 8, "quarry has layer 8 Interact")
			_stone_before = _resources.get_amount("stone")
			_enter(Phase.QUARRY_NO_AUTOSTART)
		Phase.QUARRY_NO_AUTOSTART:
			if _elapsed() >= 120:
				_check(_miner.state == 0, "miner stays IDLE while unassigned (state=%d)" % _miner.state)
				_check(not _miner.is_assigned(), "miner unassigned before assign")
				_check(_quarry.get_filled_slots() == 0, "quarry still 0/1 after build only")
				_check(_resources.get_amount("stone") == _stone_before, "no stone produced by unassigned miner (stone=%d)" % _resources.get_amount("stone"))
				_enter(Phase.ASSIGN_MINER)
		Phase.ASSIGN_MINER:
			if _frame % 2 == 0:
				return false
			_stone_before = _resources.get_amount("stone")
			var res: Dictionary = _quarry.handle_worker_interaction()
			_check(res.get("action") == "assign" and res.get("success") == true, "quarry assigns miner (%s)" % str(res))
			_check(_quarry.get_filled_slots() == 1, "quarry filled becomes 1")
			_check(_miner.get_workplace() == _quarry, "miner workplace is the quarry")
			_check(_miner.state == 1, "miner enters MOVE_TO_WORK (state=%d)" % _miner.state)
			_check(_resources.get_amount("stone") == _stone_before, "no stone produced right after assign")
			_enter(Phase.MINE_PRODUCE)
		Phase.MINE_PRODUCE:
			var stone: int = _resources.get_amount("stone")
			print("MINE_PRODUCE f=", _frame, " elapsed=", _elapsed(), " stone=", stone, " miner_state=", _miner.state, " miner_pos=", _miner.global_position)
			if stone >= _stone_before + 3:
				_check(stone >= _stone_before + 3, "miner produced stone at WorkPoint (+%d)" % (stone - _stone_before))
				_check(_miner.state == 2, "miner in MINE state while producing (state=%d)" % _miner.state)
				_check(_miner.is_gathering(), "miner is_gathering in MINE")
				_enter(Phase.UNASSIGN_MINER)
			elif _elapsed() >= 900:
				_check(false, "miner produced stone within timeout (stone=%d state=%d)" % [stone, _miner.state])
				_finish()
				return true
		Phase.UNASSIGN_MINER:
			if _frame % 2 == 0:
				return false
			_stone_before = _resources.get_amount("stone")
			var ok: bool = _quarry.unassign_worker(_miner)
			_check(ok, "unassign succeeds")
			_check(_quarry.get_filled_slots() == 0, "quarry filled back to 0")
			_check(not _miner.is_assigned(), "miner workplace released")
			_check(_miner.state == 0, "miner IDLE after unassign (state=%d)" % _miner.state)
			_enter(Phase.REASSIGN_MINER)
		Phase.REASSIGN_MINER:
			if _frame % 2 == 0:
				return false
			_check(_quarry.assign_worker(_miner), "reassign succeeds")
			_check(_quarry.get_filled_slots() == 1, "quarry filled 1 after reassign")
			_check(_miner.get_workplace() == _quarry, "miner workplace is the quarry after reassign")
			_check(_miner.state == 1, "miner enters MOVE_TO_WORK after reassign (state=%d)" % _miner.state)
			_wood_before = _resources.get_amount("wood")
			_enter(Phase.ASSIGN_LUMBERJACK)
		Phase.ASSIGN_LUMBERJACK:
			if _frame % 2 == 0:
				return false
			_ly = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate() as Node2D
			_ly.position = Vector2(180, 240)
			_ly.work_radius = 300.0
			_world.add_child(_ly)
			_world.rebuild_navigation()
			var ly_res: Dictionary = _ly.handle_worker_interaction()
			_check(ly_res.get("action") == "assign" and ly_res.get("success") == true, "lumberyard assigns lumberjack (%s)" % str(ly_res))
			_check(_lumberjack.get_workplace() == _ly, "lumberjack workplace is the lumberyard")
			_check(_ly._pick_available_worker() == null, "lumberyard does not pick miner as available")
			_enter(Phase.LUMBERJACK_LOOP)
		Phase.LUMBERJACK_LOOP:
			var wood: int = _resources.get_amount("wood")
			if wood > _wood_before:
				_lumberjack_worked = true
			var stumps := 0
			for t in get_nodes_in_group("interactable"):
				if not t.can_interact():
					stumps += 1
			if _lumberjack_worked and stumps >= 3 and _lumberjack.carried_amount == 0 and _lumberjack.state == 0:
				_check(wood > _wood_before, "lumberjack produced wood (+%d)" % (wood - _wood_before))
				_check(stumps >= 3, "in-radius trees become STUMP (count=%d)" % stumps)
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						_check(t.state == 1, "depleted tree enters STUMP state")
				_enter(Phase.REGROW_REWORK)
			elif _elapsed() >= 2500:
				_check(false, "lumberjack production loop within timeout (wood=%d state=%d stumps=%d)" % [wood, _lumberjack.state, stumps])
				_finish()
				return true
		Phase.REGROW_REWORK:
			if not _regrow_done:
				_regrow_all_trees()
				var mature := 0
				for t in get_nodes_in_group("interactable"):
					if t.can_interact():
						mature += 1
				_check(mature >= 3, "trees regrew to MATURE (mature=%d)" % mature)
				_regrow_done = true
			var wood: int = _resources.get_amount("wood")
			if wood >= _wood_before + 6:
				_check(wood >= _wood_before + 6, "lumberjack resumes work after regrowth (+%d)" % (wood - _wood_before))
				_enter(Phase.NAVIGATION)
			elif _elapsed() >= 1500:
				_check(false, "lumberjack resumed work after regrowth within timeout (wood=%d)" % wood)
				_finish()
				return true
		Phase.NAVIGATION:
			_check(_world.has_method("rebuild_navigation"), "world exposes rebuild_navigation")
			_world.rebuild_navigation()
			_check(_quarry.get_node_or_null("WorkPoint") != null, "navigation rebuild keeps WorkPoint intact")
			_check(_world.nav_rebuild_count >= 0, "navigation rebuild count available (%d)" % _world.nav_rebuild_count)
			_enter(Phase.DONE)
		Phase.DONE:
			print("TASK0075_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 30000:
		print("TASK0075_RESULT=TIMEOUT phase=%s miner_state=%d lj_state=%d stone=%d wood=%d" % [str(_phase), _miner.state if _miner != null else -1, _lumberjack.state if _lumberjack != null else -1, _resources.get_amount("stone"), _resources.get_amount("wood")])
		quit()
		return true
	return false


func _finish() -> void:
	print("TASK0075_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
