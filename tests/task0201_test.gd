extends SceneTree

## TASK-020-1 Cooking Recipe / Meal Data 자동 검증.
##  - RecipeData 단독 생성/조회(입력/출력/효율/등급/버프 메타데이터).
##  - data-driven: CookingRecipes 레지스트리로 첫 slice recipe 1~2개 조회.
##  - recipe validation: 정의가 규칙에 맞는지(is_valid) + cooked 효율 > raw 효율.
##  - insufficient ingredient rejection: 재료 부족 시 요리 거부.
##  - output deterministic: 같은 재료로 같은 결과.
##  - snapshot round-trip: to_snapshot → from_snapshot 값 보존.
##  - 순수 데이터 태스크: 기존 게임 코드/시나리오를 변경하지 않음.

enum Phase {
	DEFS,
	VALIDATE,
	CRAFT,
	SNAPSHOT,
	DONE,
}

var _frame := 0
var _phase: Phase = Phase.DEFS
var _failed := false

## VillageResources와 같은 has/spend 인터페이스를 가진 가짜 자원 원천.
class MockSource:
	extends RefCounted
	var amounts: Dictionary = {}

	func _init(initial: Dictionary) -> void:
		amounts = initial.duplicate(true)

	func has(resource_id: String, amount: int) -> bool:
		return int(amounts.get(resource_id, 0)) >= amount

	func spend(resource_id: String, amount: int) -> bool:
		if not has(resource_id, amount):
			return false
		amounts[resource_id] = int(amounts.get(resource_id, 0)) - amount
		return true


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.DEFS:
			if _frame < 4:
				return false
			_check_defs()
			_phase = Phase.VALIDATE
			_frame = 0
		Phase.VALIDATE:
			if _frame < 3:
				return false
			_check_validate()
			_phase = Phase.CRAFT
			_frame = 0
		Phase.CRAFT:
			if _frame < 3:
				return false
			_check_craft()
			_phase = Phase.SNAPSHOT
			_frame = 0
		Phase.SNAPSHOT:
			if _frame < 3:
				return false
			_check_snapshot()
			_phase = Phase.DONE
			_frame = 0
		Phase.DONE:
			if _frame < 2:
				return false
			print("TASK0201_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 1000:
		print("TASK0201_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _check_defs() -> void:
	# 1. data-driven 레지스트리에서 recipe 1~2개 조회.
	var ids := CookingRecipes.get_all_recipe_ids()
	_check(ids.size() >= 1 and ids.size() <= 2, "first slice has 1~2 recipes (%d)" % ids.size())
	_check(CookingRecipes.has_recipe("cooked_meat"), "cooked_meat recipe exists")
	_check(CookingRecipes.has_recipe("hearty_stew"), "hearty_stew recipe exists")

	# 2. RecipeData 단독 생성/조회(필드 세팅 없이 기본값 조회 가능).
	var r := RecipeData.new("r_test", "Test")
	_check(r.recipe_id == "r_test" and r.display_name == "Test", "recipe standalone create retains id/name")
	_check(r.output_amount == 1 and r.efficiency == 0.0, "recipe default output_amount/efficiency")
	_check(r.tier == RecipeData.Tier.COMMON, "recipe default tier=COMMON")
	_check(r.get_tier_name() == "COMMON", "recipe tier name COMMON")

	# 3. cooked_meat 정의 값 확인.
	var cm := CookingRecipes.get_recipe("cooked_meat")
	_check(cm != null, "get_recipe(cooked_meat) not null")
	_check(cm.is_valid(), "cooked_meat is valid")
	_check(cm.inputs.get("meat", 0) == 2, "cooked_meat input meat=2")
	_check(cm.output == "meal_cooked_meat", "cooked_meat output meal_cooked_meat")
	_check(cm.output_amount == 1, "cooked_meat output_amount=1")
	_check(cm.efficiency == 6.0, "cooked_meat efficiency=6.0")
	_check(cm.tier == RecipeData.Tier.COMMON, "cooked_meat tier=COMMON")

	# 4. hearty_stew 정의 값 확인 + buff 확장점.
	var hs := CookingRecipes.get_recipe("hearty_stew")
	_check(hs != null and hs.is_valid(), "hearty_stew valid")
	_check(hs.inputs.get("meat", 0) == 1 and hs.inputs.get("crop", 0) == 2, "hearty_stew inputs meat=1 crop=2")
	_check(hs.output == "meal_hearty_stew", "hearty_stew output meal_hearty_stew")
	_check(hs.efficiency == 10.0, "hearty_stew efficiency=10.0")
	_check(hs.tier == RecipeData.Tier.RARE, "hearty_stew tier=RARE")
	_check(hs.get_tier_name() == "RARE", "hearty_stew tier name RARE")
	_check(hs.buff.get("kind", "") == "pre_battle", "hearty_stew buff extension point present")

	# 5. 존재하지 않는 recipe는 null.
	_check(CookingRecipes.get_recipe("nope") == null, "unknown recipe returns null")


func _check_validate() -> void:
	# 1. 전체 정의 검증 통과.
	var report := CookingRecipes.validate_all()
	_check(report["valid"] == true, "all recipe definitions valid")
	_check((report["errors"] as Array).is_empty(), "no validation errors")

	# 2. cooked 효율 > raw 직접 섭취 합.
	var cm := CookingRecipes.get_recipe("cooked_meat")
	# raw: meat 2개 * 2.0 = 4.0, cooked: 6.0
	_check(cm.get_raw_efficiency() == 4.0, "cooked_meat raw efficiency = 4.0")
	_check(cm.efficiency > cm.get_raw_efficiency(), "cooked_meat cooked > raw")
	var hs := CookingRecipes.get_recipe("hearty_stew")
	# raw: meat 1*2.0 + crop 2*1.0 = 4.0, cooked: 10.0
	_check(hs.get_raw_efficiency() == 4.0, "hearty_stew raw efficiency = 4.0")
	_check(hs.efficiency > hs.get_raw_efficiency(), "hearty_stew cooked > raw")

	# 3. is_valid 규칙: 빈 입력/출력/음수 수량 거부.
	var bad := RecipeData.new("bad", "Bad")
	_check(bad.is_valid() == false, "recipe with empty output invalid")
	bad.output = "x"
	bad.inputs = {}
	_check(bad.is_valid() == false, "recipe with empty inputs invalid")
	bad.inputs = {"meat": 0}
	_check(bad.is_valid() == false, "recipe with zero input count invalid")
	bad.inputs = {"meat": -1}
	_check(bad.is_valid() == false, "recipe with negative input count invalid")
	bad.inputs = {"meat": 1}
	bad.efficiency = 0.0
	_check(bad.is_valid() == false, "recipe with zero efficiency invalid")
	bad.efficiency = 2.0
	bad.tier = 999
	_check(bad.is_valid() == false, "recipe with out-of-range tier invalid")
	bad.tier = RecipeData.Tier.COMMON
	_check(bad.is_valid() == true, "recipe becomes valid after corrections")

	# 4. raw efficiency는 정의되지 않은 재료는 0.
	_check(CookingRecipes.get_raw_efficiency("nope") == 0.0, "unknown raw efficiency = 0")


func _check_craft() -> void:
	var cm := CookingRecipes.get_recipe("cooked_meat")
	var hs := CookingRecipes.get_recipe("hearty_stew")

	# 1. 재료 부족 → 거부(insufficient ingredient rejection).
	var poor := MockSource.new({"meat": 1, "crop": 0})
	_check(CookingRecipes.can_craft(cm, poor) == false, "insufficient meat cannot craft cooked_meat")
	var res_poor := CookingRecipes.craft(cm, poor)
	_check(res_poor["success"] == false, "craft with insufficient ingredient fails")
	_check(res_poor["reason"] == "insufficient_ingredient", "insufficient ingredient reason set")
	_check(poor.amounts.get("meat", 0) == 1, "no ingredient spent on failed craft")

	# 2. 재료 충분 → 성공, 출력 결정적.
	var full := MockSource.new({"meat": 5, "crop": 5})
	_check(CookingRecipes.can_craft(cm, full) == true, "sufficient meat can craft cooked_meat")
	var r1 := CookingRecipes.craft(cm, full)
	_check(r1["success"] == true, "craft cooked_meat succeeds")
	_check(r1["output"] == "meal_cooked_meat" and r1["amount"] == 1, "craft output deterministic (meal_cooked_meat x1)")
	_check(full.amounts.get("meat", 0) == 3, "meat consumed (5 - 2 = 3)")

	# 3. 같은 상태에서 다시 요리하면 동일 출력(결정성).
	var full2 := MockSource.new({"meat": 5, "crop": 5})
	var r2 := CookingRecipes.craft(cm, full2)
	_check(r2["success"] == true and r2["output"] == r1["output"] and r2["amount"] == r1["amount"], "craft is deterministic across calls")

	# 4. 다중 재료 recipe: 전부 있어야 성공, 하나라도 부족하면 거부.
	var half := MockSource.new({"meat": 1, "crop": 1})
	_check(CookingRecipes.can_craft(hs, half) == false, "hearty_stew with missing crop rejected")
	var res_half := CookingRecipes.craft(hs, half)
	_check(res_half["success"] == false, "hearty_stew craft fails with insufficient crop")

	var stew_ok := MockSource.new({"meat": 1, "crop": 2})
	var rs := CookingRecipes.craft(hs, stew_ok)
	_check(rs["success"] == true and rs["output"] == "meal_hearty_stew", "hearty_stew craft succeeds with full inputs")
	_check(stew_ok.amounts.get("meat", 0) == 0 and stew_ok.amounts.get("crop", 0) == 0, "hearty_stew inputs fully consumed")

	# 5. null/무효 recipe 거부.
	var no_src := CookingRecipes.craft(cm, null)
	_check(no_src["success"] == false, "craft with null source fails")
	_check(CookingRecipes.can_craft(null, full) == false, "can_craft with null recipe fails")


func _check_snapshot() -> void:
	var hs := CookingRecipes.get_recipe("hearty_stew")
	var snap := hs.to_snapshot()
	var restored := RecipeData.from_snapshot(snap)
	_check(restored is RecipeData, "from_snapshot returns RecipeData")
	_check(restored.recipe_id == hs.recipe_id, "round-trip recipe_id")
	_check(restored.display_name == hs.display_name, "round-trip display_name")
	_check(restored.inputs.get("meat", 0) == hs.inputs.get("meat", 0), "round-trip inputs meat")
	_check(restored.inputs.get("crop", 0) == hs.inputs.get("crop", 0), "round-trip inputs crop")
	_check(restored.output == hs.output, "round-trip output")
	_check(restored.output_amount == hs.output_amount, "round-trip output_amount")
	_check(restored.efficiency == hs.efficiency, "round-trip efficiency")
	_check(restored.tier == hs.tier, "round-trip tier")
	_check(restored.buff.get("kind", "") == "pre_battle", "round-trip buff")

	# mutable 복사 방지: 원본 buff 수정이 snapshot/restored에 영향 없음.
	var b := {"kind": "pre_battle", "scope": "morale", "strength": 1}
	var r2 := RecipeData.new("r_b", "B")
	r2.set_buff(b)
	b["strength"] = 99
	_check(r2.buff.get("strength", 0) == 1, "set_buff stores copy (source mutation ignored)")
	var returned := r2.get_buff()
	returned["strength"] = -1
	_check(r2.buff.get("strength", 0) == 1, "get_buff returns copy (internal unchanged)")


func _initialize() -> void:
	pass
