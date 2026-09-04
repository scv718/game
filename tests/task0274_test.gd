extends SceneTree

## TASK-027-4 Dungeon Encounter 재사용 전투(Auto Combat + Tactical Command) 검증.
## - [재사용] begin_run 후 파티가 ENCOUNTER_RALLY로 진군해 기존 Mercenary auto combat
##   (target 획득/추격/공격/death) 만으로 enemy와 교전한다(신규 전투 런타임 없음).
## - [tactical] dungeon 파티에 FOCUS_TARGET/REGROUP/RETREAT 명령을 내리면 기존 Actor
##   command(적극 활성화)로 반응한다: focus 부여/해제 토글, REGROUP 상태, RETREAT 상태
##   + dungeon 전용 safe rally로 후퇴.
## - [edge] enemy 전멸 후 stale target(freed/death) 정리 → 파티 IDLE, zombie chase 없음.
## - [충돌 없음] 해당 명령은 dungeon 파티(mercenaries_3d)만 대상 → Overworld roster3D
##   focus_mode 변경 없음. Player는 runtime Actor로 생성되지 않는다(direct attack 불가).
## - [회귀] cleanup(Death Ledger 무기록)/dungeon state 유지/3D main 구조 유지.

const DUNGEON_ID := "ne_ruins"

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const ARENA_SCENE_PATH := "res://scenes/dungeon_arena_3d.tscn"

## precondition 세팅에 필요한 settle physics frame(arena nav bake 대기 포함 여유).
const SETTLE_FRAMES := 60
## queue_free가 실제로 node를 해제할 때까지의 physics frame.
const FLUSH_FRAMES := 10
## 자동전투 시작(진군/첫 피격)을 기다리는 최대 frame.
const COMBAT_MAX_FRAMES := 600
## 전술 명령 검증: 명령 후 반영 대기 frame.
const TACTICAL_WAIT_FRAMES := 4
## enemy 전멸을 기다리는 최대 frame(진군+공격+재교전 여유).
const KILL_MAX_FRAMES := 1500
## 전멸 후 stale target 정리/IDLE 정착 대기 frame.
const IDLE_SETTLE_FRAMES := 60

var _frame := 0
var _failed := false
var _stage := 0
var _tstep := 0
var _stage_start := 0

var _main: Node = null
var _world: Node = null
var _runtime: Node = null
var _dungeon_manager: Node = null
var _prep_manager: Node = null
var _roster: Node = null
var _ledger: Node = null
var _ledger_baseline := -1
var _roster3d: Node = null

var _spawn_positions: Dictionary = {}
var _engaged_reported := false
var _all_enemies_dead := false

