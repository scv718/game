extends SceneTree

## TASK-017-2 Subsequent NIGHT Ghost Spawn 자동 검증.
## 소비 가능한 GhostReturnCandidate가 이후 NIGHT spawn 경로(기존 Portal/Spawn marker
## convention)를 통해 실제 3D GhostActor3D로 정확히 1회 등장한다.
##   - lethal death → 다음 유효 NIGHT → Ghost spawn.
##   - Ghost 자동전투 참여(EnemyActor3D combat foundation 재사용).
##   - duplicate spawn 없음(같은 candidate는 consume()로 정확히 1회만 spawn).
##   - failed spawn recovery 안전(spawn 실패 시 candidate는 미소모 유지).
##   - Ghost 사망 시 신규 GhostReturnCandidate를 만들지 않음(재귀 방지).
##   - 원본 identity(source_uid/display_name/combat stat)가 Ghost에서 확인 가능.
##   - Player 직접 전투 없음(EnemyActor3D 계약 유지).
##
## 기존 테스트 관례(task3dcmb0013)에 따라 GhostSpawner3D와 mercenary fixture는
## autoload 정적 참조를 피하기 위해 런타임 load()로만 접근한다.

enum Phase {
	SETUP,
	STRUCTURE,
	REGISTER_CANDIDATE,
	TO_NIGHT,
	GHOST_SPAWN_WAIT,
	SPAWN_VERIFY,
	COMBAT_ARM,
	COMBAT_WAIT,
	GHOST_DEATH_WAIT,
	NO_RECURSION_CHECK,
	TO_DAY,
	NO_DUPLICATE_NIGHT,
	FAILED_SPAWN_RECOVERY,
	RECOVERY_NIGHT,
	FINAL_CHECK,
	DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 12
const OBSERVE_BUDGET := 600

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _game_time: Node = null
var _ledger: Node = null
var _ghost_return: Node = null
var _spawner: Node = null
var _candidate_record_id := ""
var _second_record_id := ""
var _ghost: Node = null
var _ghost_uid := ""
var _merc_fixture: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK0172_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _make_enemy_snapshot(source_uid: String, day := 1) -> Dictionary:
	var e := DeathRecord.new("")
	e.source_uid = source_uid
	e.source_kind = DeathRecord.SourceKind.ENEMY
	e.display_name = "Raider"
	e.class_or_type = "RAIDER"
	e.level = 1
	e.max_hp = 60
	e.attack_damage = 8
	e.attack_interval = 1.0
	e.move_speed = 90.0
	e.death_day = day
	e.death_phase = DeathRecord.DeathPhase.NIGHT
	e.death_position = Vector2(0, -448)
	return e.to_snapshot()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.REGISTER_CANDIDATE:
			_register_candidate()
		Phase.TO_NIGHT:
			_to_night()
		Phase.GHOST_SPAWN_WAIT:
			_ghost_spawn_wait()
		Phase.SPAWN_VERIFY:
			_spawn_verify()
		Phase.COMBAT_ARM:
			_combat_arm()
		Phase.COMBAT_WAIT:
			_combat_wait()
		Phase.GHOST_DEATH_WAIT:
			_ghost_death_wait()
		Phase.NO_RECURSION_CHECK:
			_no_recursion_check()
		Phase.TO_DAY:
			_to_day()
		Phase.NO_DUPLICATE_NIGHT:
			_no_duplicate_night()
		Phase.FAILED_SPAWN_RECOVERY:
			_failed_spawn_recovery()
		Phase.RECOVERY_NIGHT:
			_recovery_night()
		Phase.FINAL_CHECK:
			_final_check()
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0172_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _initialize() -> void:
	var gt := root.get_node_or_null("GameTime")
	if gt != null:
		gt.set_auto_advance(false)
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_game_time = root.get_node_or_null("GameTime")
	_ledger = root.get_node_or_null("DeathLedger")
	_ghost_return = root.get_node_or_null("GhostReturn")
	_check(_world != null, "3D world loads")
	_check(_game_time != null and _ledger != null and _ghost_return != null,
		"GameTime/DeathLedger/GhostReturn autoloads available")
	if _world == null or _game_time == null or _ledger == null or _ghost_return == null:
		_finish()
		return
	_game_time.set_auto_advance(false)
	_game_time.set_durations(2.0, 1.0)
	var nav_manager: Node = load("res://scripts/navigation_manager_3d.gd").new()
	nav_manager.name = "NavManager"
	_world.add_child(nav_manager)
	_spawner = load("res://scripts/ghost_spawner_3d.gd").new()
	_spawner.name = "GhostSpawner3D"
	root.add_child(_spawner)
	_enter(Phase.STRUCTURE)


func _structure() -> void:
	_check(_spawner.has_method("spawn_ghosts"), "GhostSpawner3D exposes spawn_ghosts")
	_check(_spawner.has_method("get_ghost_count"), "GhostSpawner3D exposes get_ghost_count")
	_check(_ghost_return.get_candidate_count() == 0, "no candidates before any death")
	_check(get_nodes_in_group("ghosts").size() == 0, "no ghost actor before NIGHT")
	_enter(Phase.REGISTER_CANDIDATE)


func _register_candidate() -> void:
	# lethal death 1회 → GhostReturn candidate 1개 자동 등록.
	var rec: DeathRecord = _ledger.record_death(_make_enemy_snapshot("raider_017_2"))
	_check(rec != null, "lethal death creates a ledger record")
	_candidate_record_id = rec.record_id
	_check(_ghost_return.get_candidate_count() == 1, \
		"lethal death -> exactly 1 ghost candidate")
	_check(_ghost_return.get_eligible_candidates().size() == 1, \
		"1 eligible candidate before NIGHT")
	_enter(Phase.TO_NIGHT)


func _to_night() -> void:
	_game_time.advance(_game_time.day_duration)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT, \
		"phase advanced to NIGHT")
	_enter(Phase.GHOST_SPAWN_WAIT)


