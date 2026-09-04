extends SceneTree

## TASK-022-4 Recruitment Capacity Regression.
## 여관(Inn) → 고용/보유 용량(capacity) 전체 loop를 실제 Main 3D Runtime에서
## 결정적으로 회귀 검증한다. TASK-022-2(InnCapacity 데이터 기반 레벨/용량 +
## Roster cap enforcement)와 TASK-022-3(UI/visual) 구현이 회귀 없이 유지되는지
## 단일 시나리오로 고정한다.
##
## 검증 항목 (TASK-022-4 검증 목록):
##  1. 초기 capacity: Lv.1 worker/mercenary 용량이 데이터 테이블 × 유효 여관 수와 일치.
##  2. hire: 용량까지 고용 성공.
##  3. cap 도달: 용량 초과 고용 거부 + count 유지.
##  4. upgrade: 레벨 상승 → 용량 증가(데이터 테이블 반영).
##  5. 추가 hire: 업그레이드 후 증가된 용량까지 추가 고용 성공.
##  6. building count policy: 여관 1채 상한, can_place_inn 거부, capacity 연동.
##  7. remove/refund 안전성: 보유 해제 시 count 감소 + 빈 슬롯 재고용 가능,
##     미보유 id remove는 안전하게 false.
##  8. active Mercenary reference 안전: NIGHT Actor spawn 중 remove/died 시
##     _actors에서 즉시 정리되어 dangling reference 없이 get_actor/get_actor_count
##     조회가 안전하고, despawn이 멱등하다.
##
## 완료조건: Inn → recruitment capacity loop PASS.

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const SETTLE_FRAMES := 10

