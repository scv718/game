extends SceneTree

## TASK-026-2 Expedition Party Data 자동검증 테스트.
## Runtime Actor와 분리된 Expedition persistent data의 데이터 생명주기
## (create/start/progress/complete)를 Actor 없이 headless로 검증한다.
## 상세 구현기록은 impl_fun/TASK-026-2_EXPEDITION_PARTY_DATA.md 참고.
##
## 검증 contract:
##   1. create: ExpeditionPartyData/ExpeditionManager 생성과 기본 필드.
##   2. duplicate expedition_id 차단.
##   3. duplicate member 차단(같은 expedition 내 + 다른 active expedition).
##   4. unavailable/dead member 출발 validation 실패.
##   5. serialize 가능한 순수 data(snapshot 순수성/round-trip/복사 보호).
##   6. member list 순서 deterministic 유지.
##   7. create/start/progress/complete lifecycle이 Actor 없이 동작.
##   8. Expedition 완료/귀환 후 member availability 복구.

var _frame := 0
var _failed := false

var _roster: Node = null
var _manager: ExpeditionManager = null
var _completed_count := 0
var _completed_id := ""


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 300:
		print("TASK0262_RESULT=TIMEOUT")
		quit()
		return true
	if _frame == 10:
		_run()
		return true
	return false


