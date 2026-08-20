extends CharacterBody2D
class_name Lumberjack

enum State { IDLE, FIND_TREE, MOVE_TO_TREE, GATHER, RETURN_TO_LUMBERYARD, DEPOSIT }

const STATE_NAMES := {
	State.IDLE: "IDLE",
	State.FIND_TREE: "FIND",
	State.MOVE_TO_TREE: "MOVE",
	State.GATHER: "GATHER",
	State.RETURN_TO_LUMBERYARD: "RETURN",
	State.DEPOSIT: "DEPOSIT",
}

const TREE_APPROACH_DISTANCE := 22.0
const STUCK_TIMEOUT := 1.5
const WALL_PRESS_TIMEOUT := 0.5
const DESPAWN_TIMEOUT := 6.0

@export var move_speed: float = 90.0
@export var carry_capacity: int = 5
@export var gather_interval: float = 0.6
@export var search_interval: float = 1.0

var state: State = State.IDLE
var workplace: Lumberyard = null
var worker_data: WorkerData = null
var target_tree: ResourceNode = null
var carried_resource_id: String = ""
var carried_amount: int = 0
var _final_deposit: bool = false

var _search_timer: float = 0.0
var _gather_timer: float = 0.0
var _skip_tree: ResourceNode = null
var _stuck_timer: float = 0.0
var _last_move_pos := Vector2.ZERO
var _wall_press_timer: float = 0.0
var _despawn_pending := false
var _despawn_callback: Callable = Callable()
var _despawn_timeout: float = 0.0

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _state_label: Label = %StateLabel


func _ready() -> void:
	add_to_group("lumberjacks")
	_nav_agent.navigation_finished.connect(_on_navigation_failed)
	_update_state_label()


func _physics_process(delta: float) -> void:
	_search_timer = maxf(_search_timer - delta, 0.0)
	_gather_timer = maxf(_gather_timer - delta, 0.0)
	if _despawn_pending:
		_despawn_timeout -= delta
		if _despawn_timeout <= 0.0:
			_try_despawn()
			return
	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			_tick_idle()
		State.FIND_TREE:
			velocity = Vector2.ZERO
			_tick_find_tree()
		State.MOVE_TO_TREE:
			_tick_move_to_tree(delta)
		State.GATHER:
			velocity = Vector2.ZERO
			_tick_gather()
		State.RETURN_TO_LUMBERYARD:
			_tick_return(delta)
		State.DEPOSIT:
			velocity = Vector2.ZERO
			_tick_deposit()


func _tick_idle() -> void:
	if _final_deposit and carried_amount > 0:
		if is_instance_valid(workplace):
			_set_state(State.RETURN_TO_LUMBERYARD)
		else:
			_deposit_last_carry()
		return
	if not is_instance_valid(workplace):
		workplace = null
		return
	if _search_timer > 0.0:
		return
	_skip_tree = null
	_set_state(State.FIND_TREE)


func _tick_find_tree() -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_search_timer = 0.0
		_set_state(State.IDLE)
		return
	var best := _find_nearest_tree()
	if best == null:
		_search_timer = search_interval
		_set_state(State.IDLE)
		return
	_skip_tree = null
	target_tree = best
	best.claim(self)
	_set_state(State.MOVE_TO_TREE)


func _tick_move_to_tree(delta: float) -> void:
	if carried_amount >= carry_capacity:
		_release_tree_claim()
		target_tree = null
		_set_state(State.RETURN_TO_LUMBERYARD)
		return
	if not is_instance_valid(target_tree) or not target_tree.can_interact():
		_release_tree_claim()
		target_tree = null
		if carried_amount > 0:
			_set_state(State.RETURN_TO_LUMBERYARD)
		else:
			_set_state(State.FIND_TREE)
		return
	var to_tree := global_position.distance_to(target_tree.global_position)
	if to_tree <= 14.0:
		velocity = Vector2.ZERO
		_gather_timer = 0.0
		_set_state(State.GATHER)
		return
	_nav_agent.target_position = target_tree.global_position \
		- global_position.direction_to(target_tree.global_position) * TREE_APPROACH_DISTANCE
	if _nav_agent.is_target_reachable() and _nav_agent.is_target_reached():
		velocity = Vector2.ZERO
		_gather_timer = 0.0
		_set_state(State.GATHER)
		return
	if _check_stuck(delta):
		_release_tree_claim()
		_skip_tree = target_tree
		target_tree = null
		if carried_amount > 0:
			_set_state(State.RETURN_TO_LUMBERYARD)
		else:
			_set_state(State.FIND_TREE)
		return
	var next_pos := _nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_pos) * move_speed
	move_and_slide()


