extends SceneTree

enum Phase {
	SETUP, NO_AUTOSTART, BUILD_YARD, STILL_IDLE_AFTER_BUILD, ASSIGN,
	WORK_LOOP, OUT_OF_RADIUS_CHECK, UNASSIGN_EMPTY_IDLE, NO_SEARCH_AFTER_UNASSIGN,
	REASSIGN_CARRY_UNASSIGN, FINAL_DEPOSIT, DONE
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _failed := false
var _world: Node = null
var _lj: Node = null
var _lj_start_pos := Vector2.ZERO
var _no_move_frames := 0
var _pos: Vector2 = Vector2.ZERO
var _ly: Node = null
var _far_tree: Node = null
var _far_dist := 0.0
var _wood_assign := 0
var _wood_final_before := 0
var _wood_deposited := false
var _out_radius_frames := 0
var _saw_move := false

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
			_world = main.get_node("World")
			_lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lj.position = Vector2(300, 200)
			_world.add_child(_lj)
			_lj_start_pos = _lj.global_position
			print("  setup lumberjack=%s trees=%d" % [str(_lj_start_pos), get_nodes_in_group("interactable").size()])
			_enter(Phase.NO_AUTOSTART)
		Phase.NO_AUTOSTART:
			if _lj.global_position.distance_to(_lj_start_pos) < 2.0:
				_no_move_frames += 1
			if _frame % 60 == 0:
				print("  noautostart frame=%d state=%d dist=%.1f" % [_frame, _lj.state, _lj.global_position.distance_to(_lj_start_pos)])
			if _elapsed() >= 150:
				_check(_no_move_frames >= 140, "unassigned stays idle with trees around (frames=%d)" % _no_move_frames)
				_check(_lj.state == 0, "unassigned stays IDLE with trees around (state=%d)" % _lj.state)
				_check(not _lj.is_assigned(), "no workplace before assignment")
				var tree_scene: PackedScene = load("res://scenes/tree.tscn")
				_far_tree = tree_scene.instantiate() as Node2D
				_far_tree.position = Vector2(1200, 700)
				_world.add_child(_far_tree)
				_world.rebuild_navigation()
				_far_dist = _lj.global_position.distance_to(_far_tree.global_position)
				_enter(Phase.BUILD_YARD)
		Phase.BUILD_YARD:
			var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
			_ly = ly_scene.instantiate() as Node2D
			_ly.position = Vector2(180, 240)
			_world.add_child(_ly)
			_world.rebuild_navigation()
			_check(not _ly.has_worker(_lj), "lumberyard starts with no workers")
			_no_move_frames = 0
			_enter(Phase.STILL_IDLE_AFTER_BUILD)
		Phase.STILL_IDLE_AFTER_BUILD:
			if _lj.global_position.distance_to(_lj_start_pos) < 2.0:
				_no_move_frames += 1
			if _frame % 60 == 0:
				print("  stillidle frame=%d state=%d dist=%.1f" % [_frame, _lj.state, _lj.global_position.distance_to(_lj_start_pos)])
			if _elapsed() >= 220:
				_check(_no_move_frames >= 210, "no auto-start after Lumberyard built without assignment (frames=%d)" % _no_move_frames)
				_check(_lj.state == 0, "stays IDLE after Lumberyard built without assignment (state=%d)" % _lj.state)
				_enter(Phase.ASSIGN)
		Phase.ASSIGN:
			if _frame % 2 == 0:
				return false
			_wood_assign = root.get_node("VillageResources").get_amount("wood")
			var ok: bool = _ly.assign_worker(_lj)
			_check(ok, "assign succeeds")
			_check(_lj.get_workplace() == _ly, "workplace is the assigned lumberyard")
			_check(_lj.is_assigned(), "is_assigned true")
			_check(not _ly.assign_worker(_lj), "duplicate assign rejected")
			_enter(Phase.WORK_LOOP)
		Phase.WORK_LOOP:
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			if wood > _wood_assign:
				_wood_deposited = true
				print("  workloop wood_before=%d wood_now=%d state=%d carried=%d" % [_wood_assign, wood, _lj.state, _lj.carried_amount])
			var stump_count := 0
			for t in get_nodes_in_group("interactable"):
				if not t.can_interact():
					stump_count += 1
			if _wood_deposited and _lj.carried_amount == 0 and _lj.state == 0 and stump_count >= 3:
				var wood_now: int = root.get_node("VillageResources").get_amount("wood")
				_check(wood_now > _wood_assign, "wood produced via workplace loop (+%d)" % (wood_now - _wood_assign))
				_check(stump_count >= 3, "in-radius trees become STUMP (count=%d)" % stump_count)
				for t in get_nodes_in_group("interactable"):
					if not t.can_interact():
						_check(t.state == 1, "depleted tree enters STUMP state")
				_enter(Phase.OUT_OF_RADIUS_CHECK)
		Phase.OUT_OF_RADIUS_CHECK:
			if _lj.state == 2:
				_saw_move = true
			if _lj.global_position.distance_to(_far_tree.global_position) >= _far_dist - 2.0:
				_out_radius_frames += 1
			if _frame % 60 == 0:
				print("  outradius frame=%d state=%d dist_tree=%.1f far=%d" % [_frame, _lj.state, _lj.global_position.distance_to(_far_tree.global_position), int(_out_radius_frames)])
			if _elapsed() >= 360:
				_check(_out_radius_frames >= 340, "worker does not chase tree outside work_radius (frames=%d)" % _out_radius_frames)
				_check(not _saw_move, "worker never enters MOVE toward out-of-radius tree")
				_enter(Phase.UNASSIGN_EMPTY_IDLE)
		Phase.UNASSIGN_EMPTY_IDLE:
			if _frame % 2 == 0:
				return false
			var ok: bool = _ly.unassign_worker(_lj)
			_check(ok, "unassign succeeds while empty-handed")
			_check(_lj.state == 0, "worker IDLE after empty unassign (state=%d)" % _lj.state)
			_check(not _lj.is_assigned(), "workplace released after empty unassign")
			_pos = _lj.global_position
			_no_move_frames = 0
			_enter(Phase.NO_SEARCH_AFTER_UNASSIGN)
		Phase.NO_SEARCH_AFTER_UNASSIGN:
			if _lj.global_position.distance_to(_pos) < 2.0:
				_no_move_frames += 1
			if _frame % 60 == 0:
				print("  nosearch frame=%d state=%d dist=%.1f" % [_frame, _lj.state, _lj.global_position.distance_to(_pos)])
			if _elapsed() >= 360:
				_check(_no_move_frames >= 340, "worker does not search new trees after unassign (frames=%d)" % _no_move_frames)
				_check(_lj.state == 0, "worker stays IDLE after unassign (state=%d)" % _lj.state)
				_enter(Phase.REASSIGN_CARRY_UNASSIGN)
		Phase.REASSIGN_CARRY_UNASSIGN:
			if _frame % 2 == 0:
				return false
			_check(_ly.assign_worker(_lj), "reassign succeeds after unassign")
			_wood_final_before = root.get_node("VillageResources").get_amount("wood")
			_lj.carried_resource_id = "wood"
			_lj.carried_amount = 3
			var deposit: Node = _ly.get_node("DepositPoint")
			_lj.global_position = deposit.global_position - Vector2(2, 0)
			var ok: bool = _ly.unassign_worker(_lj)
			_check(ok, "unassign succeeds while carrying wood")
			_check(_ly.get_filled_slots() == 0, "slot freed on carrying unassign")
			_check(_lj.state == 4, "worker in RETURN for final deposit (state=%d)" % _lj.state)
			_enter(Phase.FINAL_DEPOSIT)
		Phase.FINAL_DEPOSIT:
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			if wood > _wood_final_before:
				_check(wood - _wood_final_before == 3, "final deposit adds exactly carried 3 wood (+%d)" % (wood - _wood_final_before))
				_check(_lj.carried_amount == 0, "carried cleared after final deposit")
				_check(_lj.state == 0, "worker IDLE after final deposit (state=%d)" % _lj.state)
				_check(not _lj.is_assigned(), "workplace released after final deposit")
				_enter(Phase.DONE)
		Phase.DONE:
			print("TASK0063_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 4000:
		print("TASK0063_RESULT=TIMEOUT phase=%s state=%d wood=%d carried=%d" % [str(_phase), _lj.state, root.get_node("VillageResources").get_amount("wood"), _lj.carried_amount])
		quit()
		return true
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)