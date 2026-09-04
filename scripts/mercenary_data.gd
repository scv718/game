extends RefCounted
class_name MercenaryData

## TASK-014-1 최소 MercenaryData.
## 고용된 용병의 데이터를 월드 전투 Actor와 분리해 보관하는 데이터 클래스.
## 미소환/미배치 상태에서는 Roster에만 존재하고 월드 전투 Actor는 생성하지 않는다.
## 실제 NIGHT Actor spawn / DAY despawn 라이프사이클은 TASK-014-2에서 다룬다.
## level / combat stats는 prototype 값이며 영구 Save/Load는 구현하지 않는다.

enum MercClass { SWORDSMAN }
enum DefenseZone { NONE, NORTH, EAST, SOUTH, WEST }

const CLASS_NAMES := {
	MercClass.SWORDSMAN: "SWORDSMAN",
}

const DEFENSE_NAMES := {
	DefenseZone.NONE: "NONE",
	DefenseZone.NORTH: "NORTH",
	DefenseZone.EAST: "EAST",
	DefenseZone.SOUTH: "SOUTH",
	DefenseZone.WEST: "WEST",
}

var id: String = ""
var display_name: String = ""
var merc_class: MercClass = MercClass.SWORDSMAN
var level: int = 1
var max_hp: int = 100
var attack_damage: int = 10
var attack_interval: float = 1.0
var move_speed: float = 120.0
var alive := true
var defense_zone: DefenseZone = DefenseZone.NONE

## TASK-021-3 Mercenary 별도 Potion slot.
## battle start 전에 장착하는 Potion slot(potion_id + count)이다. TASK-021-2의
## PotionData 정의만 받으며, 실제 자동 소비/효과 적용은 MercenaryPotionService가
## 수행한다. Food와 별도 계층이며 영구 Save/Load는 구현하지 않는다(기존 data 계약).
var potion_slot_id: String = ""
var potion_slot_count: int = 0


func _init(p_id: String = "", p_name: String = "", p_class: MercClass = MercClass.SWORDSMAN) -> void:
	id = p_id
	display_name = p_name
	merc_class = p_class


func get_class_name() -> String:
	return CLASS_NAMES.get(merc_class, "?")


func get_defense_name() -> String:
	return DEFENSE_NAMES.get(defense_zone, "?")


func set_defense_zone(zone: DefenseZone) -> void:
	if zone >= DefenseZone.NONE and zone <= DefenseZone.WEST:
		defense_zone = zone


func get_defense_zone() -> DefenseZone:
	return defense_zone


## TASK-021-3: Potion slot에 포션을 장착한다. 알려진 potion_id와 양수 count만
## 받아들인다. battle start 전에 장착하는 것을 전제로 한다(전투 중 재장착은 아님).
func equip_potion(potion_id: String, count: int) -> bool:
	if not PotionData.is_known(potion_id):
		return false
	potion_slot_id = potion_id
	potion_slot_count = maxi(0, count)
	return true


## TASK-021-3: Potion slot 장착을 해제한다.
func unequip_potion() -> void:
	potion_slot_id = ""
	potion_slot_count = 0


func get_potion_slot_id() -> String:
	return potion_slot_id


func get_potion_slot_count() -> int:
	return potion_slot_count


## TASK-021-3: Potion slot에 장착된 포션이 있는지.
func has_potion_slot() -> bool:
	return potion_slot_id != "" and potion_slot_count > 0