extends RefCounted
class_name PotionData

## TASK-021-2 Potion definition (data-driven).
## 포션 정의를 코드 분기 없이 데이터로 유지한다. effect / trigger / stack 규칙은
## 전부 필드로 분리해 TASK-021-3(Mercenary Potion Slot / Auto Consume)이 이
## 데이터만 소비하도록 한다.
##
## - 첫 slice는 회복 포션 1종(healing_potion)이다.
## - ingredient는 resource_id 기반 Dictionary(VillageResources 재료 계약과 동일).
## - exact trigger/amount는 queue LOCK대로 data-driven이며 밸런스 수치는
##   `DESIGN_TUNING`으로 둔다(설계 기준: HP 30% 이하 -> 회복 포션).
## - stack 규칙: 슬롯 1칸에 최대 max_stack개까지 쌓인다. 실제 슬롯 장착/자동
##   소비 연결은 TASK-021-3에서 수행한다.
## - crafting workplace(연금술 공방)가 아직 건물로 확정되지 않아(TASK-021-2
##   요구: 임의 건물 추가 금지) 이 태스크에서는 data + service까지만 제공한다.

enum EffectType { NONE, HEAL }
enum TriggerType { NONE, HP_BELOW_RATIO }

const EFFECT_NAMES := {
	EffectType.NONE: "NONE",
	EffectType.HEAL: "HEAL",
}

const TRIGGER_NAMES := {
	TriggerType.NONE: "NONE",
	TriggerType.HP_BELOW_RATIO: "HP_BELOW_RATIO",
}

## 포션 정의 레지스트리(첫 slice 1종). get_definition()으로 인스턴스를 만든다.
const DEFINITIONS := {
	"healing_potion": {
		"id": "healing_potion",
		"display_name": "치유 포션",
		"description": "약초로 빚은 즉효 회복 포션.",
		"ingredients": {"herb": 2},
		"effect_type": EffectType.HEAL,
		"effect_amount": 30,
		"trigger_type": TriggerType.HP_BELOW_RATIO,
		"trigger_value": 0.3,
		"max_stack": 3,
	},
}

var id: String = ""
var display_name: String = ""
var description: String = ""
var ingredients: Dictionary = {}
var effect_type: EffectType = EffectType.NONE
var effect_amount: int = 0
var trigger_type: TriggerType = TriggerType.NONE
var trigger_value: float = 0.0
var max_stack: int = 1


static func is_known(potion_id: String) -> bool:
	return DEFINITIONS.has(potion_id)


static func get_all_ids() -> Array[String]:
	return DEFINITIONS.keys()


static func get_definition(potion_id: String) -> PotionData:
	var def: Dictionary = DEFINITIONS.get(potion_id, {})
	if def.is_empty():
		return null
	var data := PotionData.new()
	data.id = String(def.get("id", ""))
	data.display_name = String(def.get("display_name", ""))
	data.description = String(def.get("description", ""))
	data.ingredients = (def.get("ingredients", {}) as Dictionary).duplicate()
	data.effect_type = int(def.get("effect_type", EffectType.NONE))
	data.effect_amount = int(def.get("effect_amount", 0))
	data.trigger_type = int(def.get("trigger_type", TriggerType.NONE))
	data.trigger_value = float(def.get("trigger_value", 0.0))
	data.max_stack = int(def.get("max_stack", 1))
	return data


func get_effect_name() -> String:
	return EFFECT_NAMES.get(effect_type, "?")


func get_trigger_name() -> String:
	return TRIGGER_NAMES.get(trigger_type, "?")