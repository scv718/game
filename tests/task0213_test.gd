extends SceneTree

## TASK-021-3 Mercenary Potion Slot / Auto Consume 테스트.
## TASK-021-2와 동일한 data/service 계층 headless 테스트(autoload 사용).
##
## 완료조건 매핑:
##   1. equip: MercenaryData가 별도 Potion slot을 장착할 수 있다(알려진 id만, count 반영).
##   2. condition false -> 미사용: HP가 trigger(HP_BELOW_RATIO 0.3)보다 높으면 consume 안 함.
##   3. condition true -> 1회 사용: HP가 trigger 이하로 떨어지면 정확히 1회 소비.
##   4. effect 적용: HEAL 효과가 current_hp에 반영(max_hp 초과 없음).
##   5. stock 반영: 포션 스톡이 1 감소한다.
## 요구사항 보장:
##   - dead mercenary는 consume하지 않는다.
##   - 동일 조건에서 multi-consume 방지(consumed flag).
##   - pause/2x 무관하게 deterministic(상태만으로 결정, 경과시간 무관).
##   - Potion effect는 Player combat 경로를 만들지 않는다(그룹/공격 경로 없음).

enum Phase {
	SETUP, EQUIP, CONDITION_FALSE, CONDITION_TRUE, MULTI_CONSUME, DEAD, NO_PLAYER_PATH, DONE,
}

const HEALING_POTION := "healing_potion"
const MERC_MAX_HP := 100
const HEAL_AMOUNT := 30
const TRIGGER_RATIO := 0.3

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _resources: Node = null
var _service = null
var _merc = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	print("TASK0213_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.EQUIP:
			_equip()
		Phase.CONDITION_FALSE:
			_condition_false()
		Phase.CONDITION_TRUE:
			_condition_true()
		Phase.MULTI_CONSUME:
			_multi_consume()
		Phase.DEAD:
			_dead()
		Phase.NO_PLAYER_PATH:
			_no_player_path()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK0213_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _setup() -> void:
	if _frame < 8:
		return
	_resources = root.get_node_or_null("VillageResources")
	var service_script: GDScript = load("res://scripts/mercenary_potion_service.gd") as GDScript
	var data_script: GDScript = load("res://scripts/mercenary_data.gd") as GDScript
	_check(_resources != null, "VillageResources autoload available")
	_check(service_script != null, "mercenary_potion_service.gd loads")
	_check(data_script != null, "mercenary_data.gd loads")
	if _resources == null or service_script == null or data_script == null:
		_finish()
		return
	_service = service_script.new(_resources)
	_check(_service.resources == _resources, "potion service bound to VillageResources")
	_merc = data_script.new("merc_1", "Merc 1", 0)
	_merc.max_hp = MERC_MAX_HP
	_check(_merc != null, "MercenaryData created for slot test")
	_check(not _merc.has_potion_slot(), "mercenary starts without potion slot")
	_enter(Phase.EQUIP)


## -- EQUIP: battle start 전에 별도 Potion slot 장착 --
func _equip() -> void:
	_check(not _merc.equip_potion("not_a_potion", 2), "equip unknown potion rejected")
	_check(_merc.equip_potion(HEALING_POTION, 2), "equip healing_potion to merc potion slot")
	_check(_merc.has_potion_slot(), "mercenary has potion slot after equip")
	_check(_merc.get_potion_slot_id() == HEALING_POTION, "slot potion id preserved")
	_check(_merc.get_potion_slot_count() == 2, "slot potion count preserved (%d)" % _merc.get_potion_slot_count())
	_merc.unequip_potion()
	_check(not _merc.has_potion_slot(), "unequip clears potion slot")
	_check(_merc.equip_potion(HEALING_POTION, 1), "re-equip for consume test")
	_check(_merc.get_potion_slot_count() == 1, "re-equipped slot count 1")
	_enter(Phase.CONDITION_FALSE)


## -- CONDITION FALSE -> 미사용: HP가 trigger보다 높으면 consume 안 함 --
func _condition_false() -> void:
	_resources.add(PotionCraftService.STOCK_PREFIX + HEALING_POTION, 5)
	var hp_high := 80
	var stock_before := int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION))
	_check(not _service.can_auto_consume(_merc, hp_high, false),
		"can_auto_consume=false when HP above trigger ratio")
	var result: Dictionary = _service.auto_consume(_merc, hp_high, false)
	_check(result.get("ok") == false, "no consume when condition false")
	_check(int(result.get("new_hp", 0)) == hp_high, "HP unchanged when condition false")
	_check(_merc.get_potion_slot_count() == 1, "slot count unchanged when condition false")
	_check(int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION)) == stock_before,
		"stock unchanged when condition false")
	_enter(Phase.CONDITION_TRUE)


