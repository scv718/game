extends SceneTree

## TASK-026-3 Expedition Runtime / Time Progression 자동검증 테스트.
## GameTime 기반 OUTBOUND → EXPLORING → RETURNING → COMPLETED 구간 진행 owner를
## Actor 없이 headless로 검증한다. 상세 구현기록은
## impl_fun/TASK-026-3_EXPEDITION_RUNTIME.md 참고.
##
## 검증 contract:
##   1. deterministic time progression: 구간 duration에 따라 진행도/status 전환이 정확히
##      1회씩 발생한다(active expedition query 포함).
##   2. Pause/1x/2x 정책이 기존 GameTime 정의와 일치(동일 elapsed에서 배율만큼 곱해짐).
##   3. repeated DAY/NIGHT 반복에도 status 전환 duplicate가 없다.
##   4. frame-rate 독립: 대규모 delta 한 번(한 프레임)에도 전 구간을 순서대로 진행·완료.
##   5. reload/reconstruction: snapshot 복원 후 새 registry 등록으로 동일하게 완료.
##   6. 파견 중 member death hook: 아직 임의 death event를 만들지 않고 완료는 유지.

var _frame := 0
var _failed := false

var _roster: Node = null
var _game_time: Node = null
var _manager: ExpeditionManager = null
## [[expedition_id, from_status, to_status], ...] 전환 이벤트 누적.
var _phase_events: Array = []
var _completed_ids: Array = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 300:
		print("TASK0263_RESULT=TIMEOUT")
		quit()
		return true
	if _frame == 10:
		_run()
		return true
	return false