var _frame_of_stage2 := -1
var _removed_count := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 2600:
		print("TASK0274_RESULT=TIMEOUT")
		quit()
		return true
	match _stage:
		0:
			if _frame < SETTLE_FRAMES:
				return false
			_stage = 1
			_run_setup()
			return false
		1:
			_run_spawn_checks()
			_stage = 2
			_stage_start = _frame
			return false
		2:
			_check_combat_engaged()
			if not _engaged_reported and _frame < _stage_start + COMBAT_MAX_FRAMES:
				return false
			_stage = 3
			_tstep = 1
			_stage_start = _frame
			_runtime.apply_tactical_command(TacticalCommandUI.Command.REGROUP)
			return false
		3:
			_tick_tactical()
			if _tstep <= 5:
				return false
			_stage = 4
			_stage_start = _frame
			return false
		4:
			if not _all_enemies_dead and _frame < _stage_start + KILL_MAX_FRAMES:
				_all_enemies_dead = _runtime.get_alive_enemy_count() == 0
				return false
			_check(_all_enemies_dead, "encounter enemies all cleared by auto combat")
			_stage = 5
			_stage_start = _frame
			return false
		5:
			if _frame < _stage_start + IDLE_SETTLE_FRAMES:
				return false
			_check_idle_and_stale_cleanup()
			_stage = 6
			_frame_of_stage2 = _frame
			_removed_count = _runtime.end_run()
			return false
		6:
			if _frame < _frame_of_stage2 + FLUSH_FRAMES:
				return false
			_stage = 7
			_run_cleanup_checks()
			return false
		7:
			_run_final_checks()
			_stage = 8
			return false
		_:
			print("TASK0274_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true


func _run_setup() -> void:
	_check(load(ARENA_SCENE_PATH) != null, "dungeon_arena_3d.tscn exists and loads")
	_main = root.get_node("Main3D")
	_check(_main != null, "main_3d.tscn loads as Main3D")
	_world = _main.get_node("World3D")
	_check(_world != null, "World3D present in main_3d")
	var runtime_nodes := get_nodes_in_group("dungeon_runtime")
	_check(runtime_nodes.size() == 1, "exactly one DungeonRuntime in the scene (no duplicate arena)")
	_runtime = runtime_nodes[0]
	_check(_runtime != null and is_instance_valid(_runtime), "DungeonRuntime wired and valid")

	_dungeon_manager = root.get_node_or_null("DungeonManager")
	_prep_manager = root.get_node_or_null("DungeonPreparationManager")
	_roster = root.get_node_or_null("MercenaryRoster")
	_ledger = root.get_node_or_null("DeathLedger")
	_check(_dungeon_manager != null and _prep_manager != null and _roster != null \
		and _ledger != null, "dungeon managers + roster + ledger autoloads present")
	_ledger_baseline = _ledger.get_all_records().size()
	var roster3d_nodes := get_nodes_in_group("mercenary_roster_3d")
	_check(roster3d_nodes.size() >= 1, "Overworld MercenaryRoster3D present (no-op 대상)")
	_roster3d = roster3d_nodes[0]

	# dungeon + preparation + roster(identity) 준비
	_check(_dungeon_manager.create_dungeon(DUNGEON_ID) != null, "create dungeon instance")
	_check(_prep_manager.create_preparation(DUNGEON_ID), "create dungeon preparation")
	var m_a := MercenaryData.new("merc_A", "Merc A", MercenaryData.MercClass.SWORDSMAN)
	var m_b := MercenaryData.new("merc_B", "Merc B", MercenaryData.MercClass.SWORDSMAN)
	_check(_roster.add_mercenary(m_a), "roster add merc_A")
	_check(_roster.add_mercenary(m_b), "roster add merc_B")
	_check(_prep_manager.add_member(DUNGEON_ID, "merc_A")["ok"], "prep add merc_A")
	_check(_prep_manager.add_member(DUNGEON_ID, "merc_B")["ok"], "prep add merc_B")
	# depart -> IN_PROGRESS
	var dep: Dictionary = _prep_manager.depart(DUNGEON_ID)
	_check(dep.get("ok", false), "valid party departs (dungeon IN_PROGRESS)")
	_check(_dungeon_manager.get_dungeon_state(DUNGEON_ID) \
		== DungeonDefinition.DungeonState.IN_PROGRESS, "dungeon state IN_PROGRESS")

	var started: bool = _runtime.begin_run(DUNGEON_ID)
	_check(started, "begin_run starts a clean encounter")
	_check(_runtime.is_run_active(), "runtime reports run active")
	_check(_runtime.get_dungeon_id() == DUNGEON_ID, "runtime dungeon_id set")
	_check(_runtime.get_arena() != null and is_instance_valid(_runtime.get_arena()), \
		"dungeon arena scene loaded on enter (scene load)")
	# 027-4: encounter 진군 앵커 적용(파티가 기존 auto combat으로 교전 디딤)
	var a: Node = _runtime.get_party_actor("merc_A")
	var b: Node = _runtime.get_party_actor("merc_B")
	_check(a != null and b != null, "party actors present after begin_run")
	_check(a.get("defense_point") == _runtime.get_encounter_rally() \
		and b.get("defense_point") == _runtime.get_encounter_rally(), \
		"party defense_point moved to encounter rally (auto combat 앵커)")
	_spawn_positions["merc_A"] = a.global_position
	_spawn_positions["merc_B"] = b.global_position


func _run_spawn_checks() -> void:
	# spawn 1회 (027-3 규약 유지)
	_check(_runtime.get_party_count() == 2, "party spawned for 2 identities (spawn 1회)")
	_check(_runtime.get_alive_party_count() == 2, "2 party actors alive")
	_check(_runtime.get_enemy_count() == 3, "3 enemies spawned from encounter data")
	_check(_runtime.get_alive_enemy_count() == 3, "3 enemies alive")
	var actor_a: Node = _runtime.get_party_actor("merc_A")
	var actor_b: Node = _runtime.get_party_actor("merc_B")
	_check(actor_a != null and actor_a is MercenaryActor3D, "merc_A spawned as MercenaryActor3D")
	_check(actor_b.get("merc_data") == _roster.get_mercenary("merc_B"), \
		"party actor carries persistent roster identity (MercenaryData)")
	# duplicate actor 없음 / 이중 begin_run 차단
	_runtime.spawn_party(["merc_A", "merc_B", "merc_A"])
	_check(_runtime.get_party_count() == 2, "duplicate identity spawn does not add actors")
	_check(_runtime.begin_run(DUNGEON_ID) == false, "begin_run guarded while active (no duplicate run)")
	# Player 없음: dungeon encounter는 Player 직접 공격 대상이 아니다
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor (direct attack 불가)")


func _check_combat_engaged() -> void:
	var hit := false
	var adv := false
	for e in _runtime.get_arena().get_children():
		if e is EnemyActor3D and is_instance_valid(e) and e.get("alive") != false:
			if e.get("current_hp") < e.get("max_hp"):
				hit = true
				break
	for m in [_runtime.get_party_actor("merc_A"), _runtime.get_party_actor("merc_B")]:
		if m == null or not is_instance_valid(m):
			continue
		var st: int = m.get_state()
		if st == MercenaryActor3D.MercState.MOVE_TO_TARGET \
				or st == MercenaryActor3D.MercState.ATTACK:
			adv = true
		var from: Vector3 = _spawn_positions.get(m.get_mercenary_id(), m.global_position)
		if WorldCoords3D.distance_xz(from, m.global_position) > 2.0:
			adv = true
	if (hit or adv) and not _engaged_reported:
		_engaged_reported = true
		_check(_frame < _stage_start + COMBAT_MAX_FRAMES, \
			"auto combat engaged via existing AI (진군/첫 피격)")
		_check(_runtime.get_party_count() == 2, "runtime tracks 2 party actors during combat")
		_check(_runtime.get_enemy_count() >= 1, "runtime still tracks encounter enemies")


func _tick_tactical() -> void:
	if _frame - _stage_start < TACTICAL_WAIT_FRAMES:
		return
	var alive: Array = _runtime.get_alive_party_actor_nodes()
	match _tstep:
		1:
			_check(_all_in_state(alive, MercenaryActor3D.MercState.REGROUP), \
				"REGROUP activates on dungeon party (기존 regroup 명령 재사용)")
		2:
			_check(_all_focus_valid(alive), \
				"FOCUS_TARGET assigns a valid alive enemy to dungeon party")
		3:
			_check(_all_focus_cleared(alive), \
				"FOCUS_TARGET re-command clears focus (stale focus 없음)")
		4:
			_check(_all_retreated(alive), \
				"RETREAT activates on dungeon party to dungeon safe rally")
	_tstep += 1
	if _tstep > 5:
		return
	# 다음 검증 명령 발행 (5 = 진군 재개용 reroute, 검증 없음)
	match _tstep:
		2:
			_runtime.apply_tactical_command(TacticalCommandUI.Command.FOCUS_TARGET)
		3:
			_runtime.apply_tactical_command(TacticalCommandUI.Command.FOCUS_TARGET)
		4:
			_runtime.apply_tactical_command(TacticalCommandUI.Command.RETREAT)
		5:
			_runtime.apply_tactical_command(TacticalCommandUI.Command.REGROUP)
	_stage_start = _frame


func _all_in_state(alive: Array, want: int) -> bool:
	if alive.size() != 2:
		return false
	for a in alive:
		if (a as MercenaryActor3D).get_state() != want:
			return false
	return true


func _all_focus_valid(alive: Array) -> bool:
	for a in alive:
		var ft: Node = (a as MercenaryActor3D).get_focus_target()
		if ft == null or not is_instance_valid(ft) or ft.get("alive") == false:
			return false
	return true


func _all_focus_cleared(alive: Array) -> bool:
	for a in alive:
		if (a as MercenaryActor3D).get_focus_target() != null:
			return false
	return true


func _all_retreated(alive: Array) -> bool:
	if alive.size() != 2:
		return false
	for a in alive:
		var md := a as MercenaryActor3D
		if md.get_state() != MercenaryActor3D.MercState.RETREAT:
			return false
		if md.get_retreat_point() != _runtime.get_retreat_safe_rally():
			return false
	return true


func _check_idle_and_stale_cleanup() -> void:
	# 전멸 후 stale target(freed/death) 정리: 파티가 영구 chase 없이 IDLE로 정착
	var alive: Array = _runtime.get_alive_party_actor_nodes()
	var idle := alive.size() == 2
	for a in alive:
		var md := a as MercenaryActor3D
		_check(md.get_target() == null or (is_instance_valid(md.get_target()) \
			and md.get_target().get("alive") != false), \
			"no stale/freed target held after enemy death")
		_check(md.get_focus_target() == null, "no stale focus target held after enemy death")
		var st: int = md.get_state()
		if st != MercenaryActor3D.MercState.IDLE \
				and st != MercenaryActor3D.MercState.ACQUIRE_TARGET:
			idle = false
	_check(idle, "party settles to IDLE after encounter cleared (영구 chase 없음)")
	_check(_runtime.get_alive_party_count() == 2, "party both alive after encounter")


func _run_cleanup_checks() -> void:
	# enemy는 전투(자동전투)로 사망해 추적에서 이미 제거됐고, end_run은 살아 있는
	# 파티(2)와 남은 enemy를 정리한다. enemy가 전부 전사했으므로 정리는 파티가 주체.
	_check(_removed_count >= 2, \
		"end_run cleaned living party actors (enemies died in combat): %d" % _removed_count)
	_check(_runtime.is_run_active() == false, "runtime inactive after end_run")
	_check(_runtime.get_party_count() == 0 and _runtime.get_enemy_count() == 0, \
		"runtime actor tracking cleared")
	_check(_runtime.get_arena() == null, "dungeon arena scene unloaded on exit (scene unload)")
	var returned: Array = ([] + _runtime.get_returned_alive_ids())
	returned.sort()
	_check(returned == ["merc_A", "merc_B"], "living party identities returned to roster")
	_check(_roster.get_mercenary("merc_A").alive and _roster.get_mercenary("merc_B").alive, \
		"roster identity remains alive (roster data 유지)")
	_check(_count_direct_enemy_children() == 0 and _count_direct_party_children() == 0, \
		"no orphan party/enemy actor under arena after flush")


func _run_final_checks() -> void:
	# 전투로 enemy 3마리가 사망한 기록만 추가돼야 하고, 파티(mercenary) 사망 기록은
	# 없어야 한다. (enemy 전투 사망 기록 = 기존 death handling이 정상 동작한 증거)
	var records: Array = _ledger.get_all_records()
	var added := records.size() - _ledger_baseline
	var merc_deaths := 0
	for i in range(_ledger_baseline, records.size()):
		if records[i].get("source_kind") == DeathRecord.SourceKind.MERCENARY:
			merc_deaths += 1
	_check(added == 3, "combat recorded exactly %d enemy deaths (ledger +3)" % added)
	_check(merc_deaths == 0, "no mercenary death records (party survived)")
	_dungeon_manager.complete_run(DUNGEON_ID)
	_dungeon_manager.mark_ready(DUNGEON_ID)
	_check(_runtime.begin_run(DUNGEON_ID) == false, \
		"begin_run rejected when dungeon not IN_PROGRESS (no illegal run)")
	_check(_dungeon_manager.get_dungeon(DUNGEON_ID) != null, "dungeon instance preserved")
	_check(_dungeon_manager.get_completion_count(DUNGEON_ID) == 1, \
		"completion_count incremented by complete_run (1)")
	_check(_world.get_node_or_null("Ground") != null, "World3D ground preserved")
	_check(get_nodes_in_group("player").size() == 0, "no runtime player Actor")
	if _roster3d != null and is_instance_valid(_roster3d):
		_check(_roster3d.get("focus_mode") == false, \
			"Overworld roster3D focus_mode untouched (우선순위 충돌 없음)")


func _count_direct_enemy_children() -> int:
	var arena: Node = _runtime.get_arena()
	if arena == null:
		return 0
	var n := 0
	for child in arena.get_children():
		if child is EnemyActor3D:
			n += 1
	return n


func _count_direct_party_children() -> int:
	var arena: Node = _runtime.get_arena()
	if arena == null:
		return 0
	var n := 0
	for child in arena.get_children():
		if child is MercenaryActor3D:
			n += 1
	return n


func _initialize() -> void:
	var scene: Node = load(MAIN_SCENE_PATH).instantiate()
	root.add_child(scene)
