extends Node3D
class_name StoneDeposit3D

## TASK-3D-RES-001-1/-2 Stone Deposit 3D. 기존 stone_deposit.gd(StoneDeposit = Node2D)의
## occupancy anchor 계약을 3D로 이전한 신규 파일이다. 기존 2D 파일은 LOCK 12에 따라 유지.
##
## - StoneDeposit은 채집 상호작용 대상이 아니라 Quarry가 종속되는 자원 지점
##   anchor다(TASK-007 구조 유지). 따라서 Interactable3D를 쓰지 않고 순수 Node3D로
##   남으며, 물리 블록은 자식 StaticBody3D Block(CollisionLayers3D.RESOURCE)이 소유한다.
## - occupy/release 규약과 "stone_deposits_3d" 그룹은 2D("stone_deposits")와 분리된
##   3D 전용 계약이다. BLD 도메인의 3D placement가 이 그룹으로 deposit을 조회해
##   Quarry를 bind한다.
## - collision은 mesh polygon 대신 단순 SphereShape3D(r=2.25 unit = 2D Block r=18px
##   환산 불변)를 사용한다.

var quarry: Node = null


func _ready() -> void:
	add_to_group("stone_deposits_3d")


func is_occupied() -> bool:
	return is_instance_valid(quarry)


func get_quarry() -> Node:
	return quarry


func occupy(quarry_node: Node) -> bool:
	if quarry_node == null or not is_instance_valid(quarry_node):
		return false
	if is_occupied():
		return false
	quarry = quarry_node
	return true


func release() -> void:
	quarry = null
