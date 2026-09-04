extends Node

## TASK-027-2 DungeonPreparationManager(autoload).
## Dungeon 출발 전 준비(preparation)를 던전별로 보관하고, 파티 편성/준비 자원
## hook 입력, 검증(DungeonPreparationService), 출발(depart)을 담당하는 persistent owner.
## Runtime Combat Actor reference를 저장하지 않는다. 실제 Dungeon Runtime 진입은
## TASK-027-3부터 depart 이후 상태(IN_PROGRESS)를 읽어 별도로 처리한다.
##
## - preparation은 dungeon_id당 정확히 1개이며, 없으면 DungeonManager.create_dungeon으로
##   instance를 보장한 뒤 생성한다(중복 생성 방지, DungeonManager 소유권 위임).
## - add_member는 dead / unavailable(active run/expedition) / duplicate member를
##   즉시 거부해 UI에서 명확한 사유를 보여준다.
## - member availability는 동적으로 계산한다. depart로 IN_PROGRESS가 된 dungeon의
##   편성 member는 다른 준비에서 unavailable이고, run이 CLEARED/FAILED로 종료되면
##   자동으로 다시 available이 된다(별도 run_end 이벤트 불필요).
## - depart는 검증 후 DISCOVERED -> READY -> IN_PROGRESS 전환까지 수행한다.
##   이는 데이터 상태 전환이며 Player가 직접 던전에 진입하는 것이 아니다.

signal preparation_changed(dungeon_id: String)
signal run_started(dungeon_id: String)

var _preparations: Dictionary = {}


## --- preparation lifecycle ---

## dungeon_id당 preparation을 1개 생성한다. dungeon instance가 없으면
## DungeonManager.create_dungeon으로 확보 후 생성한다(소유권은 DungeonManager).
func create_preparation(dungeon_id: String) -> bool:
	if dungeon_id.is_empty() or _preparations.has(dungeon_id):
		return false
	var dungeon: DungeonDefinition = DungeonManager.get_dungeon(dungeon_id)
	if dungeon == null:
		dungeon = DungeonManager.create_dungeon(dungeon_id)
	if dungeon == null:
		return false
	_preparations[dungeon_id] = DungeonPreparation.new(dungeon_id)
	preparation_changed.emit(dungeon_id)
	return true


func get_preparation(dungeon_id: String) -> DungeonPreparation:
	return _preparations.get(dungeon_id)


func has_preparation(dungeon_id: String) -> bool:
	return _preparations.has(dungeon_id)


func clear_preparation(dungeon_id: String) -> bool:
	if not _preparations.has(dungeon_id):
		return false
	_preparations.erase(dungeon_id)
	preparation_changed.emit(dungeon_id)
	return true


## --- member 편성 ---

## member 편성. duplicate / 미등록 / dead / unavailable(active run/expedition) member는
## 거부하고 사유를 함께 반환한다.
func add_member(dungeon_id: String, member_id: String) -> Dictionary:
	var prep := get_preparation(dungeon_id)
	if prep == null:
		return {"ok": false, "reason": "No preparation for this dungeon"}
	var mercenary: MercenaryData = null
	var roster: Node = _roster()
	if roster != null:
		mercenary = roster.get_mercenary(member_id)
	if mercenary == null:
		return {"ok": false, "reason": "Member not in roster"}
	if not mercenary.alive:
		return {"ok": false, "reason": "Member is dead"}
	if get_unavailable_member_ids().has(member_id):
		return {"ok": false, "reason": "Member is unavailable (on another active run/expedition)"}
	if prep.has_member(member_id):
		return {"ok": false, "reason": "Duplicate member"}
	if not prep.add_member(member_id):
		return {"ok": false, "reason": "Duplicate member"}
	preparation_changed.emit(dungeon_id)
	return {"ok": true, "reason": ""}


func remove_member(dungeon_id: String, member_id: String) -> bool:
	var prep := get_preparation(dungeon_id)
	if prep == null:
		return false
	if not prep.remove_member(member_id):
		return false
	preparation_changed.emit(dungeon_id)
	return true


## --- 준비 자원 hook (기존 설계에 필수 규칙이 없으므로 선택, 차단하지 않음) ---

func set_food_slot(dungeon_id: String, food_id: String) -> void:
	var prep := get_preparation(dungeon_id)
	if prep == null:
		return
	prep.set_food_slot(food_id)
	preparation_changed.emit(dungeon_id)


