extends SceneTree

## TASK-016-3 Mercenary / Enemy Combat Death Integration 자동 검증.
##  - Mercenary 실제 lethal 사망(Enemy 공격으로 HP 0) → MERCENARY DeathRecord 정확히 1개.
##    MercenaryData.alive=false 유지, Actor cleanup/roster freed-reference 제거 유지.
##  - Enemy 실제 lethal 사망(Mercenary auto combat / 직접 take_damage) → ENEMY
##    DeathRecord 정확히 1개. 같은 display_name이라도 source_uid(독립 id)로 서로 다른 record.
##  - 기록 금지 경로: DAY cleanup / FirstEncounterSpawner despawn / 단순 queue_free /
##    scene unload는 die()를 거치지 않아 record가 생성되지 않음.
##  - die() 내부 단일 경로에서만 record 생성(died signal 핸들러는 생성하지 않음) →
##    동일 실제 죽음 중복 record 없음.
##  - snapshot은 Actor/Node reference 없는 순수 데이터.
##  - Day/Night 전환 후에도 record 유지.
##  - 회귀: TASK-014 death cleanup 흐름(그룹 제외/freed) / Player 비전투 / Worker 무spawn.

enum Phase {
	SETUP,
	NIGHT_READY,
	ENEMY_DEATH,
	DIRECT_KILL,
	MERC_DEATH,
	CLEANUP_NO_RECORD,
	DAY_NIGHT_RETAIN,
	REGRESSION,
	DONE,
}

const GATE_POS := Vector2(0, -448)
const NORTH_RALLY := Vector2(0, -280)
const BUDGET := 2000

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
var _resources: Node = null
var _ledger: Node = null
var _mercenary: MercenaryData = null
var _actor: Node = null

var _enemy_seq := 0
var _budget := 0


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
	print("TASK0163_RESULT=" + ("FAIL" if _failed else "PASS"))
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
func _spawn_enemy(pos: Vector2, hp := 60, with_route := false) -> EnemyActor:
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	var enemy := scene.instantiate() as EnemyActor
	if enemy == null:
		return null
	enemy.max_hp = hp
	enemy.setup("test_enemy_%d" % _enemy_seq, "Raider", "north")
	enemy.position = pos
	_world.add_child(enemy)
	_enemy_seq += 1
	if with_route:
		enemy.set_route([], Vector2(0, -150))
	return enemy


