extends SceneTree

## TASK-025-1 Eligibility / Identity Generalization 자동 검증.
##  - entity category 기반 eligibility: DeathLedger.ELIGIBLE_CATEGORIES에 존재하는
##    category(MERCENARY/ENEMY)만 사망 기록 대상.
##  - unsupported category는 안전하게 skip: record 생성 안 함, record_added 미발행,
##    반환 null, 기존 record 무변경.
##  - category가 명시되지 않으면 source_kind 이름으로 대체(기존 호출 호환).
##  - identity snapshot(display_name/class/level/stat) 보존.
##  - source/death context(source_uid/death_day/death_phase/death_position) 보존.
##  - one-return invariant: 같은 source_uid duplicate death → record 1개 유지.
##  - Ghost(재귀) death는 신규 record 미생성.
##  - 회귀: main scene / 기존 autoload / Player 비전투 / Ghost Actor 미spawn 유지.

enum TestPhase {
	SETUP,
	ELIGIBLE_RECORD,
	UNSUPPORTED_SKIP,
	CATEGORY_FALLBACK,
	IDENTITY_CONTEXT,
	ONE_RETURN,
	GHOST_RECURSIVE,
	REGRESSION,
	DONE,
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _ledger: Node = null

var _added_count := 0

var _m_record_id := ""


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: TestPhase) -> void:
	_phase = p
	_sub = 0
	_wait = 0


func _wait_frames(n: int) -> void:
	_wait = n
	_sub += 1


func _waited() -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	return true


func _on_record_added(_record_id: String) -> void:
	_added_count += 1


func _make_snapshot(source_uid: String, source_kind: int, category := "") -> Dictionary:
	var r := DeathRecord.new("")
	r.source_uid = source_uid
	r.source_kind = source_kind
	r.category = category
	r.display_name = "Test Being"
	r.class_or_type = "CLASS_X"
	r.level = 2
	r.max_hp = 80
	r.attack_damage = 12
	r.attack_interval = 1.0
	r.move_speed = 100.0
	r.death_day = 3
	r.death_phase = DeathRecord.DeathPhase.NIGHT
	r.death_position = Vector2(40, -120)
	return r.to_snapshot()


func _make_enemy_snapshot(source_uid: String) -> Dictionary:
	return _make_snapshot(source_uid, DeathRecord.SourceKind.ENEMY)


func _make_mercenary_snapshot(source_uid: String) -> Dictionary:
	return _make_snapshot(source_uid, DeathRecord.SourceKind.MERCENARY)


