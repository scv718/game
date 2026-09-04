extends RefCounted
class_name RecipeData

## TASK-020-1 최소 Cooking Recipe / Meal 데이터 모델.
## 생재료(raw ingredient) → 요리된 식사(cooked meal) 전환 규칙을 담는 순수 데이터
## 클래스. Actor/Node reference를 저장하지 않으며 snapshot(Dictionary)으로 직렬화해
## 재료 소진/요리 생산 로직(TASK-020-2)과 소비 효율(TASK-020-3)에서 독립적으로
## 재사용한다.
## 등급(tier)은 GAME_DESIGN 음식 등급(일반/레어/유니크/에픽/레전더리)을 반영한다.
## buff는 장기/전투 전 사전 버프 메타데이터 확장 지점으로, 값이 명확해질 때까지
## 빈 Dictionary로 두며 임의 combat stat buff를 강제하지 않는다.

enum Tier { COMMON = 1, RARE = 2, UNIQUE = 3, EPIC = 4, LEGENDARY = 5 }

const TIER_NAMES := {
	Tier.COMMON: "COMMON",
	Tier.RARE: "RARE",
	Tier.UNIQUE: "UNIQUE",
	Tier.EPIC: "EPIC",
	Tier.LEGENDARY: "LEGENDARY",
}

var recipe_id: String = ""
var display_name: String = ""
## raw ingredient input: resource_id -> 필요 수량. VillageResources의 자원 id 규칙과
## 동일한 문자열 key를 사용한다(예: "meat", "crop").
var inputs: Dictionary = {}
## 생산되는 meal/resource id.
var output: String = ""
var output_amount: int = 1
## 한 serving(출력 1단위)의 음식 효율(포만감 값). raw 직접 섭취보다 커야 한다.
var efficiency: float = 0.0
## 등급. 값이 클수록 고급. 첫 slice는 일반/레어만 사용하고 확장을 허용한다.
var tier: Tier = Tier.COMMON
## 장기/전투 전 사전 버프 메타데이터 확장점. data-driven dict이며 설계가 명확해질
## 때까지 빈 Dictionary 유지.
var buff: Dictionary = {}


func _init(p_recipe_id: String = "", p_display_name: String = "") -> void:
	recipe_id = p_recipe_id
	display_name = p_display_name


func get_tier_name() -> String:
	return TIER_NAMES.get(tier, "?")


## recipe 정의의 유효성을 검증한다. 입력이 비었거나 수량이 양수가 아니면 false.
## 출력/효율이 비정상이어도 false. 최소한의 data validation으로 문자열 하드코딩
## 분기 대신 규칙 기반 판정을 쓴다.
func is_valid() -> bool:
	if recipe_id.is_empty() or output.is_empty():
		return false
	if inputs.is_empty():
		return false
	for key in inputs.keys():
		var count: Variant = inputs[key]
		if typeof(count) != TYPE_INT or int(count) <= 0:
			return false
	if output_amount <= 0:
		return false
	if efficiency <= 0.0:
		return false
	if tier < Tier.COMMON or tier > Tier.LEGENDARY:
		return false
	return true


## 입력 raw 재료를 전부 직접 섭취했을 때의 총 효율(포만감 합).
## raw보다 cooked efficiency가 높아야 한다는 완료조건을 판정하기 위한 기준값.
func get_raw_efficiency() -> float:
	var total := 0.0
	for key in inputs.keys():
		var count: Variant = inputs[key]
		# raw 단위 효율은 재료 id별로 CookingRecipes.raw_efficiency에 정의된다.
		total += CookingRecipes.get_raw_efficiency(str(key)) * float(int(count))
	return total


## buff 확장 지점을 위한 설정/조회. 복사본으로 저장/반환해 내부 상태 우회 변경을
## 막는다(DeathRecord.metadata와 동일 규칙).
func set_buff(value: Dictionary) -> void:
	buff = value.duplicate(true)


func get_buff() -> Dictionary:
	return buff.duplicate(true)


## 순수 snapshot(Dictionary) 직렬화. 모든 값은 기본 타입이며 Node reference를
## 포함하지 않는다. inputs/buff는 복사본으로 포함한다.
func to_snapshot() -> Dictionary:
	return {
		"recipe_id": recipe_id,
		"display_name": display_name,
		"inputs": inputs.duplicate(true),
		"output": output,
		"output_amount": output_amount,
		"efficiency": efficiency,
		"tier": tier,
		"buff": buff.duplicate(true),
	}


## snapshot으로부터 recipe를 복원한다. inputs/buff는 복사본으로 참조해 원본
## Dictionary 수정이 내부 상태에 영향이 없게 한다.
static func from_snapshot(snapshot: Dictionary) -> RecipeData:
	var recipe := RecipeData.new(str(snapshot.get("recipe_id", "")), str(snapshot.get("display_name", "")))
	recipe.inputs = (snapshot.get("inputs", {}) as Dictionary).duplicate(true)
	recipe.output = str(snapshot.get("output", ""))
	recipe.output_amount = int(snapshot.get("output_amount", 1))
	recipe.efficiency = float(snapshot.get("efficiency", 0.0))
	recipe.tier = int(snapshot.get("tier", Tier.COMMON))
	var b: Variant = snapshot.get("buff", {})
	if typeof(b) == TYPE_DICTIONARY:
		recipe.buff = (b as Dictionary).duplicate(true)
	return recipe
