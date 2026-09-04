extends SceneTree

## TASK-017-4 Ghost Vertical Slice Regression.
## First Ghost Return 전체 세로 슬라이스를 실제 Runtime Actor 위에서 순서대로 재생한다:
##   1. 실제 Enemy lethal death(실제 Actor die() → DeathLedger → GhostReturn candidate).
##   2. Death Ledger 확인(원 death record 1개, candidate 1개).
##   3. DAY.
##   4. 다음 NIGHT → Ghost spawn 1회.
##   5. Ghost combat(실제 자동전투, 살아 있는 Mercenary를 공격).
##   6. Ghost lethal death(실제 combat damage로 사망).
##   7. 다음 DAY/NIGHT 반복: Mercenary lethal death → 다시 NIGHT → Mercenary Ghost
##      spawn → combat → lethal death → DAY.
##
## 검증 항목(큐 "검증" 대응):
##   - 원 death record 1개(source_uid 기준 정확히 1 record).
##   - ghost candidate 1개(lethal death 1회 → candidate 1개).
##   - ghost spawn 1회(candidate consume 후 재spawn 없음).
##   - ghost death 후 candidate 재귀 생성 없음(is_ghost=true record는 신규 후보 차단).
##   - freed reference 없음(spawner 추적/월드 그룹에 stale/freed instance 없음).
##   - duplicate actor 없음(동시에 같은 enemy_id/source ghost 2개 없음).
##   - Death Ledger 기존 기능 회귀 없음(record 조회/상태 전환 API 유지).
##   - Player combat 없음(런타임 player Actor 없음, enemy target은 mercenaries_3d만).
##
## 기존 테스트 관례(task0172/0173, task3dcmb0013)에 따라 autoload/GhostSpawner3D는
## 런타임 load()로만 접근하고, 공통 클래스(WorldCoords3D/DeathRecord/MercenaryData/
## EnemyActor3D/GhostActor3D)는 정적 참조를 사용한다.

