extends Node

## TASK-011-2 최소 Worker Roster 기반.
## 고용된 WorkerData를 월드와 독립적으로 보관한다.
## 미배치 WorkerData는 이 Roster에만 존재하며 월드 Worker Actor는 생성하지 않는다.
## 같은 WorkerData가 동시에 두 workplace에 배치될 수 없도록 보장한다.
## freed workplace에 대한 안전한 정리를 제공한다. 영구 Save/Load는 구현하지 않는다.

var _workers: Array[WorkerData] = []
var _actors: Dictionary = {}

signal workers_changed


func add_worker(worker: WorkerData) -> bool:
	if worker == null or not worker is WorkerData:
		return false
	if get_worker(worker.id) != null:
		return false
	_workers.append(worker)
	workers_changed.emit()
	return true


func remove_worker(worker: WorkerData) -> bool:
	if worker == null or not _workers.has(worker):
		return false
	worker._clear_assignment()
	_workers.erase(worker)
	workers_changed.emit()
	return true


func get_worker(worker_id: String) -> WorkerData:
	for w in _workers:
		if w.id == worker_id:
			return w
	return null


func get_workers() -> Array[WorkerData]:
	return _workers.duplicate()


func get_unassigned() -> Array[WorkerData]:
	var out: Array[WorkerData] = []
	for w in _workers:
		if not w.is_assigned():
			out.append(w)
	return out


func get_count() -> int:
	return _workers.size()


func get_assigned_count() -> int:
	var n := 0
	for w in _workers:
		if w.is_assigned():
			n += 1
	return n


func get_workers_for_workplace(workplace: Object) -> Array[WorkerData]:
	var out: Array[WorkerData] = []
	for w in _workers:
		if w.is_assigned() and w.get_workplace() == workplace:
			out.append(w)
	return out


## WorkerData를 workplace에 배치한다. 이미 배치된 Worker는 다른 workplace에
## 재배치할 수 없고, 같은 workplace에 중복 배치할 수도 없다.
## Workplace(slot capacity를 가진 시설)인 경우 가득 찬 시설에는 추가 배치를 거부한다.
## TASK-011-5: 배치가 성공하면 workplace가 spawn_worker_actor를 지원하는 경우
## 해당 시설에서 실제 Worker Actor를 생성하고 Actor 수/월드 Actor를 추적한다.
func assign(worker: WorkerData, workplace: Object) -> bool:
	if worker == null or workplace == null or not is_instance_valid(workplace):
		return false
	if not _workers.has(worker):
		return false
	if worker.is_assigned():
		return false
	var pending: Node = _actors.get(worker.id)
	if pending != null and is_instance_valid(pending):
		return false
	if workplace.has_method("get_slot_capacity"):
		var cap: int = workplace.get_slot_capacity()
		if get_workers_for_workplace(workplace).size() >= cap:
			return false
	if not worker._set_assignment(workplace):
		return false
	_spawn_actor(worker, workplace)
	workers_changed.emit()
	return true


func unassign(worker: WorkerData) -> bool:
	if worker == null or not _workers.has(worker):
		return false
	if not worker.is_assigned():
		return false
	var workplace: Object = worker.get_workplace()
	var actor: Node = _actors.get(worker.id)
	worker._clear_assignment()
	if actor != null and is_instance_valid(actor):
		_begin_actor_despawn(worker, actor, workplace)
	else:
		_actors.erase(worker.id)
	workers_changed.emit()
	return true


## TASK-011-5: 배치된 WorkerData에 연결된 Worker Actor를 조회한다. 미배치/미생성이면 null.
func get_actor(worker: WorkerData) -> Node:
	if worker == null:
		return null
	var actor: Node = _actors.get(worker.id)
	if actor != null and is_instance_valid(actor):
		return actor
	return null


## 현재 월드에 존재하는 Worker Actor 수 (미배치 WorkerData는 제외).
func get_actor_count() -> int:
	var n := 0
	for actor in _actors.values():
		if is_instance_valid(actor):
			n += 1
	return n


func _spawn_actor(worker: WorkerData, workplace: Object) -> void:
	if workplace != null and is_instance_valid(workplace) \
			and workplace.has_method("spawn_worker_actor"):
		var actor: Node = workplace.spawn_worker_actor(worker)
		if actor != null:
			_actors[worker.id] = actor


func _begin_actor_despawn(worker: WorkerData, actor: Node, workplace: Object) -> void:
	if workplace != null and is_instance_valid(workplace) \
			and workplace.has_method("despawn_worker_actor"):
		workplace.despawn_worker_actor(worker, actor, _on_actor_despawned.bind(worker.id))
	elif actor.has_method("begin_despawn"):
		actor.begin_despawn(_on_actor_despawned.bind(worker.id))
	else:
		_remove_actor_now(worker.id, actor)


func _on_actor_despawned(worker_id: String) -> void:
	var actor: Node = _actors.get(worker_id)
	if actor != null and is_instance_valid(actor):
		_remove_actor_now(worker_id, actor)
	else:
		_actors.erase(worker_id)


func _remove_actor_now(worker_id: String, actor: Node) -> void:
	_actors.erase(worker_id)
	if is_instance_valid(actor):
		actor.queue_free()


## freed workplace를 참조하는 모든 WorkerData를 Unassigned로 정리한다.
## TASK-011-5: workplace가 해제된 경우 해당 Actor도 월드에서 안전하게 제거한다.
func cleanup_freed_workplaces() -> int:
	var cleaned := 0
	for w in _workers:
		if w._assigned and not is_instance_valid(w._workplace):
			w._clear_assignment()
			var actor: Node = _actors.get(w.id)
			if actor != null and is_instance_valid(actor):
				_remove_actor_now(w.id, actor)
			cleaned += 1
	if cleaned > 0:
		workers_changed.emit()
	return cleaned