var _frame := 0
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame != SETTLE_FRAMES:
		return false
	_run_checks()
	print("TASK0224_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _initialize() -> void:
	var scene: Node = load(MAIN_SCENE_PATH).instantiate()
	root.add_child(scene)


func _run_checks() -> void:
	var inn_cap: Node = root.get_node("InnCapacity")
	var worker_roster: Node = root.get_node("WorkerRoster")
	var merc_roster: Node = root.get_node("MercenaryRoster")
	var roster3d := get_first_node_in_group("mercenary_roster_3d")
	_check(inn_cap != null, "InnCapacity autoload available")
	_check(worker_roster != null, "WorkerRoster autoload available")
	_check(merc_roster != null, "MercenaryRoster autoload available")
	_check(roster3d != null, "MercenaryRoster3D wired in 3D runtime")
	if inn_cap == null or worker_roster == null or merc_roster == null or roster3d == null:
		return

	var main: Node = root.get_node("Main3D")
	_check(main != null, "main_3d.tscn loads")
	if main == null:
		return

	# 1. 초기 capacity (Lv.1).
	_check(inn_cap.get_level() == 1, "inn level baseline 1")
	var l1_worker_cap: int = inn_cap.get_worker_capacity()
	var l1_merc_cap: int = inn_cap.get_mercenary_capacity()
	var l1_row: Dictionary = inn_cap.get_level_config(1)
	_check(l1_worker_cap == int(l1_row.worker_capacity) \
			and l1_merc_cap == int(l1_row.mercenary_capacity),
		"initial capacity matches data table (worker=%d merc=%d)"
			% [l1_worker_cap, l1_merc_cap])
	_check(inn_cap.count_inns() == 1, "effective inn count 1 (capacity = table row x 1)")
	_check(worker_roster.get_count() == 0, "worker roster starts empty")
	_check(merc_roster.get_count() == 0, "mercenary roster starts empty")

	# 6. building count policy (초기 상태에서 함께 검증).
	_check(inn_cap.get_inn_count_limit() == 1, "inn count limit policy = 1")
	_check(inn_cap.count_inns() == 1, "count_inns finds exactly 1 inn (%d)" % inn_cap.count_inns())
	_check(not inn_cap.can_place_inn(), "additional inn placement blocked at limit")
	_check(inn_cap._effective_inn_count() == 1, "effective inn count clamped to 1")

	# 2/3. worker hire → cap 도달.
	var worker_filled := true
	for i in range(l1_worker_cap):
		if not worker_roster.add_worker(WorkerData.new("w%d" % i, "Worker %d" % i, WorkerData.Job.LUMBERJACK)):
			worker_filled = false
	_check(worker_filled and worker_roster.get_count() == l1_worker_cap,
		"worker hire fills to initial capacity (%d)" % worker_roster.get_count())
	_check(not worker_roster.add_worker(WorkerData.new("w_over", "Over", WorkerData.Job.LUMBERJACK)),
		"worker hire beyond capacity rejected")
	_check(worker_roster.get_count() == l1_worker_cap,
		"worker roster stays at capacity after reject")

	# 4. upgrade (worker side).
	_check(inn_cap.upgrade(), "upgrade to level 2 succeeds")
	_check(inn_cap.get_level() == 2, "inn level changes to 2 after upgrade")
	var l2_worker_cap: int = inn_cap.get_worker_capacity()
	var l2_merc_cap: int = inn_cap.get_mercenary_capacity()
	var l2_row: Dictionary = inn_cap.get_level_config(2)
	_check(l2_worker_cap == int(l2_row.worker_capacity) \
			and l2_merc_cap == int(l2_row.mercenary_capacity),
		"level 2 capacity matches data table (worker=%d merc=%d)"
			% [l2_worker_cap, l2_merc_cap])
	_check(l2_worker_cap > l1_worker_cap, "worker capacity increased (8 -> %d)" % l2_worker_cap)

	# 5. 추가 hire (worker).
	var worker_extra := true
	for i in range(l1_worker_cap, l2_worker_cap):
		if not worker_roster.add_worker(WorkerData.new("wl2_%d" % i, "Worker %d" % i, WorkerData.Job.LUMBERJACK)):
			worker_extra = false
	_check(worker_extra and worker_roster.get_count() == l2_worker_cap,
		"worker hire grows to upgraded capacity (%d)" % worker_roster.get_count())
	_check(not worker_roster.add_worker(WorkerData.new("wl2_over", "Over", WorkerData.Job.LUMBERJACK)),
		"worker hire beyond upgraded capacity rejected")

	# 7. remove 안전성 (worker) + 빈 슬롯 재고용.
	var w_first: WorkerData = worker_roster.get_workers()[0]
	var w_count_before: int = worker_roster.get_count()
	_check(worker_roster.remove_worker(w_first), "worker remove succeeds for member")
	_check(worker_roster.get_count() == w_count_before - 1,
		"worker count decreases after remove (%d)" % worker_roster.get_count())
	_check(not worker_roster.remove_worker(WorkerData.new("w_ghost", "Ghost", WorkerData.Job.LUMBERJACK)),
		"worker remove of non-member returns false (safe)")
	_check(worker_roster.add_worker(WorkerData.new("w_rehire", "Rehire", WorkerData.Job.LUMBERJACK)),
		"freed worker slot accepts rehire")
	_check(worker_roster.get_count() == w_count_before,
		"worker count returns to capacity after rehire (%d)" % worker_roster.get_count())

	# 8. active Mercenary reference 안전 (3D roster).
	#    autoload를 채우기 전에 3D roster가 비어 있는 상태에서 직접 검증해
	#    hire-sync 오염 없이 spawn/died/remove 정리 경로를 고정한다.
	var m_act := MercenaryData.new("m_act1", "Active", MercenaryData.MercClass.SWORDSMAN)
	m_act.defense_zone = MercenaryData.DefenseZone.NORTH
	_check(roster3d.add_mercenary(m_act), "3D roster accepts active-test mercenary")
	_check(roster3d.get_actor("m_act1") == null, "no actor before NIGHT spawn")
	var spawned: int = roster3d.spawn_night_actors()
	_check(spawned == 1, "NIGHT spawn creates 1 actor for defense-zone mercenary (%d)" % spawned)
	var act_ref: Node = roster3d.get_actor("m_act1")
	_check(act_ref != null and is_instance_valid(act_ref),
		"get_actor returns valid active mercenary reference")
	_check(roster3d.get_actor_count() == 1, "get_actor_count reflects spawned actor (%d)"
		% roster3d.get_actor_count())
	# died 경로: Actor 사망 시 _actors에서 즉시 정리 → dangling reference 없음.
	if act_ref != null and is_instance_valid(act_ref) and act_ref.has_signal("died"):
		act_ref.died.emit(act_ref)
		act_ref.queue_free()
	_check(roster3d.get_actor("m_act1") == null, "died actor removed from _actors (no dangling ref)")
	_check(roster3d.get_actor_count() == 0, "get_actor_count drops after died (%d)"
		% roster3d.get_actor_count())
	# died 정리 후 roster data도 제거해 후속 spawn에서 재등장하지 않게 한다.
	_check(roster3d.remove_mercenary(m_act), "died mercenary data removable after actor cleanup")
	_check(roster3d.get_count() == 0, "3D roster empty after active-test cleanup")
	# remove 경로: spawn 중인 용병을 remove하면 Actor 정리 + 빈 슬롯.
	var m_act2 := MercenaryData.new("m_act2", "Active2", MercenaryData.MercClass.SWORDSMAN)
	m_act2.defense_zone = MercenaryData.DefenseZone.WEST
	_check(roster3d.add_mercenary(m_act2), "3D roster accepts second active-test mercenary")
	_check(roster3d.spawn_night_actors() == 1, "second NIGHT spawn succeeds")
	_check(roster3d.remove_mercenary(m_act2), "remove of spawned mercenary succeeds")
	_check(roster3d.get_actor("m_act2") == null, "actor reference cleaned after remove")
	_check(roster3d.get_actor_count() == 0, "no active actor after remove (%d)"
		% roster3d.get_actor_count())
	_check(roster3d.get_mercenary("m_act2") == null, "removed mercenary gone from 3D roster")
	_check(roster3d.despawn_night_actors() == 0, "despawn_night_actors idempotent after cleanup")
	_check(roster3d.get_actor("m_unknown") == null, "get_actor of unknown id safe (null)")
	var m_act3 := MercenaryData.new("m_act3", "Active3", MercenaryData.MercClass.SWORDSMAN)
	_check(roster3d.add_mercenary(m_act3), "freed 3D slot accepts new hire (capacity decrease safe)")
	_check(roster3d.get_count() == 1, "3D roster count reflects rehire (%d)" % roster3d.get_count())

	# 2/3. mercenary hire → cap 도달 (autoload, UI 기록 경로).
	var merc_filled := true
	for i in range(l2_merc_cap):
		if not merc_roster.add_mercenary(MercenaryData.new("m%d" % i, "Merc %d" % i, MercenaryData.MercClass.SWORDSMAN)):
			merc_filled = false
	_check(merc_filled and merc_roster.get_count() == l2_merc_cap,
		"mercenary hire fills to capacity (%d)" % merc_roster.get_count())
	_check(not merc_roster.add_mercenary(MercenaryData.new("m_over", "Over", MercenaryData.MercClass.SWORDSMAN)),
		"mercenary hire beyond capacity rejected")
	_check(merc_roster.get_count() == l2_merc_cap,
		"mercenary roster stays at capacity after reject")
	# 3D roster가 hire-sync로 mirror됨 (같은 용량 소스).
	_check(roster3d.get_count() == merc_roster.get_count(),
		"3D roster mirrors autoload hire (count=%d)" % roster3d.get_count())

	# 4. 추가 upgrade → 5. 추가 hire (mercenary), max level guard.
	_check(inn_cap.upgrade(), "upgrade to level 3 (max) succeeds")
	_check(inn_cap.get_level() == inn_cap.get_max_level(), "inn reaches max level")
	_check(not inn_cap.can_upgrade(), "cannot upgrade beyond max level")
	var l3_merc_cap: int = inn_cap.get_mercenary_capacity()
	var l3_row: Dictionary = inn_cap.get_level_config(inn_cap.get_max_level())
	_check(l3_merc_cap == int(l3_row.mercenary_capacity),
		"level 3 mercenary capacity matches data table (%d)" % l3_merc_cap)
	var merc_extra := true
	for i in range(l2_merc_cap, l3_merc_cap):
		if not merc_roster.add_mercenary(MercenaryData.new("ml3_%d" % i, "Merc %d" % i, MercenaryData.MercClass.SWORDSMAN)):
			merc_extra = false
	_check(merc_extra and merc_roster.get_count() == l3_merc_cap,
		"mercenary hire grows to max-level capacity (%d)" % merc_roster.get_count())
	_check(not merc_roster.add_mercenary(MercenaryData.new("ml3_over", "Over", MercenaryData.MercClass.SWORDSMAN)),
		"mercenary hire beyond max capacity rejected")

	# 7. remove 안전성 (mercenary) + 빈 슬롯 재고용.
	var m_first: MercenaryData = merc_roster.get_mercenaries()[0]
	var m_count_before: int = merc_roster.get_count()
	_check(merc_roster.remove_mercenary(m_first), "mercenary remove succeeds for member")
	_check(merc_roster.get_count() == m_count_before - 1,
		"mercenary count decreases after remove (%d)" % merc_roster.get_count())
	_check(not merc_roster.remove_mercenary(MercenaryData.new("m_ghost", "Ghost", MercenaryData.MercClass.SWORDSMAN)),
		"mercenary remove of non-member returns false (safe)")
	_check(merc_roster.add_mercenary(MercenaryData.new("m_rehire", "Rehire", MercenaryData.MercClass.SWORDSMAN)),
		"freed mercenary slot accepts rehire")
	_check(merc_roster.get_count() == m_count_before,
		"mercenary count returns to capacity after rehire (%d)" % merc_roster.get_count())

	# 회귀: 여관 건물 identity가 InnCapacity 레벨을 mirror, 단일 고용 파이프라인 유지.
	var inn_node: Node = null
	for b in get_nodes_in_group("core_buildings_3d"):
		if b.get_core_type() == "inn":
			inn_node = b
	if inn_node != null:
		_check(inn_node.get_level() == inn_cap.get_level(),
			"inn building get_level mirrors InnCapacity (%d)" % inn_node.get_level())
	_check(get_nodes_in_group("recruitment_ui").size() == 1,
		"single recruitment UI (no duplicate framework)")
	_check(get_nodes_in_group("inn_roster_ui").size() == 1,
		"single inn roster UI (no duplicate)")
	# roster id 중복 없음 (active reference/재고용 회귀).
	var ids := {}
	var dup := false
	for m in merc_roster.get_mercenaries():
		if ids.has(m.id):
			dup = true
		ids[m.id] = true
	_check(not dup, "mercenary roster has no duplicate ids")
