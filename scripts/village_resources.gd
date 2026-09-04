extends Node

## TASK-018-1: Food Data / Village Resource Integration.
## Keep the existing resource (wood/stone) structure and add a Food resource layer.
## raw edible ingredients can be consumed directly but with low efficiency,
## and cooked meals are structured as a minimal future extension point
## (Cooking Feature / TASK-020). Uses FOOD_DEFS data-driven metadata instead of
## string branches. No persistent Save/Load is added, matching the existing policy.

enum FoodCategory {
	RAW_EDIBLE,
	COOKED_MEAL,
}

## Food item definitions (id -> metadata).
## efficiency: satiety/usefulness gained when consumed. raw is low, cooked higher.
## Exact values are balance tuning and can be split out into config/data (DESIGN_TUNING).
## TASK-018-2: "stew"는 Food 우선 소비/raw fallback 검증을 위한 최소 cooked meal
## 정의다. 세부 요리 시스템(cooked food 다양화)은 TASK-020 Cooking Feature가 맡는다.
const FOOD_DEFS := {
	"berry": {"category": FoodCategory.RAW_EDIBLE, "efficiency": 1},
	"apple": {"category": FoodCategory.RAW_EDIBLE, "efficiency": 1},
	"stew": {"category": FoodCategory.COOKED_MEAL, "efficiency": 3},
}

var _amounts: Dictionary = {"wood": 0, "stone": 0}

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


## ---- TASK-018-1 Food layer ----

## True if food_id is a defined Food item in FOOD_DEFS.
func is_food(food_id: String) -> bool:
	return FOOD_DEFS.has(food_id)


## Food stock query. Unknown food_id returns 0.
func get_food(food_id: String) -> int:
	return get_amount(food_id)


## Adds to the food stock. Only defined foods are allowed; non-positive amounts are ignored.
func add_food(food_id: String, amount: int) -> bool:
	if not is_food(food_id):
		return false
	add(food_id, amount)
	return true


## Consumes/removes from the food stock. Only defined foods are allowed; if the
## stock is insufficient it returns false and never goes negative (no negative stock).
func remove_food(food_id: String, amount: int) -> bool:
	if not is_food(food_id):
		return false
	return spend(food_id, amount)


## Returns the category of food_id, or -1 if the food is not defined.
func get_food_category(food_id: String) -> int:
	if not is_food(food_id):
		return -1
	return int(FOOD_DEFS[food_id].get("category", FoodCategory.RAW_EDIBLE))


## True if the food is a raw edible ingredient.
func is_raw_edible(food_id: String) -> bool:
	return get_food_category(food_id) == FoodCategory.RAW_EDIBLE


## True if the food is a cooked meal. Future extension point for the Cooking feature.
func is_cooked(food_id: String) -> bool:
	return get_food_category(food_id) == FoodCategory.COOKED_MEAL


## Consumption efficiency metadata. raw is low, cooked higher. Undefined food returns 0.
func get_food_efficiency(food_id: String) -> int:
	if not is_food(food_id):
		return 0
	return int(FOOD_DEFS[food_id].get("efficiency", 0))


## Returns the ids of all foods defined as raw edible (query of immediately edible items).
func get_raw_edible_food_ids() -> Array[String]:
	var out: Array[String] = []
	for food_id in FOOD_DEFS.keys():
		if is_raw_edible(food_id):
			out.append(food_id)
	return out
