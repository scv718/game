extends SceneTree

enum Phase {
	SETUP, NO_AUTOSTART, ASSIGN, MOVE_NO_PRODUCTION, PRODUCE,
	UNASSIGN, UNASSIGN_WAIT, REASSIGN, REASSIGN_WAIT, REASSIGN_PRODUCE, DONE
}

const IDLE := 0
const MOVE := 1
const MINE := 2

var _frame := 0
var _phys_start := 0
var _phase: Phase = Phase.SETUP
var _phys_phase_start := 0
var _failed := false
var _world: Node = null
var _placement: Node = null
var _resources: Node = null
var _deposit: Node = null
var _quarry: Node = null
var _miner: Node = null
var _lumberjack: Node = null
var _stone_before := 0
var _move_peak_stone := 0
var _last_stone := 0
var _last_production_phys := 0
var _intervals: Array[int] = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: Phase) -> void:
	_phase = new_phase
	_phys_phase_start = Engine.get_physics_frames()


func _physics_elapsed() -> int:
	return Engine.get_physics_frames() - _phys_phase_start


func _process(_delta: float) -> bool:
	_frame += 1
	if _phys_start == 0:
		_phys_start = Engine.get_physics_frames()
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
			_check(not _miner.is_assigned(), "miner starts unassigned")
			_check(_miner.state == IDLE, "miner starts IDLE (state=%d)" % _miner.state)
			_check(not _miner.is_gathering(), "miner not gathering at start")

			_placement._set_building_type("quarry")
			_resources._amounts["wood"] = 20
			_placement._try_place_quarry_at(_deposit.global_position)
			_check(get_nodes_in_group("quarries").size() == 1, "quarry built on deposit")
			_check(_deposit.is_occupied(), "deposit occupied by quarry")
			_quarry = get_nodes_in_group("quarries")[0]
			_check(_quarry.get_filled_slots() == 0, "quarry starts with 0 workers")
			var work_point: Node = _quarry.get_node_or_null("WorkPoint")
			_check(work_point != null, "quarry has WorkPoint marker")
			_enter(Phase.NO_AUTOSTART)
		Phase.NO_AUTOSTART:
			if _physics_elapsed() >= 120:
				_check(_miner.state == IDLE, "miner stays IDLE while unassigned (state=%d)" % _miner.state)
				_check(not _miner.is_assigned(), "miner unassigned before assign")
				_check(_resources.get_amount("stone") == 0, "no stone produced by unassigned miner (stone=%d)" % _resources.get_amount("stone"))
				_enter(Phase.ASSIGN)
		Phase.ASSIGN:
			if _frame % 2 == 0:
				return false
			_stone_before = _resources.get_amount("stone")
			var res: Dictionary = _quarry.handle_worker_interaction()
			_check(res.get("action") == "assign" and res.get("success") == true, "quarry interaction assigns miner (%s)" % str(res))
			_check(_quarry.get_filled_slots() == 1, "quarry filled becomes 1 after assign")
			_check(_quarry.has_worker(_miner), "quarry has worker")
			_check(_miner.get_workplace() == _quarry, "miner workplace is exactly the quarry")
			_check(_miner.is_assigned(), "miner is_assigned true")
			_check(_miner.state == MOVE, "miner enters MOVE_TO_WORK after assign (state=%d)" % _miner.state)
			_check(_resources.get_amount("stone") == _stone_before, "no stone produced right after assign")
			_move_peak_stone = _stone_before
			_enter(Phase.MOVE_NO_PRODUCTION)
		Phase.MOVE_NO_PRODUCTION:
			var stone: int = _resources.get_amount("stone")
			if stone > _move_peak_stone:
				_move_peak_stone = stone
			if _miner.state == MINE:
				_check(_move_peak_stone == _stone_before, "no stone produced while moving to WorkPoint (peak=%d, before=%d)" % [_move_peak_stone, _stone_before])
				_check(_miner.is_gathering(), "miner gathering (MINE) after arriving at WorkPoint")
				_last_stone = _move_peak_stone
				_last_production_phys = Engine.get_physics_frames()
				_enter(Phase.PRODUCE)
			elif _physics_elapsed() >= 500:
				_check(false, "miner reached MINE state within timeout (state=%d)" % _miner.state)
				_finish()
				return true
		Phase.PRODUCE:
			var stone: int = _resources.get_amount("stone")
			if stone > _last_stone:
				var interval := Engine.get_physics_frames() - _last_production_phys
				_intervals.append(interval)
				_last_stone = stone
				_last_production_phys = Engine.get_physics_frames()
				if _intervals.size() >= 3:
					var expected: int = int(round(_miner.production_interval * float(Engine.get_physics_ticks_per_second())))
					for iv in _intervals:
						_check(absf(iv - expected) <= 2, "production interval ~%d physics frames (got %d)" % [expected, iv])
					_check(_miner.state == MINE, "miner stays MINE while producing (state=%d)" % _miner.state)
					_check(_resources.get_amount("stone") >= _stone_before + 3, "stone increased exactly 3 times at WorkPoint (stone=%d)" % _resources.get_amount("stone"))
					_enter(Phase.UNASSIGN)
			elif _physics_elapsed() >= 600:
				_check(false, "miner produced stone within timeout (stone=%d)" % stone)
				_finish()
				return true
		Phase.UNASSIGN:
			if _frame % 2 == 0:
				return false
			_stone_before = _resources.get_amount("stone")
			var ok: bool = _quarry.unassign_worker(_miner)
			_check(ok, "unassign succeeds")
			_check(_quarry.get_filled_slots() == 0, "quarry filled back to 0 after unassign")
			_check(not _miner.is_assigned(), "miner workplace released after unassign")
			_check(_miner.state == IDLE, "miner IDLE after unassign (state=%d)" % _miner.state)
			_check(not _miner.is_gathering(), "miner not gathering after unassign")
			_enter(Phase.UNASSIGN_WAIT)
		Phase.UNASSIGN_WAIT:
			if _physics_elapsed() >= 180:
				_check(_resources.get_amount("stone") == _stone_before, "no stale-timer stone after unassign (stone=%d)" % _resources.get_amount("stone"))
				_check(_miner.state == IDLE, "miner stays IDLE after unassign")
				_enter(Phase.REASSIGN)
		Phase.REASSIGN:
			if _frame % 2 == 0:
				return false
			_check(_quarry.assign_worker(_miner), "reassign succeeds")
			_check(_quarry.get_filled_slots() == 1, "quarry filled 1 after reassign")
			_check(_miner.get_workplace() == _quarry, "miner workplace is the quarry after reassign")
			_check(_miner.state == MOVE, "miner enters MOVE_TO_WORK after reassign (state=%d)" % _miner.state)
			_stone_before = _resources.get_amount("stone")
			_move_peak_stone = _stone_before
			_enter(Phase.REASSIGN_WAIT)
		Phase.REASSIGN_WAIT:
			var stone: int = _resources.get_amount("stone")
			if stone > _move_peak_stone:
				_move_peak_stone = stone
			if _miner.state == MINE:
				_check(_move_peak_stone == _stone_before, "no stone produced while moving to WorkPoint on reassign (peak=%d, before=%d)" % [_move_peak_stone, _stone_before])
				_last_stone = _move_peak_stone
				_enter(Phase.REASSIGN_PRODUCE)
			elif _physics_elapsed() >= 500:
				_check(false, "miner reached MINE state after reassign within timeout (state=%d)" % _miner.state)
				_finish()
				return true
		Phase.REASSIGN_PRODUCE:
			var stone: int = _resources.get_amount("stone")
			if stone > _last_stone:
				_check(true, "miner produces again after reassign (stone=%d)" % stone)
				_check(_miner.is_gathering(), "miner gathering again after reassign")
				_enter(Phase.DONE)
			elif _physics_elapsed() >= 600:
				_check(false, "miner resumed production after reassign within timeout (stone=%d)" % stone)
				_finish()
				return true
		Phase.DONE:
			print("TASK0074_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if Engine.get_physics_frames() - _phys_start > 20000:
		print("TASK0074_RESULT=TIMEOUT phase=%s miner_state=%d stone=%d" % [str(_phase), _miner.state if _miner != null else -1, _resources.get_amount("stone")])
		quit()
		return true
	return false


func _finish() -> void:
	print("TASK0074_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
