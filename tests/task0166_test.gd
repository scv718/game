extends SceneTree

## TASK-016-6 Death Ledger 통합 검증.
## Mercenary/Enemy 실제 전투 사망부터 DeathRecord 생성/유지까지 Death Ledger 전체
## 흐름을 하나의 headless 시나리오로 검증한다.
##
## 시나리오:
##   1. DAY 시작 + DeathLedger 초기 상태 확인.
##   2. Mercenary 고용 + WEST 방어 배치(West Gate 설치로 WEST 축 고정).
##   3. NIGHT 전환 → Mercenary Actor spawn (WEST rally).
##   4. WEST Enemy encounter spawn (FirstEncounterSpawner 기본 west 방향).
##   5. 실제 auto combat → Enemy lethal death → ENEMY record 정확히 생성.
##   6. 같은 이름(display_name 'Raider')의 서로 다른 Enemy → 별도 record.
##   7. duplicate source_uid 차단 (동일 죽음 = record 1개).
##   8. 강한 Enemy가 Mercenary를 실제로 사살 → MERCENARY record 생성.
##   9. MercenaryData.alive == false / Actor cleanup / roster freed-reference 제거.
##  10. 모든 record status == PENDING, eligible_day == death_day + 1 확인.
##  11. DAY 전환 → cleanup이 신규 record를 만들지 않고 기존 record 유지.
##  12. 다음 NIGHT 전환 → record 유지, Ghost spawn 미발생 확인.
##  13. Ledger 상태 API 검증: mark_active/mark_pending/resolve + RESOLVED 보호.
##  14. ghost source 신규 death 기록 차단 + snapshot 순수 데이터(Actor/Node ref 없음).
##  15. 회귀: main scene / Worker / Navigation / TASK-012 World / TASK-013 Wall·Gate /
##      TASK-014 Combat / TASK-015 Tactical UI / World Visual Composition.

enum Phase {
	SETUP,
	HIRE_ASSIGN,
	NIGHT_SPAWN,
	ENEMY_COMBAT,
	MERC_DEATH,
	RECORDS_PENDING,
	DAY_CYCLE,
	NEXT_NIGHT,
	LEDGER_API,
	REGRESSION,
	DONE,
}

const WEST_GATE_POS := Vector2(-528, 0)
const WEST_RALLY := Vector2(-280, 0)
const VILLAGE_CORE := Vector2.ZERO
const BUDGET := 6000

var _frame := 0
var _phase: Phase = Phase.SETUP
var _sub := 0
var _wait := 0
var _failed := false

var _game_time: Node = null
var _world: Node = null
var _placement: Node = null
var _spawner: Node = null
var _roster: Node = null
var _worker_roster: Node = null
var _resources: Node = null
var _ledger: Node = null
var _hud: Node = null

var _mercenary: MercenaryData = null
var _actor: Node = null
var _gate: Node = null

var _enemy_seq := 0
var _budget := 0
var _added_count := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
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