enum Phase {
	SETUP, STRUCTURE,
	ENEMY_DEATH, LEDGER_VERIFY_1,
	TO_NIGHT_1, GHOST_SPAWN_WAIT_1, SPAWN_VERIFY_1,
	COMBAT_ARM_1, COMBAT_WAIT_1, GHOST_DEATH_WAIT_1,
	NO_RECURSION_1, GHOST_CLEANUP_WAIT_1,
	TO_DAY_1, DAY_VERIFY_1,
	REPEAT_NIGHT_WAIT, NO_DUPLICATE_NIGHT, TO_DAY_2,
	MERC_DEATH, LEDGER_VERIFY_2,
	TO_NIGHT_2, GHOST_SPAWN_WAIT_2, SPAWN_VERIFY_2,
	COMBAT_ARM_2, COMBAT_WAIT_2, GHOST_DEATH_WAIT_2,
	NO_RECURSION_2, GHOST_CLEANUP_WAIT_2,
	TO_DAY_3, FINAL_CHECK, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 12
const OBSERVE_BUDGET := 900
## ghost 사망 fade-out + queue_free 여유 프레임(DEATH_FADE_SECONDS ≈ 0.9s @60fps).
const DEATH_CLEANUP_BUDGET := 180

## 실제 Enemy lethal death 배치 위치(마을 외곽이라도 world 내부).
const ENEMY_POS := Vector3(20.0, 0.0, 20.0)
const MERC_POS := Vector3(-20.0, 0.0, -20.0)
## ghost가 spawn하는 서쪽 포탈 근처에 combat 상대 Mercenary를 두기 위한 오프셋.
const COMBAT_OFFSET := Vector3(2.0, 0.0, 0.0)

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP

var _world: Node3D = null
var _game_time: Node = null
var _ledger: Node = null
var _ghost_return: Node = null
var _spawner: Node = null

## 1차 사이클(Enemy): 실제 Enemy Actor / 기록 ID / ghost.
var _enemy_uid := "enemy_slice_1"
var _enemy_record_id := ""
var _ghost: Node = null
var _ghost1_enemy_id := ""
var _merc_fixture: Node = null

## 2차 사이클(Mercenary): 실제 Mercenary Actor / 기록 ID / ghost.
var _merc_uid := "m_slice_2"
var _merc_data: MercenaryData = null
var _merc_victim: Node = null
var _merc_record_id := ""
var _ghost2: Node = null
var _merc_fixture2: Node = null

## 관측된 실제 died signal 총횟수(Enemy/Mercenary/Ghost 전부). ledger 증가와 대응.
var _deaths_total := 0


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
	print("TASK0174_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.ENEMY_DEATH:
			_enemy_death()
		Phase.LEDGER_VERIFY_1:
			_ledger_verify_1()
		Phase.TO_NIGHT_1:
			_to_night_1()
		Phase.GHOST_SPAWN_WAIT_1:
			_ghost_spawn_wait()
		Phase.SPAWN_VERIFY_1:
			_spawn_verify_1()
		Phase.COMBAT_ARM_1:
			_combat_arm()
		Phase.COMBAT_WAIT_1:
			_combat_wait()
		Phase.GHOST_DEATH_WAIT_1:
			_ghost_death_wait()
		Phase.NO_RECURSION_1:
			_no_recursion_check()
		Phase.GHOST_CLEANUP_WAIT_1:
			_ghost_cleanup_wait()
		Phase.TO_DAY_1:
			_to_day_1()
		Phase.DAY_VERIFY_1:
			_day_verify_1()
		Phase.REPEAT_NIGHT_WAIT:
			_repeat_night_wait()
		Phase.NO_DUPLICATE_NIGHT:
			_no_duplicate_night()
		Phase.TO_DAY_2:
			_to_day_2()
		Phase.MERC_DEATH:
			_merc_death()
		Phase.LEDGER_VERIFY_2:
			_ledger_verify_2()
		Phase.TO_NIGHT_2:
			_to_night_2()
		Phase.GHOST_SPAWN_WAIT_2:
			_ghost_spawn_wait()
		Phase.SPAWN_VERIFY_2:
			_spawn_verify_2()
		Phase.COMBAT_ARM_2:
			_combat_arm()
		Phase.COMBAT_WAIT_2:
			_combat_wait()
		Phase.GHOST_DEATH_WAIT_2:
			_ghost_death_wait()
		Phase.NO_RECURSION_2:
			_no_recursion_check()
		Phase.GHOST_CLEANUP_WAIT_2:
			_ghost_cleanup_wait()
		Phase.TO_DAY_3:
			_to_day_3()
		Phase.FINAL_CHECK:
			_final_check()
		Phase.DONE:
			_finish()
			return true
	if _frame > 40000:
		print("TASK0174_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	_check(_ghost_return.get_candidate_count() == 0, "no candidates before any death")
	_check(get_nodes_in_group("enemies_3d").size() == 0, "no enemies before the slice starts")
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor at start")
	_enter(Phase.ENEMY_DEATH)


## -- 시나리오 1: 실제 Enemy lethal death. 실제 Actor die() → DeathLedger → candidate. --
func _enemy_death() -> void:
	if _wait == 0:
		var enemy := (load("res://scenes/enemy_3d.tscn") as PackedScene).instantiate()
		enemy.setup(_enemy_uid, "Raider", "west")
		enemy.max_hp = 60
		enemy.attack_damage = 8
		enemy.position = ENEMY_POS
		_world.add_child(enemy)
		enemy.died.connect(_on_tracked_died)
		_check((enemy as Node).get("alive") == true, "real enemy actor spawns alive")
	_wait += 1
	if _wait < 4:
		return
	_wait = 0
	# 실제 lethal combat damage와 동일한 die() 경로(take_damage → HP 0 → die → record).
	# 대상 Actor를 직접 보관하지 않고, 다음 phase에서 ledger로만 검증한다.
	var enemies := get_nodes_in_group("enemies_3d")
	var victim: Node = null
	for e in enemies:
		if (e as Node).get("enemy_id") == _enemy_uid:
			victim = e
			break
	if victim != null and is_instance_valid(victim):
		victim.take_damage(9999)
	_check(victim != null and is_instance_valid(victim)
		and (victim as Node).get("alive") == false,
		"enemy takes lethal combat damage and dies")
	_enter(Phase.LEDGER_VERIFY_1)


func _ledger_verify_1() -> void:
	_check(_count_records_for(_enemy_uid) == 1,
		"original enemy death record exactly 1 (%d)" % _count_records_for(_enemy_uid))
	_check(_ledger.get_all_records().size() == 1,
		"ledger holds exactly the 1 original record (%d)" % _ledger.get_all_records().size())
	_check(_ghost_return.get_candidate_count() == 1,
		"enemy lethal death -> exactly 1 ghost candidate")
	_check(_ghost_return.get_eligible_candidates().size() == 1,
		"1 eligible candidate before NIGHT")
	var rec := _record_for(_enemy_uid)
	if rec != null:
		_check(rec.is_ghost == false, "original record is NORMAL (is_ghost=false)")
		_check(rec.source_kind == DeathRecord.SourceKind.ENEMY, "original record kind is ENEMY")
		_check(rec.max_hp == 60, "original record preserves combat max_hp")
		_check(is_equal_approx(rec.move_speed, 90.0),
			"original record stores logical px/s move_speed (%.2f)" % rec.move_speed)
		_enemy_record_id = rec.record_id
	var cand: GhostReturnCandidate = _ghost_return.get_candidate(_enemy_record_id)
	_check(cand != null and cand.is_consumed() == false,
		"enemy candidate is registered and not yet consumed")
	_check(_game_time.get_phase() == GameTime.Phase.DAY,
		"original death occurs during DAY")
	_enter(Phase.TO_NIGHT_1)


func _to_night_1() -> void:
	_game_time.advance(_game_time.day_duration)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "phase advanced to NIGHT")
	_enter(Phase.GHOST_SPAWN_WAIT_1)


func _ghost_spawn_wait() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES + NAV_SYNC_FRAMES:
		return
	_wait = 0
	if _phase == Phase.GHOST_SPAWN_WAIT_1:
		_enter(Phase.SPAWN_VERIFY_1)
	else:
		_enter(Phase.SPAWN_VERIFY_2)


func _spawn_verify_1() -> void:
	_check(_spawner.get_ghost_count() == 1,
		"NIGHT spawns exactly 1 ghost from the enemy candidate (%d)" % _spawner.get_ghost_count())
	_check(get_nodes_in_group("enemies_3d").size() == 1,
		"exactly 1 ghost actor in enemies_3d (no duplicate actor)")
	var ghosts: Array[Node] = _spawner.get_ghosts()
	if ghosts.size() > 0:
		_ghost = ghosts[0]
		_ghost1_enemy_id = str((_ghost as Node).get("enemy_id"))
		if not (_ghost as Node).died.is_connected(_on_tracked_died):
			(_ghost as Node).died.connect(_on_tracked_died)
		_check((_ghost as Node).get("enemy_id") == "ghost_%s" % _enemy_record_id,
			"ghost has deterministic enemy_id from candidate record")
		_check((_ghost as Node).get("source_uid") == _enemy_uid,
			"ghost tracks original enemy source_uid")
		_check((_ghost as Node).get("ghost_kind") == DeathRecord.SourceKind.ENEMY,
			"ghost tracks original entity category (ENEMY)")
		_check((_ghost as Node).get("max_hp") == 60, "ghost reuses original combat max_hp")
		# unit fix 회귀: enemy record가 px/s를 보관하므로 ghost world move_speed는 90*PX_TO_UNIT.
		_check(is_equal_approx((_ghost as Node).get("move_speed"),
			90.0 * WorldCoords3D.PX_TO_UNIT),
			"ghost world move_speed is consistent with original enemy speed")
	_check(_ghost_return.is_consumed(_enemy_record_id),
		"enemy candidate consumed after successful spawn")
	_check(_ghost_return.get_eligible_candidates().size() == 0,
		"no eligible candidate remains after consume")
	_enter(Phase.COMBAT_ARM_1)


## -- 시나리오 5~6: Ghost combat. 살아 있는 Mercenary를 실제 자동전투로 공격한다. --
func _combat_arm() -> void:
	var ghost := _active_ghost()
	var ghost_pos: Vector3 = (ghost as Node3D).global_position
	if _phase == Phase.COMBAT_ARM_1:
		_merc_fixture = _make_merc_fixture("m_slice_combat1",
			ghost_pos + COMBAT_OFFSET, 100000, 30)
		_enter(Phase.COMBAT_WAIT_1)
	else:
		_merc_fixture2 = _make_merc_fixture("m_slice_combat2",
			ghost_pos + COMBAT_OFFSET, 100000, 30)
		_enter(Phase.COMBAT_WAIT_2)


## 현재 사이클의 활성 ghost(1차=_ghost, 2차=_ghost2).
func _active_ghost() -> Node:
	if _phase == Phase.COMBAT_WAIT_2 or _phase == Phase.COMBAT_ARM_2 \
			or _phase == Phase.GHOST_DEATH_WAIT_2 or _phase == Phase.GHOST_CLEANUP_WAIT_2:
		return _ghost2
	return _ghost


func _combat_wait() -> void:
	_wait += 1
	var ghost := _active_ghost()
	var ghost_attacking: bool = ghost != null and is_instance_valid(ghost) \
		and (ghost as Node).get("alive") == true \
		and (ghost as Node).get("state") == 2  # EnemyActor3D.EnemyState.ATTACK
	var merc := _merc_fixture if _phase == Phase.COMBAT_WAIT_1 else _merc_fixture2
	var damaged: bool = merc != null and is_instance_valid(merc) \
		and (merc as Node).get("current_hp") < 100000
	if (not ghost_attacking or not damaged) and _wait <= OBSERVE_BUDGET:
		return
	_wait = 0
	_check(ghost_attacking,
		"ghost auto-combat engages the nearby mercenary (EnemyState.ATTACK)")
	_check(damaged, "ghost deals combat damage to the mercenary")
	_check(_poll_enemy_targets_safe(), "enemy/ghost targets only mercenaries_3d (no player combat)")
	_enter(Phase.GHOST_DEATH_WAIT_1 if _phase == Phase.COMBAT_WAIT_1 \
		else Phase.GHOST_DEATH_WAIT_2)


## -- 시나리오 7: Ghost lethal death. combat 상대(Mercenary, attack 30)가 ghost를
## 실제 공격으로 사망시킨다(real combat lethal path, 결정성 유지). --
func _ghost_death_wait() -> void:
	_wait += 1
	var ghost := _active_ghost()
	var died: bool = ghost == null or not is_instance_valid(ghost) \
		or (ghost as Node).get("alive") == false
	if not died and _wait <= OBSERVE_BUDGET * 2:
		return
	_wait = 0
	_check(died, "ghost dies to lethal combat damage")
	_enter(Phase.NO_RECURSION_1 if _phase == Phase.GHOST_DEATH_WAIT_1 \
		else Phase.NO_RECURSION_2)


## -- 시나리오 8 이후: ghost death → candidate 재귀 생성 없음. --
func _no_recursion_check() -> void:
	var expected := 1 if _phase == Phase.NO_RECURSION_1 else 2
	_check(_ghost_return.get_candidate_count() == expected,
		"ghost death adds no new candidate (recursion guard, count=%d)"
			% _ghost_return.get_candidate_count())
	_check(_ghost_return.get_eligible_candidates().size() == 0,
		"no new eligible candidate after ghost death")
	_check(_ledger.get_all_records().size() == expected,
		"ghost death creates no new ledger record (count=%d)" % _ledger.get_all_records().size())
	_enter(Phase.GHOST_CLEANUP_WAIT_1 if _phase == Phase.NO_RECURSION_1 \
		else Phase.GHOST_CLEANUP_WAIT_2)


## ghost fade-out + queue_free 이후 freed reference 검증.
func _ghost_cleanup_wait() -> void:
	_wait += 1
	if _wait < DEATH_CLEANUP_BUDGET:
		return
	_wait = 0
	var ghost_ref := _active_ghost()
	_check(ghost_ref == null or not is_instance_valid(ghost_ref),
		"dead ghost is freed (no stale runtime reference)")
	_check(_spawner.get_ghost_count() == 0, "spawner no longer tracks the dead ghost")
	_enter(Phase.TO_DAY_1 if _phase == Phase.GHOST_CLEANUP_WAIT_1 else Phase.TO_DAY_3)


func _to_day_1() -> void:
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "phase returned to DAY")
	_enter(Phase.DAY_VERIFY_1)


func _day_verify_1() -> void:
	_check(_spawner.get_ghost_count() == 0,
		"DAY return has no remaining ghost (cleanup, no record)")
	_check(get_nodes_in_group("enemies_3d").size() == 0, "no enemy residue on DAY")
	_check(_ledger.get_all_records().size() == 1,
		"DAY cleanup creates no death records")
	# 1차 사이클 combat fixture 정리(cleanup → record 없음).
	if _merc_fixture != null and is_instance_valid(_merc_fixture):
		_merc_fixture.queue_free()
	_enter(Phase.REPEAT_NIGHT_WAIT)


## -- 다음 NIGHT 반복: 소모된 candidate가 재spawn되지 않음(duplicate spawn 없음). --
func _repeat_night_wait() -> void:
	if _wait == 0:
		_game_time.advance(_game_time.day_duration)
		_check(_game_time.get_phase() == GameTime.Phase.NIGHT,
			"next NIGHT begins (repeat cycle)")
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.NO_DUPLICATE_NIGHT)


