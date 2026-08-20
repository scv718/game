extends Workplace
class_name Lumberyard

@export var work_radius: float = 192.0


func _init() -> void:
	max_workers = 2


func _ready() -> void:
	super._ready()
	add_to_group("lumberyards")


func get_worker_group() -> String:
	return "lumberjacks"


func get_worker_label() -> String:
	return "Worker"


## TASK-011-5: Lumberjack Actor를 이 시설의 SpawnPoint에 생성하고 기존 FSM을 시작한다.
func spawn_worker_actor(worker: WorkerData) -> Node:
	var scene: PackedScene = load("res://scenes/lumberjack.tscn")
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
