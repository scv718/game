extends Node
class_name MercenaryHireSync3D

## TASK-3D-INT-001-2 주점 고용 → 3D MercenaryRoster 동기화 bridge.
## TavernRecruitmentUI는 차원 중립 UI로서 고용 MercenaryData를 autoload
## MercenaryRoster(2D combat autoload)에 기록한다. 3D Main World에서 실제 NIGHT
## spawn을 수행하는 주체는 MercenaryRoster3D(scene 노드)이므로, 이 노드가 고용
## 데이터를 id 기준으로 3D roster로 이월한다(UI/2D autoload 무수정, INT 소유 wiring).
##
## - 같은 MercenaryData "참조"를 이월한다(copy 아님). 따라서 여관 UI의 방어 구역
##   변경(m.set_defense_zone)과 사망(alive=false) 상태가 양쪽 roster에서 항상
##   일치하고, DeathLedger/despawn 규약도 단일 데이터 소스로 유지된다.
## - 중복 이월은 MercenaryRoster3D.add_mercenary의 id 중복 거부로 멱등하게 차단된다.
## - phase_changed(NIGHT) 시점에는 반드시 이 노드가 먼저 동기화되어야 spawn이
##   고용분을 포함한다. signal dispatch 순서 = connect 순서(트리 선언 순서)이므로
##   main_3d.tscn에서 MercenaryRoster3D보다 먼저 배치한다.
## - INT-001-3(2D runtime cleanup)에서 autoload MercenaryRoster가 제거될 경우
##   이 bridge도 함께 정리 대상이다(소스 부재 시 안전 no-op).

var _source: Node = null
var _target: Node = null


func _ready() -> void:
	_source = get_node_or_null("/root/MercenaryRoster")
	_target = get_tree().get_first_node_in_group("mercenary_roster_3d")
	if _target == null:
		# scene 자식 간 ready 순서상 target이 늦게 준비되는 경우를 위한 지연 조회.
		_target_ready.call_deferred()
	if _source != null and _source.has_signal("mercenaries_changed") \
			and not _source.mercenaries_changed.is_connected(_sync):
		_source.mercenaries_changed.connect(_sync)
	GameTime.phase_changed.connect(_on_phase_changed)


func _target_ready() -> void:
	_target = get_tree().get_first_node_in_group("mercenary_roster_3d")


func _on_phase_changed(phase: int, _day_number: int) -> void:
	if phase == GameTime.Phase.NIGHT:
		_sync()


## source(주점 UI가 기록하는 autoload)의 고용분을 target(3D roster)으로 이월한다.
## source/target 부재(freed) 시 안전 no-op. 반복 호출은 멱등(id 중복 거부).
func _sync() -> void:
	if _source == null or not is_instance_valid(_source):
		return
	if _target == null or not is_instance_valid(_target):
		return
	if not _source.has_method("get_mercenaries") \
			or not _target.has_method("add_mercenary"):
		return
	for m in _source.get_mercenaries():
		_target.add_mercenary(m)