func _no_duplicate_night() -> void:
	_check(_spawner.get_ghost_count() == 0,
		"consumed candidate does NOT respawn on the next NIGHT (no duplicate spawn)")
	_check(get_nodes_in_group("enemies_3d").size() == 0,
		"no duplicate ghost actor in enemies_3d")
	_enter(Phase.TO_DAY_2)


func _to_day_2() -> void:
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "back to DAY")
	_enter(Phase.MERC_DEATH)


## -- 2차 사이클: 실제 Mercenary lethal death(다음 DAY/NIGHT 반복). --
func _merc_death() -> void:
	if _wait == 0:
		_merc_data = MercenaryData.new(_merc_uid, "Blade")
		_merc_data.max_hp = 150
		_merc_data.attack_damage = 20
		_merc_data.attack_interval = 1.0
		_merc_data.move_speed = 120.0
		var merc: Node = (load("res://scenes/mercenary_3d.tscn") as PackedScene).instantiate()
		merc.merc_data = _merc_data
		merc.position = MERC_POS
		_world.add_child(merc)
		merc.died.connect(_on_tracked_died)
		_merc_victim = merc
	_wait += 1
	if _wait < 4:
		return
	_wait = 0
	if _merc_victim != null and is_instance_valid(_merc_victim):
		_merc_victim.take_damage(9999)
	_check(_merc_victim != null and is_instance_valid(_merc_victim)
		and (_merc_victim as Node).get("alive") == false,
		"mercenary takes lethal combat damage and dies")
	_enter(Phase.LEDGER_VERIFY_2)


