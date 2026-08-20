extends CharacterBody2D
class_name Miner

enum State { IDLE, MOVE_TO_WORK, MINE, RETURN_TO_FACILITY }

const STATE_NAMES := {
	State.IDLE: "IDLE",
	State.MOVE_TO_WORK: "MOVE",
	State.MINE: "MINE",
	State.RETURN_TO_FACILITY: "RETURN",
}

const WORK_APPROACH_DISTANCE := 12.0
const DESPAWN_TIMEOUT := 6.0

@export var move_speed: float = 90.0
@export var production_interval: float = 1.0
@export var stone_per_cycle: int = 1

var state: State = State.IDLE
var workplace: Quarry = null
var worker_data: WorkerData = null

var _produce_timer: float = 0.0
var _despawn_pending := false
var _despawn_callback: Callable = Callable()
var _despawn_timeout: float = 0.0

@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _state_label: Label = %StateLabel


func _ready() -> void:
	add_to_group("miners")
	_nav_agent.navigation_finished.connect(_on_navigation_finished)
	_update_state_label()


func _physics_process(delta: float) -> void:
	if _despawn_pending:
		_despawn_timeout -= delta
		if _despawn_timeout <= 0.0:
			_try_despawn()
			return
	match state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.MOVE_TO_WORK:
			_tick_move_to_work()
		State.MINE:
			velocity = Vector2.ZERO
			_tick_mine(delta)
		State.RETURN_TO_FACILITY:
			_tick_return_to_facility()


func _tick_move_to_work() -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_set_state(State.IDLE)
		return
	var work_point := _get_work_point()
	if work_point == null:
		_set_state(State.IDLE)
		return
	var dest := work_point.global_position
	_nav_agent.target_position = dest
	if (_nav_agent.is_target_reachable() and _nav_agent.is_target_reached()) \
			or global_position.distance_to(dest) <= WORK_APPROACH_DISTANCE:
		velocity = Vector2.ZERO
		_produce_timer = production_interval
		_set_state(State.MINE)
		return
	var next_pos := _nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_pos) * move_speed
	move_and_slide()


func _tick_mine(delta: float) -> void:
	if not is_instance_valid(workplace):
		workplace = null
		_produce_timer = 0.0
		_set_state(State.IDLE)
		return
	_produce_timer -= delta
	if _produce_timer > 0.0:
		return
	_produce_timer = production_interval
	VillageResources.add("stone", stone_per_cycle)


## TASK-011-5: 배치 해제 시 Miner가 시설 Spawn/Return point로 복귀한 뒤 despawn한다.
func _tick_return_to_facility() -> void:
	if not is_instance_valid(workplace):
		_try_despawn()
		return
	var spawn := workplace.get_node_or_null("SpawnPoint") as Node2D
	var dest := spawn.global_position if spawn != null else workplace.global_position
	_nav_agent.target_position = dest
	if (_nav_agent.is_target_reachable() and _nav_agent.is_target_reached()) \
			or global_position.distance_to(dest) <= WORK_APPROACH_DISTANCE:
		_try_despawn()
		return
	var next_pos := _nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_pos) * move_speed
	move_and_slide()


## TASK-011-5: 새 생산 cycle을 즉시 중단하고 시설 복귀 → despawn 흐름을 시작한다.
## Navigation 문제로 영구 정지하지 않도록 bounded timeout을 둔다.
func begin_despawn(callback: Callable) -> void:
	_despawn_pending = true
	_despawn_callback = callback
	_despawn_timeout = DESPAWN_TIMEOUT
	_produce_timer = 0.0
	if is_instance_valid(workplace):
		_set_state(State.RETURN_TO_FACILITY)
	else:
		_try_despawn()


func _try_despawn() -> void:
	_despawn_pending = false
	if _despawn_callback.is_valid():
		var cb := _despawn_callback
		_despawn_callback = Callable()
		cb.call()


func _on_navigation_finished() -> void:
	match state:
		State.MOVE_TO_WORK:
			if is_instance_valid(workplace):
				var work_point := _get_work_point()
				if work_point != null and _nav_agent.is_target_reachable() \
						and global_position.distance_to(work_point.global_position) <= 24.0:
					velocity = Vector2.ZERO
					_produce_timer = production_interval
					_set_state(State.MINE)
					return
			_set_state(State.IDLE)


func _get_work_point() -> Node2D:
	if not is_instance_valid(workplace):
		return null
	if workplace.has_method("get_work_point_for"):
		return workplace.get_work_point_for(self)
	return workplace.get_node_or_null("WorkPoint") as Node2D


func is_gathering() -> bool:
	return state == State.MINE


func get_workplace() -> Quarry:
	return workplace


func is_assigned() -> bool:
	return is_instance_valid(workplace)


func _on_assigned(building: Quarry) -> void:
	workplace = building
	_produce_timer = production_interval
	_set_state(State.MOVE_TO_WORK)


func _on_unassigned() -> void:
	workplace = null
	_produce_timer = 0.0
	_set_state(State.IDLE)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_update_state_label()


func _update_state_label() -> void:
	if _state_label:
		_state_label.text = STATE_NAMES.get(state, "?")
