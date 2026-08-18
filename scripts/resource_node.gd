extends Interactable
class_name ResourceNode

@export var resource_id: String = "wood"
@export var max_amount: int = 5
@export var current_amount: int = 5
@export var gather_amount: int = 1


func _ready() -> void:
	add_to_group("interactable")
	prompt = "채집"


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