func _ledger_verify_2() -> void:
	_check(_count_records_for(_merc_uid) == 1,
		"original mercenary death record exactly 1 (%d)" % _count_records_for(_merc_uid))
	_check(_ledger.get_all_records().size() == 2,
		"ledger holds exactly the 2 original records (%d)" % _ledger.get_all_records().size())
	_check(_ghost_return.get_candidate_count() == 2,
		"2 distinct lethal deaths -> 2 candidates (%d)" % _ghost_return.get_candidate_count())
	_check(_ghost_return.get_eligible_candidates().size() == 1,
		"only the new mercenary candidate is eligible")
	var rec := _record_for(_merc_uid)
	if rec != null:
		_check(rec.is_ghost == false, "mercenary record is NORMAL")
		_check(rec.source_kind == DeathRecord.SourceKind.MERCENARY,
			"mercenary record kind is MERCENARY")
		_check(rec.max_hp == 150, "mercenary record preserves combat max_hp")
		_merc_record_id = rec.record_id
	_enter(Phase.TO_NIGHT_2)


func _to_night_2() -> void:
	_game_time.advance(_game_time.day_duration)
	_check(_game_time.get_phase() == GameTime.Phase.NIGHT, "second NIGHT begins")
	_enter(Phase.GHOST_SPAWN_WAIT_2)


