extends Building
class_name Lumberyard

@export var work_radius: float = 192.0
@export var max_workers: int = 2

var _assigned_workers: Array[Node] = []

signal workers_changed(filled: int, capacity: int)


func _ready() -> void:
	super._ready()
	add_to_group("lumberyards")


func get_slot_capacity() -> int:
	return maxi(max_workers, 0)


func get_filled_slots() -> int:
	return _assigned_workers.size()


func get_available_slots() -> int:
	return maxi(get_slot_capacity() - get_filled_slots(), 0)


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
	_assigned_workers.append(worker)
	_connect_worker_cleanup(worker)
	workers_changed.emit(get_filled_slots(), get_slot_capacity())
	return true


func unassign_worker(worker: Node) -> bool:
	if worker == null or not is_instance_valid(worker):
		return false
	if not _assigned_workers.has(worker):
		return false
	_assigned_workers.erase(worker)
	_disconnect_worker_cleanup(worker)
	workers_changed.emit(get_filled_slots(), get_slot_capacity())
	return true


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