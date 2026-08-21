extends CharacterBody2D
class_name MercenaryActor

## TASK-014-2 최소 Mercenary 전투 Actor.
## NIGHT 시작 시 defense zone에 해당하는 Gate 안쪽 Rally Space(또는 fallback RallyPoint)에
## spawn되고, DAY 복귀 시 despawn된다. 아직 전투 AI/FSM은 없으며(TASK-014-4) 월드에서의
## 존재/식별/위치만 담당한다. `merc_data`는 Roster의 MercenaryData를 참조하고,
## current_hp는 prototype으로 복사해 보관한다(사망/부활 처리는 TASK-014-6 이후).

var merc_data: MercenaryData = null
var current_hp: int = 0

@onready var _visual: AnimatedSprite2D = $Visual


func _ready() -> void:
	add_to_group("mercenaries")
	if merc_data != null:
		current_hp = merc_data.max_hp


func get_mercenary_id() -> String:
	return merc_data.id if merc_data != null else ""


func get_defense_zone() -> int:
	return merc_data.defense_zone if merc_data != null else MercenaryData.DefenseZone.NONE