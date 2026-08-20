extends Workplace
class_name Quarry

var deposit: Node = null


func _init() -> void:
	max_workers = 2


func _ready() -> void:
	super._ready()
	add_to_group("quarries")


func bind_deposit(deposit_node: Node) -> void:
	deposit = deposit_node


func get_deposit() -> Node:
	return deposit


func get_worker_group() -> String:
	return "miners"


func get_worker_label() -> String:
	return "Miner"


## TASK-011-6: 두 Miner가 안정적으로 작업할 WorkPoint를 배치 index 기반으로 돌려준다.
## 두 Miner가 완전히 같은 위치에 겹쳐 영구 충돌/Navigation stall이 나지 않도록 한다.
func get_work_point_for(actor: Node) -> Node2D:
	var points: Array[Node2D] = []
	for child in get_children():
		if child is Marker2D and (child.name == "WorkPoint" or child.name == "WorkPoint2"):
			points.append(child)
	if points.is_empty():
		return get_node_or_null("WorkPoint") as Node2D
	var idx := 0
	for i in _assigned_workers.size():
		if _assigned_workers[i] == actor:
			idx = i
			break
	return points[idx % points.size()]


## TASK-011-5: Miner Actor를 이 시설의 SpawnPoint에 생성하고 기존 FSM을 시작한다.
func spawn_worker_actor(worker: WorkerData) -> Node:
	var scene: PackedScene = load("res://scenes/miner.tscn")
	var actor := scene.instantiate()
	var parent := get_parent()
	if parent == null:
		return null
	var spawn := get_node_or_null("SpawnPoint") as Node2D
	actor.position = spawn.global_position if spawn != null else global_position
	parent.add_child(actor)
	actor.worker_data = worker
	assign_worker(actor)
	return actor
