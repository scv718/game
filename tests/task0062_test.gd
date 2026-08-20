extends SceneTree

enum Phase {
	SETUP, NO_AUTOSTART, ASSIGN, PROMPT_UI, SECOND_YARD_REJECT, WORK_LOOP,
	UNASSIGN_EMPTY_IDLE, REASSIGN_CARRY_UNASSIGN, FINAL_DEPOSIT, DONE
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _failed := false
var _world: Node = null
var _lj: Node = null
var _lj_start_pos := Vector2.ZERO
var _no_move_frames := 0
var _ly: Node = null
var _ly2: Node = null
var _wood_assign := 0
var _wood_final_before := 0
var _wood_deposited := false
var _unassign_empty_ok := false

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true

func _process(_delta: float) -> bool:
	_frame += 1
	var main: Node = root.get_node("Main")
	var hud: Node = main.get_node("HUD")
	match _phase:
		Phase.SETUP:
			_world = main.get_node("World")
			_lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lj.position = Vector2(300, 200)
			_world.add_child(_lj)
			_lj_start_pos = _lj.global_position
			var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
			_ly = ly_scene.instantiate() as Node2D
			_ly.position = Vector2(300, 260)
			_world.add_child(_ly)
			_world.rebuild_navigation()
			print("LUMBERYARD_BUILT capacity=%d filled=%d" % [_ly.get_slot_capacity(), _ly.get_filled_slots()])
			_phase = Phase.NO_AUTOSTART
		Phase.NO_AUTOSTART:
			if _lj.global_position.distance_to(_lj_start_pos) < 2.0:
				_no_move_frames += 1
			if _frame % 60 == 0:
				print("  noautostart frame=%d state=%d dist=%.1f" % [_frame, _lj.state, _lj.global_position.distance_to(_lj_start_pos)])
			if _frame >= 150:
				_check(_no_move_frames >= 140, "worker does not auto-start after Lumberyard built (still frames=%d)" % _no_move_frames)
				_check(_lj.state == 0, "worker stays IDLE after Lumberyard built (state=%d)" % _lj.state)
				_check(not _lj.is_assigned(), "worker has no workplace before assign")
				_check(_ly.get_interact_prompt() == "Workers: 0/2 - Assign Worker", "prompt shows Workers: 0/2 - Assign Worker (got '%s')" % _ly.get_interact_prompt())
				var interact: Node = _ly.get_node("Interact")
				_check(interact.prompt == "Workers: 0/2 - Assign Worker", "interact node prompt syncs (got '%s')" % interact.prompt)
				_phase = Phase.ASSIGN
		Phase.ASSIGN:
			if _frame % 2 == 0:
				return false
			_wood_assign = root.get_node("VillageResources").get_amount("wood")
			var res: Dictionary = _ly.handle_worker_interaction()
			_check(res.get("action") == "assign" and res.get("success") == true, "interaction assigns worker (%s)" % str(res))
			_check(_ly.get_filled_slots() == 1, "filled becomes 1 after assign (got %d)" % _ly.get_filled_slots())
			_check(_ly.has_worker(_lj), "lumberyard has worker")
			_check(_lj.get_workplace() == _ly, "worker workplace is the lumberyard")
			_check(_lj.is_assigned(), "worker is_assigned true")
			_check(_ly.get_interact_prompt() == "Workers: 1/2 - Assign Worker", "prompt shows Workers: 1/2 - Assign Worker (got '%s')" % _ly.get_interact_prompt())
			_phase = Phase.PROMPT_UI
		Phase.PROMPT_UI:
			if _frame % 2 == 0:
				return false
			var interact: Node = _ly.get_node("Interact")
			_check(interact.prompt == "Workers: 1/2 - Assign Worker", "interact node prompt updates to 1/2 (got '%s')" % interact.prompt)
			hud._on_interactable_changed(interact)
			_ly.workers_changed.emit(_ly.get_filled_slots(), _ly.get_slot_capacity())
			_check(hud.interact_label.text == "E - Workers: 1/2 - Assign Worker", "HUD interact label refreshes on workers_changed (got '%s')" % hud.interact_label.text)
			var player: Node = main.get_node("Player")
			player.global_position = _ly.global_position + Vector2(40, 0)
			_phase = Phase.SECOND_YARD_REJECT
		Phase.SECOND_YARD_REJECT:
			if _frame % 2 == 0:
				return false
			var ly_scene: PackedScene = load("res://scenes/lumberyard.tscn")
			_ly2 = ly_scene.instantiate() as Node2D
			_ly2.position = Vector2(600, 200)
			_world.add_child(_ly2)
			_world.rebuild_navigation()
			_check(not _ly2.assign_worker(_lj), "second workplace rejects already-assigned worker")
			var res: Dictionary = _ly2.handle_worker_interaction()
			_check(res.get("success") == false, "interaction on second workplace does not assign (%s)" % str(res))
			_check(_ly2.get_filled_slots() == 0, "second workplace stays empty")
			_check(_lj.get_workplace() == _ly, "worker still assigned to first workplace")
			_phase = Phase.WORK_LOOP
		Phase.WORK_LOOP:
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			if wood > _wood_assign:
				_wood_deposited = true
				print("  workloop wood_before=%d wood_now=%d state=%d carried=%d" % [_wood_assign, wood, _lj.state, _lj.carried_amount])
			if _wood_deposited and _lj.carried_amount == 0:
				_phase = Phase.UNASSIGN_EMPTY_IDLE
		Phase.UNASSIGN_EMPTY_IDLE:
			if _frame % 2 == 0:
				return false
			var ok: bool = _ly.unassign_worker(_lj)
			_check(ok, "unassign succeeds while empty-handed")
			_check(_ly.get_filled_slots() == 0, "filled back to 0 after unassign (got %d)" % _ly.get_filled_slots())
			_check(_lj.state == 0, "worker immediately IDLE after empty unassign (state=%d)" % _lj.state)
			_check(not _lj.is_assigned(), "worker workplace released after empty unassign")
			_check(not _lj.is_gathering(), "worker not gathering after unassign")
			_phase = Phase.REASSIGN_CARRY_UNASSIGN
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
			_phase = Phase.FINAL_DEPOSIT
		Phase.FINAL_DEPOSIT:
			var wood: int = root.get_node("VillageResources").get_amount("wood")
			if wood > _wood_final_before:
				_check(wood - _wood_final_before == 3, "final deposit adds exactly carried 3 wood (+%d)" % (wood - _wood_final_before))
				_check(_lj.carried_amount == 0, "carried cleared after final deposit")
				_check(_lj.state == 0, "worker IDLE after final deposit (state=%d)" % _lj.state)
				_check(not _lj.is_assigned(), "workplace released after final deposit")
				_phase = Phase.DONE
		Phase.DONE:
			print("TASK0062_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 3000:
		print("TASK0062_RESULT=TIMEOUT phase=%s wood=%d state=%d carried=%d" % [str(_phase), root.get_node("VillageResources").get_amount("wood"), _lj.state, _lj.carried_amount])
		quit()
		return true
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)