func _records_for_source(source_uid: String) -> Array[DeathRecord]:
	var out: Array[DeathRecord] = []
	for r in _ledger.get_all_records():
		if r.source_uid == source_uid:
			out.append(r)
	return out


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_ledger = root.get_node("DeathLedger")
			_check(_ledger != null, "DeathLedger autoload exists")
			_check(_ledger.has_method("record_death"), "DeathLedger has record_death")
			_check(_ledger.has_method("is_eligible_category"), "DeathLedger has is_eligible_category")
			_ledger.record_added.connect(_on_record_added)
			_check(_ledger.get_all_records().size() == 0, "ledger starts empty")
			_enter(TestPhase.ELIGIBLE_RECORD)
		TestPhase.ELIGIBLE_RECORD:
			# 실제 구현된 eligible category(MERCENARY/ENEMY)는 기록된다.
			_check(_ledger.is_eligible_category("MERCENARY"), "MERCENARY is eligible")
			_check(_ledger.is_eligible_category("ENEMY"), "ENEMY is eligible")
			var m: DeathRecord = _ledger.record_death(_make_mercenary_snapshot("mercenary_e"))
			_check(m != null, "eligible MERCENARY death recorded")
			if m != null:
				_check(m.get_category() == "MERCENARY", "mercenary category resolves to MERCENARY")
				_m_record_id = m.record_id
			var e: DeathRecord = _ledger.record_death(_make_enemy_snapshot("enemy_e"))
			_check(e != null, "eligible ENEMY death recorded")
			if e != null:
				_check(e.get_category() == "ENEMY", "enemy category resolves to ENEMY")
			_check(_added_count == 2, "record_added emitted for 2 eligible deaths")
			_enter(TestPhase.UNSUPPORTED_SKIP)
		TestPhase.UNSUPPORTED_SKIP:
			# unsupported category는 안전하게 skip: record 미생성, signal 미발행, null 반환.
			var count_before: int = _ledger.get_all_records().size()
			var added_before := _added_count
			var animal := _make_snapshot("animal_1", DeathRecord.SourceKind.ENEMY, "ANIMAL")
			var skipped: DeathRecord = _ledger.record_death(animal)
			_check(skipped == null, "unsupported ANIMAL category skipped (null returned)")
			var npc := _make_snapshot("npc_1", DeathRecord.SourceKind.MERCENARY, "NPC")
			_check(_ledger.record_death(npc) == null, "unsupported NPC category skipped (null returned)")
			_check(_ledger.is_eligible_category("ANIMAL") == false, "ANIMAL not eligible")
			_check(_ledger.is_eligible_category("NPC") == false, "NPC not eligible")
			_check(_ledger.is_eligible_category("UNKNOWN") == false, "UNKNOWN not eligible")
			_check(_ledger.get_all_records().size() == count_before, \
				"unsupported categories add no records (%d)" % _ledger.get_all_records().size())
			_check(_ledger.has_record_for_source("animal_1") == false, "animal_1 not recorded")
			_check(_ledger.has_record_for_source("npc_1") == false, "npc_1 not recorded")
			_check(_added_count == added_before, "no record_added for unsupported categories")
			_enter(TestPhase.CATEGORY_FALLBACK)
		TestPhase.CATEGORY_FALLBACK:
			# category가 비어 있으면 source_kind 이름으로 대체(기존 호출 호환).
			var no_cat := _make_enemy_snapshot("enemy_no_cat")
			no_cat["category"] = ""
			var rec: DeathRecord = _ledger.record_death(no_cat)
			_check(rec != null, "empty category falls back to source_kind (ENEMY) and is recorded")
			if rec != null:
				_check(rec.get_category() == "ENEMY", "fallback category resolves to ENEMY")
				_check(rec.category == "", "raw category field stays empty")
			_enter(TestPhase.IDENTITY_CONTEXT)
		TestPhase.IDENTITY_CONTEXT:
			# identity snapshot + source/death context 보존.
			var m: DeathRecord = _ledger.get_record(_m_record_id)
			_check(m != null, "mercenary record retrievable")
			if m != null:
				_check(m.source_uid == "mercenary_e", "source_uid context retained")
				_check(m.display_name == "Test Being", "identity display_name retained")
				_check(m.class_or_type == "CLASS_X", "identity class_or_type retained")
				_check(m.level == 2, "identity level retained")
				_check(m.max_hp == 80, "identity max_hp retained")
				_check(m.attack_damage == 12, "identity attack_damage retained")
				_check(m.death_day == 3, "death_day context retained")
				_check(m.death_phase == DeathRecord.DeathPhase.NIGHT, "death_phase context retained")
				_check(m.death_position == Vector2(40, -120), "death_position context retained")
				_check(m.get_status() == DeathRecord.Status.PENDING, "new record starts PENDING")
				_check(m.eligible_day == 4, "eligible_day = death_day + 1 retained")
			# category snapshot round-trip 보존.
			var roundtrip := _make_mercenary_snapshot("mercenary_rt")
			roundtrip["category"] = "MERCENARY"
			var rt: DeathRecord = _ledger.record_death(roundtrip)
			_check(rt != null and rt.category == "MERCENARY", "category preserved through snapshot round-trip")
			_enter(TestPhase.ONE_RETURN)
		TestPhase.ONE_RETURN:
			# one-return invariant: 같은 source_uid duplicate death → record 1개 유지.
			var count_before: int = _ledger.get_all_records().size()
			var added_before := _added_count
			var dup: DeathRecord = _ledger.record_death(_make_mercenary_snapshot("mercenary_e"))
			_check(dup != null and dup.record_id == _m_record_id, \
				"duplicate death deduped to same record (one-return)")
			_check(_ledger.get_all_records().size() == count_before, \
				"duplicate adds no new record")
			_check(_added_count == added_before, "no record_added for duplicate")
			_check(_records_for_source("mercenary_e").size() == 1, \
				"exactly 1 record for source (one-return invariant)")
			_enter(TestPhase.GHOST_RECURSIVE)
		TestPhase.GHOST_RECURSIVE:
			# Ghost(재귀) death는 신규 record를 만들지 않는다.
			var count_before: int = _ledger.get_all_records().size()
			var added_before := _added_count
			var ghost := _make_enemy_snapshot("enemy_ghost")
			ghost["is_ghost"] = true
			ghost["category"] = "ENEMY"
			var g: DeathRecord = _ledger.record_death(ghost)
			_check(g == null, "ghost death with no existing record returns null (no recursion)")
			_check(_ledger.get_all_records().size() == count_before, "ghost death adds no record")
			_check(_added_count == added_before, "no record_added for ghost death")
			var ghost_existing := _make_enemy_snapshot("enemy_e")
			ghost_existing["is_ghost"] = true
			ghost_existing["category"] = "ENEMY"
			var ge: DeathRecord = _ledger.record_death(ghost_existing)
			_check(ge != null and ge.source_uid == "enemy_e", \
				"ghost death for existing source returns existing record (no new)")
			_check(_ledger.get_all_records().size() == count_before, \
				"ghost-over-existing adds no new record")
			_enter(TestPhase.REGRESSION)
		TestPhase.REGRESSION:
			if _sub == 0:
				var main: Node = root.get_node("Main")
				_check(main != null and main.get_node("HUD") != null, "main scene intact")
				_check(get_nodes_in_group("player").size() == 0, \
					"no runtime player Actor (no direct combat)")
				_check(root.get_node("MercenaryRoster") != null \
					and root.get_node("FirstEncounterSpawner") != null, \
					"combat autoloads intact")
				_check(get_nodes_in_group("ghosts").size() == 0, \
					"no ghost actor spawned (Ghost spawn not part of TASK-025-1)")
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_enter(TestPhase.DONE)
		TestPhase.DONE:
			print("TASK0251_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 30000:
		print("TASK0251_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
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