func _clear_test_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 8:
				return false
			if _sub == 0:
				_game_time = root.get_node("GameTime")
				if _game_time != null and _game_time.has_method("set_auto_advance"):
					_game_time.set_auto_advance(false)
				if _game_time != null and _game_time.has_method("set_durations"):
					_game_time.set_durations(2.0, 1.0)
				_world = root.get_node("Main").get_node("World")
				_placement = root.get_node("Main").get_node("BuildingPlacement")
				_spawner = root.get_node("FirstEncounterSpawner")
				_spawner.set_direction("north")
				_roster = root.get_node("MercenaryRoster")
				_resources = root.get_node("VillageResources")
				_ledger = root.get_node("DeathLedger")
				_check(_game_time != null and _world != null and _placement != null \
					and _spawner != null and _roster != null and _resources != null \
					and _ledger != null, "core autoloads + ledger present")
				_check(_ledger.get_all_records().size() == 0, "ledger starts empty")
				_resources._amounts["wood"] = 10000
				var ui: Control = get_first_node_in_group("recruitment_ui")
				_check(ui != null, "recruitment UI present")
				ui._on_mercenary_hire_pressed("mercenary_A")
				_mercenary = _roster.get_mercenary("mercenary_A")
				_check(_mercenary != null and _mercenary.alive, "mercenary_A hired alive")
				if _mercenary != null:
					_mercenary.set_defense_zone(MercenaryData.DefenseZone.NORTH)
					_mercenary.max_hp = 80
					_mercenary.attack_damage = 30
					_mercenary.attack_interval = 0.05
					_mercenary.move_speed = 120.0
				_placement._set_building_type("gate")
				_placement._try_place_gate_at(_placement._snap_gate(GATE_POS))
				_check(_find_gate_at(GATE_POS) != null, "north gate placed")
				_check(_ledger.get_all_records().size() == 0, "no records before any death")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase is NIGHT")
				_enter(Phase.NIGHT_READY)
		Phase.NIGHT_READY:
			if _sub == 0:
				_check(_count_mercenaries() == 1, "mercenary actor spawned at NIGHT (%d)" % _count_mercenaries())
				_actor = _roster.get_actor("mercenary_A")
				_check(_actor != null, "mercenary actor retrievable by id")
				if _actor != null:
					_check(_actor.merc_data == _mercenary, "actor references roster MercenaryData")
					_check(_actor.current_hp == 80, "actor current_hp from max_hp (80)")
					var pos: Vector2 = (_actor as Node2D).global_position
					_check(pos.distance_to(NORTH_RALLY) < 1.0, "actor at north rally (pos=%s)" % pos)
				_check(_ledger.get_all_records().size() == 0, "no records after NIGHT spawn (no death yet)")
				# auto-encounter는 despawn해 격리된 사망 테스트로 진행.
				_spawner.despawn_encounter()
				_wait_frames(2)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_count_enemies() == 0, "auto-encounter cleaned (%d)" % _count_enemies())
				_enter(Phase.ENEMY_DEATH)
		Phase.ENEMY_DEATH:
			if _sub == 0:
				# 북방 근처 HOLD 적 2마리 → A가 자동 추격/공격/사살.
				var e1 := _spawn_enemy(Vector2(0, -360), 60, false)
				var e2 := _spawn_enemy(Vector2(0, -400), 60, false)
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
				_check(_records_for_source("test_enemy_0").size() == 1, "enemy test_enemy_0 recorded exactly once")
				_check(_records_for_source("test_enemy_1").size() == 1, "enemy test_enemy_1 recorded exactly once")
				_check(_records_for_source("test_enemy_0").size() == 1 \
					and _records_for_source("test_enemy_1").size() == 1, \
					"died signal + die() does not duplicate records (exactly 1 each)")
				var distinct_uids := true
				var same_names := true
				for r in erecords:
					if r.source_kind != DeathRecord.SourceKind.ENEMY:
						distinct_uids = false
					if r.display_name != "Raider":
						same_names = false
				_check(distinct_uids, "all enemy records source_kind=ENEMY")
				_check(same_names, "all enemy records keep display_name 'Raider'")
				_check(erecords[0].source_uid != erecords[1].source_uid, "distinct source_uid for same-name enemies")
				var death_day: int = _game_time.get_day_number()
				for r in erecords:
					_check(r.death_day == death_day, "enemy record death_day = current day (%d)" % death_day)
					_check(r.death_phase == DeathRecord.DeathPhase.NIGHT, "enemy record death_phase=NIGHT")
					_check(r.eligible_day == r.death_day + 1, "enemy record eligible_day = death_day + 1 (%d)" % r.eligible_day)
					_check(r.get_status() == DeathRecord.Status.PENDING, "enemy record starts PENDING")
					_check(r.max_hp == 60, "enemy record retains max_hp")
					_check(r.level == 1, "enemy record level=1")
				if _actor != null and is_instance_valid(_actor):
					_check(_actor.get_target() == null, "mercenary target cleared after enemy death")
				_enter(Phase.DIRECT_KILL)
		Phase.DIRECT_KILL:
			if _sub == 0:
				# 직접 사망 경로(take_damage → die)도 정확히 1 record.
				var ed := _spawn_enemy(Vector2(0, -380), 60, false)
				_check(ed != null, "direct-kill enemy spawned")
				if ed != null:
					ed.take_damage(99999)
					_check(ed.alive == false, "direct-kill enemy alive=false immediately after damage")
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_enemy_records().size() == 3, "exactly 3 ENEMY records after direct kill (%d)" % _enemy_records().size())
				_check(_records_for_source("test_enemy_2").size() == 1, "direct-kill enemy recorded exactly once")
				_enter(Phase.MERC_DEATH)
		Phase.MERC_DEATH:
			if _sub == 0:
				# 강한 적이 A를 공격해 사망시킨다(실제 lethal combat death).
				var e3 := _spawn_enemy(Vector2(0, -330), 100000, true)
				_check(e3 != null, "strong enemy E3 spawned for merc death")
				if e3 != null:
					e3.attack_damage = 25
					e3.attack_interval = 0.05
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
					_check(mr.death_phase == DeathRecord.DeathPhase.NIGHT, "mercenary record death_phase=NIGHT")
					_check(mr.eligible_day == mr.death_day + 1, "mercenary record eligible_day = death_day + 1")
					_check(mr.get_status() == DeathRecord.Status.PENDING, "mercenary record starts PENDING")
				# snapshot이 Actor/Node reference를 포함하지 않는 순수 데이터인지 확인.
				var snap := mrecords[0].to_snapshot() if mrecords.size() > 0 else {}
				var valid_types := [
					TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING,
					TYPE_VECTOR2, TYPE_DICTIONARY, TYPE_ARRAY,
				]
				var pure := true
				for key in snap.keys():
					if typeof(snap[key]) not in valid_types:
						pure = false
						break
				_check(pure, "mercenary record snapshot is pure data (no Node references)")
				for e in get_nodes_in_group("enemies"):
					if is_instance_valid(e):
						e.queue_free()
				_wait_frames(3)
			elif _sub == 3 and not _waited():
				return false
			elif _sub == 3:
				_check(_count_enemies() == 0, "strong enemy cleaned after merc death test")
				_check(_ledger.get_all_records().size() == 4, "ledger holds 4 records at this point (%d)" % _ledger.get_all_records().size())
				_enter(Phase.CLEANUP_NO_RECORD)
		Phase.CLEANUP_NO_RECORD:
			if _sub == 0:
				# FirstEncounterSpawner despawn 경로는 die()를 거치지 않아 record 미생성.
				var spawned: int = _spawner.spawn_encounter()
				_check(spawned == 3, "spawner spawned 3 enemies for despawn test (%d)" % spawned)
				var before: int = _ledger.get_all_records().size()
				_spawner.despawn_encounter()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_spawner._enemies.size() == 0, "spawner tracking empty after despawn")
				_check(_count_enemies() == 0, "despawned enemies removed from world (%d)" % _count_enemies())
				_check(_ledger.get_all_records().size() == 4, "despawn created no new records (still 4)")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase DAY after cleanup")
				_check(_ledger.get_all_records().size() == 4, "DAY cleanup created no new records (still 4)")
				_check(_roster.get_actor_count() == 0, "roster actor_count 0 during DAY")
				_enter(Phase.DAY_NIGHT_RETAIN)
		Phase.DAY_NIGHT_RETAIN:
			if _sub == 0:
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 1 and not _waited():
				return false
			elif _sub == 1:
				_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "next NIGHT arrived")
				_check(_count_mercenaries() == 0, "dead merc NOT re-spawned next NIGHT (%d)" % _count_mercenaries())
				_check(_ledger.get_all_records().size() == 4, "records retained into next NIGHT (%d)" % _ledger.get_all_records().size())
				_check(_merc_records().size() == 1 and _enemy_records().size() == 3, \
					"1 MERCENARY + 3 ENEMY records retained")
				_advance_to_next_phase()
				_wait_frames(3)
			elif _sub == 2 and not _waited():
				return false
			elif _sub == 2:
				_check(_game_time.get_phase() == GameTime.Phase.DAY, "final DAY arrived")
				_check(_ledger.get_all_records().size() == 4, "records retained after full cycle (still 4)")
				_check(_ledger.has_record_for_source("mercenary_A"), "has_record_for_source(mercenary_A) true")
				_check(_ledger.has_record_for_source("test_enemy_0"), "has_record_for_source(test_enemy_0) true")
				_check(_ledger.has_record_for_source("unknown_src") == false, "unknown source not recorded")
				_enter(Phase.REGRESSION)
		Phase.REGRESSION:
			if _sub == 0:
				var player: Node = root.get_node("Main").get_node("Player")
				_check(player != null, "player intact")
				_check(not player.has_method("attack") and not player.has_method("_attack"), "player has no attack method")
				_check(not player.is_in_group("enemies") and not player.is_in_group("mercenaries"), "player excluded from combat groups")
				_check(root.get_node("WorkerRoster").get_count() == 0, "worker roster unaffected")
				_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor spawned")
				_check(get_nodes_in_group("miners").size() == 0, "no miner actor spawned")
				_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
				var floor_node: TileMapLayer = _world.get_node("Floor") as TileMapLayer
				_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact")
				_check(_find_gate_at(GATE_POS) != null, "north gate still present")
				_check(get_nodes_in_group("ghosts").size() == 0, "no ghost actor spawned")
				_check(_spawner._enemies.size() == 0, "spawner holds no stale enemy references at end")
				_check(_roster._actors.size() == 0, "roster _actors empty at end")
				_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 200000:
		print("TASK0163_RESULT=TIMEOUT phase=%s sub=%d" % [str(_phase), _sub])
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)