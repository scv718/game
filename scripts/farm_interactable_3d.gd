extends Interactable3D
class_name FarmInteractable3D

## TASK-019-1 Farm 선택 volume. lumberyard_interactable_3d.gd와 동일한 parent 위임
## 구조의 3D판이다.
##
## interact()는 기존 Workplace 계약에 따라 {}를 반환한다(Worker assign/unassign은
## Roster UI 소유이며 world 클릭으로 수행하지 않는다). farm UI 열기는 추후
## TASK-019-3에서 crop 관리와 함께 연결되며, 여기서는 선택/식별 prompt만 제공한다.

@onready var _farm: Farm3D = get_parent() as Farm3D


func _ready() -> void:
	if _farm == null:
		push_warning("FarmInteractable3D requires a Farm3D parent")
		return
	prompt = _farm.get_interact_prompt()


func get_farm() -> Farm3D:
	return _farm


func can_interact() -> bool:
	return true


func interact(_interactor: Node) -> Variant:
	return {}
