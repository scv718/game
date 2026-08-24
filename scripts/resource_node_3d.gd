extends Interactable3D
class_name ResourceNode3D

## TASK-3D-RES-001-1 Resource Node 3D base.
## 기존 resource_node.gd(Interactable = Area2D)의 claim/gather 규약을
## Foundation Interaction3D 계약(interactable_3d.gd = Area3D) 위로 이전한 신규 파일이다.
## 기존 2D resource_node.gd / tree.gd / stone_deposit.gd는 LOCK 12에 따라
## reference로 유지되며 이 파일들이 대신하는 것은 3D Runtime뿐이다.
##
## - game logic은 이 노드가 소유하고 visual/collision 표현은 자식에 둔다
##   (visual child와 game logic 분리 - tree_3d.gd의 Visual child 구조 참고).
## - is_selectable()은 false로 재정의한다. 자원 채집은 Worker 전용이며
##   Player 마우스 직접 채집 차단 정책(world_selection.gd allow-list)을
##   interactable_3d.gd가 예고한 hook으로 유지한다. 따라서 WorldSelection3D는
##   이 노드를 structurally 조회조차 하지 않도록 root Area3D를 INTERACTABLE
##   layer가 아닌 RESOURCE layer에 올린다(선택 광선이 자원에 가려져 뒤의
##   건물 선택을 막는 2D에는 없던 regression을 구조적으로 차단).
## - freed 후 reference 정리: _exit_tree에서 claim을 즉시 해제하고
##   NavigationPolicy3D.request_rebuild_debounced로 nav rebake를 요청한다
##   (기존 resource_node.gd _exit_tree -> world.rebuild_navigation_debounced의 3D판).
## - Worker 도메인(WRK)은 "resource_nodes_3d" 그룹으로 자원 노드를 탐색하고
##   claim/interact 규약을 그대로 소비한다.

@export var resource_id: String = "wood"
@export var max_amount: int = 5
@export var current_amount: int = 5
@export var gather_amount: int = 1

## TASK-011-6 경량 claim의 3D판. worker가 이 노드를 대상으로 정하면 claim하고,
## 떠나면 release한다. 다른 worker가 이미 claim한 노드는 우선 피한다.
var _claimed_by: Node = null


func _ready() -> void:
	add_to_group("resource_nodes_3d")
	prompt = "채집"


func is_claimed() -> bool:
	return is_instance_valid(_claimed_by)


func is_claimed_by_other(worker: Node) -> bool:
	return is_instance_valid(_claimed_by) and _claimed_by != worker


func claim(worker: Node) -> bool:
	if is_instance_valid(_claimed_by) and _claimed_by != worker:
		return false
	_claimed_by = worker
	return true


func release(worker: Node) -> void:
	if _claimed_by == worker or not is_instance_valid(_claimed_by):
		_claimed_by = null


## 마우스 직접 채집 차단(Worker 전용 자원). Foundation 선택 계약의 skip hook.
func is_selectable() -> bool:
	return false


func can_interact() -> bool:
	return current_amount > 0


func interact(_interactor: Node) -> Dictionary:
	if not can_interact():
		return {}
	var gained: int = min(gather_amount, current_amount)
	current_amount -= gained
	if current_amount <= 0:
		_on_depleted()
	return {"resource_id": resource_id, "amount": gained}


## 고갈 처리. regrowth 없이 사라지는 자원의 기본 동작은 제거다.
## Tree처럼 stump/regrowth를 가지면 tree_3d.gd처럼 override한다.
func _on_depleted() -> void:
	queue_free()


func _exit_tree() -> void:
	# instance가 tree에서 빠지는 순간 claim/reference와 nav 장애물 상태를 정리한다.
	# 남은 worker의 stale target 판정은 WRK 도메인의 is_instance_valid 가드 규약.
	_claimed_by = null
	NavigationPolicy3D.request_rebuild_debounced(get_tree())
