extends RefCounted
class_name PotionCraftService

## TASK-021-2 Potion crafting service.
## ingredient validation + potion create를 담당하는 data/service 계층이다.
##
## - 재료는 VillageResources 스톡(resource_id 계약)에서 소비하고, 제작 결과는
##   같은 VillageResources에 포션 전용 키(prefix "potion:")로 추가한다.
## - 모든 재료를 사전 검증 후 일괄 소비하므로 중간 소비로 인한 부분 제작이 없고,
##   실패 시 재료/스톡이 전혀 변하지 않는다(완료조건: stock negative 없음).
## - crafting workplace(연금술 공방)가 건물로 확정되기 전까지는 이 서비스를
##   호출부(테스트 / 후속 TASK-021-3/038)에서 직접 생성해 사용한다. 임의 건물은
##   추가하지 않는다.
## - effect 적용/자동 소비는 TASK-021-3(Mercenary Potion Slot / Auto Consume)이
##   PotionData만 읽고 수행하므로 여기서는 생성까지로 한정한다.

const STOCK_PREFIX := "potion:"

## 재료 소비 대상 자원 싱글톤(VillageResources). 없으면 can_craft=false로 동작.
var resources: Node = null


func _init(p_resources: Node = null) -> void:
	resources = p_resources


## 제작 가능 여부: 정의 존재 + 모든 재료가 스톡에 충분.
func can_craft(potion_id: String) -> bool:
	var data := PotionData.get_definition(potion_id)
	if data == null:
		return false
	return _has_all_ingredients(data)


## 제작 실행. 성공/실패 사유를 Dictionary로 반환한다.
##   성공: {"ok": true, "potion_id": ..., "count": 1}
##   실패: {"ok": false, "reason": "unknown_potion" | "insufficient_ingredients"
##          | "no_resources", "potion_id": ..., "count": 0}
func craft(potion_id: String) -> Dictionary:
	var data := PotionData.get_definition(potion_id)
	if data == null:
		return {"ok": false, "reason": "unknown_potion", "potion_id": potion_id, "count": 0}
	if resources == null or not is_instance_valid(resources):
		return {"ok": false, "reason": "no_resources", "potion_id": potion_id, "count": 0}
	if not _has_all_ingredients(data):
		return {"ok": false, "reason": "insufficient_ingredients", "potion_id": potion_id, "count": 0}
	for resource_id in data.ingredients:
		resources.spend(resource_id, int(data.ingredients[resource_id]))
	resources.add(stock_key(potion_id), 1)
	return {"ok": true, "reason": "", "potion_id": potion_id, "count": 1}


## 포션 스톡 키. raw 자원(herb/wood/stone)과 분리해 같은 VillageResources에 둔다.
func stock_key(potion_id: String) -> String:
	return STOCK_PREFIX + potion_id


func get_stock(potion_id: String) -> int:
	if resources == null or not is_instance_valid(resources):
		return 0
	return int(resources.get_amount(stock_key(potion_id)))


func _has_all_ingredients(data: PotionData) -> bool:
	if resources == null or not is_instance_valid(resources):
		return false
	for resource_id in data.ingredients:
		if not resources.has(resource_id, int(data.ingredients[resource_id])):
			return false
	return true
