extends SceneTree

const REPEATS := 8
const MAX_MOVE_EPISODE := 600
const MAX_FRAMES := 1600

enum Phase { SETUP, ENROUTE, PLACE_BLOCK, WATCH, NEXT, DONE }

var _frame := 0
var _pf := 0
var _phase: Phase = Phase.SETUP
var _phase_start := 0
var _run := 0
var _world: Node = null
var _lj: Node = null
var _ly: Node = null
var _tree: Node = null
var _obstacles: Array[Node] = []
var _prev_state := -1
var _failed := false
var _move_episode := 0
var _max_move_episode := 0
var _reach_time := -1
var _return_time := -1
var _deposit_time := -1
var _start_wood := 0

func _enter(p: Phase) -> void:
	_phase = p
	_phase_start = _pf

func _elapsed() -> int:
	return _pf - _phase_start

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true

func _clear_obstacles() -> void:
	for ob in _obstacles:
		if is_instance_valid(ob):
			ob.queue_free()
	_obstacles.clear()

func _place_building_obstacle(pos: Vector2) -> void:
	var ob: Node2D = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate()
	ob.position = pos
	_world.add_child(ob)
	_obstacles.append(ob)

func _reset_worker() -> void:
	_lj.target_tree = null
	_lj.carried_amount = 0
	_lj.carried_resource_id = ""
	_lj._final_deposit = false
	_lj.global_position = Vector2(100, 360)
	_lj._set_state(0)

func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			var main: Node = root.get_node("Main")
			_world = main.get_node("World")
			_lj = (load("res://scenes/lumberjack.tscn") as PackedScene).instantiate()
			_lj.position = Vector2(300, 200)
			_world.add_child(_lj)
			_tree = get_nodes_in_group("interactable")[0]
			_enter(Phase.NEXT)
		Phase.NEXT:
			_run += 1
			if _run > REPEATS:
				_enter(Phase.DONE)
				return false
			_clear_obstacles()
			_tree.position = Vector2(620, 360)
			_tree.regrow_time = 100000.0
			_tree.max_amount = 1
			_tree.current_amount = 1
			for i in range(1, get_nodes_in_group("interactable").size()):
				var t: Node = get_nodes_in_group("interactable")[i]
				t.position = Vector2(900, 900)
				t.current_amount = 0
			if _ly == null:
				_ly = (load("res://scenes/lumberyard.tscn") as PackedScene).instantiate() as Node2D
				_ly.position = Vector2(100, 400)
				_ly.work_radius = 900.0
				_world.add_child(_ly)
				_world.rebuild_navigation()
				_check(_ly.assign_worker(_lj), "run %d: assign worker" % _run)
			_reset_worker()
			_world.rebuild_navigation()
			_prev_state = -1
			_move_episode = 0
			_max_move_episode = 0
			_reach_time = -1
			_return_time = -1
			_deposit_time = -1
			_start_wood = root.get_node("VillageResources").get_amount("wood")
			_enter(Phase.ENROUTE)
		Phase.ENROUTE:
			if _elapsed() >= 40 and _lj.state == 2:
				var ahead: Vector2 = _lj.global_position + Vector2(80, 0)
				_place_building_obstacle(ahead)
				_world.rebuild_navigation()
				print("RUN %d: building dropped at %s worker=%s state=%d" % [_run, ahead, _lj.global_position, _lj.state])
				_enter(Phase.WATCH)
			elif _elapsed() >= 300:
				_check(false, "run %d: worker never entered MOVE (state=%d pos=%s)" % [_run, _lj.state, _lj.global_position])
				_enter(Phase.NEXT)
		Phase.WATCH:
			if _lj.state != _prev_state:
				if _prev_state == 3 and _return_time < 0:
					_return_time = _elapsed()
				_prev_state = _lj.state
			if _lj.state == 3 and _reach_time < 0:
				_reach_time = _elapsed()
				print("  run %d reached tree at pf %d" % [_run, _elapsed()])
			if _reach_time >= 0 and _deposit_time < 0:
				var wood: int = root.get_node("VillageResources").get_amount("wood")
				if wood > _start_wood:
					_deposit_time = _elapsed()
					print("  run %d deposited wood at pf %d" % [_run, _elapsed()])
			if _elapsed() >= MAX_FRAMES:
				if _reach_time < 0:
					_check(false, "run %d: worker never reached tree (state=%d pos=%s)" % [_run, _lj.state, _lj.global_position])
				else:
					_check(true, "run %d: worker reached tree after obstacle (t=%d)" % [_run, _reach_time])
				if _max_move_episode > MAX_MOVE_EPISODE:
					_check(false, "run %d: stuck pushing same direction for %d pf (max allowed %d)" % [_run, _max_move_episode, MAX_MOVE_EPISODE])
				else:
					_check(true, "run %d: longest MOVE episode %d pf" % [_run, _max_move_episode])
				if _return_time >= 0:
					_check(true, "run %d: RETURN normal (t=%d)" % [_run, _return_time])
				else:
					_check(false, "run %d: never entered RETURN (state=%d)" % [_run, _lj.state])
				if _deposit_time >= 0:
					_check(true, "run %d: DEPOSIT normal (t=%d)" % [_run, _deposit_time])
				else:
					_check(false, "run %d: never deposited wood (state=%d carried=%d)" % [_run, _lj.state, _lj.carried_amount])
				_enter(Phase.NEXT)
	if _frame > 400000:
		print("NAVREPEAT_RESULT=GLOBAL_TIMEOUT run=%d" % _run)
		quit()
		return true
	if _phase == Phase.DONE:
		print("NAVREPEAT_RESULT=" + ("FAIL" if _failed else "PASS"))
		quit()
		return true
	return false

func _physics_process(_delta: float) -> bool:
	_pf += 1
	if _phase == Phase.WATCH and _lj != null and _lj.state == 2:
		_move_episode += 1
	elif _move_episode > 0:
		if _move_episode > _max_move_episode:
			_max_move_episode = _move_episode
		_move_episode = 0
	return false

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)