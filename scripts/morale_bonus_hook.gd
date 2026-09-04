extends RefCounted
class_name MoraleBonusHook

## TASK-023-2 Global Morale Bonus Hook.
## 살아 있는 강한 동료(MoraleState 총 사기)가 전역적으로 부대의 전투 능력에
## 보너스를 주는 hook이다. 기존 combat stat pipeline의 최소 연결 지점으로
## MercenaryActor3D._get_attack_damage()의 base attack에 승수(multiplier)를
## 적용한다(GAME_DESIGN §8 사기 시스템의 "공격 능력" 항목).
##
## 설계 원칙:
##   - 보너스는 MoraleState.get_total_morale()로부터 유도되는 순수 함수다. 총 사기는
##     roster identity 기반이라 월드 Actor(duplicate) 수와 무관하게 결정된다.
##     따라서 승수는 Actor spawn/despawn 횟수에 절대 영향받지 않아 "누적 중복 없음"
##     이 구조적으로 보장된다.
##   - base stat(merc_data.attack_damage)은 절대 변조하지 않는다. Actor가 보너스를
##     읽을 때만 승수를 곱하고, 원본 데이터는 그대로 둔다(영구 변조 금지).
##   - apply_to / remove_from은 mercenary_id 기준 멱등(add는 1회만, remove는 1회만)
##     하고, _refresh 시 freed(despawn/사망) Actor는 자동 정리해 stale/freed
##     reference가 남지 않는다. exact formula는 DESIGN_TUNING.

## DESIGN_TUNING: 총 사기 단위당 공격 보너스 승수. 정확한 밸런스 수치는 추후 확정.
const ATTACK_BONUS_PER_UNIT := 0.05

var _state: MoraleState = null
## mercenary_id -> Node(actor). 구독 중인 Actor 목록(멱등 중복 방지).
var _applied: Dictionary = {}

## morale 상태 변경 또는 보너스 승수 변경 시 발행.
signal changed


## bonus source인 MoraleState를 (재)할당한다. 기존 state 연결은 해제하고 새
## state의 morale_changed에 연결해 승수를 즉시 갱신한다. 동일 state 재할당은 no-op.
func set_state(state: MoraleState) -> void:
	if _state == state:
		return
	if _state != null and _state.morale_changed.is_connected(_refresh):
		_state.morale_changed.disconnect(_refresh)
	_state = state
	if _state != null and not _state.morale_changed.is_connected(_refresh):
		_state.morale_changed.connect(_refresh)
	_refresh()


func get_state() -> MoraleState:
	return _state


## 총 사기로부터 유도되는 전역 공격 보너스 승수(순수 함수). morale 0 이하는
## 보너스 없음(1.0, 페널티 부여 없음). state가 없으면 중립 1.0.
func get_attack_multiplier() -> float:
	if _state == null:
		return 1.0
	return 1.0 + maxf(0.0, _state.get_total_morale()) * ATTACK_BONUS_PER_UNIT


## morale_changed / set_state 시 구독 중인 모든 Actor에 최신 승수를 반영하고,
## freed(despawn/사망) Actor는 자동으로 정리한다. 승수는 총 사기로만 결정되므로
## 구독 수와 무관하게 동일 값이 유지돼 누적이 없다.
func _refresh() -> void:
	var mult := get_attack_multiplier()
	for id in _applied.keys():
		var actor: Variant = _applied[id]
		if actor == null or not is_instance_valid(actor):
			_applied.erase(id)
			continue
		if actor.has_method("set_morale_multiplier"):
			actor.set_morale_multiplier(mult)
	changed.emit()


## Actor에 보너스를 적용(구독 등록). mercenary_id 기준 정확히 1회만 등록돼
## 중복 누적이 없다. 이미 적용된 Actor는 false(멱등 no-op)를 반환한다.
func apply_to(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var id: String = _actor_id(actor)
	if _applied.has(id):
		return false
	if actor.has_method("set_morale_multiplier"):
		actor.set_morale_multiplier(get_attack_multiplier())
	_applied[id] = actor
	return true


## Actor에서 보너스를 제거(구독 해제). 멱등이며 미등록 Actor는 false를 반환한다.
## 승수는 유도 값이라 이 호출로 총 사기/보너스 자체는 변하지 않는다.
func remove_from(actor: Node) -> bool:
	if actor == null:
		return false
	var id: String = _actor_id(actor)
	if not _applied.has(id):
		return false
	if is_instance_valid(actor) and actor.has_method("set_morale_multiplier"):
		actor.set_morale_multiplier(1.0)
	_applied.erase(id)
	return true


## 현재 구독 중인(보너스 적용된) Actor 수.
func get_active_count() -> int:
	return _applied.size()


## freed(despawn/사망)된 Actor의 구독을 정리하고 제거 수를 반환한다.
## DAY despawn 등으로 Actor가 사라졌을 때 다음 spawn이 같은 mercenary_id의 새
## Actor로 재등록될 수 있도록 registry를 비운다(apply_to 멱등과 함께 누적 금지 보장).
func prune() -> int:
	var removed := 0
	for id in _applied.keys():
		var actor: Variant = _applied[id]
		if actor == null or not is_instance_valid(actor):
			_applied.erase(id)
			removed += 1
	if removed > 0:
		changed.emit()
	return removed


## Actor identity key. mercenary_id가 있으면 그것을, 없으면 instance_id를 쓴다.
func _actor_id(actor: Node) -> String:
	if actor.has_method("get_mercenary_id"):
		var id: String = actor.get_mercenary_id()
		if id != "":
			return id
	return str(actor.get_instance_id())