func _ghost_spawn_wait() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES + NAV_SYNC_FRAMES:
		return
	_wait = 0
	_enter(Phase.SPAWN_VERIFY)


func _spawn_verify() -> void:
	var count: int = _spawner.get_ghost_count()
	_check(count == 1, "NIGHT spawns exactly 1 ghost from eligible candidate (%d)" % count)
	_check(get_nodes_in_group("enemies_3d").size() == 1, \
		"ghost joins enemies_3d combat group")
	var ghosts: Array[Node] = _spawner.get_ghosts()
	if ghosts.size() > 0:
		_ghost = ghosts[0]
		_ghost_uid = "ghost_%s" % _candidate_record_id
		_check((_ghost as Node).get("enemy_id") == _ghost_uid, \
			"ghost has deterministic enemy_id from candidate record")
		_check((_ghost as Node).get("display_name") == "Ghost of Raider", \
			"ghost label preserves original identity (Ghost of Raider)")
		_check((_ghost as Node).get("source_uid") == "raider_017_2", \
			"ghost tracks original source_uid")
		_check((_ghost as Node).get("ghost_kind") == DeathRecord.SourceKind.ENEMY, \
			"ghost tracks original entity category (ENEMY)")
		_check((_ghost as Node).get("max_hp") == 60, \
			"ghost reuses original combat max_hp")
		_check((_ghost as Node).get("alive") == true, "ghost alive after spawn")
	# candidate consumed: 1회 return 불변식 → 더 이상 eligible 아님.
	_check(_ghost_return.is_consumed(_candidate_record_id), \
		"candidate consumed after successful spawn")
	_check(_ghost_return.get_eligible_candidates().size() == 0, \
		"no eligible candidate remains after consume")
	_enter(Phase.COMBAT_ARM)


func _combat_arm() -> void:
	# Ghost 자동전투 검증용 상대 mercenary fixture(EnemyActor3D는 mercenaries_3d만 target).
	# Ghost spawn 지점 부근에 두어 움직임 없이 즉시 교전 범위에 들어가게 한다.
	var data = load("res://scripts/mercenary_data.gd").new()
	data.id = "m_fixture_017"
	data.display_name = "Defender"
	data.max_hp = 100000
	data.attack_damage = 30
	data.attack_interval = 1.0
	var merc: Node = (load("res://scenes/mercenary_3d.tscn") as PackedScene).instantiate()
	merc.merc_data = data
	var ghost_pos: Vector3 = (_ghost as Node3D).position
	merc.position = ghost_pos + Vector3(2.0, 0.0, 0.0)
	_world.add_child(merc)
	_merc_fixture = merc
	_enter(Phase.COMBAT_WAIT)


