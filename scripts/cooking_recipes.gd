extends RefCounted
class_name CookingRecipes

## TASK-020-1 Cooking Recipe / Meal 데이터 레지스트리.
## 첫 slice recipe 1~2개를 data-driven Dictionary로 정의하고, recipe 조회/검증/
## 재료 부족 거부/결정적 요리 생산을 제공한다. 문자열 하드코딩 분기를 최소화하고
## 모든 값은 데이터(RecipeData)로 표현한다.
## raw efficiency table은 생재료를 직접 섭취했을 때의 단위 효율로, cooked 효율이
## raw보다 높아야 한다는 완료조건 판정에 사용한다.

## raw ingredient 단위 효율(직접 섭취). resource_id -> 단위 포만감.
const RAW_EFFICIENCY := {
	"meat": 2.0,
	"crop": 1.0,
}

## 첫 slice recipe 정의. recipe_id -> RecipeData 생성 인자 Dictionary.
## data-driven: 새 recipe를 추가하려면 여기에 항목을 추가하면 된다.
const RECIPE_DEFS := {
	"cooked_meat": {
		"display_name": "Cooked Meat",
		"inputs": {"meat": 2},
		"output": "meal_cooked_meat",
		"output_amount": 1,
		"efficiency": 6.0,
		"tier": RecipeData.Tier.COMMON,
	},
	"hearty_stew": {
		"display_name": "Hearty Stew",
		"inputs": {"meat": 1, "crop": 2},
		"output": "meal_hearty_stew",
		"output_amount": 1,
		"efficiency": 10.0,
		"tier": RecipeData.Tier.RARE,
		"buff": {"kind": "pre_battle", "scope": "morale", "strength": 1},
	},
}


static func get_raw_efficiency(resource_id: String) -> float:
	return float(RAW_EFFICIENCY.get(resource_id, 0.0))


## recipe_id에 해당하는 RecipeData를 생성해 반환한다. 정의가 없으면 null.
static func get_recipe(recipe_id: String) -> RecipeData:
	if not RECIPE_DEFS.has(recipe_id):
		return null
	var def: Dictionary = RECIPE_DEFS[recipe_id]
	var recipe := RecipeData.new(recipe_id, str(def.get("display_name", recipe_id)))
	recipe.inputs = (def.get("inputs", {}) as Dictionary).duplicate(true)
	recipe.output = str(def.get("output", ""))
	recipe.output_amount = int(def.get("output_amount", 1))
	recipe.efficiency = float(def.get("efficiency", 0.0))
	recipe.tier = int(def.get("tier", RecipeData.Tier.COMMON))
	var b: Variant = def.get("buff", {})
	if typeof(b) == TYPE_DICTIONARY:
		recipe.buff = (b as Dictionary).duplicate(true)
	return recipe


static func has_recipe(recipe_id: String) -> bool:
	return RECIPE_DEFS.has(recipe_id)


static func get_all_recipe_ids() -> Array:
	return RECIPE_DEFS.keys()


## 모든 정의 recipe를 RecipeData로 만들어 검증한다.
## 반환: {"valid": bool, "errors": [String]}.
static func validate_all() -> Dictionary:
	var errors: Array = []
	for recipe_id in RECIPE_DEFS.keys():
		var recipe := get_recipe(recipe_id)
		if recipe == null or not recipe.is_valid():
			errors.append("invalid recipe definition: " + str(recipe_id))
		elif recipe.efficiency <= recipe.get_raw_efficiency():
			# cooked 효율이 raw 직접 섭취 합보다 높아야 한다(핵심 규칙 LOCK).
			errors.append(
				"cooked efficiency must exceed raw: %s (cooked=%.2f raw=%.2f)"
				% [recipe_id, recipe.efficiency, recipe.get_raw_efficiency()]
			)
	return {"valid": errors.is_empty(), "errors": errors}


## 재료 부족 거부: source가 모든 입력 재료를 보유하면 true, 아니면 false.
## source는 has(resource_id, amount) -> bool 인터페이스를 제공해야 한다
## (VillageResources 등). has가 없으면(보유 불가 판정) false.
static func can_craft(recipe: RecipeData, source: Object) -> bool:
	if recipe == null or not recipe.is_valid():
		return false
	if source == null or not source.has_method("has"):
		return false
	for key in recipe.inputs.keys():
		if not source.has(str(key), int(recipe.inputs[key])):
			return false
	return true


## 결정적 요리 생산. 재료가 충분하면 source에서 재료를 소비하고 출력을 반환한다.
## 재료가 부족하면 실패(success=false, reason="insufficient_ingredient").
## source는 has/spend 인터페이스(VillageResources 등)를 제공해야 한다.
## 반환: {"success": bool, "recipe_id": String, "output": String,
##        "amount": int, "reason": String}.
static func craft(recipe: RecipeData, source: Object) -> Dictionary:
	if recipe == null or not recipe.is_valid():
		return {"success": false, "recipe_id": (recipe.recipe_id if recipe != null else ""), "output": "", "amount": 0, "reason": "invalid_recipe"}
	if not can_craft(recipe, source):
		return {"success": false, "recipe_id": recipe.recipe_id, "output": "", "amount": 0, "reason": "insufficient_ingredient"}
	# has 검증 통과 후 spend. spend 실패 시(방어적) 이미 소비된 재료를 원복하지 않고
	# 실패 처리한다. 순수 데이터 태스크에서는 source가 결정적이므로 실패하지 않는다.
	for key in recipe.inputs.keys():
		if not source.spend(str(key), int(recipe.inputs[key])):
			return {"success": false, "recipe_id": recipe.recipe_id, "output": "", "amount": 0, "reason": "spend_failed"}
	return {
		"success": true,
		"recipe_id": recipe.recipe_id,
		"output": recipe.output,
		"amount": recipe.output_amount,
		"reason": "",
	}
