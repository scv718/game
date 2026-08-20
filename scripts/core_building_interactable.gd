extends Interactable
class_name CoreBuildingInteractable

## TASK-011-1 핵심 건물용 최소 Interactable.
## 현재는 prompt 표시(식별 가능)만 제공하며 실제 기능은 없다.
## 식료품점/장비점/거점은 최소 prompt까지만 허용된다.
## 주점은 TASK-011-3에서 고용 UI를 열고, 여관은 후속 TASK-011-4에서 Roster 기능을 연결한다.

@onready var _building: CoreBuilding = get_parent() as CoreBuilding


func _ready() -> void:
	if _building == null:
		push_warning("CoreBuildingInteractable requires a CoreBuilding parent")
		return
	prompt = _building.get_interact_prompt()


func get_core_building() -> CoreBuilding:
	return _building


func can_interact() -> bool:
	return true


func interact(_interactor: Node) -> Variant:
	if _building == null:
		return {}
	var core_type := _building.get_core_type()
	if core_type == "tavern":
		var ui := get_tree().get_first_node_in_group("recruitment_ui")
		if ui != null and ui.has_method("open"):
			ui.open()
	elif core_type == "inn":
		var roster_ui := get_tree().get_first_node_in_group("inn_roster_ui")
		if roster_ui != null and roster_ui.has_method("open"):
			roster_ui.open()
	return {}
