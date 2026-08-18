extends CharacterBody2D

@export var move_speed: float = 120.0

var current_interactable: Interactable = null
var _nearby: Array[Interactable] = []

signal current_interactable_changed(interactable)


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * move_speed
	move_and_slide()
	_update_current_interactable()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		try_interact()


func try_interact() -> void:
	if not is_instance_valid(current_interactable):
		return
	var result: Variant = current_interactable.interact(self)
	if result is Dictionary:
		var amount: int = int(result.get("amount", 0))
		if amount > 0:
			VillageResources.add(String(result.get("resource_id", "")), amount)


func _on_interact_area_area_entered(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable != null:
		_nearby.append(interactable)


func _on_interact_area_area_exited(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable != null:
		_nearby.erase(interactable)


func _update_current_interactable() -> void:
	var best: Interactable = null
	var best_dist := INF
	for interactable in _nearby:
		if not is_instance_valid(interactable) or not interactable.can_interact():
			continue
		var d := global_position.distance_squared_to(interactable.global_position)
		if d < best_dist:
			best = interactable
			best_dist = d
	if not is_instance_valid(current_interactable) or best != current_interactable:
		current_interactable = best
		current_interactable_changed.emit(best)