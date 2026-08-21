extends Node

## TASK-014-1 최소 Mercenary Roster 기반.
## 고용된 MercenaryData를 월드와 독립적으로 보관한다.
## 미소환 MercenaryData는 이 Roster에만 존재하며 월드 전투 Actor는 생성하지 않는다.
## 같은 id의 용병 중복 고용을 거부하고, id 조회/생존 상태 조회를 제공한다.
## NIGHT Actor spawn / DAY despawn 라이프사이클은 TASK-014-2에서 다룬다.
## 영구 Save/Load는 구현하지 않는다.

var _mercenaries: Array[MercenaryData] = []

signal mercenaries_changed


func add_mercenary(mercenary: MercenaryData) -> bool:
	if mercenary == null or not mercenary is MercenaryData:
		return false
	if get_mercenary(mercenary.id) != null:
		return false
	_mercenaries.append(mercenary)
	mercenaries_changed.emit()
	return true


func remove_mercenary(mercenary: MercenaryData) -> bool:
	if mercenary == null or not _mercenaries.has(mercenary):
		return false
	_mercenaries.erase(mercenary)
	mercenaries_changed.emit()
	return true


func get_mercenary(mercenary_id: String) -> MercenaryData:
	for m in _mercenaries:
		if m.id == mercenary_id:
			return m
	return null


func get_mercenaries() -> Array[MercenaryData]:
	return _mercenaries.duplicate()


func get_alive() -> Array[MercenaryData]:
	var out: Array[MercenaryData] = []
	for m in _mercenaries:
		if m.alive:
			out.append(m)
	return out


func get_count() -> int:
	return _mercenaries.size()


func get_alive_count() -> int:
	return get_alive().size()