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


var _quaternius_model: Node3D = null

func _ready() -> void:
	add_to_group("stone_deposits_3d")
	_replace_with_quaternius()


func _replace_with_quaternius() -> void:
	var model := VisualAssetCatalog3D.instantiate_model("rock/medium_1")
	if model == null:
		return
	_quaternius_model = model
	model.position = Vector3(0.0, 1.0, 0.0)
	model.scale = Vector3.ONE * 0.8
	add_child(model)
	# Hide placeholder sphere mesh
	var placeholder := get_node_or_null("Visual/RockVisual")
	if placeholder != null:
		placeholder.visible = false


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
	_update_binding_visual(true)
	return true


func release() -> void:
	quarry = null
	_update_binding_visual(false)


func _update_binding_visual(bound: bool) -> void:
	if _quaternius_model == null:
		return
	# Tint model when bound to quarry
	if _quaternius_model.has_node("MeshInstance3D"):
		var mesh: MeshInstance3D = _quaternius_model.get_node("MeshInstance3D")
		if mesh.get_surface_override_material(0) != null:
			var mat: StandardMaterial3D = mesh.get_surface_override_material(0).duplicate()
			mat.albedo_color = Color(0.6, 0.6, 0.55) if bound else Color(0.7, 0.7, 0.68)
			mesh.set_surface_override_material(0, mat)
