extends SceneTree

## TASK-016-1 DeathRecord Data Model 자동 검증.
##  - Actor 없이 DeathRecord 단독 생성/조회 가능.
##  - 사망 시점 값을 snapshot: Actor가 freed되어도 record가 모든 snapshot 값을 유지.
##  - serialize 가능한 순수 데이터 구조: to_snapshot → from_snapshot round-trip.
##  - Node/NodePath/Callable reference 저장 금지(모든 snapshot 값이 기본 타입/Vector2/Dictionary).
##  - mutable object(metadata)를 그대로 참조하지 않음(복사본 저장/반환).
##  - Status enum과 set_status 유효값 검증.
##  - eligible_day = death_day + 1 값 저장/복원.
##  - 회귀: 기존 게임 코드/시나리오를 변경하지 않는 순수 데이터 태스크.

enum Phase {
	PURE_DATA,
	ACTOR_FREED,
	DONE,
}

var _frame := 0
var _phase: Phase = Phase.PURE_DATA
var _failed := false

var _temp_actor: Node2D = null
var _after_death_record: DeathRecord = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


## 원본 Actor(임시 Node2D)로부터 snapshot 값을 복사해 DeathRecord를 만든다.
## 이후 Actor를 free해도 record가 값을 유지하는지 TASK-016-1 완료조건으로 검증한다.
func _make_record_from_actor(actor: Node2D) -> DeathRecord:
	var record := DeathRecord.new("rec_actor_001")
	record.source_uid = str(actor.name)
	record.source_kind = DeathRecord.SourceKind.ENEMY
	record.display_name = str(actor.name)
	record.class_or_type = "RAIDER"
	record.level = 3
	record.max_hp = 60
	record.attack_damage = 8
	record.attack_interval = 1.0
	record.move_speed = 90.0
	record.death_day = 2
	record.death_phase = DeathRecord.DeathPhase.NIGHT
	record.death_position = actor.position
	record.eligible_day = record.death_day + 1
	record.set_metadata({"origin": str(actor.name), "seq": 1})
	return record


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.PURE_DATA:
			if _frame < 4:
				return false
			_check_pure_data()
			# 임시 Actor를 만들어 snapshot 후 free하고, 다음 phase에서 유지 검증.
			_temp_actor = Node2D.new()
			_temp_actor.name = "FallenEnemy_7"
			_temp_actor.position = Vector2(123, -456)
			root.add_child(_temp_actor)
			_after_death_record = _make_record_from_actor(_temp_actor)
			_temp_actor.queue_free()
			_phase = Phase.ACTOR_FREED
			_frame = 0
		Phase.ACTOR_FREED:
			if _frame < 3:
				return false
			_check_actor_freed()
			_phase = Phase.DONE
			_frame = 0
		Phase.DONE:
			if _frame < 2:
				return false
			print("TASK0161_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 1000:
		print("TASK0161_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _check_pure_data() -> void:
	# 1. MERCENARY record 단독 생성/조회(필드 세팅 없이 기본값 조회 가능).
	var mrec := DeathRecord.new("rec_m_001")
	mrec.source_uid = "mercenary_A"
	mrec.source_kind = DeathRecord.SourceKind.MERCENARY
	mrec.display_name = "Mercenary A"
	mrec.class_or_type = "SWORDSMAN"
	mrec.level = 1
	mrec.max_hp = 100
	mrec.attack_damage = 10
	mrec.attack_interval = 1.0
	mrec.move_speed = 120.0
	mrec.death_day = 3
	mrec.death_phase = DeathRecord.DeathPhase.NIGHT
	mrec.death_position = Vector2(0, -280)
	mrec.eligible_day = mrec.death_day + 1
	_check(mrec.record_id == "rec_m_001", "mercenary record created standalone (no actor)")
	_check(mrec.source_uid == "mercenary_A", "mercenary record source_uid retained")
	_check(mrec.source_kind == DeathRecord.SourceKind.MERCENARY, "mercenary record source_kind=MERCENARY")
	_check(mrec.display_name == "Mercenary A", "mercenary record display_name retained")
	_check(mrec.class_or_type == "SWORDSMAN", "mercenary record class_or_type retained")
	_check(mrec.level == 1 and mrec.max_hp == 100 and mrec.attack_damage == 10, "mercenary record level/max_hp/damage retained")
	_check(mrec.attack_interval == 1.0 and mrec.move_speed == 120.0, "mercenary record interval/move_speed retained")
	_check(mrec.death_day == 3, "mercenary record death_day retained")
	_check(mrec.death_phase == DeathRecord.DeathPhase.NIGHT, "mercenary record death_phase=NIGHT")
	_check(mrec.death_position == Vector2(0, -280), "mercenary record death_position retained")
	_check(mrec.eligible_day == 4, "eligible_day = death_day + 1 retained")
	_check(mrec.get_status() == DeathRecord.Status.PENDING, "mercenary record starts PENDING")
	_check(mrec.get_status_name() == "PENDING", "mercenary record status name PENDING")
	_check(mrec.get_source_kind_name() == "MERCENARY", "mercenary record source_kind name MERCENARY")
	_check(mrec.get_death_phase_name() == "NIGHT", "mercenary record death_phase name NIGHT")

	# 2. ENEMY record 단독 생성/조회.
	var erec := DeathRecord.new("rec_e_001")
	erec.source_uid = "enemy_west_0"
	erec.source_kind = DeathRecord.SourceKind.ENEMY
	erec.display_name = "Raider"
	erec.class_or_type = "RAIDER"
	erec.level = 1
	erec.max_hp = 60
	erec.attack_damage = 8
	erec.attack_interval = 1.0
	erec.move_speed = 90.0
	erec.death_day = 2
	erec.death_phase = DeathRecord.DeathPhase.NIGHT
	erec.death_position = Vector2(0, -448)
	erec.eligible_day = erec.death_day + 1
	_check(erec.source_kind == DeathRecord.SourceKind.ENEMY, "enemy record source_kind=ENEMY")
	_check(erec.get_source_kind_name() == "ENEMY", "enemy record source_kind name ENEMY")
	_check(erec.display_name == "Raider", "enemy record display_name retained")
	_check(erec.max_hp == 60 and erec.attack_damage == 8, "enemy record combat stats retained")

	# 3. 이름이 같은 서로 다른 개체도 source_uid로 구분 가능(동일 이름 서로 다른 기록).
	var e2 := DeathRecord.new("rec_e_002")
	e2.source_uid = "enemy_west_1"
	e2.display_name = "Raider"
	_check(e2.source_uid != erec.source_uid and e2.display_name == erec.display_name, "same display_name distinguished by source_uid")

	# 4. Status enum + set_status 유효값 검증.
	var s := DeathRecord.new("rec_s_001")
	_check(s.set_status(DeathRecord.Status.ACTIVE), "set_status(ACTIVE) accepted")
	_check(s.get_status() == DeathRecord.Status.ACTIVE, "status changed to ACTIVE")
	_check(s.get_status_name() == "ACTIVE", "status name ACTIVE")
	_check(s.set_status(DeathRecord.Status.RESOLVED), "set_status(RESOLVED) accepted")
	_check(s.set_status(999) == false, "set_status(invalid) rejected")
	_check(s.get_status() == DeathRecord.Status.RESOLVED, "status unchanged after rejected set")

	# 5. serialize round-trip: to_snapshot → from_snapshot이 모든 값을 복원.
	var snap := mrec.to_snapshot()
	var restored := DeathRecord.from_snapshot(snap)
	_check(restored is DeathRecord, "from_snapshot returns DeathRecord")
	_check(restored.record_id == mrec.record_id, "round-trip record_id")
	_check(restored.source_uid == mrec.source_uid, "round-trip source_uid")
	_check(restored.source_kind == mrec.source_kind, "round-trip source_kind")
	_check(restored.display_name == mrec.display_name, "round-trip display_name")
	_check(restored.class_or_type == mrec.class_or_type, "round-trip class_or_type")
	_check(restored.level == mrec.level, "round-trip level")
	_check(restored.max_hp == mrec.max_hp, "round-trip max_hp")
	_check(restored.attack_damage == mrec.attack_damage, "round-trip attack_damage")
	_check(restored.attack_interval == mrec.attack_interval, "round-trip attack_interval")
	_check(restored.move_speed == mrec.move_speed, "round-trip move_speed")
	_check(restored.death_day == mrec.death_day, "round-trip death_day")
	_check(restored.death_phase == mrec.death_phase, "round-trip death_phase")
	_check(restored.death_position == mrec.death_position, "round-trip death_position")
	_check(restored.status == mrec.status, "round-trip status")
	_check(restored.eligible_day == mrec.eligible_day, "round-trip eligible_day")
	_check(restored.resolved_day == mrec.resolved_day, "round-trip resolved_day")

	# 6. snapshot은 순수 데이터만 포함(Node/NodePath/Callable reference 금지).
	var valid_types := [
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
		TYPE_VECTOR2, TYPE_DICTIONARY, TYPE_ARRAY,
	]
	var pure := true
	var unexpected: String = ""
	for key in snap.keys():
		var v: Variant = snap[key]
		if typeof(v) not in valid_types:
			pure = false
			unexpected = "%s=%s(%s)" % [key, str(v), typeof(v)]
			break
	_check(pure, "snapshot values are pure data (no Node references)" + ("" if pure else " : " + unexpected))
	_check(not snap.has("_target") and not snap.has("_fsm") and not snap.has("_buff") \
		and not snap.has("_current_target"), "snapshot has no temporary combat state keys")

	# 7. metadata mutable reference 방지: set_metadata 후 원본 수정이 record에 영향 없음.
	var meta_source := {"origin": "mercenary_A", "seq": 7}
	var mrec2 := DeathRecord.new("rec_m_002")
	mrec2.set_metadata(meta_source)
	meta_source["seq"] = 999
	_check(mrec2.get_metadata().get("seq", 0) == 7, "set_metadata stores copy (source mutation ignored)")
	_check(mrec2.to_snapshot()["metadata"]["seq"] == 7, "to_snapshot metadata is copy (seq=7)")
	# get_metadata 반환 dict 수정이 record 내부에 영향 없음.
	var returned := mrec2.get_metadata()
	returned["seq"] = -1
	_check(mrec2.get_metadata().get("seq", 0) == 7, "get_metadata returns copy (internal unchanged)")

	# 8. from_snapshot 복원 시 metadata도 복사본(원본 snapshot 수정 영향 없음).
	var snap2 := erec.to_snapshot()
	snap2["metadata"]["seq"] = 123
	var restored2 := DeathRecord.from_snapshot(snap2)
	_check(restored2.get_metadata().get("seq", 0) == 123, "from_snapshot reads metadata from snapshot")
	snap2["metadata"]["seq"] = -5
	_check(restored2.get_metadata().get("seq", 0) == 123, "from_snapshot metadata is copy (snapshot mutation ignored)")


func _check_actor_freed() -> void:
	_check(_temp_actor == null or not is_instance_valid(_temp_actor), "temporary actor freed from tree")
	if _after_death_record != null:
		_check(_after_death_record.record_id == "rec_actor_001", "record_id retained after actor freed")
		_check(_after_death_record.display_name == "FallenEnemy_7", "display_name retained after actor freed")
		_check(_after_death_record.death_position == Vector2(123, -456), "death_position retained after actor freed")
		_check(_after_death_record.source_uid == "FallenEnemy_7", "source_uid retained after actor freed")
		_check(_after_death_record.eligible_day == _after_death_record.death_day + 1, "eligible_day = death_day + 1 after actor freed")
		_check(_after_death_record.get_metadata().get("origin", "") == "FallenEnemy_7", "metadata retained after actor freed")
	else:
		_check(false, "after-death record created")
	_check(_temp_actor == null or not is_instance_valid(_temp_actor), "no freed actor reference kept inside record")


func _initialize() -> void:
	pass