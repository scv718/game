extends Node
class_name CookingProduction

## TASK-020-2 최소 Cooking Production Path.
## 기존 worker production pattern을 재사용해 raw ingredient -> cooked meal 전환을
## 수행한다. VillageResources가 유일한 자원 원장(worker가 반납/소비하는 동일 계약)이고,
## CookingRecipes.craft가 결정적 소비/생산을 담당한다.
##
## 확정된 Kitchen building identity(장면/슬롯/배치 지점)는 GAME_DESIGN.md에 최소
## 형태(주방/식당 = 생재료를 음식으로 가공하고 요리사를 배치)만 존재할 뿐 구체 설계가
## 없으므로, 이 태스크에서는 건물/worker actor를 임의로 발명하지 않는다. 대신 순수
## production driver로 완료조건(재료 소비/meal 생성/중복 생산 없음/음수 재료 없음)을
## 만족시킨다. 실제 Kitchen workplace/building는 설계 확정 이후 별도 태스크에서 연결한다.
##
## 생산 규약(worker production pattern 재사용):
##   - craft_recipe(recipe_id): recipe 1건을 결정적으로 1회 수행. 재료가 충분할 때만
##     VillageResources에서 소비하고 출력 meal을 추가한다(중복/음수 방지).
##   - _process timed driver: production_interval 마다 설정된 recipe 전체를 순회해
##     한 주기당 각 recipe 1회만 생산한다(miner production_interval 패턴).
##   - can_craft가 재료 부족을 차단하므로 재료가 음수가 되는 경로가 없다.

signal meal_produced(recipe_id: String, output: String, amount: int)
signal craft_failed(recipe_id: String, reason: String)

@export var production_interval: float = 2.0

var _timer := 0.0
var _enabled := true
## recipe_id 목록. data-driven: CookingRecipes 레지스트리를 참조한다(문자열 하드코딩 최소).
var _recipe_ids: Array = []

var _resources: Node = null


func _ready() -> void:
	if _recipe_ids.is_empty():
		_recipe_ids = CookingRecipes.get_all_recipe_ids()
	_resources = get_tree().root.get_node_or_null("VillageResources")


## 배치될 recipe id 목록을 설정한다(기본은 레지스트리 전체). 사본으로 저장한다.
func set_recipe_ids(ids: Array) -> void:
	_recipe_ids = ids.duplicate()


func get_recipe_ids() -> Array:
	return _recipe_ids.duplicate()


func set_enabled(value: bool) -> void:
	_enabled = value


func is_enabled() -> bool:
	return _enabled


## 현재 자원 원장(테스트에서 VillageResources 대신 대체물 주입용).
func set_resource_source(source: Node) -> void:
	_resources = source


func get_resource_source() -> Node:
	return _resources


func _process(delta: float) -> void:
	if not _enabled:
		return
	if _resources == null or not is_instance_valid(_resources):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = production_interval
	for recipe_id in _recipe_ids:
		craft_recipe(str(recipe_id))


## recipe 1건을 결정적으로 1회 생산한다.
## 반환: {"success": bool, "recipe_id": String, "output": String, "amount": int,
##        "reason": String} (CookingRecipes.craft 결과에 meal 추가까지 반영).
## 재료 부족 시 성공 없이 실패하고 원장을 건드리지 않는다(음수 재료 방지).
func craft_recipe(recipe_id: String) -> Dictionary:
	if _resources == null or not is_instance_valid(_resources):
		return {"success": false, "recipe_id": recipe_id, "output": "", "amount": 0, "reason": "no_source"}
	var recipe := CookingRecipes.get_recipe(recipe_id)
	if recipe == null or not recipe.is_valid():
		craft_failed.emit(recipe_id, "invalid_recipe")
		return {"success": false, "recipe_id": recipe_id, "output": "", "amount": 0, "reason": "invalid_recipe"}
	if not CookingRecipes.can_craft(recipe, _resources):
		craft_failed.emit(recipe_id, "insufficient_ingredient")
		return {"success": false, "recipe_id": recipe_id, "output": "", "amount": 0, "reason": "insufficient_ingredient"}
	var result := CookingRecipes.craft(recipe, _resources)
	if not result["success"]:
		craft_failed.emit(recipe_id, str(result["reason"]))
		return {"success": false, "recipe_id": recipe_id, "output": "", "amount": 0, "reason": str(result["reason"])}
	var amount: int = int(result["amount"])
	# craft가 source에서 이미 재료를 소비했다. 출력 meal을 원장에 추가한다
	# (worker가 생산품을 VillageResources에 반납하는 패턴과 동일).
	if amount > 0:
		_resources.add(str(result["output"]), amount)
		meal_produced.emit(str(result["recipe_id"]), str(result["output"]), amount)
	return {
		"success": true,
		"recipe_id": str(result["recipe_id"]),
		"output": str(result["output"]),
		"amount": amount,
		"reason": "",
	}
