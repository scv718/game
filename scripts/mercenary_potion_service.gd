extends RefCounted
class_name MercenaryPotionService

## TASK-021-3 Mercenary Potion Slot / Auto Consume service.
## MercenaryData의 별도 Potion slot에 장착된 포션을 combat condition(trigger) 만족 시
## 자동으로 1회 소비해 effect를 적용한다. TASK-021-2 PotionData의 data-driven
## trigger/effect만 읽어 코드 분기 없이 동작한다(첫 slice: HP_BELOW_RATIO -> HEAL).
##
## 계약:
## - battle start 전에 장착한 slot(MercenaryData.equip_potion)을 사용한다.
## - condition false -> 사용하지 않는다(can_auto_consume=false).
## - condition true -> 1회 사용한다. caller가 전달하는 `consumed` flag로 동일 조건에서
##   multi-consume을 방지하고(전투/밤 단위로 소비 후 true 유지), 호출부는 반환된
##   consumed를 다시 상태에 반영한다.
## - dead mercenary -> consume하지 않는다(merc.alive false면 거부).
## - pause/2x 등 시간 배율과 무관하게 상태(trigger/effect)만으로 결정해 deterministic.
##   무작위/경과시간 기반 분기 없음.
## - effect 적용은 HP 회복(HEAL)뿐이며 Player combat 경로(그룹 추가/공격/데미지 대상
##   생성)를 만들지 않는다.
## - potion stock은 VillageResources의 PotionCraftService.STOCK_PREFIX("potion:") 키에서
##   소비해 stock에 반영한다. stock 부족 시 effect는 적용하지 않고 소비하지 않는다.
## - service는 stateless다(multi-consume 방지 상태는 caller가 consumed로 보관).

var resources: Node = null


func _init(p_resources: Node = null) -> void:
	resources = p_resources


## 자동 소비 가능 여부. alive + 아직 소비 안 함 + slot에 포션 + 재고 충분 +
## trigger(HP_BELOW_RATIO) 만족일 때 true.
func can_auto_consume(merc: MercenaryData, current_hp: int, consumed: bool) -> bool:
	if merc == null or not merc.alive:
		return false
	if consumed:
		return false
	if not merc.has_potion_slot():
		return false
	var data := PotionData.get_definition(merc.potion_slot_id)
	if data == null:
		return false
	if data.trigger_type != PotionData.TriggerType.HP_BELOW_RATIO:
		return false
	if merc.max_hp <= 0:
		return false
	if not _has_stock(merc.potion_slot_id):
		return false
	return float(current_hp) / float(merc.max_hp) <= data.trigger_value


## 자동 소비 실행. condition 미충족/소비 불가면 {"ok": false, ...}를 반환하고 아무
## 것도 바꾸지 않는다. condition 만족 시 effect 적용 + potion stock 차감 + slot count
## 감소를 한 번에 수행하고 {"ok": true, "new_hp": ..., "consumed": true}를 반환한다.
## caller는 반환된 consumed를 상태에 반영해 multi-consume을 방지한다.
func auto_consume(merc: MercenaryData, current_hp: int, consumed: bool) -> Dictionary:
	if not can_auto_consume(merc, current_hp, consumed):
		return {"ok": false, "reason": "condition_not_met", "new_hp": current_hp, "consumed": consumed}
	var data := PotionData.get_definition(merc.potion_slot_id)
	var new_hp := _apply_effect(data, current_hp, merc.max_hp)
	_spend_stock(merc.potion_slot_id)
	merc.potion_slot_count = maxi(0, merc.potion_slot_count - 1)
	return {"ok": true, "reason": "", "new_hp": new_hp, "consumed": true}


## effect 적용. HEAL이면 max_hp를 넘지 않게 회복한다. 그 외 effect는 현재 HP 유지.
## Player combat 경로를 만들지 않는 순수 HP 수정만 수행한다.
func _apply_effect(data: PotionData, current_hp: int, max_hp: int) -> int:
	var hp := current_hp
	if data.effect_type == PotionData.EffectType.HEAL:
		hp = mini(max_hp, hp + data.effect_amount)
	return hp


func _has_stock(potion_id: String) -> bool:
	if resources == null or not is_instance_valid(resources):
		return false
	return resources.has(PotionCraftService.STOCK_PREFIX + potion_id, 1)


func _spend_stock(potion_id: String) -> void:
	if resources == null or not is_instance_valid(resources):
		return
	var key := PotionCraftService.STOCK_PREFIX + potion_id
	if resources.has(key, 1):
		resources.spend(key, 1)
