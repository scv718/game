extends Interactable3D
class_name LumberyardInteractable3D

## TASK-3D-BLD-001-2 lumberyard 선택 volume. 기존 lumberyard_interactable.gd와 동일한
## parent 위임 구조의 3D판이다. 기존 2D 파일은 LOCK 12에 따라 유지된다.
##
## interact()는 기존과 동일하게 {}를 반환한다(Worker assign/unassign은 Roster UI 소유이며
## world 클릭으로 수행하지 않는다 - 기존 lumberyard_interactable.gd 규약).

@onready var _lumberyard: Lumberyard3D = get_parent() as Lumberyard3D


func _ready() -> void:
	if _lumberyard == null:
		push_warning("LumberyardInteractable3D requires a Lumberyard3D parent")
		return
	prompt = _lumberyard.get_interact_prompt()


func get_lumberyard() -> Lumberyard3D:
	return _lumberyard


func can_interact() -> bool:
	return true


func interact(_interactor: Node) -> Variant:
	return {}
