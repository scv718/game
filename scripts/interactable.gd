extends Area2D
class_name Interactable

@export var prompt: String = "상호작용"


func can_interact() -> bool:
	return true


func interact(_interactor: Node) -> Variant:
	return null