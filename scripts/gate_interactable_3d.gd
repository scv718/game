extends Interactable3D
class_name GateInteractable3D

## TASK-3D-BLD-001-3 성문 OPEN/CLOSED 토글용 최소 Interactable3D.
## 기존 gate_interactable.gd(Interactable = Area2D)의 prompt/toggle 계약을
## Interactable3D(Area3D) base로 이전한 신규 파일이다. 기존 2D 파일은 LOCK 12에
## 따라 유지된다. prompt는 현재 상태를 반영해 갱신한다.

@onready var _gate: Gate3D = get_parent() as Gate3D


func _ready() -> void:
	if _gate == null:
		push_warning("GateInteractable3D requires a Gate3D parent")
		return
	if not _gate.gate_state_changed.is_connected(_on_gate_state_changed):
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