func _spawn_verify_2() -> void:
	_check(_spawner.get_ghost_count() == 1,
		"second NIGHT spawns exactly 1 ghost from the mercenary candidate")
	_check(get_nodes_in_group("enemies_3d").size() == 1,
		"exactly 1 ghost actor in enemies_3d (no duplicate actor)")
	var ghosts: Array[Node] = _spawner.get_ghosts()
	if ghosts.size() > 0:
		_ghost2 = ghosts[0]
		if not (_ghost2 as Node).died.is_connected(_on_tracked_died):
			(_ghost2 as Node).died.connect(_on_tracked_died)
		_check((_ghost2 as Node).get("enemy_id") == "ghost_%s" % _merc_record_id,
			"mercenary ghost has deterministic enemy_id")
		_check((_ghost2 as Node).get("source_uid") == _merc_uid,
			"mercenary ghost tracks original source_uid")
		_check((_ghost2 as Node).get("ghost_kind") == DeathRecord.SourceKind.MERCENARY,
			"mercenary ghost tracks MERCENARY kind")
		_check((_ghost2 as Node).get("max_hp") == 150,
			"mercenary ghost reuses original max_hp")
		_check(_ghost1_enemy_id != str((_ghost2 as Node).get("enemy_id")),
			"ghost actors have distinct enemy_id (no duplicate actor)")
	_check(_ghost_return.is_consumed(_merc_record_id),
		"mercenary candidate consumed after spawn")
	_check(_ghost_return.get_eligible_candidates().size() == 0,
		"no eligible candidate remains after second spawn")
	_enter(Phase.COMBAT_ARM_2)


