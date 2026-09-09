extends SceneTree

## V4-003 Exact Dungeon Combat Outcome 검증.
## - depart() -> run_started -> begin_run(신호 실경로)으로 dungeon run을 자동 시작한다.
## - 같은 프레임(physics tick 없음)에 살아 있는 적 전원을 take_damage로 제거하면
##   evaluate_outcome()이 run당 정확히 1회 "VICTORY"를 해소하고 dungeon CLEARED /
##   completion_count 1 / WaveManager dungeon clear 적용(applied size 1) / last_outcome
##   VICTORY / 2차 evaluate_outcome()=="" / phase RESOLVED 경유 IDLE 복귀를 검증한다.
## - CLEARED -> READY 재진입(depart 2회차) 후 같은 프레임에 파티 전원 사망 ->
##   evaluate_outcome() "DEFEAT", dungeon FAILED / completion_count 유지(1) /
##   dungeon clear 재적용 없음(size 불변 1) / MERCENARY Death Ledger 2건(source_uid
##   고유) / run당 1회 run_outcome emit(VICTORY -> DEFEAT 순)을 검증한다.
## - Death Ledger: VICTORY run의 적 3명은 ENEMY(3건), DEFEAT run의 파티 2명은
##   MERCENARY(2건). cleanup(이동 레코드 없음)이 아니라 lethal combat death로만 기록.
## - 자동전투/타이머 간섭을 배제하기 위해 kill/evaluate는 depart 직후 같은
##   _process 틱에서(physics frame 이전) 동기적으로 수행한다. queue_free flush만
##   재진입 전에 FLUSH_FRAMES만큼 대기한다.
## - V3+ 기존 패턴(task0273)과 동일하게 autoload는 root.get_node_or_null로 조회한다.
## - NOTE: standalone `-s` 모드에서는 autoload 이름 식별자(DungeonManager 등)가
##   entry-script 컴파일 시점에 미등록이라, dungeon_runtime.gd를 compile-time에
##   끌어들이는 DungeonRuntime.RunPhase/Outcome 참조는 사용하지 않는다. 해당 enum은
##   런타임 동적 call로만 접근하고, 아래는 소스에서 확인한 contiguous enum literal이다.
##   RunPhase: IDLE=0 DEPLOYMENT=1 COMBAT=2 RESOLVED=3
##   Outcome : NONE=0 VICTORY=1 DEFEAT=2
##   DungeonState: DISCOVERED=0 READY=1 IN_PROGRESS=2 CLEARED=3 FAILED=4

const DUNGEON_ID := "ne_ruins"
const DYNAMIC_RUNTIME_SCRIPT := "res://scripts/dungeon_runtime.gd"

## 시작 전 settle frame(autoload/_ready 대기).
const SETTLE_FRAMES := 3
## queue_free flush 대기(재진입 전 arena 정리).
const FLUSH_FRAMES := 10

var _frame := 0
var _failures := 0
var _checks := 0
var _stage := 0

var _runtime: Node = null
var _rt_script: GDScript = null
var _dungeon_manager: Node = null
var _prep_manager: Node = null
var _roster: Node = null
var _ledger: Node = null
var _wave_manager: Node = null

var _run_outcomes: Array = []
var _phase_changed_to: Array = []

var _phase_idle := -1
var _phase_deployment := -1
var _phase_combat := -1
var _phase_resolved := -1
var _outcome_victory := -1
var _outcome_defeat := -1

var _stage3_start := -1


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failures += 1


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 800:
		print("V4003_RESULT=TIMEOUT")
		quit()
		return true
	match _stage:
		0:
			if _frame < SETTLE_FRAMES:
				return false
			_stage = 1
			_run_setup_and_victory()
			return false
		1:
			# VICTORY 해소 후 queue_free flush(재진입 전 arena/actor 정리 대기).
			if _frame_of_stage1 < 0:
				_frame_of_stage1 = _frame
				return false
			if _frame < _frame_of_stage1 + FLUSH_FRAMES:
				return false
			_stage = 2
			_run_defeat()
			return false
		2:
			_check(_runtime.is_run_active() == false, \
				"runtime inactive after defeat resolution")
			_check(_runtime.get_phase() == _phase_idle, \
				"phase back to IDLE after defeat resolution")
			_stage = 3
			return false
		3:
			_run_final_checks()
			_stage = 4
			return false
		_:
			_finish()
			return true