func _tick_gather() -> void:
	if not is_instance_valid(target_tree) or not target_tree.can_interact():
		_release_tree_claim()
		target_tree = null
		if carried_amount > 0:
			_set_state(State.RETURN_TO_LUMBERYARD)
		else:
			_set_state(State.FIND_TREE)
		return
	if _gather_timer > 0.0:
		return
	var result: Variant = target_tree.interact(self)
	if result is Dictionary:
		var gained: int = int(result.get("amount", 0))
		if gained > 0:
			carried_resource_id = String(result.get("resource_id", ""))
			carried_amount += gained
			_gather_timer = gather_interval
			if carried_amount >= carry_capacity:
				_release_tree_claim()
				target_tree = null
				_set_state(State.RETURN_TO_LUMBERYARD)
			return
	_release_tree_claim()
	target_tree = null
	if carried_amount > 0:
		_set_state(State.RETURN_TO_LUMBERYARD)
	else:
		_set_state(State.FIND_TREE)


func _tick_return(delta: float) -> void:
	if not is_instance_valid(workplace):
		if _final_deposit and carried_amount > 0:
			_deposit_last_carry()
		else:
			workplace = null
			_set_state(State.IDLE)
		return
	var deposit := workplace.get_node_or_null("DepositPoint") as Node2D
	var dest := deposit.global_position if deposit != null else workplace.global_position
	_nav_agent.target_position = dest
	if (_nav_agent.is_target_reachable() and _nav_agent.is_target_reached()) \
			or global_position.distance_to(dest) <= 12.0:
		if _despawn_pending and carried_amount == 0:
			_try_despawn()
			return
		velocity = Vector2.ZERO
		_set_state(State.DEPOSIT)
		return
	if _check_stuck(delta):
		_set_state(State.IDLE)
		return
	var next_pos := _nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_pos) * move_speed
	move_and_slide()


func _tick_deposit() -> void:
	if carried_amount > 0 and carried_resource_id != "":
		VillageResources.add(carried_resource_id, carried_amount)
		carried_amount = 0
		carried_resource_id = ""
	if _despawn_pending:
		_try_despawn()
		return
	if _final_deposit:
		_final_deposit = false
		workplace = null
		_set_state(State.IDLE)
		return
	_set_state(State.FIND_TREE)


func _on_navigation_failed() -> void:
	match state:
		State.MOVE_TO_TREE:
			if is_instance_valid(target_tree) \
					and _nav_agent.is_target_reachable() \
					and global_position.distance_to(_nav_agent.target_position) <= 6.0:
				velocity = Vector2.ZERO
				_gather_timer = 0.0
				_set_state(State.GATHER)
				return
			_release_tree_claim()
			_skip_tree = target_tree
			target_tree = null
			if carried_amount > 0:
				_set_state(State.RETURN_TO_LUMBERYARD)
			else:
				_set_state(State.FIND_TREE)
		State.RETURN_TO_LUMBERYARD:
			if is_instance_valid(workplace):
				var deposit := workplace.get_node_or_null("DepositPoint") as Node2D
				var dest := deposit.global_position if deposit != null else workplace.global_position
				if _nav_agent.is_target_reachable() and global_position.distance_to(dest) <= 24.0:
					velocity = Vector2.ZERO
					_set_state(State.DEPOSIT)
					return
			_set_state(State.IDLE)


