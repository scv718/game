extends SceneTree

## TASK-011-2 WorkerData / Worker Roster 기반 검증.
## WorkerData 필드, Roster 추가/조회, 미배치 시 Actor 미생성,
## 동일 WorkerData 중복 배치 방지, assignment 상태 조회,
## freed workplace 안전 정리를 자동 검증한다.

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
	if _frame != 10:
		return false

	var roster: Node = root.get_node("WorkerRoster")
	_check(roster != null, "WorkerRoster autoload exists")

	# 빈 Roster 초기 상태
	_check(roster.get_count() == 0, "roster starts empty (count=%d)" % roster.get_count())
	_check(roster.get_unassigned().size() == 0, "no unassigned initially")
	_check(roster.get_assigned_count() == 0, "no assigned initially")

	# WorkerData 생성/필드
	var w1 := WorkerData.new("lumberjack_A", "Lumberjack A", WorkerData.Job.LUMBERJACK)
	_check(w1.id == "lumberjack_A", "worker id set")
	_check(w1.display_name == "Lumberjack A", "worker display name set")
	_check(w1.job == WorkerData.Job.LUMBERJACK, "worker job set to LUMBERJACK")
	_check(w1.get_job_name() == "LUMBERJACK", "worker job name resolves")

	var w2 := WorkerData.new("miner_A", "Miner A", WorkerData.Job.MINER)
	_check(w2.get_job_name() == "MINER", "miner job name resolves")

	# Roster 추가
	_check(roster.add_worker(w1), "add lumberjack worker")
	_check(roster.add_worker(w2), "add miner worker")
	_check(not roster.add_worker(w1), "duplicate id rejected")
	_check(not roster.add_worker(null), "null worker rejected")
	_check(roster.get_count() == 2, "roster holds 2 workers")

	# 미배치: Roster에 존재하지만 Actor는 없음 (미배치 시 월드 Actor 자동 생성 없음)
	_check(roster.get_worker("lumberjack_A") == w1, "get_worker by id")
	_check(roster.get_worker("nope") == null, "unknown id returns null")
	_check(roster.get_unassigned().size() == 2, "both workers unassigned")
	_check(roster.get_assigned_count() == 0, "no assigned yet")
	_check(not w1.is_assigned(), "lumberjack not assigned")
	_check(w1.get_workplace() == null, "no workplace reference while unassigned")

	# 배치 테스트용 workplace 노드 2개 (실제 시설 대신 더미)
	var ly := Node2D.new()
	ly.name = "Lumberyard1"
	root.add_child(ly)
	var qy := Node2D.new()
	qy.name = "Quarry1"
	root.add_child(qy)

	# assign
	_check(roster.assign(w1, ly), "assign lumberjack to Lumberyard1")
	_check(w1.is_assigned(), "lumberjack is assigned after assign")
	_check(w1.get_workplace() == ly, "workplace reference set")
	_check(w1.get_workplace_id() == "Lumberyard1", "workplace id resolves")
	_check(roster.get_assigned_count() == 1, "assigned count is 1")
	_check(roster.get_unassigned().size() == 1, "one remains unassigned")
	_check(roster.get_workers_for_workplace(ly).size() == 1, "worker listed for Lumberyard1")

	# 동일 WorkerData 동시 2 workplace 배치 방지
	_check(not roster.assign(w1, qy), "same worker cannot assign to a second workplace")
	_check(w1.get_workplace() == ly, "assignment unchanged after rejected second assign")
	_check(not roster.assign(w1, ly), "same worker cannot re-assign to same workplace")
	_check(roster.get_assigned_count() == 1, "still only 1 assigned")

	# 로스터에 없는 worker 배치 거부
	var stranger := WorkerData.new("x", "X", WorkerData.Job.LUMBERJACK)
	_check(not roster.assign(stranger, ly), "worker not in roster cannot be assigned")

	# unassign
	_check(roster.unassign(w1), "unassign lumberjack")
	_check(not w1.is_assigned(), "lumberjack unassigned after unassign")
	_check(w1.get_workplace() == null, "workplace cleared on unassign")
	_check(not roster.unassign(w1), "unassign again returns false")
	_check(roster.get_assigned_count() == 0, "assigned count back to 0")

	# freed workplace 안전 정리
	_check(roster.assign(w1, ly), "re-assign to Lumberyard1")
	_check(roster.assign(w2, qy), "assign miner to Quarry1")
	_check(roster.get_assigned_count() == 2, "two assigned before cleanup")
	ly.free()
	qy.free()
	_check(w1.get_workplace() == null, "freed workplace no longer returned by get_workplace")
	_check(w1.is_assigned() == false, "freed workplace makes worker is_assigned false")
	# cleanup_freed_workplaces 정리
	_check(roster.cleanup_freed_workplaces() == 2, "cleanup handles both freed workplaces")
	_check(roster.get_assigned_count() == 0, "no assigned after cleanup")
	_check(w1.get_workplace() == null, "lumberjack workplace cleared")
	_check(w2.get_workplace() == null, "miner workplace cleared")
	_check(w1.get_workplace_id() == "", "workplace id empty after cleanup")
	_check(roster.get_workers().size() == 2, "workers retained in roster after cleanup")

	# remove_worker
	_check(roster.remove_worker(w1), "remove lumberjack from roster")
	_check(roster.get_count() == 1, "roster count drops to 1 after removal")
	_check(roster.get_worker("lumberjack_A") == null, "removed id no longer found")
	_check(not roster.remove_worker(w1), "removing again returns false")

	# main smoke 회귀 (시작 시 월드 Actor 존재는 기존 시스템 회귀 확인용)
	var main: Node = root.get_node("Main")
	_check(main != null, "main.tscn loads with WorkerRoster autoload present")
	var floor_node: TileMapLayer = main.get_node("World/Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() == 128 * 128, "world floor intact (128x128)")
	# TASK-011-5: 시작 시 테스트용 Worker Actor가 월드에 미리 배치되지 않는다.
	_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor at start (%d)" % get_nodes_in_group("lumberjacks").size())
	_check(get_nodes_in_group("miners").size() == 0, "no miner actor at start (%d)" % get_nodes_in_group("miners").size())

	print("TASK0112_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