func set_potion_slots(dungeon_id: String, potion_ids: Array) -> void:
	var prep := get_preparation(dungeon_id)
	if prep == null:
		return
	prep.set_potion_slots(potion_ids)
	preparation_changed.emit(dungeon_id)


func set_equipment_summary(dungeon_id: String, summary: Array) -> void:
	var prep := get_preparation(dungeon_id)
	if prep == null:
		return
	prep.set_equipment_summary(summary)
	preparation_changed.emit(dungeon_id)


## --- 검증 / 출발 ---

## DungeonPreparationService.validate를 현재 상태(roster/active run) 기준으로 호출한다.
func validate(dungeon_id: String) -> Dictionary:
	var prep := get_preparation(dungeon_id)
	var dungeon: DungeonDefinition = DungeonManager.get_dungeon(dungeon_id)
	return DungeonPreparationService.validate(
		prep, dungeon, _roster(), get_unavailable_member_ids())


## 검증 후 출발한다. valid하면 non-READY(DISCOVERED/CLEARED/FAILED) -> READY ->
## IN_PROGRESS 전환까지 수행하고 true를 반환한다(재진입 포함). IN_PROGRESS는
## 검증에서 DUNGEON_NOT_PREPARABLE로 차단되므로 중복 출발이 없다.
## 출발 자체는 데이터 전환이며 Player가 직접 던전에 진입하는 것이 아니다.
func depart(dungeon_id: String) -> Dictionary:
	var report := validate(dungeon_id)
	if not report.get("valid", false):
		return {"ok": false, "report": report}
	var dungeon: DungeonDefinition = DungeonManager.get_dungeon(dungeon_id)
	if dungeon == null:
		return {"ok": false, "report": report}
	if dungeon.get_state() != DungeonDefinition.DungeonState.READY:
		DungeonManager.mark_ready(dungeon_id)
	if DungeonManager.start_run(dungeon_id):
		run_started.emit(dungeon_id)
		return {"ok": true, "report": report}
	return {"ok": false, "report": report}


## --- 위험도 / 보상 표시용 헬퍼 (읽기 전용) ---

## Dungeon 위험도. 발견된 region의 base_risk를 우선하고, region이 없으면
## dungeon metadata의 "risk"를 fallback으로 사용한다(0이면 미지정).
func get_dungeon_risk(dungeon_id: String) -> int:
	var dungeon: DungeonDefinition = DungeonManager.get_dungeon(dungeon_id)
	if dungeon == null:
		return 0
	var exploration: Node = get_node_or_null("/root/ExplorationManager")
	if exploration != null and exploration.has_method("get_region"):
		var region: ExplorationRegion = exploration.get_region(dungeon.region_id)
		if region != null:
			return int(region.base_risk)
	return int(dungeon.get_metadata().get("risk", 0))


## 예상 보상 정보 중 현재 공개 가능한 값: reward table entry 요약 + threat reward.
## 실제 지급 규칙은 TASK-027-7에서 이 데이터를 읽어 처리한다.
func get_public_reward_lines(dungeon_id: String) -> Array:
	var lines: Array = []
	var dungeon: DungeonDefinition = DungeonManager.get_dungeon(dungeon_id)
	if dungeon == null:
		return lines
	var table: DungeonRewardTable = DungeonManager.get_reward_table_for_dungeon(dungeon_id)
	if table != null:
		for entry in table.get_entries():
			lines.append("%s x%s" % [str(entry.get("id", "?")), str(entry.get("amount", 0))])
	if dungeon.threat_reward > 0:
		lines.append("Threat reduced by %d" % dungeon.threat_reward)
	return lines


## --- availability ---

## 현재 unavailable(active run/expedition) member id -> dungeon_id 맵.
## IN_PROGRESS 상태 dungeon의 편성 member를 포함하며, run 종료(CLEARED/FAILED) 시
## 자동 해제된다. 추후 Expedition 시스템은 별도 id를 이 집합에 병합해 전달한다.
func get_unavailable_member_ids() -> Dictionary:
	var out: Dictionary = {}
	for dungeon_id in _preparations:
		var prep: DungeonPreparation = _preparations[dungeon_id]
		var dungeon: DungeonDefinition = DungeonManager.get_dungeon(dungeon_id)
		if dungeon == null:
			continue
		if dungeon.get_state() != DungeonDefinition.DungeonState.IN_PROGRESS:
			continue
		for member_id in prep.get_member_ids():
			out[member_id] = dungeon_id
	return out


func _roster() -> Node:
	return get_node_or_null("/root/MercenaryRoster")
