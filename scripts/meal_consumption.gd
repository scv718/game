extends Node
class_name MealConsumption

## TASK-020-3 최소 Meal Consumption / Efficiency.
## cooked meal을 raw보다 높은 효율로 소비하고, meal이 부족하면 raw ingredient로
## fallback하며, 둘 다 부족하면 shortage 상태를 기록하는 순수 consumption driver.
## VillageResources가 유일한 자원 원장(worker 생산/소비와 동일 계약)이고,
## CookingRecipes의 recipe efficiency / raw efficiency를 효율 기준으로 사용한다.
##
## 소비 우선순위(consumption priority)는 GAME_DESIGN.md에 exact policy가 없으므로
## 결정적(deterministic)으로 데이터에서 유도한다:
##   1) cooked meal을 tier 내림차순, 동률이면 efficiency 내림차순으로 우선 소비.
##   2) meal이 부족하면 raw ingredient를 efficiency 내림차순으로 fallback 소비.
##   3) 그래도 부족하면 need가 남은 채 shortage 상태로 종료.
## 이 정책은 문자열 하드코딩 분기가 아니라 CookingRecipes 데이터 레지스트리에서
## 계산되므로, data-driven 규칙을 유지한다(임의 combat stat buff는 만들지 않는다).
##
## buff: GAME_DESIGN 음식 buff는 "전투 전 장기 준비" 메타데이터일 뿐 구체 적용
## 규칙이 확정되지 않았으므로, 이 태스크에서는 효율 증가(소비)까지만 완료하고
## 임의 combat stat buff를 생성하지 않는다. RecipeData.buff 확장점은 그대로 둔다.

signal meal_consumed(resource_id: String, amount: int)
signal raw_consumed(resource_id: String, amount: int)
signal shortage_occurred(need_remaining: float)

var _resources: Node = null
var _priority_cache: Array = []
var _priority_dirty := true


func _ready() -> void:
	if _resources == null:
		_resources = get_tree().root.get_node_or_null("VillageResources")


## 현재 자원 원장(테스트에서 VillageResources 대신 대체물 주입용).
func set_resource_source(source: Node) -> void:
	_resources = source


func get_resource_source() -> Node:
	return _resources


## 결정적 소비 우선순위 정책(데이터 유도). meal 우선 → raw fallback.
func get_consumption_priority() -> Array:
	if _priority_dirty:
		_priority_cache = _build_consumption_priority()
		_priority_dirty = false
	return _priority_cache.duplicate()


func _build_consumption_priority() -> Array:
	var meals := []
	for recipe_id in CookingRecipes.get_all_recipe_ids():
		var r := CookingRecipes.get_recipe(recipe_id)
		if r == null:
			continue
		meals.append({"id": str(r.output), "eff": r.efficiency, "tier": r.tier})
	meals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["tier"] != b["tier"]:
			return int(a["tier"]) > int(b["tier"])
		return float(a["eff"]) > float(b["eff"]))
	var raws := []
	for rid in CookingRecipes.RAW_EFFICIENCY.keys():
		raws.append({"id": str(rid), "eff": CookingRecipes.get_raw_efficiency(str(rid))})
	raws.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["eff"]) > float(b["eff"]))
	var priority: Array = []
	for m in meals:
		priority.append(str(m["id"]))
	for r in raws:
		priority.append(str(r["id"]))
	return priority


## resource_id가 meal이면(recipe output이면) 해당 recipe 효율, 아니면 raw 효율.
static func get_resource_efficiency(resource_id: String) -> float:
	for recipe_id in CookingRecipes.get_all_recipe_ids():
		var r := CookingRecipes.get_recipe(recipe_id)
		if r != null and str(r.output) == resource_id:
			return r.efficiency
	return CookingRecipes.get_raw_efficiency(resource_id)


## resource_id가 cooked meal 출력인지 여부.
static func is_meal(resource_id: String) -> bool:
	for recipe_id in CookingRecipes.get_all_recipe_ids():
		var r := CookingRecipes.get_recipe(recipe_id)
		if r != null and str(r.output) == resource_id:
			return true
	return false


## 필요 소비량(need, 포만감 단위)만큼 우선순위 순으로 소비한다.
## 반환: {"met": bool, "need": float, "need_remaining": float,
##        "efficiency_gained": float, "consumed": {resource_id: amount},
##        "shortage": bool}.
func consume_need(need: float) -> Dictionary:
	var consumed := {}
	var gained := 0.0
	if _resources == null or not is_instance_valid(_resources):
		return _result(need, need, consumed, gained, true)
	var remaining := need
	for resource_id in get_consumption_priority():
		if remaining <= 0.0:
			break
		var eff := get_resource_efficiency(str(resource_id))
		if eff <= 0.0:
			continue
		var amount: int = int(_resources.get_amount(str(resource_id)))
		if amount <= 0:
			continue
		var needed_units: int = ceili(remaining / eff)
		var to_consume: int = mini(int(needed_units), amount)
		if to_consume <= 0:
			continue
		if not _resources.spend(str(resource_id), to_consume):
			continue
		consumed[str(resource_id)] = int(consumed.get(str(resource_id), 0)) + to_consume
		gained += eff * float(to_consume)
		remaining -= eff * float(to_consume)
		if is_meal(str(resource_id)):
			meal_consumed.emit(str(resource_id), to_consume)
		else:
			raw_consumed.emit(str(resource_id), to_consume)
	var shortage := remaining > 0.001
	if shortage:
		shortage_occurred.emit(remaining)
	return _result(need, maxf(remaining, 0.0), consumed, gained, shortage)


func _result(need: float, remaining: float, consumed: Dictionary, gained: float, shortage: bool) -> Dictionary:
	return {
		"met": not shortage,
		"need": need,
		"need_remaining": remaining,
		"efficiency_gained": gained,
		"consumed": consumed.duplicate(true),
		"shortage": shortage,
	}