var _frame_of_stage1 := -1


func _on_run_outcome(outcome: int, _dungeon_id: String) -> void:
	_run_outcomes.append(outcome)


func _on_phase_changed(_from: int, to: int) -> void:
	_phase_changed_to.append(to)


func _run_setup_and_victory() -> void:
	_dungeon_manager = root.get_node_or_null("DungeonManager")
	_prep_manager = root.get_node_or_null("DungeonPreparationManager")
	_roster = root.get_node_or_null("MercenaryRoster")
	_ledger = root.get_node_or_null("DeathLedger")
	_wave_manager = root.get_node_or_null("WaveManager")
	_check(_dungeon_manager != null and _prep_manager != null and _roster != null \
		and _ledger != null and _wave_manager != null, \
		"dungeon managers + roster + ledger + wave autoloads present")

	var game_time := root.get_node_or_null("GameTime")
	var threat := root.get_node_or_null("ThreatSystem")
	if game_time != null and game_time.has_method("set_auto_advance"):
		game_time.set_auto_advance(false)
	if threat != null and threat.has_method("set_auto_grow"):
		threat.set_auto_grow(false)
	if _wave_manager != null and _wave_manager.has_method("reset"):
		_wave_manager.reset()

	_rt_script = load(DYNAMIC_RUNTIME_SCRIPT)
	_check(_rt_script != null, "DungeonRuntime script loads at runtime (autoload scope)")
	if _rt_script != null:
		var phase_map: Dictionary = _rt_script.get("RunPhase")
		var outcome_map: Dictionary = _rt_script.get("Outcome")
		_phase_idle = phase_map["IDLE"]
		_phase_deployment = phase_map["DEPLOYMENT"]
		_phase_combat = phase_map["COMBAT"]
		_phase_resolved = phase_map["RESOLVED"]
		_outcome_victory = outcome_map["VICTORY"]
		_outcome_defeat = outcome_map["DEFEAT"]
	_check(_phase_idle == 0 and _phase_combat == 2 and _outcome_victory == 1 \
		and _outcome_defeat == 2, "runtime enum cache matches source literals (RunPhase/Outcome)")
	_runtime = _rt_script.new()
	root.add_child(_runtime)
	_check(_runtime != null and is_instance_valid(_runtime), \
		"dynamic DungeonRuntime node wired into tree (run_started auto-connect)")
	_runtime.run_outcome.connect(_on_run_outcome)
	_runtime.phase_changed.connect(_on_phase_changed)

	_check(_dungeon_manager.create_dungeon(DUNGEON_ID) != null, "create dungeon instance")
	_check(_prep_manager.create_preparation(DUNGEON_ID), "create dungeon preparation")
	var m_a := MercenaryData.new("v4003_m1", "V4003 Merc A", \
		MercenaryData.MercClass.SWORDSMAN)
	var m_b := MercenaryData.new("v4003_m2", "V4003 Merc B", \
		MercenaryData.MercClass.SWORDSMAN)
	_check(_roster.add_mercenary(m_a), "roster add v4003_m1")
	_check(_roster.add_mercenary(m_b), "roster add v4003_m2")
	_check(_prep_manager.add_member(DUNGEON_ID, "v4003_m1")["ok"], "prep add v4003_m1")
	_check(_prep_manager.add_member(DUNGEON_ID, "v4003_m2")["ok"], "prep add v4003_m2")

	# depart() → run_started → begin_run(자동, 동기). physics tick 전에 진행된다.
	var dep: Dictionary = _prep_manager.depart(DUNGEON_ID)
	_check(dep.get("ok", false), "valid party departs (run_started emitted)")
	_check(_runtime.is_run_active(), "runtime reports run active after depart")
	_check(_dungeon_manager.get_dungeon_state(DUNGEON_ID) \
		== DungeonDefinition.DungeonState.IN_PROGRESS, "dungeon state IN_PROGRESS")
	_check(_runtime.get_phase() == _phase_combat, \
		"phase COMBAT (3 alive enemies) after auto begin_run")

	_check(_runtime.get_alive_party_count() == 2, "2 party actors alive")
	_check(_runtime.get_alive_enemy_count() == 3, "3 enemies spawned from encounter data")
	_check(_runtime.evaluate_outcome() == "", \
		"no premature resolution while both sides alive")

	# 같은 프레임(physics tick 이전)에 적 전원 lethal damage → 1차 해소.
	_kill_alive_enemies()
	_check(_runtime.get_alive_enemy_count() == 0, "all enemies killed by damage")
	_check(_runtime.evaluate_outcome() == "VICTORY", \
		"evaluate_outcome resolves VICTORY (enemies 0, party alive)")
	_check(_runtime.get_last_outcome() == _outcome_victory, \
		"get_last_outcome returns VICTORY")
	_check(_runtime.get_last_outcome_name() == "VICTORY", \
		"get_last_outcome_name returns VICTORY")
	_check(_dungeon_manager.get_dungeon_state(DUNGEON_ID) \
		== DungeonDefinition.DungeonState.CLEARED, "dungeon state CLEARED after victory")
	_check(_dungeon_manager.get_completion_count(DUNGEON_ID) == 1, \
		"completion_count incremented exactly once (1)")
	_check(_wave_manager.is_dungeon_clear_applied(DUNGEON_ID), \
		"WaveManager dungeon clear applied for this run")
	var snap: Dictionary = _wave_manager.get_wave_snapshot()
	_check((snap.get("applied_dungeon_clears", []) as Array).size() == 1, \
		"wave snapshot applied_dungeon_clears size 1")
	_check(_runtime.evaluate_outcome() == "", \
		"second evaluate_outcome returns empty (run resolves exactly once)")
	_check(_runtime.is_run_active() == false, "runtime inactive after victory resolution")
	_check(_runtime.get_phase() == _phase_idle, \
		"phase IDLE after victory (RESOLVED이 관찰됨)")


