extends Interactable
class_name GateInteractable

## TASK-013-4 성문 OPEN/CLOSED 토글용 최소 Interactable.
## Player가 성문 근처에서 상호작용(E)을 누르면 Gate를 toggle한다.
## prompt는 현재 상태를 반영해 갱신한다. 대규모 Command UI 선행 구현은 하지 않는다.

@onready var _gate: Gate = get_parent() as Gate


func _ready() -> void:
	if _gate == null:
		push_warning("GateInteractable requires a Gate parent")
		return
	if _gate.gate_state_changed.is_connected(_on_gate_state_changed):
		return
	_gate.gate_state_changed.connect(_on_gate_state_changed)
	_refresh_prompt()


func _refresh_prompt() -> void:
	if _gate == null:
		return
	prompt = "Gate (%s) - Toggle" % ("OPEN" if _gate.is_open() else "CLOSED")


func _on_gate_state_changed(_gate: Node, _open: bool) -> void:
	_refresh_prompt()


func can_interact() -> bool:
	return is_instance_valid(_gate)


func interact(_interactor: Node) -> Variant:
	if is_instance_valid(_gate):
		_gate.toggle()
	return {}