func _run() -> void:
	_roster = root.get_node_or_null("MercenaryRoster")
	_game_time = root.get_node_or_null("GameTime")
	_check(_game_time != null, "GameTime autoload available")
	_check(_roster != null, "MercenaryRoster autoload available")
	if _game_time == null or _roster == null:
		print("TASK0263_RESULT=FAIL")
		quit()
		return

	_game_time.set_auto_advance(false)
	_game_time.set_time_scale(1.0)
	_game_time.set_durations(60.0, 30.0)
	# TASK-022 adds a canonical roster cap. This long-form runtime test creates ten
	# independent fixtures, so provision the existing Inn owner instead of silently
	# overflowing the roster and misdiagnosing Expedition transitions.
	var inn_capacity := root.get_node_or_null("InnCapacity")
	if inn_capacity != null:
		while inn_capacity.can_upgrade():
			inn_capacity.upgrade()

	_manager = load("res://scripts/expedition_manager.gd").new()
	_manager.name = "ExpeditionManager"
	root.add_child(_manager)
	_manager.set_auto_advance(false)
	_manager.expedition_phase_changed.connect(_on_phase_changed)
	_manager.expedition_completed.connect(_on_completed)

	_test_deterministic_progression()
	_test_time_scale_policy()
	_test_pause_policy()
	_test_repeated_day_night_no_duplicate()
	_test_large_delta_single_frame()
	_test_reload_reconstruction()
	_test_active_query_and_registration()

	print("TASK0263_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _on_phase_changed(expedition_id: String, from_status: int, to_status: int) -> void:
	_phase_events.append([expedition_id, from_status, to_status])


func _on_completed(expedition_id: String) -> void:
	_completed_ids.append(expedition_id)


## 새 mercenary를 roster에 추가(각 섹션 간 겹침을 피하기 위해 고유 id 사용).
func _add_mercs(ids: Array) -> void:
	for id in ids:
		var m := MercenaryData.new(str(id), str(id))
		_roster.add_mercenary(m)


## READY Expedition 생성(편성 + 구간 duration 설정 + 출발). 사용 member는 미리 roster에 있어야 한다.
func _make_expedition(exp_id: String, member_ids: Array,
		out_dur: float, exp_dur: float, ret_dur: float) -> ExpeditionPartyData:
	var exp := _manager.create_expedition(exp_id, "ne_dungeon")
	_check(exp != null, "create expedition %s" % exp_id)
	for mid in member_ids:
		_check(_manager.add_member(exp_id, str(mid)), "member %s added to %s" % [mid, exp_id])
	exp.outbound_duration = out_dur
	exp.exploration_duration = exp_dur
	exp.return_duration = ret_dur
	_check(_manager.start_departure(exp_id, 1, 0.0, _roster), \
		"start departure %s" % exp_id)
	_check(exp.get_status() == ExpeditionPartyData.Status.OUTBOUND, \
		"%s departures to OUTBOUND" % exp_id)
	return exp


## 특정 expedition의 phase transition 이벤트를 [from, to] 쌍 목록으로 반환.
func _events_for(exp_id: String) -> Array:
	var out: Array = []
	for ev in _phase_events:
		if ev[0] == exp_id:
			out.append([ev[1], ev[2]])
	return out


func _transition_count_for(exp_id: String) -> int:
	return _events_for(exp_id).size()


func _count_occurrences(needle: String) -> int:
	var n := 0
	for id in _completed_ids:
		if id == needle:
			n += 1
	return n


## expected[[from,to],...]가 정확히 이 순서대로 1회씩 발생했는지.
func _check_transitions_exact(exp_id: String, expected: Array, msg: String) -> void:
	var got := _events_for(exp_id)
	var ok := got.size() == expected.size()
	if ok:
		for i in got.size():
			if got[i][0] != expected[i][0] or got[i][1] != expected[i][1]:
				ok = false
				break
	_check(ok, "%s (got=%s expected=%s)" % [msg, str(got), str(expected)])


## 해상 경로: OUTBOUND→EXPLORING→RETURNING→COMPLETED가 duration에 정확히 일치하는지.
func _test_deterministic_progression() -> void:
	_add_mercs(["d1", "d2"])
	_phase_events.clear()
	_completed_ids.clear()
	var exp := _make_expedition("exp_det", ["d1", "d2"], 10.0, 5.0, 2.0)

	_check(_manager.get_active_expeditions().size() == 1, \
		"active expedition query shows OUTBOUND expedition")
	_check(_manager.is_member_in_active_expedition("d1"), \
		"member reserved while expedition active")

	_manager.advance(5.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.OUTBOUND, \
		"still OUTBOUND after half outbound duration")
	_check(_approx(exp.progress, 0.5), "OUTBOUND progress 5/10 at 1x")

	_manager.advance(5.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.EXPLORING, \
		"OUTBOUND -> EXPLORING after full outbound duration")
	_check(_approx(exp.progress, 0.0), "EXPLORING progress reset to 0")

	_manager.advance(5.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.RETURNING, \
		"EXPLORING -> RETURNING after full exploration duration")

	_manager.advance(2.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"RETURNING -> COMPLETED after full return duration")
	_check(_count_occurrences("exp_det") == 1, "expedition_completed emitted once")
	_check(_manager.get_active_expeditions().size() == 0, \
		"active expedition query empty after completion")
	_check(_manager.is_member_in_active_expedition("d1") == false, \
		"member released after completion (availability restored)")
	_check_transitions_exact("exp_det", [
			[ExpeditionPartyData.Status.READY, ExpeditionPartyData.Status.OUTBOUND],
			[ExpeditionPartyData.Status.OUTBOUND, ExpeditionPartyData.Status.EXPLORING],
			[ExpeditionPartyData.Status.EXPLORING, ExpeditionPartyData.Status.RETURNING],
			[ExpeditionPartyData.Status.RETURNING, ExpeditionPartyData.Status.COMPLETED],
		], "deterministic progression has exactly one transition per phase")


## 동일 elapsed에서 1x/2x가 GameTime 배율 정의와 일치하는지.
func _test_time_scale_policy() -> void:
	_add_mercs(["s1", "s2"])
	_phase_events.clear()
	_completed_ids.clear()

	# 1x 컨트롤: outbound 20초 중 advance(10) → progress 0.5
	var exp1x := _make_expedition("exp_1x", ["s1"], 20.0, 4.0, 1.0)
	_game_time.set_time_scale(1.0)
	_manager.advance(10.0)
	_check(exp1x.get_status() == ExpeditionPartyData.Status.OUTBOUND \
		and _approx(exp1x.progress, 0.5), "1x: advance(10) over 20s outbound = 0.5")
	_manager.advance(10.0)
	_check(exp1x.get_status() == ExpeditionPartyData.Status.EXPLORING, \
		"1x: 10s more completes outbound (20s total)")
	_manager.advance(4.0)
	_manager.advance(1.0)
	_check(exp1x.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"1x control reached COMPLETED")

	# 2x: advance(5) == 1x advance(10) 과 동일 진행
	var exp2x := _make_expedition("exp_2x", ["s2"], 20.0, 4.0, 1.0)
	_game_time.set_time_scale(2.0)
	_manager.advance(5.0)
	_check(exp2x.get_status() == ExpeditionPartyData.Status.OUTBOUND \
		and _approx(exp2x.progress, 0.5), \
		"2x: advance(5) over 20s outbound = 0.5 (same elapsed as 1x advance(10))")
	# 2x: 다시 5초 → outbound(20초 가상) 완료 → 1x에서 advance(10)과 동일 결과
	_manager.advance(5.0)
	_check(exp2x.get_status() == ExpeditionPartyData.Status.EXPLORING, \
		"2x: 5s more completes outbound (same as 1x 10s)")
	_game_time.set_time_scale(1.0)
	# exp_2x를 완료로 정리(후속 섹션의 active query를 오염시키지 않도록).
	_manager.advance(100.0)
	_check(exp2x.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"2x control expedition finished (registry cleanup)")


## Pause(0)에서 진행이 멈추고 1x 복귀 후 재개되는지.
func _test_pause_policy() -> void:
	_add_mercs(["p1"])
	_phase_events.clear()
	var exp := _make_expedition("exp_pause", ["p1"], 10.0, 5.0, 2.0)

	_game_time.set_time_scale(0.0)
	_manager.advance(10.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.OUTBOUND \
		and _approx(exp.progress, 0.0), \
		"Pause(scale 0): advance does not progress expedition")

	_game_time.set_time_scale(1.0)
	_manager.advance(10.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.EXPLORING, \
		"1x resume: outbound completes after resume")
	_check(_events_for("exp_pause") == [
			[ExpeditionPartyData.Status.READY, ExpeditionPartyData.Status.OUTBOUND],
			[ExpeditionPartyData.Status.OUTBOUND, ExpeditionPartyData.Status.EXPLORING],
		], "pause/resume creates no extra transitions")
	_manager.advance(100.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"paused expedition finished after resume (registry cleanup)")


## GameTime을 반복해서 DAY/NIGHT 경계를 넘겨도 status 전환이 duplicate되지 않는지.
func _test_repeated_day_night_no_duplicate() -> void:
	_game_time.set_time_scale(1.0)
	_game_time.set_durations(2.0, 1.0)
	_add_mercs(["n1"])
	_phase_events.clear()
	_completed_ids.clear()
	var exp := _make_expedition("exp_dn", ["n1"], 4.0, 3.0, 2.0)

	var crossings := 0
	var _gt_crossings := [0]
	_game_time.phase_changed.connect(func(_p: int, _d: int) -> void: _gt_crossings[0] += 1)
	for i in 6:
		_game_time.advance(1.0)
		_manager.advance(1.0)
	crossings = _gt_crossings[0]
	# 이 시점까지 게임시간이 여러 DAY/NIGHT를 넘었고 manager도 6초 진행.
	_check(crossings >= 2, \
		"GameTime crossed multiple DAY/NIGHT boundaries (count=%d)" % crossings)
	_check(exp.get_status() == ExpeditionPartyData.Status.EXPLORING, \
		"expedition progressed while DAY/NIGHT toggled (6s: outbound 4 done)")

	# 나머지 구간 진행 후 완료.
	_manager.advance(100.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"expedition completes after repeated DAY/NIGHT")
	_check(_count_occurrences("exp_dn") == 1, "completed emitted once after repeated DAY/NIGHT")
	_check_transitions_exact("exp_dn", [
			[ExpeditionPartyData.Status.READY, ExpeditionPartyData.Status.OUTBOUND],
			[ExpeditionPartyData.Status.OUTBOUND, ExpeditionPartyData.Status.EXPLORING],
			[ExpeditionPartyData.Status.EXPLORING, ExpeditionPartyData.Status.RETURNING],
			[ExpeditionPartyData.Status.RETURNING, ExpeditionPartyData.Status.COMPLETED],
		], "no duplicate transition despite repeated DAY/NIGHT")

	_game_time.set_durations(60.0, 30.0)


## 한 번의 대규모 delta(한 프레임)로 전 구간이 순서대로 완료되는(frame-rate 독립)지.
func _test_large_delta_single_frame() -> void:
	_add_mercs(["b1"])
	_phase_events.clear()
	_completed_ids.clear()
	_game_time.set_time_scale(1.0)
	var exp := _make_expedition("exp_big", ["b1"], 5.0, 3.0, 2.0)
	_manager.advance(10.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"single large delta completes through all phases")
	_check(_count_occurrences("exp_big") == 1, "single delta completes exactly once")
	_check_transitions_exact("exp_big", [
			[ExpeditionPartyData.Status.READY, ExpeditionPartyData.Status.OUTBOUND],
			[ExpeditionPartyData.Status.OUTBOUND, ExpeditionPartyData.Status.EXPLORING],
			[ExpeditionPartyData.Status.EXPLORING, ExpeditionPartyData.Status.RETURNING],
			[ExpeditionPartyData.Status.RETURNING, ExpeditionPartyData.Status.COMPLETED],
		], "large delta keeps single ordered transition per phase")


## snapshot 복원 → 새 registry 등록 → 동일 진행(reload/reconstruction 안전)인지.
func _test_reload_reconstruction() -> void:
	_add_mercs(["r1", "r2"])
	_phase_events.clear()
	_completed_ids.clear()
	var exp := _make_expedition("exp_reload", ["r1", "r2"], 8.0, 4.0, 2.0)
	_manager.advance(6.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.OUTBOUND \
		and _approx(exp.progress, 0.75), "pre-reload progression at 6/8")

	var snap := exp.to_snapshot()
	_check(snap.has("member_identity_ids") and exp.get_class() == "RefCounted", \
		"snapshot contains no runtime state reference (pure data path)")
	var restored := ExpeditionPartyData.from_snapshot(snap)

	var manager2: ExpeditionManager = load("res://scripts/expedition_manager.gd").new()
	manager2.name = "ExpeditionManager2"
	root.add_child(manager2)
	manager2.set_auto_advance(false)
	manager2.expedition_phase_changed.connect(_on_phase_changed)
	manager2.expedition_completed.connect(_on_completed)
	_check(manager2.register_expedition(restored), \
		"reconstructed expedition registered in new registry")
	_check(manager2.register_expedition(restored) == false, \
		"duplicate register rejected")
	_check(manager2.register_expedition(null) == false, "null register rejected")
	_check(manager2.register_expedition(ExpeditionPartyData.new("", "x")) == false, \
		"empty-id register rejected")
	_check(manager2.get_active_expeditions().size() == 1, \
		"reconstructed expedition active after register")

	# 남은 진행(OUTBOUND 2s) 후 동일하게 나머지 구간을 끝냄.
	manager2.advance(2.0)
	_check(restored.get_status() == ExpeditionPartyData.Status.EXPLORING, \
		"reconstructed expedition continues OUTBOUND -> EXPLORING")
	manager2.advance(4.0)
	_check(restored.get_status() == ExpeditionPartyData.Status.RETURNING, \
		"reconstructed expedition EXPLORING -> RETURNING")
	manager2.advance(2.0)
	_check(restored.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"reconstructed expedition reaches COMPLETED deterministically")
	_check(_count_occurrences("exp_reload") == 1, \
		"reconstructed expedition completed exactly once")
	_check(_transition_count_for("exp_reload") == 4, \
		"reconstructed expedition keeps single transitions (no timer leak)")

	# 원본 exp_reload도 완료로 정리(후속 섹션의 active query를 오염시키지 않도록).
	_manager.advance(100.0)
	_check(exp.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"original expedition finished after reconstruction test (registry cleanup)")


## active query/register 가드 추가 확인.
func _test_active_query_and_registration() -> void:
	_check(_manager.get_expedition("exp_det").get_status() \
		== ExpeditionPartyData.Status.COMPLETED, "completed expedition still queryable")
	_check(_manager.get_active_expeditions().size() == 0, \
		"all main-registry expeditions finished")
	_add_mercs(["q1"])
	_phase_events.clear()
	var exp := _make_expedition("exp_query", ["q1"], 30.0, 30.0, 30.0)
	_check(_manager.get_active_expeditions() == [exp], \
		"active expedition query returns the active one")
	_check(_manager.is_member_in_active_expedition("q1"), "active member guarded")
	# destination은 String data로만 처리하므로 freed/invalid marker여도 진행에 영향 없음.
	var snap := exp.to_snapshot()
	snap["destination_region_id"] = "freed_marker_xyz"
	var restored := ExpeditionPartyData.from_snapshot(snap)
	restored.outbound_duration = 5.0
	restored.exploration_duration = 1.0
	restored.return_duration = 1.0
	var manager3: ExpeditionManager = load("res://scripts/expedition_manager.gd").new()
	manager3.name = "ExpeditionManager3"
	root.add_child(manager3)
	manager3.set_auto_advance(false)
	manager3.expedition_phase_changed.connect(_on_phase_changed)
	_check(manager3.register_expedition(restored), "freed-marker expedition registered")
	manager3.advance(100.0)
	_check(restored.get_status() == ExpeditionPartyData.Status.COMPLETED, \
		"invalid/freed destination marker handled safely via region_id data")
	_check(restored.destination_region_id == "freed_marker_xyz", \
		"region id string retained without node reference")
