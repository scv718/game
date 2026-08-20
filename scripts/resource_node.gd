extends Interactable
class_name ResourceNode

@export var resource_id: String = "wood"
@export var max_amount: int = 5
@export var current_amount: int = 5
@export var gather_amount: int = 1

## TASK-011-6: 두 Worker가 같은 Tree를 동시에 선택하지 않도록 하는 가벼운 claim.
## worker가 이 노드를 대상으로 정하면 claim하고, 떠나면 release한다.
## 다른 worker가 이미 claim한 노드는 우선 피한다. 대규모 Reservation Manager 없음.
var _claimed_by: Node = null


func _ready() -> void:
	add_to_group("interactable")
	prompt = "채집"


func is_claimed() -> bool:
	return is_instance_valid(_claimed_by)


func is_claimed_by_other(worker: Node) -> bool:
	return is_instance_valid(_claimed_by) and _claimed_by != worker


func claim(worker: Node) -> bool:
	if is_instance_valid(_claimed_by) and _claimed_by != worker:
		return false
	_claimed_by = worker
	return true


func release(worker: Node) -> void:
	if _claimed_by == worker or not is_instance_valid(_claimed_by):
		_claimed_by = null


func can_interact() -> bool:
	return current_amount > 0


func interact(_interactor: Node) -> Dictionary:
	if not can_interact():
		return {}
	var gained: int = min(gather_amount, current_amount)
	current_amount -= gained
	if current_amount <= 0:
		_on_depleted()
	return {"resource_id": resource_id, "amount": gained}


func _on_depleted() -> void:
	queue_free()


func _exit_tree() -> void:
	var world = get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("rebuild_navigation_debounced"):
		world.rebuild_navigation_debounced()