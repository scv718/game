extends SceneTree

## TASK-017-1 Death Ledger → Ghost Return Candidate 자동 검증.
##  - GhostReturn autoload가 DeathLedger.record_added를 받아 lethal death record를
##    GhostReturnCandidate로 등록(DeathRecord source-of-truth 재사용).
##  - lethal death 1회 → candidate 1개.
##  - duplicate death signal(같은 source_uid) → 신규 candidate 없음(1개 유지).
##  - cleanup/despawn → record 없음 → candidate 0개.
##  - candidate는 원본 entity category(source_kind) / source death(death_day/phase/
##    position) / combat identity(level/max_hp/attack_damage/attack_interval/move_speed)
##    를 추적한다.
##  - Ghost death → 신규 candidate 없음(재귀 방지).
##  - consume 1회 후 재-consume 불가(1회 return 불변식, 재사용 없음).
##  - distinct source_uid는 각각 distinct candidate.
##  - candidate snapshot은 순수 데이터.
##  - 회귀: main scene / 기존 autoload / Player 비전투 / Ghost를 spawn하지 않음.

enum TestPhase {
	SETUP,
	INITIAL_STATE,
	LETHAL_ONE_CANDIDATE,
	DUPLICATE_SIGNAL,
	CLEANUP_ZERO,
	IDENTITY_TRACKING,
	GHOST_NO_CANDIDATE,
	CONSUME_ONCE,
	DISTINCT_SOURCES,
	SNAPSHOT_PURITY,
	REGRESSION,
	DONE,
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _failed := false

var _ledger: Node = null
var _ghost_return: Node = null
var _game_time: Node = null

var _m_record_id := ""
var _e_record_id := ""
var _e2_record_id := ""


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _make_mercenary_snapshot(source_uid: String) -> Dictionary:
	var m := DeathRecord.new("")
	m.source_uid = source_uid
	m.source_kind = DeathRecord.SourceKind.MERCENARY
	m.display_name = "Merc A"
	m.class_or_type = "SWORDSMAN"
	m.level = 3
	m.max_hp = 150
	m.attack_damage = 20
	m.attack_interval = 0.8
	m.move_speed = 130.0
	m.death_day = 4
	m.death_phase = DeathRecord.DeathPhase.NIGHT
	m.death_position = Vector2(12, -280)
	return m.to_snapshot()


func _make_enemy_snapshot(source_uid: String, hp := 60) -> Dictionary:
	var e := DeathRecord.new("")
	e.source_uid = source_uid
	e.source_kind = DeathRecord.SourceKind.ENEMY
	e.display_name = "Raider"
	e.class_or_type = "RAIDER"
	e.level = 1
	e.max_hp = hp
	e.attack_damage = 8
	e.attack_interval = 1.0
	e.move_speed = 90.0
	e.death_day = 3
	e.death_phase = DeathRecord.DeathPhase.DAY
	e.death_position = Vector2(0, -448)
	return e.to_snapshot()


func _make_ghost_snapshot(source_uid: String) -> Dictionary:
	var snap := _make_enemy_snapshot(source_uid)
	snap["is_ghost"] = true
	return snap


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_ledger = root.get_node("DeathLedger")
			_ghost_return = root.get_node("GhostReturn")
			_game_time = root.get_node("GameTime")
			if _game_time != null and _game_time.has_method("set_auto_advance"):
				_game_time.set_auto_advance(false)
			_check(_ledger != null, "DeathLedger autoload exists")
			_check(_ghost_return != null, "GhostReturn autoload exists")
			_check(_ghost_return != null and _ghost_return.has_method("get_eligible_candidates"), \
				"GhostReturn has candidate API")
			_phase = TestPhase.INITIAL_STATE
		TestPhase.INITIAL_STATE:
			_check(_ledger.get_all_records().size() == 0, "ledger starts empty")
			_check(_ghost_return.get_candidate_count() == 0, "no candidates at start")
			_check(_ghost_return.get_eligible_candidates().size() == 0, "no eligible candidates at start")
			_check(_ghost_return.get_candidate("nonexistent") == null, "get_candidate(nonexistent) -> null")
			_check(_ghost_return.consume("nonexistent") == false, "consume(nonexistent) safe no-op")
			_phase = TestPhase.LETHAL_ONE_CANDIDATE
		TestPhase.LETHAL_ONE_CANDIDATE:
			# lethal death 1회 → candidate 1개(record_added 경유 자동 등록).
			var rec: DeathRecord = _ledger.record_death(_make_mercenary_snapshot("merc_017_0"))
			_check(rec != null, "lethal death creates record")
			_m_record_id = rec.record_id
			_check(_ghost_return.get_candidate_count() == 1, \
				"1 lethal death -> 1 candidate (%d)" % _ghost_return.get_candidate_count())
			var cand: GhostReturnCandidate = _ghost_return.get_candidate(_m_record_id)
			_check(cand != null, "candidate retrievable by record_id")
			if cand != null:
				_check(cand.source_uid == "merc_017_0", "candidate tracks source_uid")
				_check(cand.source_kind == DeathRecord.SourceKind.MERCENARY, \
					"candidate tracks entity category (MERCENARY)")
				_check(cand.is_consumed() == false, "candidate starts not consumed")
				_check(cand.get_state() == GhostReturnCandidate.CandidateState.PENDING, \
					"candidate starts PENDING")
			_check(_ghost_return.get_eligible_candidates().size() == 1, \
				"eligible contains new candidate")
			_phase = TestPhase.DUPLICATE_SIGNAL
		TestPhase.DUPLICATE_SIGNAL:
			# 같은 source_uid duplicate death → 신규 candidate 없음(1개 유지).
			var count_before: int = _ghost_return.get_candidate_count()
			var dup: DeathRecord = _ledger.record_death(_make_mercenary_snapshot("merc_017_0"))
			_check(dup != null and dup.record_id == _m_record_id, \
				"duplicate death returns same record_id")
			_check(_ghost_return.get_candidate_count() == count_before, \
				"duplicate death signal -> candidate count unchanged (%d)" % _ghost_return.get_candidate_count())
			_check(_ghost_return.get_eligible_candidates().size() == 1, \
				"still exactly 1 eligible candidate after duplicate signal")
			_phase = TestPhase.CLEANUP_ZERO
		TestPhase.CLEANUP_ZERO:
			# cleanup/despawn은 record를 만들지 않으므로 candidate도 추가되지 않는다.
			var count_before: int = _ghost_return.get_candidate_count()
			var ghost_none: DeathRecord = _ledger.record_death(_make_ghost_snapshot("ghost_new_017"))
			_check(ghost_none == null, "ghost death with no record returns null (cleanup-like)")
			_check(_ghost_return.get_candidate_count() == count_before, \
				"no candidate for cleanup/despawn (count unchanged)")
			# 비존재 source의 record 부재 확인: cleanup은 record가 아예 없다.
			_check(_ledger.has_record_for_source("ghost_new_017") == false, \
				"cleanup source has no record -> no candidate")
			_phase = TestPhase.IDENTITY_TRACKING
		TestPhase.IDENTITY_TRACKING:
			# enemy lethal death → candidate가 원본 source death/combat identity를 추적.
			var erec: DeathRecord = _ledger.record_death(_make_enemy_snapshot("enemy_017_0"))
			_check(erec != null, "enemy lethal death creates record")
			_e_record_id = erec.record_id
			var ecand: GhostReturnCandidate = _ghost_return.get_candidate(_e_record_id)
			_check(ecand != null, "enemy candidate exists")
			if ecand != null:
				_check(ecand.source_kind == DeathRecord.SourceKind.ENEMY, \
					"entity category ENEMY tracked")
				_check(ecand.display_name == "Raider" and ecand.class_or_type == "RAIDER", \
					"combat identity name/type tracked")
				_check(ecand.level == 1 and ecand.max_hp == 60, "combat identity level/hp tracked")
				_check(ecand.attack_damage == 8 and is_equal_approx(ecand.attack_interval, 1.0) \
					and is_equal_approx(ecand.move_speed, 90.0), "combat identity combat stats tracked")
				_check(ecand.death_day == 3, "source death day tracked")
				_check(ecand.death_phase == DeathRecord.DeathPhase.DAY, "source death phase tracked")
				_check(ecand.death_position == Vector2(0, -448), "source death position tracked")
				_check(ecand.is_ghost == false, "enemy candidate is_ghost false (NORMAL)")
			_check(_ghost_return.get_candidate_count() == 2, \
				"2 distinct lethal deaths -> 2 candidates (%d)" % _ghost_return.get_candidate_count())
			_phase = TestPhase.GHOST_NO_CANDIDATE
		TestPhase.GHOST_NO_CANDIDATE:
			# Ghost death → 신규 candidate 없음(재귀 방지). 기존 source에 대한 ghost death도 신규 후보 없음.
			var count_before: int = _ghost_return.get_candidate_count()
			var g_over_existing: DeathRecord = _ledger.record_death(_make_ghost_snapshot("enemy_017_0"))
			_check(g_over_existing != null and g_over_existing.record_id == _e_record_id, \
				"ghost death over existing source returns existing record")
			_check(_ghost_return.get_candidate_count() == count_before, \
				"ghost death -> no new candidate (count unchanged)")
			_check(_ghost_return.get_candidate(_e_record_id).is_ghost == false, \
				"existing candidate not replaced by ghost death")
			_phase = TestPhase.CONSUME_ONCE
		TestPhase.CONSUME_ONCE:
			# consume 1회 성공, 재-consume 불가(1회 return 불변식).
			_check(_ghost_return.consume(_m_record_id), "consume candidate once succeeds")
			_check(_ghost_return.is_consumed(_m_record_id), "candidate now consumed")
			_check(_ghost_return.consume(_m_record_id) == false, \
				"re-consume consumed candidate rejected (no reuse)")
			_check(_ghost_return.get_eligible_candidates().size() == 1, \
				"consumed candidate removed from eligible (only enemy eligible)")
			var all: Array[GhostReturnCandidate] = _ghost_return.get_all_candidates()
			_check(all.size() == 2, "all candidates retains consumed + pending")
			# consumed candidate의 상태가 snapshot copy로 유지되는지 확인.
			_check(_ghost_return.get_candidate(_m_record_id).is_consumed(), \
				"consumed state preserved through copy query")
			_phase = TestPhase.DISTINCT_SOURCES
		TestPhase.DISTINCT_SOURCES:
			# 같은 display_name이어도 source_uid가 다르면 distinct candidate.
			var rec2: DeathRecord = _ledger.record_death(_make_enemy_snapshot("enemy_017_1"))
			_check(rec2 != null, "second enemy death recorded")
			_e2_record_id = rec2.record_id
			var a: GhostReturnCandidate = _ghost_return.get_candidate(_e_record_id)
			var b: GhostReturnCandidate = _ghost_return.get_candidate(_e2_record_id)
			_check(a != null and b != null, "both same-name enemies have candidates")
			if a != null and b != null:
				_check(a.record_id != b.record_id, "distinct record_id per source")
				_check(a.source_uid != b.source_uid, "distinct source_uid per candidate")
			_check(_ghost_return.get_candidate_count() == 3, \
				"3 distinct deaths -> 3 candidates")
			_phase = TestPhase.SNAPSHOT_PURITY
		TestPhase.SNAPSHOT_PURITY:
			var cand: GhostReturnCandidate = _ghost_return.get_candidate(_e2_record_id)
			_check(cand != null, "candidate available for purity check")
			if cand != null:
				var snap := cand.to_snapshot()
				var valid_types := [
					TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
					TYPE_VECTOR2, TYPE_DICTIONARY, TYPE_ARRAY,
				]
				var pure := true
				for key in snap.keys():
					if typeof(snap[key]) not in valid_types:
						pure = false
						break
				_check(pure, "candidate snapshot is pure data")
				var restored := GhostReturnCandidate.from_snapshot(snap)
				_check(restored.record_id == cand.record_id, "candidate snapshot round-trip record_id")
				_check(restored.source_kind == cand.source_kind, "candidate snapshot round-trip kind")
				_check(restored.is_consumed() == cand.is_consumed(), \
					"candidate snapshot round-trip consumed state")
			_phase = TestPhase.REGRESSION
		TestPhase.REGRESSION:
			if _frame < 20:
				return false
			var main: Node = root.get_node("Main")
			_check(main != null and main.get_node("HUD") != null, "main scene intact")
			_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor (no direct combat)")
			_check(root.get_node("MercenaryRoster") != null \
				and root.get_node("FirstEncounterSpawner") != null, "combat autoloads intact")
			_check(get_nodes_in_group("ghosts").size() == 0, "no ghost actor spawned")
			_check(_ledger.get_all_records().size() >= 3, \
				"ledger retains records (%d)" % _ledger.get_all_records().size())
			_check(_ghost_return.get_candidate_count() == 3, \
				"candidates retained across frames (%d)" % _ghost_return.get_candidate_count())
			_phase = TestPhase.DONE
		TestPhase.DONE:
			print("TASK0171_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 30000:
		print("TASK0171_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