func _combat_wait() -> void:
	_wait += 1
	var ghost_attacking: bool = _ghost != null and is_instance_valid(_ghost) \
		and (_ghost as Node).get("alive") == true \
		and (_ghost as Node).get("state") == 2  # EnemyActor3D.EnemyState.ATTACK
	if not ghost_attacking and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(ghost_attacking, \
		"ghost auto-combat engages a nearby mercenary (EnemyState.ATTACK)")
	_check((_merc_fixture as Node).get("current_hp") < 100000, \
		"ghost deals combat damage to the mercenary")
	_enter(Phase.GHOST_DEATH_WAIT)


func _ghost_death_wait() -> void:
	_wait += 1
	var died: bool = _ghost == null or not is_instance_valid(_ghost) \
		or (_ghost as Node).get("alive") == false
	if not died and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(died, "ghost dies to lethal combat")
	_enter(Phase.NO_RECURSION_CHECK)


func _no_recursion_check() -> void:
	# Ghost death는 is_ghost=true record → DeathLedger가 신규 candidate 생성을 차단.
	_check(_ghost_return.get_candidate_count() == 1, \
		"ghost death adds no new candidate (recursion guard, count=%d)" \
			% _ghost_return.get_candidate_count())
	_check(_ghost_return.get_eligible_candidates().size() == 0, \
		"no new eligible candidate after ghost death")
	_enter(Phase.TO_DAY)


func _to_day() -> void:
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase returned to DAY")
	_check(_spawner.get_ghost_count() == 0, \
		"DAY return has no remaining ghost (cleanup, no record)")
	_enter(Phase.NO_DUPLICATE_NIGHT)


func _no_duplicate_night() -> void:
	# 같은 candidate는 consume된 상태이므로 다음 NIGHT에 재spawn되지 않아야 한다.
	if _wait == 0:
		_game_time.advance(_game_time.day_duration)
		_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "next NIGHT begins")
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_check(_spawner.get_ghost_count() == 0, \
		"consumed candidate does NOT respawn on the next NIGHT (no duplicate spawn)")
	_check(get_nodes_in_group("enemies_3d").size() == 0, \
		"no duplicate ghost actor in enemies_3d")
	_enter(Phase.FAILED_SPAWN_RECOVERY)


func _failed_spawn_recovery() -> void:
	# failed spawn recovery: spawn 성공에만 consume이 일어나므로, spawn되지 않은
	# candidate(예: 이번 NIGHT spawn 창 이후 등록된 죽음)는 미소모로 유지되어
	# 다음 유효 NIGHT에 재시도 가능하다.
	var pre_count: int = _ghost_return.get_candidate_count()
	var rec: DeathRecord = _ledger.record_death(_make_enemy_snapshot("raider_017_2b", 3))
	_check(rec != null and rec.record_id != _candidate_record_id, \
		"second distinct lethal death creates a new record")
	_second_record_id = rec.record_id
	_check(_ghost_return.get_candidate_count() == pre_count + 1, \
		"second candidate registered (count=%d)" % _ghost_return.get_candidate_count())
	# 현재 NIGHT에는 spawn 창이 이미 닫혔으므로 candidate는 미소모로 남는다.
	_check(_ghost_return.is_consumed(_second_record_id) == false, \
		"candidate not consumed without a successful spawn (recovery safe)")
	_check(_ghost_return.get_eligible_candidates().size() == 1, \
		"second candidate remains eligible for a later NIGHT")
	# DAY로 전환(despawn만 일어나고 candidate 상태는 그대로).
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "back to DAY")
	_check(_ghost_return.is_consumed(_second_record_id) == false, \
		"candidate still not consumed across DAY (no false consume)")
	_enter(Phase.RECOVERY_NIGHT)


func _recovery_night() -> void:
	# 다음 유효 NIGHT에 미소모 candidate가 재시도되어 정상 spawn + consume된다.
	if _wait == 0:
		_game_time.advance(_game_time.day_duration)
		_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "recovery NIGHT begins")
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_check(_spawner.get_ghost_count() == 1, \
		"failed-spawn candidate is retried and spawned on the next valid NIGHT")
	_check(_ghost_return.is_consumed(_second_record_id), \
		"recovery candidate consumed after successful retry spawn")
	_check(_ghost_return.get_eligible_candidates().size() == 0, \
		"no eligible candidate remains after recovery spawn")
	_enter(Phase.FINAL_CHECK)


func _final_check() -> void:
	_check(get_nodes_in_group("player").size() == 0, \
		"no runtime player Actor (no direct combat)")
	_check(get_nodes_in_group("ghosts").size() == 0, \
		"no leftover ghost after cleanup")
	_check(_ledger.get_all_records().size() >= 2, \
		"ledger retains the original death records")
	_enter(Phase.DONE)
