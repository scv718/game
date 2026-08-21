extends SceneTree

## TASK-016-2 DeathLedger Autoload + Record State 자동 검증.
##  - record_death(snapshot)로 DeathRecord 생성: record_id 자동 생성, eligible_day =
##    death_day + 1 자동 계산(NIGHT Day N 사망 → 최소 Day N+1), record_added 시그널.
##  - get_record / get_all_records / get_pending|active|resolved_records 조회.
##  - PENDING→ACTIVE→PENDING 전환 가능(멱등, 중복 시그널 없음).
##  - PENDING/ACTIVE→RESOLVED 가능(resolved_day 기록, record_resolved 시그널).
##  - RESOLVED record는 ACTIVE/PENDING으로 되돌릴 수 없음(명확한 정책).
##  - 상태 변경 API는 존재하지 않는 record에 대해 안전 no-op(false).
##  - query 결과(복사본)를 외부에서 수정해도 Ledger 내부 상태가 변하지 않음.
##  - Day/Night 전환 후에도 Autoload 내부 record 유지.
##  - 같은 display_name이라도 source_uid가 다르면 서로 다른 record.
##  - 회귀: main scene / 기존 autoload / Player 비전투 유지.
##  - Ghost를 spawn하지 않음(ghosts 그룹에 Actor 없음).