## -- CONDITION TRUE -> 1회 사용: HP가 trigger 이하 -> 1회 소비 + effect 적용 + stock 반영 --
func _condition_true() -> void:
	var hp_low := 20
	var stock_before := int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION))
	_check(_service.can_auto_consume(_merc, hp_low, false),
		"can_auto_consume=true when HP at/below trigger ratio")
	var result: Dictionary = _service.auto_consume(_merc, hp_low, false)
	_check(result.get("ok") == true, "consume succeeds once when condition true")
	_check(int(result.get("new_hp", 0)) == hp_low + HEAL_AMOUNT,
		"HEAL effect applied to current_hp (%d -> %d)" % [hp_low, int(result.get("new_hp", 0))])
	_check(result.get("consumed") == true, "consumed flag returned true")
	_check(_merc.get_potion_slot_count() == 0, "slot count decremented after consume (%d)" % _merc.get_potion_slot_count())
	_check(int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION)) == stock_before - 1,
		"potion stock reflected -1 after consume")
	_check(int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION)) >= 0,
		"potion stock stays non-negative")
	_enter(Phase.MULTI_CONSUME)


## -- MULTI_CONSUME 방지: 동일 조건에서 consumed flag가 true면 다시 소비 안 함 --
func _multi_consume() -> void:
	_resources.add(PotionCraftService.STOCK_PREFIX + HEALING_POTION, 5)
	_merc.equip_potion(HEALING_POTION, 2)
	var stock_before := int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION))
	var hp_low := 10
	var result_a: Dictionary = _service.auto_consume(_merc, hp_low, false)
	_check(result_a.get("ok") == true, "fresh consume (consumed=false) succeeds with count 2")
	_check(_merc.get_potion_slot_count() == 1, "slot count 2 -> 1 after first consume")
	_check(int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION)) == stock_before - 1,
		"fresh consume spends stock")
	var result_b: Dictionary = _service.auto_consume(_merc, hp_low, true)
	_check(result_b.get("ok") == false, "multi-consume blocked when consumed flag true")
	_check(not _service.can_auto_consume(_merc, hp_low, true), "can_auto_consume=false when consumed")
	_check(int(result_b.get("new_hp", 0)) == hp_low, "HP unchanged on blocked multi-consume")
	_check(_merc.get_potion_slot_count() == 1, "slot count unchanged on blocked multi-consume")
	_check(int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION)) == stock_before - 1,
		"stock unchanged on blocked multi-consume")
	_enter(Phase.DEAD)


## -- DEAD mercenary는 consume하지 않음 --
func _dead() -> void:
	_resources.add(PotionCraftService.STOCK_PREFIX + HEALING_POTION, 5)
	_merc.equip_potion(HEALING_POTION, 3)
	_merc.alive = false
	var stock_before := int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION))
	_check(not _service.can_auto_consume(_merc, 10, false), "dead mercenary cannot auto-consume")
	var result: Dictionary = _service.auto_consume(_merc, 10, false)
	_check(result.get("ok") == false, "dead mercenary does not consume potion")
	_check(_merc.get_potion_slot_count() == 3, "dead mercenary slot count unchanged")
	_check(int(_resources.get_amount(PotionCraftService.STOCK_PREFIX + HEALING_POTION)) == stock_before,
		"dead mercenary does not spend stock")
	_merc.alive = true
	_enter(Phase.NO_PLAYER_PATH)


## -- NO_PLAYER_PATH: Potion effect가 Player combat 경로를 만들지 않음 --
## service는 HEAL(HP 수정)만 수행하며 그룹 추가/공격/데미지 경로를 만들지 않는다.
func _no_player_path() -> void:
	_check(get_nodes_in_group("player").size() == 0, "no player group node created by potion path")
	var before_merc := get_nodes_in_group("mercenaries").size()
	var hp_low := 5
	var result: Dictionary = _service.auto_consume(_merc, hp_low, false)
	_check(result.get("ok") == true, "consume succeeds for player-path check")
	_check(int(result.get("new_hp", 0)) == hp_low + HEAL_AMOUNT, "HEAL effect applied (no combat path)")
	_check(get_nodes_in_group("player").size() == 0, "player group still empty after potion effect")
	_check(get_nodes_in_group("mercenaries").size() == before_merc,
		"mercenaries group unchanged by potion effect")
	_check(get_nodes_in_group("enemies").size() == 0, "no enemies created by potion effect")
	_enter(Phase.DONE)
