extends RefCounted
class_name DungeonPreparationService

## TASK-027-2 Dungeon 출발 전 준비 검증 서비스.
## DungeonPreparation / DungeonDefinition / roster 데이터만으로 파티와 준비 자원을
## 검증해 명확한 사유(issue)를 반환한다. Runtime Actor reference를 저장하지 않으며
## 상태를 변경하지 않는 순수 함수형 검증이다.
##
## 검증 규칙(기존 설계 기준):
##  - dead/unavailable/expedition 중 member 거부 (MEMBER_DEAD / MEMBER_UNAVAILABLE).
##  - 동일 member 중복 거부 (MEMBER_DUPLICATE).
##  - party 크기는 Dungeon metadata의 required_party_min/max 범위를 따른다.
##  - 필수 Food 정책: 기존 설계/코드에 없으므로 적용하지 않는다(미지정 허용).
##  - Potion 미장착: 기존 설계상 선택이므로 허용한다(차단 없음).
##  - Equipment 미장착: 기존 설계상 선택이므로 허용한다(차단 없음).
##  신규 Food/Potion/Equipment 규칙을 발명하지 않는다.
##
## unavailable_ids는 "현재 다른 활동(active dungeon run / expedition)에 편성된
## member" 집합이다. Expedition 시스템이 이 분기에는 없으므로 DungeonPreparationManager가
## active run 소속 member를 이 집합으로 넘기고, 추후 Expedition 시스템이 있으면
## 별도 id를 병합해 전달할 수 있는 확장 지점이다.
## 반환: { "valid": bool, "can_depart": bool, "issues": [ { "code": int, "message": String } ] }

enum IssueCode {
	DUNGEON_NOT_FOUND,
	DUNGEON_NOT_PREPARABLE,
	PARTY_EMPTY,
	PARTY_TOO_SMALL,
	PARTY_TOO_LARGE,
	MEMBER_MISSING,
	MEMBER_DEAD,
	MEMBER_UNAVAILABLE,
	MEMBER_DUPLICATE,
}

const DEFAULT_MIN_PARTY := 0
const DEFAULT_MAX_PARTY := 99


static func validate(
		preparation: DungeonPreparation,
		dungeon: DungeonDefinition,
		roster: Node = null,
		unavailable_ids: Dictionary = {}) -> Dictionary:
	var issues: Array = []
	if preparation == null or preparation.dungeon_id.is_empty() \
			or dungeon == null or dungeon.dungeon_id != preparation.dungeon_id:
		issues.append(_issue(IssueCode.DUNGEON_NOT_FOUND, "Dungeon not found"))
		return {"valid": false, "can_depart": false, "issues": issues}

	# dungeon 상태: DISCOVERED/READY만 준비 가능. IN_PROGRESS(중복 출발 금지),
	# CLEARED/FAILED(종료)는 준비 불가 사유를 명확히 표시한다.
	var state: int = dungeon.get_state()
	if state == DungeonDefinition.DungeonState.IN_PROGRESS \
			or state == DungeonDefinition.DungeonState.CLEARED \
			or state == DungeonDefinition.DungeonState.FAILED:
		issues.append(_issue(IssueCode.DUNGEON_NOT_PREPARABLE,
			"Dungeon cannot be prepared (state: %s)" % dungeon.get_state_name()))

	var metadata: Dictionary = dungeon.get_metadata()
	var min_party := int(metadata.get("required_party_min", DEFAULT_MIN_PARTY))
	var max_party := int(metadata.get("required_party_max", DEFAULT_MAX_PARTY))
	var member_ids: Array = preparation.get_member_ids()

	if member_ids.is_empty():
		issues.append(_issue(IssueCode.PARTY_EMPTY, "No party members selected"))
	if member_ids.size() < min_party:
		issues.append(_issue(IssueCode.PARTY_TOO_SMALL,
			"Party needs at least %d members" % min_party))
	if member_ids.size() > max_party:
		issues.append(_issue(IssueCode.PARTY_TOO_LARGE,
			"Party exceeds maximum %d members" % max_party))

	var seen: Dictionary = {}
	for member_id in member_ids:
		if seen.has(member_id):
			issues.append(_issue(IssueCode.MEMBER_DUPLICATE,
				"Duplicate member '%s'" % member_id))
			continue
		seen[member_id] = true
		var mercenary: MercenaryData = null
		if roster != null and roster.has_method("get_mercenary"):
			mercenary = roster.get_mercenary(member_id)
		if mercenary == null:
			issues.append(_issue(IssueCode.MEMBER_MISSING,
				"Member '%s' does not exist in roster" % member_id))
			continue
		if not mercenary.alive:
			issues.append(_issue(IssueCode.MEMBER_DEAD,
				"Member '%s' is dead" % member_id))
			continue
		if unavailable_ids.has(member_id):
			issues.append(_issue(IssueCode.MEMBER_UNAVAILABLE,
				"Member '%s' is unavailable (active run/expedition)" % member_id))

	var valid := issues.is_empty()
	return {
		"valid": valid,
		"can_depart": valid,
		"issues": issues,
	}


static func _issue(code: int, message: String) -> Dictionary:
	return {"code": code, "message": message}