func _to_day_3() -> void:
	_game_time.advance(_game_time.night_duration)
	_check(_game_time.get_phase() == GameTime.Phase.DAY, "final phase returned to DAY")
	_enter(Phase.FINAL_CHECK)


func _final_check() -> void:
	# 남은 fixture 정리를 먼저 수행하고(cleanup, record 없음), queue_free 적용 후
	# 그룹/참조 최종 검증을 수행한다.
	if _wait == 0:
		if _merc_fixture2 != null and is_instance_valid(_merc_fixture2):
			_merc_fixture2.queue_free()
	_wait += 1
	if _wait < 8:
		return
	_wait = 0
	# freed reference 없음: spawner 추적 목록에 invalid instance가 없어야 한다.
	var stale := false
	for g in _spawner.get_ghosts():
		if not is_instance_valid(g):
			stale = true
	_check(not stale, "spawner ghost list holds no freed/invalid references")
	_check(get_nodes_in_group("enemies_3d").size() == 0, "no enemy residue at the end")
	_check(get_nodes_in_group("mercenaries_3d").size() == 0,
		"no orphan mercenary actor remains at the end")
	_check(get_nodes_in_group("player").size() == 0,
		"no runtime player Actor (no direct combat)")
	# Death Ledger 기존 기능 회귀: 상태 전환/조회 API가 여전히 동작한다.
	_check(_ledger.has_record_for_source(_enemy_uid),
		"Death Ledger has_record_for_source still works")
	_check(_ledger.mark_active(_enemy_record_id), "Death Ledger mark_active still works")
	_check(_ledger.resolve(_enemy_record_id, _game_time.get_day_number()),
		"Death Ledger resolve still works")
	var resolved: Array = _ledger.get_resolved_records()
	_check(resolved.size() >= 1, "resolved record query still works")
	_check(_ledger.get_all_records().size() == 2,
		"ledger retains exactly the 2 original records (%d)" % _ledger.get_all_records().size())
	_check(_ghost_return.get_candidate_count() == 2,
		"candidates retained across the full vertical slice (%d)"
			% _ghost_return.get_candidate_count())
	_check(_deaths_total == 4,
		"observed lethal deaths = 4 (enemy + ghost + mercenary + ghost2, got %d)"
			% _deaths_total)
	_enter(Phase.DONE)


func _count_records_for(uid: String) -> int:
	var n := 0
	for record in _ledger.get_all_records():
		if record.source_uid == uid:
			n += 1
	return n


func _record_for(uid: String) -> DeathRecord:
	for record in _ledger.get_all_records():
		if record.source_uid == uid:
			return record
	return null


func _make_merc_fixture(id: String, pos: Vector3, hp: int, atk: int) -> Node:
	var data := MercenaryData.new(id, "Defender")
	data.max_hp = hp
	data.attack_damage = atk
	data.attack_interval = 1.0
	data.move_speed = 120.0
	var merc: Node = (load("res://scenes/mercenary_3d.tscn") as PackedScene).instantiate()
	merc.merc_data = data
	merc.position = pos
	_world.add_child(merc)
	return merc


## 모든 살아 있는 Enemy/Ghost가 target으로 가지는 것은 살아 있는 mercenaries_3d뿐인지
## 확인한다(Player combat 없음, stale/freed reference 없음).
func _poll_enemy_targets_safe() -> bool:
	for e in get_nodes_in_group("enemies_3d"):
		if not is_instance_valid(e):
			continue
		var target: Variant = e.get("_target")
		if target != null:
			if not is_instance_valid(target):
				return false
			if not (target as Node).is_in_group("mercenaries_3d"):
				return false
	return true


func _on_tracked_died(_actor: Node) -> void:
	_deaths_total += 1