func _find_nearest_tree() -> ResourceNode:
	if not is_instance_valid(workplace):
		return null
	var origin: Vector2 = workplace.global_position
	var radius_sq: float = workplace.work_radius * workplace.work_radius
	var map := _nav_agent.get_navigation_map()
	var best: ResourceNode = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("interactable"):
		var resource_node := node as ResourceNode
		if resource_node == null or not is_instance_valid(resource_node):
			continue
		if resource_node == _skip_tree:
			continue
		if resource_node.is_claimed_by_other(self):
			continue
		if resource_node.resource_id != "wood" or not resource_node.can_interact():
			continue
		var d := origin.distance_squared_to(resource_node.global_position)
		if d > radius_sq:
			continue
		var approach := resource_node.global_position \
			- global_position.direction_to(resource_node.global_position) * TREE_APPROACH_DISTANCE
		if NavigationServer2D.map_get_path(map, global_position, approach, true).is_empty():
			continue
		if d < best_dist:
			best = resource_node
			best_dist = d
	return best


func _release_tree_claim() -> void:
	if is_instance_valid(target_tree) and target_tree.has_method("release"):
		target_tree.release(self)


func _check_stuck(delta: float) -> bool:
	if global_position.distance_to(_last_move_pos) < 2.0:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIMEOUT:
			return true
	else:
		_last_move_pos = global_position
		_stuck_timer = 0.0
	if is_on_wall() and not _nav_agent.is_target_reachable():
		_wall_press_timer += delta
		if _wall_press_timer >= WALL_PRESS_TIMEOUT:
			_wall_press_timer = 0.0
			return true
	else:
		_wall_press_timer = 0.0
	return false


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_last_move_pos = global_position
	_stuck_timer = 0.0
	_wall_press_timer = 0.0
	_update_state_label()


func _update_state_label() -> void:
	if _state_label:
		_state_label.text = STATE_NAMES.get(state, "?")


func is_gathering() -> bool:
	return state == State.GATHER


func get_workplace() -> Lumberyard:
	return workplace


func is_assigned() -> bool:
	return is_instance_valid(workplace)


func _on_assigned(building: Lumberyard) -> void:
	workplace = building
	_final_deposit = false
	_search_timer = 0.0


func _on_unassigned() -> void:
	_release_tree_claim()
	target_tree = null
	if carried_amount > 0:
		_final_deposit = true
		_set_state(State.RETURN_TO_LUMBERYARD)
		return
	_final_deposit = false
	workplace = null
	_set_state(State.IDLE)


## TASK-011-5: 배치 해제 시 Actor를 시설로 복귀시킨 뒤 despawn한다.
## carrying 중이면 마지막 1회 deposit 후 복귀, 아니면 즉시 시설 복귀 후 despawn한다.
## Navigation 문제로 영구 정지하지 않도록 bounded timeout을 둔다.
func begin_despawn(callback: Callable) -> void:
	_despawn_pending = true
	_despawn_callback = callback
	_despawn_timeout = DESPAWN_TIMEOUT
	_release_tree_claim()
	target_tree = null
	_skip_tree = null
	if carried_amount > 0:
		_final_deposit = true
		if is_instance_valid(workplace):
			_set_state(State.RETURN_TO_LUMBERYARD)
		else:
			_deposit_last_carry()
			_try_despawn()
		return
	_final_deposit = false
	if is_instance_valid(workplace):
		_set_state(State.RETURN_TO_LUMBERYARD)
	else:
		_try_despawn()


func _try_despawn() -> void:
	_despawn_pending = false
	if _despawn_callback.is_valid():
		var cb := _despawn_callback
		_despawn_callback = Callable()
		cb.call()


func _deposit_last_carry() -> void:
	if carried_amount > 0 and carried_resource_id != "":
		VillageResources.add(carried_resource_id, carried_amount)
		carried_amount = 0
		carried_resource_id = ""
	_final_deposit = false
	workplace = null
	_set_state(State.IDLE)