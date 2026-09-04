extends SceneTree

## TASK-022-2 Inn Level / Capacity Data.
## 여관 업그레이드 레벨(데이터 기반)과 그에 따른 주민/용병 보유 한도(capacity)
## 및 고용 cap 강제를 실제 Main 3D Runtime에서 결정적으로 검증한다.
##
## 검증 항목:
##  1. InnCapacity autoload 존재 + data-driven INN_LEVELS 테이블(level/cost/
##     worker_capacity/mercenary_capacity).
##  2. level 변화: upgrade() 성공, max level 도달 후 거부.
##  3. capacity 변화: 레벨 상승 시 get_worker_capacity/get_mercenary_capacity 증가.
##  4. cap enforcement:
##     - WorkerRoster.add_worker: 용량 초과 거부.
##     - MercenaryRoster.add_mercenary: 용량 초과 거부.
##     - MercenaryRoster3D.add_mercenary: 3D roster도 동일 거부.
##  5. Inn count 제한 연결: count_inns/get_inn_count_limit/can_place_inn.
##  6. building identity: 여관 get_level() == InnCapacity 레벨, 주점은 1 유지.
##  7. 회귀: 단일 고용 파이프라인(recruitment_ui/inn_roster_ui) 무결성.

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
	print("TASK0222_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _initialize() -> void:
	var scene: Node = load(MAIN_SCENE_PATH).instantiate()
	root.add_child(scene)


func _run_checks() -> void:
	var inn_cap: Node = root.get_node("InnCapacity")
	var worker_roster: Node = root.get_node("WorkerRoster")
	var merc_roster: Node = root.get_node("MercenaryRoster")
	_check(inn_cap != null, "InnCapacity autoload exists")
	_check(worker_roster != null, "WorkerRoster autoload exists")
	_check(merc_roster != null, "MercenaryRoster autoload exists")
	if inn_cap == null or worker_roster == null or merc_roster == null:
		return

	var main: Node = root.get_node("Main3D")
	_check(main != null, "main_3d.tscn loads")
	if main == null:
		return

	# 1. data-driven 테이블.
	_check(inn_cap.INN_LEVELS.size() >= 2, "INN_LEVELS data table has >= 2 levels (%d)" % inn_cap.INN_LEVELS.size())
	var table_ok := true
	for row in inn_cap.INN_LEVELS:
		if not row.has("level") or not row.has("cost") \
				or not row.has("worker_capacity") or not row.has("mercenary_capacity"):
			table_ok = false
	_check(table_ok, "every level row exposes level/cost/worker_capacity/mercenary_capacity")
	var max_level: int = inn_cap.get_max_level()
	_check(max_level == int(inn_cap.INN_LEVELS[inn_cap.INN_LEVELS.size() - 1].level),
		"max level matches data table tail (%d)" % max_level)

	# 2. baseline + level 변화 (level 1).
	_check(inn_cap.get_level() == 1, "inn level baseline 1")
	var l1_worker: int = inn_cap.get_worker_capacity()
	var l1_merc: int = inn_cap.get_mercenary_capacity()
	_check(inn_cap.can_upgrade(), "can upgrade from baseline")
	_check(inn_cap.get_upgrade_cost() == int(inn_cap.INN_LEVELS[1].cost),
		"upgrade cost reads from data table (level 2 cost)")
	_check(l1_worker == int(inn_cap.INN_LEVELS[0].worker_capacity) \
			and l1_merc == int(inn_cap.INN_LEVELS[0].mercenary_capacity),
		"level 1 capacities match data table row (worker=%d merc=%d)" % [l1_worker, l1_merc])

	# 3. cap enforcement - worker (level 1).
	var worker_filled := true
	for i in range(l1_worker):
		var w := WorkerData.new("w%d" % i, "Worker %d" % i, WorkerData.Job.LUMBERJACK)
		if not worker_roster.add_worker(w):
			worker_filled = false
	_check(worker_filled and worker_roster.get_count() == l1_worker,
		"worker roster fills to level 1 capacity (%d)" % worker_roster.get_count())
	_check(not worker_roster.add_worker(WorkerData.new("w_over", "Over", WorkerData.Job.LUMBERJACK)),
		"worker hire beyond level 1 capacity rejected (cap enforcement)")
	_check(worker_roster.get_count() == l1_worker, "worker roster stays at capacity after reject")

	# 4. cap enforcement - 3D roster (level 1).
	#    MercenaryHireSync3D가 autoload MercenaryRoster를 3D roster로 이월하므로
	#    autoload에 먼저 채우면 3D roster가 오염된다. 3D roster는 비어 있는 상태에서
	#    먼저 검증한다.
	var roster3d := get_first_node_in_group("mercenary_roster_3d")
	_check(roster3d != null, "MercenaryRoster3D wired in 3D runtime")
	if roster3d != null:
		var r3d_filled := true
		for i in range(l1_merc):
			var m := MercenaryData.new("m3d%d" % i, "Merc3D %d" % i, MercenaryData.MercClass.SWORDSMAN)
			if not roster3d.add_mercenary(m):
				r3d_filled = false
		_check(r3d_filled and roster3d.get_count() == l1_merc,
			"3D roster fills to level 1 capacity (%d)" % roster3d.get_count())
		_check(not roster3d.add_mercenary(MercenaryData.new("m3d_over", "Over3D", MercenaryData.MercClass.SWORDSMAN)),
			"3D roster hire beyond level 1 capacity rejected (cap enforcement)")

	# 5. cap enforcement - mercenary autoload (level 1).
	var merc_filled := true
	for i in range(l1_merc):
		var m := MercenaryData.new("m%d" % i, "Merc %d" % i, MercenaryData.MercClass.SWORDSMAN)
		if not merc_roster.add_mercenary(m):
			merc_filled = false
	_check(merc_filled and merc_roster.get_count() == l1_merc,
		"mercenary roster fills to level 1 capacity (%d)" % merc_roster.get_count())
	_check(not merc_roster.add_mercenary(MercenaryData.new("m_over", "Over", MercenaryData.MercClass.SWORDSMAN)),
		"mercenary hire beyond level 1 capacity rejected (cap enforcement)")
	_check(merc_roster.get_count() == l1_merc, "mercenary roster stays at capacity after reject")

	# 6. Inn count 제한 연결 (level 1).
	var inn_buildings := get_nodes_in_group("core_buildings_3d")
	var inn_node: Node = null
	for b in inn_buildings:
		if b.get_core_type() == "inn":
			inn_node = b
	_check(inn_node != null, "inn core building present in 3D runtime")
	_check(inn_cap.count_inns() == 1, "count_inns finds exactly 1 inn (%d)" % inn_cap.count_inns())
	_check(inn_cap.get_inn_count_limit() == 1, "inn count limit policy = 1 (no unlimited inn spam)")
	_check(not inn_cap.can_place_inn(), "additional inn placement blocked at limit")
	if inn_node != null:
		_check(inn_node.get_level() == inn_cap.get_level(),
			"inn building get_level mirrors InnCapacity (%d)" % inn_node.get_level())

	# 7. capacity 변화 + level 변화 (upgrade to level 2).
	_check(inn_cap.upgrade(), "upgrade to level 2 succeeds")
	_check(inn_cap.get_level() == 2, "level changes to 2 after upgrade")
	var l2_worker: int = inn_cap.get_worker_capacity()
	var l2_merc: int = inn_cap.get_mercenary_capacity()
	_check(l2_worker > l1_worker, "worker capacity increases with level (%d -> %d)" % [l1_worker, l2_worker])
	_check(l2_merc > l1_merc, "mercenary capacity increases with level (%d -> %d)" % [l1_merc, l2_merc])
	_check(l2_worker == int(inn_cap.INN_LEVELS[1].worker_capacity) \
			and l2_merc == int(inn_cap.INN_LEVELS[1].mercenary_capacity),
		"level 2 capacities match data table row (worker=%d merc=%d)" % [l2_worker, l2_merc])
	if inn_node != null:
		_check(inn_node.get_level() == 2, "inn building reflects upgraded level 2")

	# 8. cap enforcement - worker (level 2).
	var worker_l2 := true
	for i in range(l1_worker, l2_worker):
		var w := WorkerData.new("wl2_%d" % i, "Worker %d" % i, WorkerData.Job.LUMBERJACK)
		if not worker_roster.add_worker(w):
			worker_l2 = false
	_check(worker_l2 and worker_roster.get_count() == l2_worker,
		"worker roster grows to level 2 capacity (%d)" % worker_roster.get_count())
	_check(not worker_roster.add_worker(WorkerData.new("wl2_over", "Over", WorkerData.Job.LUMBERJACK)),
		"worker hire beyond level 2 capacity rejected")
	_check(worker_roster.get_count() == l2_worker, "worker roster stays at level 2 capacity after reject")

	# 9. cap enforcement - mercenary (level 2).
	var merc_l2 := true
	for i in range(l1_merc, l2_merc):
		var m := MercenaryData.new("ml2_%d" % i, "Merc %d" % i, MercenaryData.MercClass.SWORDSMAN)
		if not merc_roster.add_mercenary(m):
			merc_l2 = false
	_check(merc_l2 and merc_roster.get_count() == l2_merc,
		"mercenary roster grows to level 2 capacity (%d)" % merc_roster.get_count())
	_check(not merc_roster.add_mercenary(MercenaryData.new("ml2_over", "Over", MercenaryData.MercClass.SWORDSMAN)),
		"mercenary hire beyond level 2 capacity rejected")
	_check(merc_roster.get_count() == l2_merc, "mercenary roster stays at level 2 capacity after reject")

	# 10. max level.
	_check(inn_cap.upgrade(), "upgrade to level 3 (max) succeeds")
	_check(inn_cap.get_level() == max_level, "level reaches data table max")
	_check(not inn_cap.can_upgrade(), "cannot upgrade beyond max level")
	_check(not inn_cap.upgrade(), "upgrade beyond max rejected")
	_check(inn_cap.get_level() == max_level, "level stays at max after rejected upgrade")
	_check(inn_cap.get_upgrade_cost() == 0, "no upgrade cost at max level")

	# 11. building identity: 주점은 여전히 레벨 1 유지.
	var tavern_node: Node = null
	for b in inn_buildings:
		if b.get_core_type() == "tavern":
			tavern_node = b
	if tavern_node != null:
		_check(tavern_node.get_level() == 1, "tavern building keeps level 1 (upgrade only for inn)")

	# 12. 회귀: 단일 고용 파이프라인 무결성.
	var recruit_uis := get_nodes_in_group("recruitment_ui")
	_check(recruit_uis.size() == 1, "single recruitment UI (no duplicate framework, got %d)" % recruit_uis.size())
	_check(get_nodes_in_group("inn_roster_ui").size() == 1, "single inn roster UI (no duplicate)")
	_check(worker_roster.get_worker("lumberjack_A") == null, "candidate id untouched by capacity test")
	var ui: Control = recruit_uis[0] if recruit_uis.size() > 0 else null
	if ui != null:
		ui._on_hire_pressed("lumberjack_A")
		_check(worker_roster.get_worker("lumberjack_A") != null,
			"legacy hire path still adds exactly once (capacity not exceeded yet)")
		_check(worker_roster.get_count() == l2_worker + 1,
			"legacy hire lands within current capacity")