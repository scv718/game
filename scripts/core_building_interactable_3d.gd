extends Interactable3D
class_name CoreBuildingInteractable3D

## TASK-3D-BLD-001-1 핵심 건물용 3D Interactable.
## 기존 core_building_interactable.gd(Interactable = Area2D)의 위임 구조를
## Foundation Interaction3D 계약(interactable_3d.gd = Area3D) 위로 이전한 신규 파일이다.
## 기존 2D 파일은 LOCK 12에 따라 유지되며 이 파일이 대신하는 것은 3D Runtime뿐이다.
##
## - prompt는 parent CoreBuilding3D의 identity data에서 가져온다(2D와 동일 위임 구조).
## - interact 그룹 계약도 2D와 동일하다: 주점(tavern)은 "recruitment_ui" 그룹 노드의
##   open(), 여관(inn)은 "inn_roster_ui" 그룹 노드의 open(). 거점/식료품점/장비점은
##   최소 prompt까지만 허용된다(기존 TASK-011-1 경계 유지).
## - 선택 가능 대상이므로 is_selectable은 재정의하지 않는다(Foundation 기본값 true).

@onready var _building: CoreBuilding3D = get_parent() as CoreBuilding3D


func _ready() -> void:
	if _building == null:
		push_warning("CoreBuildingInteractable3D requires a CoreBuilding3D parent")
		return
	prompt = _building.get_interact_prompt()


func get_core_building() -> CoreBuilding3D:
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