func _run_defeat() -> void:
	# 재진입 준비: CLEARED -> READY(ALLOWED_TRANSITIONS) 후 preparation 재구성.
	_check(_dungeon_manager.mark_ready(DUNGEON_ID), "mark_ready allows CLEARED -> READY")
	_check(_dungeon_manager.get_dungeon_state(DUNGEON_ID) \
		== DungeonDefinition.DungeonState.READY, "dungeon state READY")
	_check(_prep_manager.clear_preparation(DUNGEON_ID), "clear preparation for re-entry")
	_check(_prep_manager.create_preparation(DUNGEON_ID), \
		"recreate dungeon preparation (2nd run)")
	_check(_prep_manager.add_member(DUNGEON_ID, "v4003_m1")["ok"], \
		"re-add v4003_m1 (available again after CLEARED)")
	_check(_prep_manager.add_member(DUNGEON_ID, "v4003_m2")["ok"], \
		"re-add v4003_m2 (available again after CLEARED)")

	var dep: Dictionary = _prep_manager.depart(DUNGEON_ID)
	_check(dep.get("ok", false), "valid party departs again (re-entry run)")
	_check(_runtime.is_run_active(), "runtime reports 2nd run active")
	_check(_dungeon_manager.get_dungeon_state(DUNGEON_ID) \
		== DungeonDefinition.DungeonState.IN_PROGRESS, "dungeon state IN_PROGRESS (2nd run)")
	_check(_runtime.get_phase() == _phase_combat, \
		"phase COMBAT on 2nd run")
	_check(_runtime.get_alive_party_count() == 2, "2 party actors alive (2nd run)")
	_check(_runtime.get_alive_enemy_count() == 3, "3 enemies alive (2nd run)")
	_check(_runtime.evaluate_outcome() == "", \
		"no premature resolution before party wipe")

	# 같은 프레임(physics tick 이전)에 파티 전원 lethal damage → 2차 해소.
	_kill_alive_party()
	_check(_runtime.get_alive_party_count() == 0, "all party actors killed by damage")
	_check(_runtime.evaluate_outcome() == "DEFEAT", \
		"evaluate_outcome resolves DEFEAT (party 0, enemies alive)")
	_check(_dungeon_manager.get_dungeon_state(DUNGEON_ID) \
		== DungeonDefinition.DungeonState.FAILED, "dungeon state FAILED after defeat")
	_check(_dungeon_manager.get_completion_count(DUNGEON_ID) == 1, \
		"completion_count unchanged on defeat (1)")
	var snap: Dictionary = _wave_manager.get_wave_snapshot()
	_check((snap.get("applied_dungeon_clears", []) as Array).size() == 1, \
		"no dungeon clear applied on defeat (applied size stays 1)")
	_check(_wave_manager.is_dungeon_clear_applied(DUNGEON_ID), \
		"previous CLEARED reward remains applied (idempotent)")
	_check(_runtime.get_last_outcome() == _outcome_defeat, \
		"get_last_outcome returns DEFEAT after 2nd run")
	_check(_runtime.get_last_outcome_name() == "DEFEAT", \
		"get_last_outcome_name returns DEFEAT")
	_check(_runtime.evaluate_outcome() == "", \
		"second evaluate_outcome returns empty after defeat")


