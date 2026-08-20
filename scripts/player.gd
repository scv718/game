extends CharacterBody2D

@export var move_speed: float = 120.0

## TASK-010-3 밤 tactical view 카메라 배율. DAY에서는 day_zoom으로 복귀한다.
## 프로토타입 값이며 추후 실제 플레이에서 조정 가능하다(export).
@export var day_zoom: float = 1.0
@export var night_zoom: float = 0.5
@export var zoom_transition_speed: float = 3.0

var current_interactable: Interactable = null
var _nearby: Array[Interactable] = []
var _night_mode := false
var _camera: Camera2D = null

signal current_interactable_changed(interactable)


func _ready() -> void:
	add_to_group("player")
	_camera = $Camera2D
	GameTime.phase_changed.connect(_on_phase_changed)
	_apply_phase(GameTime.get_phase())


func _physics_process(delta: float) -> void:
	if _night_mode:
		velocity = Vector2.ZERO
	else:
		var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = input_dir * move_speed
	move_and_slide()
	_update_current_interactable()


func _process(delta: float) -> void:
	if _camera != null:
		var target := night_zoom if _night_mode else day_zoom
		_camera.zoom = _camera.zoom.lerp(Vector2(target, target), clampf(zoom_transition_speed * delta, 0.0, 1.0))


func _on_phase_changed(phase: int, _day_number: int) -> void:
	_apply_phase(phase)


func _apply_phase(phase: int) -> void:
	_night_mode = (phase == GameTime.Phase.NIGHT)


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