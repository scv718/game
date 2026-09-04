extends RefCounted
class_name MercenaryPotionService

## TASK-027-5: shared, stateless auto-consume hook for 2D and Dungeon 3D actors.
## Stock remains in the existing VillageResources contract under potion:<id>.

var resources: Node = null
const POTION_STOCK_PREFIX := "potion:"

func _init(p_resources: Node = null) -> void:
	resources = p_resources

func can_auto_consume(merc: MercenaryData, current_hp: int, consumed: bool) -> bool:
	if merc == null or not merc.alive or consumed or not merc.has_potion_slot():
		return false
	var data := PotionData.get_definition(merc.potion_slot_id)
	if data == null or data.trigger_type != PotionData.TriggerType.HP_BELOW_RATIO:
		return false
	if merc.max_hp <= 0 or not _has_stock(merc.potion_slot_id):
		return false
	return float(current_hp) / float(merc.max_hp) <= data.trigger_value

func auto_consume(merc: MercenaryData, current_hp: int, consumed: bool) -> Dictionary:
	if not can_auto_consume(merc, current_hp, consumed):
		return {"ok": false, "new_hp": current_hp, "consumed": consumed}
	var data := PotionData.get_definition(merc.potion_slot_id)
	var new_hp := current_hp
	if data.effect_type == PotionData.EffectType.HEAL:
		new_hp = mini(merc.max_hp, current_hp + data.effect_amount)
	_spend_stock(merc.potion_slot_id)
	merc.potion_slot_count = maxi(0, merc.potion_slot_count - 1)
	return {"ok": true, "new_hp": new_hp, "consumed": true}

func _has_stock(potion_id: String) -> bool:
	return resources != null and is_instance_valid(resources) \
		and resources.has(POTION_STOCK_PREFIX + potion_id, 1)

func _spend_stock(potion_id: String) -> void:
	if _has_stock(potion_id):
		resources.spend(POTION_STOCK_PREFIX + potion_id, 1)