func _run_final_checks() -> void:
	_check(_run_outcomes.size() == 2, "run_outcome emitted exactly once per run (2 total)")
	_check(_run_outcomes.size() >= 1 \
		and _run_outcomes[0] == _outcome_victory, \
		"first run_outcome is VICTORY")
	_check(_run_outcomes.size() >= 2 \
		and _run_outcomes[1] == _outcome_defeat, \
		"second run_outcome is DEFEAT")

	# phase 전이 히스토리: run1 DEPLOYMENT->COMBAT->RESOLVED->IDLE, run2 동일.
	var expected_tos: Array = []
	for _i in 2:
		expected_tos.append(_phase_deployment)
		expected_tos.append(_phase_combat)
		expected_tos.append(_phase_resolved)
		expected_tos.append(_phase_idle)
	_check(_phase_changed_to == expected_tos, \
		"observed phase transitions DEPLOYMENT->COMBAT->RESOLVED->IDLE per run")

	# Death Ledger: VICTORY 3 ENEMY + DEFEAT 2 MERCENARY, 모두 lethal combat death.
	var merc_source_uids: Array = []
	var enemy_ids_used := {}
	var counts := {"MERCENARY": 0, "ENEMY": 0}
	for record in _ledger.get_all_records():
		var cat: String = record.get_category()
		if cat == "MERCENARY":
			counts["MERCENARY"] += 1
			merc_source_uids.append(record.source_uid)
		elif cat == "ENEMY":
			counts["ENEMY"] += 1
			enemy_ids_used[record.source_uid] = true
	_check(counts["MERCENARY"] == 2, \
		"DeathLedger records exactly 2 MERCENARY deaths")
	var sorted_uids := merc_source_uids.duplicate()
	sorted_uids.sort()
	_check(sorted_uids == ["v4003_m1", "v4003_m2"], \
		"MERCENARY deaths have distinct source_uids (party wiped by combat)")
	_check(counts["ENEMY"] == 3, \
		"DeathLedger records exactly 3 ENEMY deaths (victory combat kills)")


func _kill_alive_enemies() -> void:
	var to_kill: Array = []
	for e in get_nodes_in_group("enemies_3d"):
		if e != null and is_instance_valid(e) and e.get("alive") == true:
			to_kill.append(e)
	for e in to_kill:
		if is_instance_valid(e):
			e.take_damage(999999)


func _kill_alive_party() -> void:
	var actors: Array = _runtime.get_alive_party_actor_nodes()
	for a in actors:
		if a != null and is_instance_valid(a):
			a.take_damage(999999)


func _finish() -> void:
	var passed := _checks - _failures
	print("V4003_ASSERTIONS=%d/%d" % [passed, _checks])
	print("V4003_RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)


func _initialize() -> void:
	pass