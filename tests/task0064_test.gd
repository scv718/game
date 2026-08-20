extends SceneTree

enum Phase {
	SETUP, NO_AUTOSTART, ASSIGN, WORK_LOOP, REGROW_REWORK, UNASSIGN_EMPTY_IDLE,
	REASSIGN_CARRY_UNASSIGN, FINAL_DEPOSIT, WORKPLACE_FREE, WORKPLACE_FREE_WORK,
	WORKPLACE_FREE_IDLE, REASSIGN_AFTER_FREE, SECOND_WORK, DONE
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _failed := false
var _world: Node = null
var _lj: Node = null
var _lj_start_pos := Vector2.ZERO
var _no_move_frames := 0
var _ly: Node = null
var _ly2: Node = null
var _ly3: Node = null
var _wood_before_assign := 0
var _wood_first_loop := 0
var _wood_final_before := 0
var _wood_after_free := 0
var _stump_count := 0
var _regrow_done := false
var _saw_work := false


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
			_world = main.get_node("World")
			_lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lj.position = Vector2(300, 200)
			_world.add_child(_lj)
			_lj_start_pos = _lj.global_position
			for t in get_nodes_in_group("interactable"):
				t.regrow_time = 10000.0
				t.max_amount = 1
				t.current_amount = 1
			_ly = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate() as Node2D
			_ly.position = Vector2(180, 240)
			_world.add_child(_ly)
			_world.rebuild_navigation()
			_check(_lj.state == 0, "worker starts IDLE (state=%d)" % _lj.state)
			_check(not _lj.is_assigned(), "worker has no workplace at start")
			_enter(Phase.NO_AUTOSTART)
		Phase.NO_AUTOSTART:
			if _lj.global_position.distance_to(_lj_start_pos) < 2.0:
				_no_move_frames += 1
			if _elapsed() >= 150:
				_check(_no_move_frames >= 140, "no auto-start after Lumberyard built (still frames=%d)" % _no_move_frames)
				_check(_lj.state == 0, "worker stays IDLE after build (state=%d)" % _lj.state)
				_check(not _lj.is_assigned(), "no workplace before assign")
				_check(_ly.get_filled_slots() == 0, "lumberyard starts Workers: 0/1")
				_enter(Phase.ASSIGN)
		Phase.ASSIGN:
			if _frame % 2 == 0:
				return false
			_wood_before_assign = root.get_node("VillageResources").get_amount("wood")
			var res: Dictionary = _ly.handle_worker_interaction()
			_check(res.get("action") == "assign" and res.get("success") == true, "interaction assigns worker (%s)" % str(res))
			_check(_ly.get_filled_slots() == 1, "filled becomes 1 after assign (got %d)" % _ly.get_filled_slots())
			_check(_ly.has_worker(_lj), "lumberyard has worker")
			_check(_lj.get_workplace() == _ly, "worker workplace is the assigned lumberyard")
			_check(not _ly.assign_worker(_lj), "duplicate assign rejected")
			_ly2 = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate() as Node2D
			_ly2.position = Vector2(600, 200)
			_world.add_child(_ly2)
			_world.rebuild_navigation()
			_check(not _ly2.assign_worker(_lj), "second workplace rejects already-assigned worker")
			_enter(Phase.WORK_LOOP)
		Phase.WORK_LOOP:
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			_stump_count = 0
			for t in get_nodes_in_group("interactable"):
				if not t.can_interact():
					_stump_count += 1
			if wood >= 3 and _stump_count >= 3:
				_check(wood > _wood_before_assign, "production loop produced wood (+%d)" % (wood - _wood_before_assign))
				_check(_stump_count >= 3, "all in-radius trees become STUMP (count=%d)" % _stump_count)
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						_check(t.state == 1, "depleted tree enters STUMP state")
				_wood_first_loop = wood
				_enter(Phase.REGROW_REWORK)
		Phase.REGROW_REWORK:
			if not _regrow_done:
				var stumped_before: Array = []
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						stumped_before.append(t)
				_regrow_all_trees()
				var mature := 0
				for t in get_nodes_in_group("interactable"):
					if t.can_interact():
						mature += 1
				_check(mature == get_nodes_in_group("interactable").size(), "all trees regrew to MATURE (mature=%d total=%d)" % [mature, get_nodes_in_group("interactable").size()])
				_check(stumped_before.size() >= 3, "at least 3 trees were stumped before regrow (count=%d)" % stumped_before.size())
				for t in stumped_before:
					_check(is_instance_valid(t) and t.can_interact(), "previously stumped tree regrew to MATURE (%s)" % t.name)
				_regrow_done = true
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			if wood >= _wood_first_loop + 3:
				_check(wood >= _wood_first_loop + 3, "worker resumes work after tree regrowth (+%d)" % (wood - _wood_first_loop))
				_enter(Phase.UNASSIGN_EMPTY_IDLE)
		Phase.UNASSIGN_EMPTY_IDLE:
			if _lj.state == 0 and _lj.carried_amount == 0:
				if _frame % 2 == 0:
					return false
				var ok: bool = _ly.unassign_worker(_lj)
				_check(ok, "unassign succeeds while empty-handed")
				_check(_ly.get_filled_slots() == 0, "filled back to 0 after unassign (got %d)" % _ly.get_filled_slots())
				_check(_lj.state == 0, "worker immediately IDLE after empty unassign (state=%d)" % _lj.state)
				_check(not _lj.is_assigned(), "workplace released after empty unassign")
				_enter(Phase.REASSIGN_CARRY_UNASSIGN)
		Phase.REASSIGN_CARRY_UNASSIGN:
			if _frame % 2 == 0:
				return false
			_check(_ly.assign_worker(_lj), "reassign after unassign succeeds")
			_wood_final_before = root.get_node("VillageResources").get_amount("wood")
			_lj.carried_resource_id = "wood"
			_lj.carried_amount = 3
			var deposit: Node = _ly.get_node("DepositPoint")
			_lj.global_position = deposit.global_position - Vector2(2, 0)
			var ok: bool = _ly.unassign_worker(_lj)
			_check(ok, "unassign succeeds while carrying wood")
			_check(_ly.get_filled_slots() == 0, "slot freed on carrying unassign")
			_check(_lj.state == 4, "worker in RETURN for final deposit (state=%d)" % _lj.state)
			_check(_lj.is_assigned(), "workplace retained until final deposit")
			_enter(Phase.FINAL_DEPOSIT)
		Phase.FINAL_DEPOSIT:
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			if wood > _wood_final_before:
				_check(wood - _wood_final_before == 3, "final deposit adds exactly carried 3 wood (+%d)" % (wood - _wood_final_before))
				_check(_lj.carried_amount == 0, "carried cleared after final deposit")
				_check(_lj.state == 0, "worker IDLE after final deposit (state=%d)" % _lj.state)
				_check(not _lj.is_assigned(), "workplace released after final deposit")
				_enter(Phase.WORKPLACE_FREE)
		Phase.WORKPLACE_FREE:
			if _frame % 2 == 0:
				return false
			_ly3 = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate() as Node2D
			_ly3.position = Vector2(180, 300)
			_world.add_child(_ly3)
			_world.rebuild_navigation()
			_check(_ly3.assign_worker(_lj), "assign to second workplace succeeds")
			_check(_lj.get_workplace() == _ly3, "worker workplace is the second lumberyard")
			_regrow_all_trees()
			_saw_work = false
			_enter(Phase.WORKPLACE_FREE_WORK)
		Phase.WORKPLACE_FREE_WORK:
			if _lj.state != 0:
				_saw_work = true
			if _elapsed() >= 240:
				_check(_saw_work, "worker engaged in work at second workplace")
				_wood_after_free = root.get_node("VillageResources").get_amount("wood")
				_ly3.queue_free()
				_enter(Phase.WORKPLACE_FREE_IDLE)
		Phase.WORKPLACE_FREE_IDLE:
			if _elapsed() < 3:
				return false
			if _elapsed() >= 360:
				_check(not is_instance_valid(_ly3), "lumberyard destroyed")
				_check(not _lj.is_assigned(), "workplace released after destruction (no freed reference)")
				_check(_lj.state == 0, "worker IDLE after workplace destroyed (state=%d)" % _lj.state)
				_enter(Phase.REASSIGN_AFTER_FREE)
		Phase.REASSIGN_AFTER_FREE:
			if _frame % 2 == 0:
				return false
			_ly = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate() as Node2D
			_ly.position = Vector2(360, 240)
			_world.add_child(_ly)
			_world.rebuild_navigation()
			_check(_ly.assign_worker(_lj), "reassign after workplace destroyed succeeds")
			_check(_lj.get_workplace() == _ly, "workplace is the new lumberyard")
			_wood_after_free = root.get_node("VillageResources").get_amount("wood")
			_regrow_all_trees()
			_enter(Phase.SECOND_WORK)
		Phase.SECOND_WORK:
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			if wood > _wood_after_free:
				_check(wood > _wood_after_free, "worker produces again after destroy+reassign (+%d)" % (wood - _wood_after_free))
				_enter(Phase.DONE)
		Phase.DONE:
			print("TASK0064_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 25000:
		print("TASK0064_RESULT=TIMEOUT phase=%s state=%d wood=%d carried=%d stumps=%d" % [str(_phase), _lj.state, root.get_node("VillageResources").get_amount("wood"), _lj.carried_amount, _stump_count])
		quit()
		return true
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)