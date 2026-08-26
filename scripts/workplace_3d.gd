extends Building3D
class_name Workplace3D

## TASK-3D-INT-001-2 Workplace 3D slot / Worker Actor spawn contract.
## 기존 workplace.gd(Workplace = StaticBody2D)의 slot/assign/Actor spawn 규약을
## 3D로 이전한 신규 파일이다. 기존 2D workplace.gd는 LOCK 12에 따라 무수정으로 유지되며,
## 이 파일이 대신하는 것은 3D Runtime뿐이다. Lumberyard3D / Quarry3D가 상속한다.
##
## - WorkerRoster.assign/unassign 오케스트레이션이 소비하는 계약은 2D와 동일하다:
##   get_slot_capacity() / spawn_worker_actor(worker) / despawn_worker_actor(...),
##   그리고 직접 배치 경로(assign_worker/unassign_worker + _on_assigned/_on_unassigned).
##   Actor 생성/despawn 실제 구현은 직업별 서브클래스가 2D와 동일 구조로 override한다.
## - workers_changed(filled, capacity) signal도 2D와 동일하다. hud.gd의 선택 prompt
##   갱신과 여관 UI의 slot 표시가 이 신호/조회 계약을 그대로 재사용한다.
## - group은 기존 차원 분리 원칙을 따르되, 여관 UI(inn_roster_ui.gd)가 조회하는
##   기존 lookup명("lumberyards"/"quarries")은 서브클래스가 BuildingPlacement3D와
##   동일한 dual-group 등록 방식으로 충족한다(3D 월드에는 2D workplace이 없으므로
##   두 runtime 어느 쪽에서도 group 오염이 없다).
## - worker actor는 CharacterBody3D다. _pick_available_worker의 거리 판정은
##   WorldCoords3D.distance_xz(지면 XZ)로 수행한다(2D distance_squared_to 의미 보존).

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
		var other: Node = worker.get_workplace()
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
	return "workers_3d"


func get_worker_label() -> String:
	return "Worker"


## TASK-011-5 규약 유지: 기본 구현은 Actor 자동 생성 없음(null). 직업별 3D Workplace가
## 2D와 동일 구조로 override한다. 생성한 Actor는 이미 월드에 add_child 되어 있어야 한다.
func spawn_worker_actor(_worker: WorkerData) -> Node:
	return null


## TASK-011-5 규약 유지: Actor가 begin_despawn을 지원하면 시설 복귀 → despawn 흐름,
## 아니면 callback 즉시 호출. 실제 제거는 callback(WorkerRoster)이 담당한다.
func despawn_worker_actor(_worker: WorkerData, actor: Node, callback: Callable) -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method("begin_despawn"):
		actor.begin_despawn(callback)
	elif callback.is_valid():
		callback.call()


## 미배치 worker actor 중 가장 가까운 1명(기존 2D _pick_available_worker 규약).
## 현재 Runtime에서의 배치 경로는 여관 UI(WorkerRoster.assign)지만, 직접 배치
## 계약의 3D판으로 유지한다.
func _pick_available_worker() -> Node:
	var best: Node = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(get_worker_group()):
		var worker := node as Node3D
		if worker == null or not is_instance_valid(worker):
			continue
		if worker.has_method("get_workplace") and is_instance_valid(worker.get_workplace()):
			continue
		var d := WorldCoords3D.distance_xz(global_position, worker.global_position)
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
