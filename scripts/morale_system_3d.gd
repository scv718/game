extends Node
class_name MoraleSystem3D

## TASK-023-3 Morale Runtime Wiring / UI source.
## 고용된 3D MercenaryRoster(MercenaryRoster3D)의 roster data로부터 사기 상태를
## 갱신하고, 전역 공격 보너스 hook(MoraleBonusHook)을 NIGHT에 spawn된 용병 Actor에
## 연결한다. UI(MoraleUI)가 current morale / major contributor / bonus를 읽는 단일
## 소스다.
##
## 설계 원칙(TASK-023-1/-2 재사용):
##   - MoraleState는 roster identity(mercenary_id) 기준이라 중복 집계가 구조적으로 없다.
##   - MoraleBonusHook 승수는 총 사기로부터 유도되는 순수 함수라 spawn/despawn 반복에도
##     누적이 없다. apply_to/remove_from은 멱등이다.
##   - state 갱신은 roster data 변화(mercenaries_changed)와 phase 전환 시점에 수행해
##     NIGHT lethal death(alive=false)와 DAY 복귀 후 상태를 항상 일관되게 유지한다.
##   - bonus hook은 base stat(merc_data.attack_damage)을 영구 변조하지 않는다(2D/3D 계약).
##
## exact formula는 DESIGN_TUNING(MoraleState.LEVEL_CONTRIBUTION /
## MoraleBonusHook.ATTACK_BONUS_PER_UNIT)이며 이 노드는 수치 자체를 정의하지 않는다.

var state: MoraleState = null
var bonus_hook: MoraleBonusHook = null

## UI/외부가 구독하는 변경 신호. state/bonus가 갱신될 때마다 발행한다.
signal changed

var _roster: Node = null


func _ready() -> void:
	add_to_group("morale_system")
	state = MoraleState.new()
	state.morale_changed.connect(_on_state_changed)
	bonus_hook = MoraleBonusHook.new()
	bonus_hook.set_state(state)
	_roster = get_tree().get_first_node_in_group("mercenary_roster_3d")
	if _roster != null and _roster.has_signal("mercenaries_changed") \
			and not _roster.mercenaries_changed.is_connected(_refresh):
		_roster.mercenaries_changed.connect(_refresh)
	GameTime.phase_changed.connect(_on_phase_changed)
	_refresh()


func _on_state_changed() -> void:
	changed.emit()


## roster data로 사기 상태를 재계산하고, 현재 spawn된 Actor에 bonus hook을 반영한다.
func _refresh() -> void:
	if _roster == null or not is_instance_valid(_roster):
		_roster = get_tree().get_first_node_in_group("mercenary_roster_3d")
	if _roster != null and _roster.has_method("get_mercenaries"):
		state.refresh_from_mercenaries(_roster.get_mercenaries())
	_sync_actor_hooks()


## NIGHT spawn 직후 / DAY despawn 시점에 spawn된 Actor로 bonus hook 구독을 동기화한다.
## apply_to/remove_from이 멱등이라 반복 호출에도 중복/누적이 없다.
## 각 Actor의 died 신호에도 연결해 NIGHT lethal death 시 사기 상태를 즉시 갱신한다.
func _sync_actor_hooks() -> void:
	if _roster == null or not is_instance_valid(_roster):
		return
	if not _roster.has_method("get_actor"):
		return
	# despawn/사망으로 freed된 stale 구독을 먼저 정리한다. 같은 mercenary_id의 새
	# Actor가 재등록될 수 있어야 한다(apply_to 멱등과 함께 누적 없음 보장).
	bonus_hook.prune()
	for m in state.get_contributors():
		if not m.alive or m.is_ghost:
			continue
		var actor: Node = _roster.get_actor(m.mercenary_id)
		if actor != null and is_instance_valid(actor):
			bonus_hook.apply_to(actor)
			if actor.has_signal("died") \
					and not actor.died.is_connected(_on_actor_died):
				actor.died.connect(_on_actor_died)


## NIGHT 중 용병 Actor가 사망하면(alive=false 반영 후) 사기 상태를 재계산한다.
## DAY cleanup/despawn은 die()를 거치지 않아 이 경로로 오지 않는다.
func _on_actor_died(_mercenary: Node) -> void:
	_refresh()


func _on_phase_changed(phase: int, _day_number: int) -> void:
	if phase == GameTime.Phase.NIGHT:
		_refresh()
	elif phase == GameTime.Phase.DAY:
		# DAY 복귀: spawn된 Actor는 despawn되므로 사기 상태만 유지하고 bonus는
		# 다음 NIGHT spawn 때 재적용한다(멱등). 상수(총 사기)는 변하지 않는다.
		_refresh()
		# despawn된 freed Actor의 stale 구독을 정리한다(누적/재등록 방지).
		bonus_hook.prune()
