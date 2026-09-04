extends RefCounted
class_name MoraleState

## TASK-023-1 Morale State / Contributor Model.
## 고용된 MercenaryData(roster identity)에서 사기 기여자를 계산하고 총 사기를 관리한다.
## duplicate actor가 아닌 roster identity(mercenary_id)를 key로 하여 중복 집계를
## 막는다(같은 id의 contributor는 정확히 1개).
## Ghost contributor는 원본 생존자로 계산하지 않는다.
## exact formula는 DESIGN_TUNING이며 LEVEL_CONTRIBUTION(레벨당 기여)으로 data-driven
## 하게 둔다. 추후 밸런스 확정 시 상수만 조정하면 된다.

## DESIGN_TUNING: 레벨당 사기 기여 가중치. 정확한 밸런스 수치는 추후 확정.
const LEVEL_CONTRIBUTION := 0.25

## mercenary_id -> MoraleContributor. roster identity 기준이라 월드 Actor(duplicate)가
## 추가돼도 같은 id의 contributor는 1개만 유지된다.
var _contributors: Dictionary = {}

## contributor 목록 변화(추가/제거/alive/level/ghost 변경) 시 발행.
signal morale_changed


## roster data로 contributor 목록을 재계산한다. mercenaries는
## MercenaryRoster.get_mercenaries()(전체) 또는 get_alive()(살아있는 roster) 같은
## Array[MercenaryData]를 그대로 받는다. roster identity 기준이라 호출 시점의
## alive/level/ghost 상태가 contributor에 반영되고, roster에서 제거된 id는 집계에서
## 빠진다. 실제 변화가 있을 때만 morale_changed를 발행한다.
func refresh_from_mercenaries(mercenaries: Array) -> void:
	var changed := false
	var seen: Dictionary = {}
	for m in mercenaries:
		if m == null:
			continue
		var id: String = str(m.get("id"))
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		# bool()는 null에 대해 오류를 던지므로(Dictionary/미존재 필드) 값 비교로 안전
		# 변환한다. is_ghost 미존재(MercenaryData 등)는 null -> false로 처리한다.
		var is_ghost: bool = (m.get("is_ghost") == true)
		# alive 미존재/미지정은 생존(true)으로 간주.
		var alive: bool = (m.get("alive") != false)
		var lv: int = int(m.get("level"))
		var prev: MoraleContributor = _contributors.get(id)
		if prev == null:
			var c := MoraleContributor.new(id)
			c.display_name = str(m.get("display_name"))
			c.level = lv
			c.alive = alive
			c.is_ghost = is_ghost
			_contributors[id] = c
			changed = true
		elif prev.alive != alive or prev.level != lv or prev.is_ghost != is_ghost:
			prev.alive = alive
			prev.level = lv
			prev.is_ghost = is_ghost
			changed = true
	# roster에 더 이상 없는 contributor(제거/해고/roster 이탈)는 집계에서 제외.
	var to_remove: Array[String] = []
	for id in _contributors.keys():
		if not seen.has(id):
			to_remove.append(id)
	if not to_remove.is_empty():
		for id in to_remove:
			_contributors.erase(id)
		changed = true
	if changed:
		morale_changed.emit()


## 단일 contributor의 사기 기여도. ghost는 0(원본 생존자로 계산 안 함), 사망은 0.
func contribution_of(c: MoraleContributor) -> float:
	if c == null or not c.alive or c.is_ghost:
		return 0.0
	return MoraleContributor.contribution_from_level(c.level, LEVEL_CONTRIBUTION)


## 총 사기. 살아 있고 ghost가 아닌 contributor의 기여 합계.
func get_total_morale() -> float:
	var total := 0.0
	for c in _contributors.values():
		total += contribution_of(c as MoraleContributor)
	return total


## contributor 수(roster identity 기준, 중복 없음).
func get_contributor_count() -> int:
	return _contributors.size()


## 살아 있고 ghost가 아닌 실제 기여자 수.
func get_active_contributor_count() -> int:
	var n := 0
	for c in _contributors.values():
		var cc := c as MoraleContributor
		if cc.alive and not cc.is_ghost:
			n += 1
	return n


func get_contributor(mercenary_id: String) -> MoraleContributor:
	return _contributors.get(mercenary_id)


func get_contributors() -> Array[MoraleContributor]:
	var out: Array[MoraleContributor] = []
	for c in _contributors.values():
		out.append(c as MoraleContributor)
	return out


## 주요 기여자(기여도 내림차순 상위 limit개, 0 초과 기여자만). TASK-023-3 UI에서 사용.
func get_major_contributors(limit: int = 3) -> Array[MoraleContributor]:
	var all := get_contributors()
	all.sort_custom(
		func(a: MoraleContributor, b: MoraleContributor) -> bool:
			return contribution_of(a) > contribution_of(b))
	var out: Array[MoraleContributor] = []
	for c in all:
		if out.size() >= limit:
			break
		if contribution_of(c) > 0.0:
			out.append(c)
	return out
