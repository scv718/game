extends Node2D
class_name StoneDeposit

var quarry: Node = null


func _ready() -> void:
	add_to_group("stone_deposits")


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