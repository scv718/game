extends Interactable
class_name QuarryInteractable

@onready var _quarry: Quarry = get_parent() as Quarry


func _ready() -> void:
	if _quarry == null:
		push_warning("QuarryInteractable requires a Quarry parent")
		return
	_quarry.workers_changed.connect(_on_workers_changed)
	prompt = _quarry.get_interact_prompt()


func get_quarry() -> Quarry:
	return _quarry


func can_interact() -> bool:
	return true


## TASK-011-4: 생산시설 직접 상호작용에서는 Worker를 Assign/Unassign하지 않는다.
## Worker 배치/해제는 여관 Roster UI에서 수행한다. 내부 assign/unassign API는
## Workplace.handle_worker_interaction/get_interact_prompt로 유지해 테스트/여관 로직에서 재사용한다.
func interact(_interactor: Node) -> Variant:
	return {}


func _on_workers_changed(_filled: int, _capacity: int) -> void:
	if _quarry != null:
		prompt = _quarry.get_interact_prompt()