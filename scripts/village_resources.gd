extends Node


var _amounts: Dictionary = {"wood": 0}

signal changed(resource_id: String, amount: int)


func add(resource_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var current: int = int(_amounts.get(resource_id, 0))
	_amounts[resource_id] = current + amount
	changed.emit(resource_id, _amounts[resource_id])


func get_amount(resource_id: String) -> int:
	return int(_amounts.get(resource_id, 0))


func has(resource_id: String, amount: int) -> bool:
	return get_amount(resource_id) >= amount


func spend(resource_id: String, amount: int) -> bool:
	if not has(resource_id, amount):
		return false
	var current: int = get_amount(resource_id)
	_amounts[resource_id] = current - amount
	changed.emit(resource_id, _amounts[resource_id])
	return true