func _finish() -> void:
	print("TASK0166_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _advance_to_next_phase() -> void:
	if _game_time.get_phase() == GameTime.Phase.DAY:
		_game_time.advance(2.0)
	else:
		_game_time.advance(1.0)


func _count_enemies() -> int:
	return get_nodes_in_group("enemies").size()


func _count_mercenaries() -> int:
	return get_nodes_in_group("mercenaries").size()


func _find_gate_at(pos: Vector2) -> Node:
	for node in get_nodes_in_group("gates"):
		if not is_instance_valid(node):
			continue
		var gate := node as Node2D
		if gate == null:
			continue
		if (gate.position - pos).length_squared() < 1.0:
			return node
	return null


func _enemy_records() -> Array[DeathRecord]:
	var out: Array[DeathRecord] = []
	for r in _ledger.get_all_records():
		if r.source_kind == DeathRecord.SourceKind.ENEMY:
			out.append(r)
	return out


func _merc_records() -> Array[DeathRecord]:
	var out: Array[DeathRecord] = []
	for r in _ledger.get_all_records():
		if r.source_kind == DeathRecord.SourceKind.MERCENARY:
			out.append(r)
	return out


func _records_for_source(source_uid: String) -> Array[DeathRecord]:
	var out: Array[DeathRecord] = []
	for r in _ledger.get_all_records():
		if r.source_uid == source_uid:
			out.append(r)
	return out


## 직접 배치하는 테스트용 Enemy. HOLD(정지) 또는 route(MOVE) 선택.
func _spawn_enemy(pos: Vector2, hp := 60, dmg := 5, with_route := false) -> EnemyActor:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	enemy.max_hp = hp
	enemy.current_hp = hp
	enemy.attack_damage = dmg
	enemy.attack_interval = 0.05
	enemy.setup("t0166_enemy_%d" % _enemy_seq, "Raider", "west")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
	if with_route:
		enemy.set_route([], VILLAGE_CORE)
	return enemy


func _clear_test_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()


func _on_record_added(_record_id: String) -> void:
	_added_count += 1


func release_all_actions() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			if _sub == 0:
				_game_time = root.get_node("GameTime")
				_game_time.set_auto_advance(false)
				_game_time.set_durations(2.0, 1.0)
				_world = root.get_node("Main").get_node("World")
				_placement = root.get_node("Main").get_node("BuildingPlacement")
				_spawner = root.get_node("FirstEncounterSpawner")
				_spawner.set_direction("west")
				_roster = root.get_node("MercenaryRoster")
				_worker_roster = root.get_node("WorkerRoster")
				_resources = root.get_node("VillageResources")
				_ledger = root.get_node("DeathLedger")
				_hud = root.get_node("Main").get_node("HUD")
				_check(_game_time != null and _world != null and _placement != null \
					and _spawner != null and _roster != null and _worker_roster != null \
					and _resources != null and _ledger != null and _hud != null,
					"core autoloads + world + hud present")
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "scenario starts in DAY")
				_check(_ledger.get_all_records().size() == 0, "DeathLedger starts empty")
				_check(_spawner.get_direction() == "west", "encounter direction is west (WEST = main threat)")
				_ledger.record_added.connect(_on_record_added)
				_check(_added_count == 0, "no record_added at start")
				_resources._amounts["wood"] = 10000
				_sub = 1
			elif _sub == 1:
				_enter(Phase.HIRE_ASSIGN)
		Phase.HIRE_ASSIGN:
			if _sub == 0:
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null and _mercenary.alive, "mercenary_A hired alive")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.WEST)
					_mercenary.max_hp = 80
					_mercenary.attack_damage = 30
					_mercenary.attack_interval = 0.05
					_mercenary.move_speed = 120.0
					_check(_mercenary.defense_zone == MercenaryData.DefenseZone.WEST, \
						"WEST defense zone assigned")
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(WEST_GATE_POS))
				_gate = _find_gate_at(WEST_GATE_POS)
				_check(_gate != null, "west gate placed at %s" % str(WEST_GATE_POS))
				if _gate != null:
					_check(_gate.get("direction") == "west", "gate direction is west")
					_check(_gate.is_closed(), "west gate starts CLOSED")
				_check(_ledger.get_all_records().size() == 0, "no records before any death")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_enter(Phase.NIGHT_SPAWN)
		Phase.NIGHT_SPAWN:
			if _sub == 0:
				_check(_count_mercenaries() == 1, "mercenary actor spawned at NIGHT (%d)" % _count_mercenaries())
				_actor = _roster.get_actor("mercenary_A")
				_check(_actor != null, "mercenary actor retrievable by id")
				if _actor != null:
					_check(_actor.merc_data == _mercenary, "actor references roster MercenaryData")
					_check(_actor.current_hp == 80, "actor current_hp from max_hp (80)")
					var pos: Vector2 = (_actor as Node2D).global_position
					_check(pos.distance_to(WEST_RALLY) < 1.0, "actor at west rally (pos=%s)" % pos)
				_check(_ledger.get_all_records().size() == 0, "no records after NIGHT spawn (no death yet)")
				_check(_spawner.get_enemy_count() == 3, \
					"WEST encounter spawned 3 enemies on NIGHT (%d)" % _spawner.get_enemy_count())
				var all_west := true
				for e in get_nodes_in_group("enemies"):
					if is_instance_valid(e) and e.get("direction") != "west":
						all_west = false
				_check(all_west, "auto-encounter enemies enter from WEST")
				# auto-encounter는 despawn해 격리된 사망 테스트로 진행.
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "auto-encounter cleaned (%d)" % _count_enemies())
				_enter(Phase.ENEMY_COMBAT)
		Phase.ENEMY_COMBAT:
			if _sub == 0:
				# WEST rally 근처 HOLD 적 2마리 → A가 자동 추격/공격/사살.
				var e1 := _spawn_enemy(WEST_RALLY + Vector2(0, -60), 60, 1, false)
				var e2 := _spawn_enemy(WEST_RALLY + Vector2(0, -100), 60, 1, false)
				_check(e1 != null and e2 != null, "2 test enemies spawned for enemy death")
				if e1 != null and e2 != null:
					_check(e1.enemy_id != e2.enemy_id, "each enemy has independent source_uid")
					_check(e1.display_name == e2.display_name, "same display_name 'Raider'")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _count_enemies() == 0:
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "test enemies never killed by mercenary in budget (enemies=%d)" % _count_enemies())
					_wait_frames(4)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(true, "enemies killed by mercenary auto combat")
				_check(_count_enemies() == 0, "dead enemies excluded from enemies group (combat/target)")
				var erecords := _enemy_records()
				_check(erecords.size() == 2, "exactly 2 ENEMY records after 2 kills (%d)" % erecords.size())
				_check(_records_for_source("t0166_enemy_0").size() == 1, "enemy t0166_enemy_0 recorded exactly once")
				_check(_records_for_source("t0166_enemy_1").size() == 1, "enemy t0166_enemy_1 recorded exactly once")
				_check(_records_for_source("t0166_enemy_0").size() == 1 \
					and _records_for_source("t0166_enemy_1").size() == 1, \
					"died signal + die() does not duplicate records (exactly 1 each)")
				var same_names := true
				for r in erecords:
					if r.source_kind != DeathRecord.SourceKind.ENEMY:
						_check(false, "enemy record source_kind=ENEMY")
					if r.display_name != "Raider":
						same_names = false
				_check(same_names, "all enemy records keep display_name 'Raider'")
				_check(erecords[0].source_uid != erecords[1].source_uid, "distinct source_uid for same-name enemies")
				_check(erecords[0].record_id != erecords[1].record_id, "distinct record_id for same-name enemies")
				var death_day: int = _game_time.get_day_number()
				for r in erecords:
					_check(r.death_day == death_day, "enemy record death_day = current day (%d)" % death_day)
					_check(r.death_phase == DeathRecord.DeathPhase.NIGHT, "enemy record death_phase=NIGHT")
					_check(r.eligible_day == r.death_day + 1, "enemy record eligible_day = death_day + 1 (%d)" % r.eligible_day)
					_check(r.get_status() == DeathRecord.Status.PENDING, "enemy record starts PENDING")
					_check(r.max_hp == 60, "enemy record retains max_hp")
				_check(_added_count == 2, "record_added emitted for each enemy death (%d)" % _added_count)
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() == null, "mercenary target cleared after enemy deaths")
				_enter(Phase.MERC_DEATH)
		Phase.MERC_DEATH:
			if _sub == 0:
				# 강한 적이 WEST→EAST로 접근해 A를 실제로 공격·사살한다(lethal combat death).
				var e3 := _spawn_enemy(WEST_RALLY + Vector2(0, -70), 100000, 25, true)
				_check(e3 != null, "strong enemy E3 spawned (routes toward village core)")
				_budget = 0
				_sub = 1
			elif _sub == 1:
				if _actor == null or not is_instance_valid(_actor):
					_wait_frames(4)
				elif _budget >= BUDGET:
					_check(false, "mercenary never died in budget")
					_wait_frames(4)
				else:
					_budget += 1
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_mercenary.alive == false, "MercenaryData.alive set to false on death")
				_check(_count_mercenaries() == 0, "dead mercenary removed from mercenaries group (%d)" % _count_mercenaries())
				_check(_roster.get_actor("mercenary_A") == null, "roster actor lookup null for dead A")
				_check(not _roster._actors.has("mercenary_A"), "roster _actors no longer holds dead A")
				_check(_roster.get_mercenary("mercenary_A") != null, "dead A data still retrievable from roster")
				var mrecords := _merc_records()
				_check(mrecords.size() == 1, "exactly 1 MERCENARY record after death (%d)" % mrecords.size())
				_check(_records_for_source("mercenary_A").size() == 1, "mercenary_A recorded exactly once")
				if mrecords.size() == 1:
					var mr := mrecords[0]
					_check(mr.source_kind == DeathRecord.SourceKind.MERCENARY, "mercenary record source_kind=MERCENARY")
					_check(mr.display_name == "Mercenary A", "mercenary record display_name retained")
					_check(mr.class_or_type == "SWORDSMAN", "mercenary record class_or_type=SWORDSMAN")
					_check(mr.level == 1 and mr.max_hp == 80 and mr.attack_damage == 30, \
						"mercenary record level/max_hp/damage retained")
					_check(mr.attack_interval == 0.05 and mr.move_speed == 120.0, \
						"mercenary record attack_interval/move_speed retained")
					_check(mr.death_phase == DeathRecord.DeathPhase.NIGHT, "mercenary record death_phase=NIGHT")
					_check(mr.eligible_day == mr.death_day + 1, "mercenary record eligible_day = death_day + 1")
					_check(mr.get_status() == DeathRecord.Status.PENDING, "mercenary record starts PENDING")
				_check(_added_count == 3, "record_added emitted for mercenary death (%d)" % _added_count)
				# snapshot이 Actor/Node reference를 포함하지 않는 순수 데이터인지 확인.
				var snap := mrecords[0].to_snapshot() if mrecords.size() > 0 else {}
				_check(_snapshot_is_pure(snap), "mercenary record snapshot is pure data (no Node references)")
				_clear_test_enemies()
				_wait_frames(3)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "strong enemy cleaned after merc death test")
				_check(_ledger.get_all_records().size() == 3, "ledger holds 3 records (%d)" % _ledger.get_all_records().size())
				_enter(Phase.RECORDS_PENDING)
		Phase.RECORDS_PENDING:
			if _sub == 0:
				var all_records: Array[DeathRecord] = _ledger.get_all_records()
				_check(all_records.size() == 3, "get_all_records returns 3 records (%d)" % all_records.size())
				_check(_ledger.get_pending_records().size() == 3, \
					"all 3 records PENDING (get_pending=%d)" % _ledger.get_pending_records().size())
				_check(_ledger.get_active_records().size() == 0, "no ACTIVE records yet")
				_check(_ledger.get_resolved_records().size() == 0, "no RESOLVED records yet")
				var all_pending := true
				var eligible_ok := true
				for r in all_records:
					if r.get_status() != DeathRecord.Status.PENDING:
						all_pending = false
					if r.eligible_day != r.death_day + 1:
						eligible_ok = false
					if not _snapshot_is_pure(r.to_snapshot()):
						_check(false, "record %s snapshot contains non-pure value" % r.record_id)
				_check(all_pending, "both MERCENARY/ENEMY records status == PENDING")
				_check(eligible_ok, "eligible_day == death_day + 1 for all records")
				_check(_ledger.has_record_for_source("mercenary_A"), "has_record_for_source(mercenary_A) true")
				_check(_ledger.has_record_for_source("t0166_enemy_0"), "has_record_for_source(t0166_enemy_0) true")
				_check(_ledger.has_record_for_source("t0166_enemy_1"), "has_record_for_source(t0166_enemy_1) true")
				_check(_ledger.has_record_for_source("unknown_src") == false, "unknown source not recorded")
				# query 결과 복사본 보호: 외부 mutation이 Ledger 내부 상태를 우회 변경 못 함.
				var rec: DeathRecord = all_records[0]
				var original_name: String = rec.display_name
				var original_id: String = rec.record_id
				rec.display_name = "MUTATED"
				var refetched: DeathRecord = _ledger.get_record(original_id)
				_check(refetched != null and refetched.display_name == original_name, \
					"ledger query returns copies (internal state protected)")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase DAY after full NIGHT")
				_enter(Phase.DAY_CYCLE)
		Phase.DAY_CYCLE:
			if _sub == 0:
				# DAY 복귀 cleanup(roster actor despawn / spawner despawn)은 신규 record 미생성.
				var before: int = _ledger.get_all_records().size()
				_check(before == 3, "3 records before DAY cleanup (%d)" % before)
				_check(_count_mercenaries() == 0, "no mercenary actor during DAY")
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 during DAY")
				_check(_spawner._enemies.size() == 0, "spawner holds no stale references during DAY")
				_check(_ledger.get_all_records().size() == 3, \
					"DAY cleanup created no new DeathRecords (still 3)")
				_check(_ledger.get_pending_records().size() == 3, "records still PENDING after DAY")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "next NIGHT arrived")
				_check(_count_mercenaries() == 0, "dead merc NOT re-spawned next NIGHT (%d)" % _count_mercenaries())
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 (dead not spawned)")
				_check(_ledger.get_all_records().size() == 3, \
					"records retained into next NIGHT (%d)" % _ledger.get_all_records().size())
				_check(get_nodes_in_group("ghosts").size() == 0, \
					"no Ghost actor spawned yet (Ghost feature not implemented)")
				# 새 NIGHT의 auto-encounter도 사망이 아니므로 record 미생성.
				_check(_spawner.get_enemy_count() == 3, \
					"next NIGHT west encounter spawned again (%d)" % _spawner.get_enemy_count())
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_spawner._enemies.size() == 0, "spawner empty after despawn")
				_check(_count_enemies() == 0, "no stale enemies after despawn")
				_check(_ledger.get_all_records().size() == 3, \
					"encounter despawn created no new records (still 3)")
				_enter(Phase.LEDGER_API)
		Phase.LEDGER_API:
			if _sub == 0:
				var all_records: Array[DeathRecord] = _ledger.get_all_records()
				var merc_id := ""
				var enemy_id := ""
				for r in all_records:
					if r.source_kind == DeathRecord.SourceKind.MERCENARY and merc_id == "":
						merc_id = r.record_id
					elif r.source_kind == DeathRecord.SourceKind.ENEMY and enemy_id == "":
						enemy_id = r.record_id
				_check(merc_id != "" and enemy_id != "", "resolved mercenary/enemy record ids")
				_check(_ledger.mark_active(merc_id), "mark_active(PENDING -> ACTIVE) accepted")
				_check(_ledger.get_record(merc_id).get_status() == DeathRecord.Status.ACTIVE, \
					"merc record now ACTIVE")
				_check(_ledger.get_active_records().size() == 1, "get_active_records returns 1 (%d)" \
					% _ledger.get_active_records().size())
				_check(_ledger.mark_active(merc_id), "mark_active again idempotent (true)")
				_check(_ledger.mark_pending(merc_id), "mark_pending(ACTIVE -> PENDING) accepted")
				_check(_ledger.get_record(merc_id).get_status() == DeathRecord.Status.PENDING, \
					"merc record back to PENDING")
				_check(_ledger.mark_pending(merc_id), "mark_pending again idempotent (true)")
				var day: int = _game_time.get_day_number()
				_check(_ledger.resolve(enemy_id, day), "resolve(enemy record, day) accepted")
				var resolved_rec: DeathRecord = _ledger.get_record(enemy_id)
				_check(resolved_rec.get_status() == DeathRecord.Status.RESOLVED, \
					"enemy record RESOLVED")
				_check(resolved_rec.resolved_day == day, "resolved_day recorded (%d)" % resolved_rec.resolved_day)
				_check(_ledger.get_resolved_records().size() == 1, \
					"get_resolved_records returns 1 (%d)" % _ledger.get_resolved_records().size())
				_check(_ledger.resolve(enemy_id, day + 5), "resolve again idempotent (true)")
				_check(_ledger.get_record(enemy_id).resolved_day == day, \
					"resolved_day unchanged on idempotent resolve (RESOLVED protected)")
				_check(_ledger.mark_active(enemy_id) == false, \
					"RESOLVED record cannot be returned to ACTIVE")
				_check(_ledger.mark_pending(enemy_id) == false, \
					"RESOLVED record cannot be returned to PENDING")
				_check(_ledger.mark_active("non_existent_id") == false, \
					"unknown record status change safe no-op")
				_sub = 1
			elif _sub == 1:
				# duplicate source_uid 차단: 동일 source 재기록 시 신규 record 미생성.
				var count_before: int = _ledger.get_all_records().size()
				var added_before := _added_count
				var dup: DeathRecord = _ledger.record_death(_make_enemy_snapshot("t0166_enemy_0"))
				var existing := _records_for_source("t0166_enemy_0")
				_check(dup != null and existing.size() == 1 and dup.record_id == existing[0].record_id, \
					"duplicate source_uid returns existing record (no new record)")
				_check(_ledger.get_all_records().size() == count_before, \
					"duplicate source_uid adds no record (still %d)" % count_before)
				_check(_added_count == added_before, "no record_added for duplicate source")
				# ghost source 신규 death 기록 차단.
				var ghost_new: DeathRecord = _ledger.record_death(_make_ghost_snapshot("ghost_block_0"))
				_check(ghost_new == null, "ghost death with no existing record returns null")
				_check(_ledger.get_all_records().size() == count_before, \
					"ghost death creates no new record (count unchanged)")
				_check(_ledger.has_record_for_source("ghost_block_0") == false, \
					"ghost_block_0 not recorded")
				var ghost_existing: DeathRecord = _ledger.record_death(_make_ghost_snapshot("t0166_enemy_1"))
				_check(ghost_existing != null \
					and _records_for_source("t0166_enemy_1").size() == 1 \
					and ghost_existing.record_id == _records_for_source("t0166_enemy_1")[0].record_id, \
					"ghost death for existing source returns existing record copy")
				_check(_ledger.get_all_records().size() == count_before, \
					"ghost-over-existing death adds no record (count unchanged)")
				_check(_added_count == added_before, "no record_added for ghost death attempts")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				var main: Node = root.get_node("Main")
				_check(main != null and main.get_node("HUD") != null, \
					"main scene intact")
				_check(get_nodes_in_group("player").size() == 0, \
					"no runtime player Actor (no direct combat)")
				_check(get_nodes_in_group("tactical_command_ui").size() == 1, \
					"TASK-015 Tactical Command UI intact")
				_check(_hud.get_node_or_null("StatusPanel") != null, "HUD StatusPanel intact")
				_check(_hud.get_node_or_null("DeathLedgerView") != null, "DeathLedgerView intact")
				_check(_worker_roster.get_count() == 0, "worker roster unaffected")
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var layout: Node = _world.get_node("MapLayout")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 192 * 192, \
					"TASK-012 world floor intact (192x192)")
				_check(layout.MAIN_ROAD_HALF == 28.0, "main road visual width intact (TASK-012)")
				_check(layout.get_direction_role("west") == "main_threat_portal", \
					"WEST = main threat portal role")
				var dressing := _world.get_node_or_null("WorldDressing")
				_check(dressing != null and dressing.get("composition_phase") == 5, \
					"world visual composition phase 5 active")
				_gate = _find_gate_at(WEST_GATE_POS)
				_check(_gate != null, "TASK-013 west gate still present")
				if _gate != null:
					_check(_gate.get("direction") == "west", "west gate direction retained")
					_check(_gate.is_closed(), "west gate CLOSED (no breach conflict)")
				_check(get_nodes_in_group("ghosts").size() == 0, "no ghost actor spawned at end")
				_check(_spawner._enemies.size() == 0, "spawner holds no stale enemy references at end")
				_check(_roster._actors.size() == 0, "roster _actors empty at end")
				_check(get_nodes_in_group("enemies").size() == 0, "no leftover enemies at end")
				_check(_ledger.get_all_records().size() == 3, \
					"ledger retains 3 records after full scenario (%d)" % _ledger.get_all_records().size())
				_check(_ledger.get_pending_records().size() == 2 \
					and _ledger.get_active_records().size() == 0 \
					and _ledger.get_resolved_records().size() == 1, \
					"ledger state queries consistent at end (2 PENDING + 1 RESOLVED)")
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 250000:
		print("TASK0166_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


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
	e.death_day = _game_time.get_day_number()
	e.death_phase = DeathRecord.DeathPhase.NIGHT
	e.death_position = WEST_RALLY
	return e.to_snapshot()


func _make_ghost_snapshot(source_uid: String, display_name := "Raider Ghost") -> Dictionary:
	var snap := _make_enemy_snapshot(source_uid, display_name)
	snap["is_ghost"] = true
	return snap


func _snapshot_is_pure(snap: Dictionary) -> bool:
	var valid_types := [
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
		TYPE_VECTOR2, TYPE_DICTIONARY, TYPE_ARRAY,
	]
	for key in snap.keys():
		if typeof(snap[key]) not in valid_types:
			return false
	return true


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	release_all_actions()
	var game_time: Node = root.get_node("GameTime")
	if game_time:
		game_time.set_auto_advance(false)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)