func _run() -> void:
	_roster = root.get_node_or_null("MercenaryRoster")
	_check(_roster != null, "MercenaryRoster autoload available")
	_manager = load("res://scripts/expedition_manager.gd").new()
	_manager.name = "ExpeditionManager"
	root.add_child(_manager)

	# --- 1. create: 기본 필드와 순수 RefCounted 데이터 ---
	var exp := _manager.create_expedition("exp_1", "ne_dungeon")
	_check(exp != null, "create_expedition returns ExpeditionPartyData")
	_check(exp.expedition_id == "exp_1", "expedition_id retained")
	_check(exp.destination_region_id == "ne_dungeon", "destination_region_id retained")
	_check(exp.get_status() == ExpeditionPartyData.Status.READY \
		and exp.get_status_name() == "READY", "default status is READY")
	_check(exp.get_class() == "RefCounted", \
		"ExpeditionPartyData is pure RefCounted data (no Node/Actor)")
	_check(exp.is_active() == false, "READY is not active")
	_check(exp.get_member_count() == 0, "member list starts empty")

	# --- 2. duplicate expedition_id 차단 ---
	var dup := _manager.create_expedition("exp_1", "ne_dungeon")
	_check(dup == null, "duplicate expedition_id rejected")
	_check(_manager.get_expedition("exp_1") == exp, "original expedition retained")
	_check(_manager.has_expedition("exp_1"), "has_expedition reflects registry")
	_check(_manager.create_expedition("", "ne_dungeon") == null, "empty expedition_id rejected")

	# --- 3. member 편성: duplicate member 차단 + deterministic 순서 ---
	var m1 := MercenaryData.new("m1", "A")
	var m2 := MercenaryData.new("m2", "B")
	var m3 := MercenaryData.new("m3", "C")
	_roster.add_mercenary(m1)
	_roster.add_mercenary(m2)
	_roster.add_mercenary(m3)

	_check(_manager.add_member("exp_1", "m1"), "member m1 added")
	_check(_manager.add_member("exp_1", "m2"), "member m2 added")
	_check(_manager.add_member("exp_1", "m3"), "member m3 added")
	_check(_manager.add_member("exp_1", "m1") == false, "duplicate member rejected")
	_check(_manager.add_member("exp_1", "") == false, "empty member id rejected")
	_check(_manager.add_member("missing_exp", "m1") == false, "unknown expedition rejected")
	var ids: Array = exp.get_member_ids()
	_check(ids == ["m1", "m2", "m3"], "member order deterministic (%s)" % str(ids))
	_check(exp.get_member_count() == 3, "member count is 3")

	# set_member_ids 복사/중복 제거/빈 id 제거(순서 유지)
	exp.set_member_ids(["m3", "m1", "m2", "m3", ""])
	_check(exp.get_member_ids() == ["m3", "m1", "m2"], \
		"set_member_ids dedups and keeps order (%s)" % str(exp.get_member_ids()))
	_check(_manager.add_member("exp_1", "m1") == false, \
		"m1 already in READY expedition (in-expedition duplicate still rejected)")
	var external := exp.get_member_ids()
	external.append("MUTATED")
	_check(not exp.has_member("MUTATED"), \
		"get_member_ids returns a copy (internal state protected)")
	exp.set_member_ids(["m1", "m2", "m3"])

	# --- 4. 출발 validation: alive member면 통과, dead/unavailable면 실패 ---
	_check(_manager.validate_departure("exp_1", _roster), \
		"departure validation passes with alive members")
	_check(_manager.validate_departure("missing_exp", _roster) == false, \
		"unknown expedition fails validation")
	var empty_exp := _manager.create_expedition("exp_empty", "region_x")
	_check(_manager.validate_departure("exp_empty", _roster) == false, \
		"expedition with no members fails validation")

	m3.alive = false
	_check(_manager.validate_departure("exp_1", _roster) == false, \
		"dead member fails departure validation")
	_check(_manager.start_departure("exp_1", 3, 10.0, _roster) == false, \
		"start_departure rejected while a member is dead")
	_check(exp.get_status() == ExpeditionPartyData.Status.READY, \
		"status unchanged after rejected departure")
	m3.alive = true
	_check(_manager.validate_departure("exp_1", _roster), \
		"departure validation passes again after member revived")

	# --- 7. lifecycle: start -> progress -> complete (Actor 없이) ---
	_check(_manager.start_departure("exp_1", 3, 10.0, _roster), "start_departure accepted")
	_check(exp.get_status() == ExpeditionPartyData.Status.OUTBOUND, \
		"READY -> OUTBOUND on departure")
	_check(exp.departure_day == 3 and _approx(exp.departure_time, 10.0), \
		"departure day/time recorded")
	_check(exp.is_active(), "OUTBOUND is active")
	_check(_manager.start_departure("exp_1", 4, 5.0, _roster) == false, \
		"duplicate departure from non-READY state rejected")
	_check(_manager.set_progress("exp_1", 0.5), "set_progress accepted")
	_check(_approx(exp.progress, 0.5), "progress stored")
	_check(_manager.set_progress("exp_1", 2.5) and _approx(exp.progress, 1.0), \
		"progress clamped to 1.0")
	_check(exp.set_status(ExpeditionPartyData.Status.EXPLORING), \
		"data-level OUTBOUND -> EXPLORING transition")
	_check(exp.set_status(ExpeditionPartyData.Status.RETURNING), \
		"data-level EXPLORING -> RETURNING transition")
	_check(exp.set_status(99) == false and exp.set_status(-1) == false, \
		"invalid status values rejected")
	_check(exp.get_status() == ExpeditionPartyData.Status.RETURNING, \
		"status unchanged after rejected set")

	# --- 6b. 다른 active Expedition 편성 차단 (member duplicate across active) ---
	var exp2 := _manager.create_expedition("exp_2", "ne_dungeon")
	_check(exp2 != null, "second expedition created")
	_check(_manager.add_member("exp_2", "m1") == false, \
		"member already in another active expedition rejected")
	var exp3 := _manager.create_expedition("exp_3", "other_region")
	var m4 := MercenaryData.new("m4", "D")
	_roster.add_mercenary(m4)
	_check(_manager.add_member("exp_3", "m4"), "fresh available member m4 added to third expedition")

	# READY expedition에 active 편성 member가 데이터 레벨로 들어온 경우 출발 실패
	exp2.add_member("m1")
	_check(_manager.validate_departure("exp_2", _roster) == false, \
		"member reserved by another active expedition fails departure validation")
	exp2.remove_member("m1")

	# --- 8. complete 후 availability 복구 ---
	_manager.expedition_completed.connect(_on_completed)
	_check(_manager.complete_expedition("exp_1"), "complete_expedition accepted (RETURNING)")
	_check(exp.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"RETURNING -> COMPLETED")
	_check(exp.is_active() == false, "COMPLETED is not active")
	_check(_approx(exp.progress, 1.0), "progress forced to 1.0 on complete")
	_check(_manager.complete_expedition("exp_1") == false, \
		"repeated complete rejected (no duplicate return)")
	_check(_manager.complete_expedition("exp_empty") == false, \
		"READY expedition cannot be completed")
	_check(_completed_count == 1 and _completed_id == "exp_1", \
		"expedition_completed emitted once")

	# exp_1 완료로 m1이 다시 편성 가능해졌는지 확인
	_check(_manager.add_member("exp_2", "m1"), \
		"member available again after expedition completed (roster availability restored)")

	# --- 5. serialize 가능한 순수 data / snapshot ---
	exp.add_discovered_feature("dungeon_entrance")
	exp.set_result({"success": true, "loot": 3})
	exp.set_metadata({"risk": 3})
	_check(exp.add_discovered_feature("dungeon_entrance") == false, \
		"duplicate discovered feature rejected")
	_check(exp.add_discovered_feature("") == false, "empty feature id rejected")
	var snap := exp.to_snapshot()
	_check(_snapshot_is_pure(snap), "snapshot contains only pure save-safe values")
	var restored := ExpeditionPartyData.from_snapshot(snap)
	_check(restored.expedition_id == exp.expedition_id \
		and restored.destination_region_id == exp.destination_region_id \
		and restored.get_status() == exp.get_status() \
		and restored.departure_day == exp.departure_day \
		and _approx(restored.departure_time, exp.departure_time) \
		and _approx(restored.progress, exp.progress), \
		"snapshot round-trip restores scalar fields")
	_check(restored.get_member_ids() == ["m1", "m2", "m3"], \
		"member ids survive round-trip in order")
	_check(restored.has_discovered_feature("dungeon_entrance"), \
		"discovered features survive round-trip")
	_check(bool(restored.get_result()["success"]) == true, "result survives round-trip")
	_check(int(restored.get_metadata()["risk"]) == 3, "metadata survives round-trip")
	snap["injected"] = true
	_check(exp.to_snapshot().has("injected") == false, \
		"to_snapshot returns an independent copy")
	var snapped_meta: Dictionary = snap.get("metadata", {})
	snapped_meta["risk"] = 999
	_check(int(exp.get_metadata()["risk"]) == 3, \
		"snapshot metadata is a copy (internal state protected)")
	var bad_snap := snap.duplicate(true)
	bad_snap["status"] = 42
	var restored_bad := ExpeditionPartyData.from_snapshot(bad_snap)
	_check(restored_bad.get_status() == ExpeditionPartyData.Status.READY, \
		"invalid status in snapshot falls back to READY")

	print("TASK0262_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _on_completed(expedition_id: String) -> void:
	_completed_count += 1
	_completed_id = expedition_id


func _snapshot_is_pure(snap: Dictionary) -> bool:
	var valid_types := [
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
		TYPE_VECTOR2, TYPE_RECT2, TYPE_DICTIONARY, TYPE_ARRAY,
	]
	for key in snap.keys():
		if typeof(snap[key]) not in valid_types:
			return false
	return true


func _initialize() -> void:
	pass
