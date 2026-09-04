extends RefCounted
class_name PotionData

## TASK-021-2 canonical potion definition consumed by the existing combat hook.
## TASK-027-5 does not add a dungeon-specific effect.
enum EffectType { NONE, HEAL }
enum TriggerType { NONE, HP_BELOW_RATIO }

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

var id := ""
var display_name := ""
var description := ""
var ingredients: Dictionary = {}
var effect_type: EffectType = EffectType.NONE
var effect_amount := 0
var trigger_type: TriggerType = TriggerType.NONE
var trigger_value := 0.0
var max_stack := 1

static func is_known(potion_id: String) -> bool:
	return DEFINITIONS.has(potion_id)

static func get_definition(potion_id: String) -> PotionData:
	var raw: Dictionary = DEFINITIONS.get(potion_id, {})
	if raw.is_empty():
		return null
	var data := PotionData.new()
	data.id = str(raw.get("id", ""))
	data.display_name = str(raw.get("display_name", ""))
	data.description = str(raw.get("description", ""))
	data.ingredients = (raw.get("ingredients", {}) as Dictionary).duplicate()
	data.effect_type = int(raw.get("effect_type", EffectType.NONE))
	data.effect_amount = int(raw.get("effect_amount", 0))
	data.trigger_type = int(raw.get("trigger_type", TriggerType.NONE))
	data.trigger_value = float(raw.get("trigger_value", 0.0))
	data.max_stack = int(raw.get("max_stack", 1))
	return data
