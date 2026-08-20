extends Building
class_name Workplace

@export var max_workers: int = 1

var _assigned_workers: Array[Node] = []

signal workers_changed(filled: int, capacity: int)


func get_slot_capacity() -> int:
	return max(max_workers, 0)


func get_filled_slots() -> int:
	return _assigned_workers.size()


func get_available_slots() -> int:
	return max(get_slot_capacity() - get_filled_slots(), 0)


func has_available_slot() -> bool:
	return get_available_slots() > 0


func has_worker(worker: Node) -> bool:
	return is_instance_valid(worker) and _assigned_workers.has(worker)


func get_assigned_workers() -> Array[Node]:
	return _assigned_workers.duplicate()


func assign_worker(worker: Node) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false
	if _assigned_workers.has(worker):
		return false
	if not has_available_slot():
		return false
	if worker.has_method("get_workplace"):
		var other := worker.get_workplace() as Node
		if is_instance_valid(other) and other != self:
			return false
	_assigned_workers.append(worker)
	_connect_worker_cleanup(worker)
	if worker.has_method("_on_assigned"):
		worker._on_assigned(self)
	workers_changed.emit(get_filled_slots(), get_slot_capacity())
	return true


func unassign_worker(worker: Node) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false
	if not _assigned_workers.has(worker):
		return false
	_assigned_workers.erase(worker)
	_disconnect_worker_cleanup(worker)
	if worker.has_method("_on_unassigned"):
		worker._on_unassigned()
	workers_changed.emit(get_filled_slots(), get_slot_capacity())
	return true


func get_interact_prompt() -> String:
	var filled := get_filled_slots()
	var cap := get_slot_capacity()
	if filled >= cap:
		return "Workers: %d/%d - Unassign %s" % [filled, cap, get_worker_label()]
	return "Workers: %d/%d - Assign %s" % [filled, cap, get_worker_label()]


func handle_worker_interaction() -> Dictionary:
	if get_filled_slots() >= get_slot_capacity():
		var worker: Node = _assigned_workers[0] if not _assigned_workers.is_empty() else null
		return {"action": "unassign", "success": unassign_worker(worker)}
	return {"action": "assign", "success": assign_worker(_pick_available_worker())}


func get_worker_group() -> String:
	return "workers"


func get_worker_label() -> String:
	return "Worker"


## TASK-011-5: WorkerData가 이 workplace에 배치될 때 실제 Worker Actor를 생성한다.
## 기본 구현은 Actor 자동 생성 없음(null). 직업별로 Actor를 만들고 싶은 Workplace가
## 이 메서드를 오버라이드한다. 생성한 Actor는 이미 월드에 add_child 되어 있어야 한다.
func spawn_worker_actor(_worker: WorkerData) -> Node:
	return null


## TASK-011-5: WorkerData가 이 workplace에서 해제될 때 Actor를 despawn한다.
## Actor가 begin_despawn을 지원하면 시설 복귀 → despawn 흐름을 시작하고,
## 그렇지 않으면 callback만 호출한다. 실제 해제는 callback(WorkerRoster)이 담당한다.
func despawn_worker_actor(_worker: WorkerData, actor: Node, callback: Callable) -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method("begin_despawn"):
		actor.begin_despawn(callback)
	elif callback.is_valid():
		callback.call()


func _pick_available_worker() -> Node:
	var best: Node = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(get_worker_group()):
		var worker := node as Node2D
		if worker == null or not is_instance_valid(worker):
			continue
		if worker.has_method("get_workplace") and is_instance_valid(worker.get_workplace()):
			continue
		var d := global_position.distance_squared_to(worker.global_position)
		if d < best_dist:
			best = worker
			best_dist = d
	return best


func _connect_worker_cleanup(worker: Node) -> void:
	var cb := _on_worker_exiting.bind(worker)
	if not worker.tree_exiting.is_connected(cb):
		worker.tree_exiting.connect(cb)


func _disconnect_worker_cleanup(worker: Node) -> void:
	var cb := _on_worker_exiting.bind(worker)
	if worker.tree_exiting.is_connected(cb):
		worker.tree_exiting.disconnect(cb)


func _on_worker_exiting(worker: Node) -> void:
	if _assigned_workers.has(worker):
		_assigned_workers.erase(worker)
		workers_changed.emit(get_filled_slots(), get_slot_capacity())
