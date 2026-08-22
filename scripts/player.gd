extends CharacterBody2D

## TASK-CTRL-001-1: Player는 더 이상 Camera2D를 소유하지 않고 WASD 직접 이동도 수행하지 않는다.
## 카메라 이동/Zoom은 CameraController(World Camera Controller)가 담당한다.
## Player는 TASK-CTRL-001-4에서 제거되므로 여기서는 상호작용 관련 로직만 유지한다.
## (TASK-CTRL-001-2에서 마우스 클릭 기반 interaction으로 대체되기 전까지 최소 유지)

var current_interactable: Interactable = null
var _nearby: Array[Interactable] = []

signal current_interactable_changed(interactable)


func _ready() -> void:
	add_to_group("player")


## WASD는 더 이상 Player 이동이 아니라 CameraController의 camera pan이므로
## Player는 정지 상태를 유지한다. 상호작용 감지만 계속 수행한다.
func _physics_process(_delta: float) -> void:
	velocity = Vector2.ZERO
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