enum TestPhase {
	SETUP,
	INITIAL_STATE,
	RECORD_MERCENARY,
	RECORD_ID_AUTO,
	MULTI_SOURCE,
	STATUS_CYCLE,
	RESOLVED_PROTECT,
	QUERY_SAFETY,
	DAY_NIGHT,
	REGRESSION,
	DONE,
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _failed := false

var _ledger: Node = null
var _game_time: Node = null

var _added_count := 0
var _status_count := 0
var _resolved_count := 0

var _m_record_id := ""
var _e_record_id := ""
var _rec2_id := ""


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _on_record_added(_record_id: String) -> void:
	_added_count += 1


func _on_record_status_changed(_record_id: String, _status: int) -> void:
	_status_count += 1


func _on_record_resolved(_record_id: String) -> void:
	_resolved_count += 1


func _make_mercenary_snapshot() -> Dictionary:
	var m := DeathRecord.new("")
	m.source_uid = "mercenary_A"
	m.source_kind = DeathRecord.SourceKind.MERCENARY
	m.display_name = "Mercenary A"
	m.class_or_type = "SWORDSMAN"
	m.level = 1
	m.max_hp = 100
	m.attack_damage = 10
	m.attack_interval = 1.0
	m.move_speed = 120.0
	m.death_day = 3
	m.death_phase = DeathRecord.DeathPhase.NIGHT
	m.death_position = Vector2(0, -280)
	return m.to_snapshot()


func _make_enemy_snapshot(source_uid: String, display_name := "Raider") -> Dictionary:
	var e := DeathRecord.new("")
	e.source_uid = source_uid
	e.source_kind = DeathRecord.SourceKind.ENEMY
	e.display_name = display_name
	e.class_or_type = "RAIDER"
	e.level = 1
	e.max_hp = 60
	e.attack_damage = 8
	e.attack_interval = 1.0
	e.move_speed = 90.0
	e.death_day = 2
	e.death_phase = DeathRecord.DeathPhase.NIGHT
	e.death_position = Vector2(0, -448)
	return e.to_snapshot()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_ledger = root.get_node("DeathLedger")
			_game_time = root.get_node("GameTime")
			_game_time.set_auto_advance(false)
			_game_time.set_durations(2.0, 1.0)
			_check(_ledger != null, "DeathLedger autoload exists")
			_check(_ledger.has_method("record_death") and _ledger.has_signal("record_added"), \
				"DeathLedger has record API + signals")
			_check(_game_time != null, "GameTime autoload exists for phase test")
			_ledger.record_added.connect(_on_record_added)
			_ledger.record_status_changed.connect(_on_record_status_changed)
			_ledger.record_resolved.connect(_on_record_resolved)
			_phase = TestPhase.INITIAL_STATE
		TestPhase.INITIAL_STATE:
			_check(_ledger.get_all_records().size() == 0, "ledger starts empty")
			_check(_ledger.get_pending_records().size() == 0, "no pending at start")
			_check(_ledger.get_active_records().size() == 0, "no active at start")
			_check(_ledger.get_resolved_records().size() == 0, "no resolved at start")
			_check(_ledger.get_record("nonexistent") == null, "get_record(nonexistent) -> null")
			_check(_ledger.has_record_for_source("unknown") == false, "has_record_for_source(unknown) -> false")
			_check(_ledger.mark_active("nonexistent") == false, "mark_active(nonexistent) safe no-op")
			_check(_ledger.mark_pending("nonexistent") == false, "mark_pending(nonexistent) safe no-op")
			_check(_ledger.resolve("nonexistent", 5) == false, "resolve(nonexistent) safe no-op")
			_check(_added_count == 0 and _status_count == 0 and _resolved_count == 0, \
				"no signals emitted for empty ledger operations")
			_phase = TestPhase.RECORD_MERCENARY
		TestPhase.RECORD_MERCENARY:
			# MERCENARY record: record_id 자동 생성 + eligible_day = death_day + 1.
			var rec: DeathRecord = _ledger.record_death(_make_mercenary_snapshot())
			_check(rec != null, "record_death returns record")
			_check(rec.record_id != "", "record_id auto-generated when snapshot has none")
			_check(rec.source_kind == DeathRecord.SourceKind.MERCENARY, "record source_kind=MERCENARY")
			_check(rec.display_name == "Mercenary A", "record display_name retained")
			_check(rec.death_day == 3, "record death_day retained")
			_check(rec.eligible_day == 4, "eligible_day auto = death_day + 1 (%d)" % rec.eligible_day)
			_check(rec.get_status() == DeathRecord.Status.PENDING, "new record starts PENDING")
			_check(_added_count == 1, "record_added emitted once")
			_m_record_id = rec.record_id
			var got: DeathRecord = _ledger.get_record(_m_record_id)
			_check(got != null, "get_record finds recorded record")
			_check(got.source_uid == "mercenary_A", "get_record retains source_uid")
			_check(got.death_position == Vector2(0, -280), "get_record retains death_position")
			_check(_ledger.get_all_records().size() == 1, "get_all_records size 1")
			_check(_ledger.get_pending_records().size() == 1, "pending contains new record")
			_check(_ledger.has_record_for_source("mercenary_A"), "has_record_for_source(mercenary_A) true")
			_check(_ledger.has_record_for_source("enemy_west_0") == false, "other source not present")
			_phase = TestPhase.RECORD_ID_AUTO
		TestPhase.RECORD_ID_AUTO:
			# 명시적 record_id / 명시적 eligible_day는 그대로 유지.
			var snap := _make_enemy_snapshot("enemy_west_0")
			snap["record_id"] = "rec_e_001"
			snap["eligible_day"] = 5
			var erec: DeathRecord = _ledger.record_death(snap)
			_check(erec.record_id == "rec_e_001", "explicit record_id preserved")
			_check(erec.eligible_day == 5, "explicit eligible_day preserved (not recomputed)")
			_check(erec.source_kind == DeathRecord.SourceKind.ENEMY, "enemy record source_kind=ENEMY")
			_e_record_id = erec.record_id
			# 두 번째 자동 id는 첫 자동 id와 달라야 한다.
			var rec2: DeathRecord = _ledger.record_death(_make_enemy_snapshot("enemy_west_1"))
			_check(rec2.record_id != "", "second auto record_id generated")
			_check(rec2.record_id != _m_record_id and rec2.record_id != _e_record_id, \
				"auto record_ids are distinct")
			_rec2_id = rec2.record_id
			_check(_ledger.get_all_records().size() == 3, "3 records stored")
			_check(_added_count == 3, "record_added emitted per record")
			_phase = TestPhase.MULTI_SOURCE
		TestPhase.MULTI_SOURCE:
			# 같은 display_name이어도 source_uid가 다르면 서로 다른 record.
			var a: DeathRecord = _ledger.get_record(_e_record_id)
			var b: DeathRecord = _ledger.get_record(_rec2_id)
			_check(a != null and b != null, "both same-name enemies retrievable")
			if a != null and b != null:
				_check(a.display_name == b.display_name, "same display_name 'Raider'")
				_check(a.source_uid != b.source_uid, "distinct source_uid")
				_check(a.record_id != b.record_id, "distinct record_id")
			_phase = TestPhase.STATUS_CYCLE
		TestPhase.STATUS_CYCLE:
			# PENDING → ACTIVE → PENDING → RESOLVED.
			_check(_ledger.mark_active(_m_record_id), "mark_active PENDING->ACTIVE accepted")
			_check(_ledger.get_record(_m_record_id).get_status() == DeathRecord.Status.ACTIVE, \
				"status now ACTIVE")
			_check(_ledger.get_active_records().size() == 1, "active list contains record")
			_check(_ledger.get_pending_records().size() == 2, "pending list no longer holds it")
			_check(_status_count == 1, "record_status_changed emitted once for ACTIVE")
			var c := _status_count
			_check(_ledger.mark_active(_m_record_id), "mark_active on ACTIVE idempotent true")
			_check(_status_count == c, "no duplicate status signal for idempotent ACTIVE")
			_check(_ledger.mark_pending(_m_record_id), "mark_pending ACTIVE->PENDING accepted")
			_check(_ledger.get_record(_m_record_id).get_status() == DeathRecord.Status.PENDING, \
				"status back to PENDING")
			c = _status_count
			_check(_ledger.mark_pending(_m_record_id), "mark_pending on PENDING idempotent true")
			_check(_status_count == c, "no duplicate status signal for idempotent PENDING")
			_check(_ledger.resolve(_m_record_id, 4), "resolve PENDING->RESOLVED accepted")
			_check(_ledger.get_record(_m_record_id).get_status() == DeathRecord.Status.RESOLVED, \
				"status RESOLVED")
			_check(_ledger.get_record(_m_record_id).resolved_day == 4, "resolved_day recorded (4)")
			_check(_resolved_count == 1, "record_resolved emitted once")
			_check(_ledger.get_resolved_records().size() == 1, "resolved list contains record")
			c = _status_count
			var r := _resolved_count
			_check(_ledger.resolve(_m_record_id, 99), "resolve on RESOLVED idempotent true")
			_check(_ledger.get_record(_m_record_id).resolved_day == 4, "resolved_day preserved on re-resolve")
			_check(_status_count == c and _resolved_count == r, "no duplicate signals on re-resolve")
			_phase = TestPhase.RESOLVED_PROTECT
		TestPhase.RESOLVED_PROTECT:
			# RESOLVED record는 ACTIVE/PENDING으로 되돌릴 수 없다.
			var c := _status_count
			var r := _resolved_count
			_check(_ledger.mark_active(_m_record_id) == false, "mark_active on RESOLVED rejected")
			_check(_ledger.mark_pending(_m_record_id) == false, "mark_pending on RESOLVED rejected")
			_check(_ledger.get_record(_m_record_id).get_status() == DeathRecord.Status.RESOLVED, \
				"RESOLVED status protected")
			_check(_ledger.get_record(_m_record_id).resolved_day == 4, "RESOLVED resolved_day intact")
			_check(_status_count == c and _resolved_count == r, \
				"no signals from rejected transitions")
			_phase = TestPhase.QUERY_SAFETY
		TestPhase.QUERY_SAFETY:
			# 조회 결과(복사본) 수정이 Ledger 내부 상태에 영향 없음.
			var resolved: DeathRecord = _ledger.get_record(_m_record_id)
			resolved.set_status(DeathRecord.Status.PENDING)
			resolved.set_metadata({"hack": 1})
			resolved.resolved_day = 999
			var internal: DeathRecord = _ledger.get_record(_m_record_id)
			_check(internal.get_status() == DeathRecord.Status.RESOLVED, "get_record copy mutation ignored")
			_check(internal.resolved_day == 4, "get_record copy resolved_day ignored")
			_check(internal.get_metadata().is_empty(), "get_record copy metadata ignored")
			var all_list: Array = _ledger.get_all_records()
			if all_list.size() > 0:
				all_list[0].set_metadata({"hack": 2})
				var check_internal: DeathRecord = _ledger.get_record(all_list[0].record_id)
				_check(check_internal.get_metadata().is_empty(), "get_all_records copy mutation ignored")
			var pending_list: Array = _ledger.get_pending_records()
			if pending_list.size() > 0:
				pending_list[0].set_metadata({"hack": 3})
				var check_internal2: DeathRecord = _ledger.get_record(pending_list[0].record_id)
				_check(check_internal2.get_metadata().is_empty(), "get_pending_records copy mutation ignored")
			_phase = TestPhase.DAY_NIGHT
		TestPhase.DAY_NIGHT:
			# Day/Night 전환 후에도 Autoload 내부 record 유지.
			_check(_ledger.get_all_records().size() == 3, "3 records before phase transitions")
			var phase_before: int = _game_time.get_phase()
			_game_time.advance(3.0)
			_game_time.advance(2.0)
			_check(_game_time.get_phase() != phase_before, "phase advanced through transitions")
			_check(root.get_node("DeathLedger") == _ledger, "DeathLedger autoload retained")
			_check(_ledger.get_all_records().size() == 3, "records retained after Day/Night transitions")
			_check(_ledger.get_record(_m_record_id).get_status() == DeathRecord.Status.RESOLVED, \
				"resolved record state retained across phases")
			_check(_ledger.get_pending_records().size() == 2, "pending records retained across phases")
			_phase = TestPhase.REGRESSION
		TestPhase.REGRESSION:
			var main: Node = root.get_node("Main")
			_check(main != null, "main.tscn intact")
			_check(main.get_node("Player") != null and main.get_node("HUD") != null, "player/HUD intact")
			var floor_node: TileMapLayer = main.get_node("World/Floor") as TileMapLayer
			_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, \
				"world floor intact (128x128)")
			_check(root.get_node("VillageResources") != null, "VillageResources autoload intact")
			_check(root.get_node("MercenaryRoster") != null, "MercenaryRoster autoload intact")
			_check(root.get_node("FirstEncounterSpawner") != null, "FirstEncounterSpawner autoload intact")
			var player: Node = main.get_node("Player")
			_check(not player.has_method("attack") and not player.has_method("_attack"), \
				"player has no attack method (no direct combat)")
			_check(not player.is_in_group("enemies") and not player.is_in_group("mercenaries"), \
				"player excluded from combat groups")
			_check(get_nodes_in_group("ghosts").size() == 0, "no ghost actor spawned by DeathLedger")
			_phase = TestPhase.DONE
		TestPhase.DONE:
			print("TASK0162_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 30000:
		print("TASK0162_RESULT=TIMEOUT phase=%s" % str(_phase))
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