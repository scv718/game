extends SceneTree

## TASK-011-3 주점 Worker 고용 프로토타입 검증.
## 주점 상호작용으로 고용 UI가 열리고, 고정 후보 목록에서
## Lumberjack/Miner를 고용하면 WorkerData가 Roster에 정확히 1회 추가되며,
## 중복 고용이 거부되고, 고용 직후 월드에 Worker Actor가 생성되지 않는지 자동 검증한다.
## 기존 시스템(smoke, 5개 핵심 건물, Roster) 회귀도 함께 확인한다.

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

	var main: Node = root.get_node("Main")
	_check(main != null, "main.tscn loads")

	var roster: Node = root.get_node("WorkerRoster")
	_check(roster != null, "WorkerRoster autoload exists")

	# 주점/상호작용 존재
	var world: Node = main.get_node("World")
	var tavern: Node = world.get_node("Tavern")
	_check(tavern != null, "tavern exists")
	_check(tavern.get("core_type") == "tavern", "tavern core_type is tavern")
	var interact: Node = tavern.get_node("Interact")
	_check(interact != null, "tavern interactable exists")
	_check(interact.has_method("interact"), "tavern interactable has interact")

	# 고용 UI 존재/초기 상태
	var ui: Control = get_first_node_in_group("recruitment_ui")
	_check(ui != null, "recruitment UI exists in group")
	_check(ui.visible == false, "recruitment UI hidden initially")

	# 고정 후보 4명
	var seen := {}
	for c in ui.CANDIDATES:
		seen[c.id] = c
	_check(seen.size() == 4, "4 candidates defined (%d)" % seen.size())
	_check(seen.has("lumberjack_A"), "lumberjack_A candidate")
	_check(seen.has("lumberjack_B"), "lumberjack_B candidate")
	_check(seen.has("miner_A"), "miner_A candidate")
	_check(seen.has("miner_B"), "miner_B candidate")

	# 초기 Roster 빈 상태
	_check(roster.get_count() == 0, "roster starts empty (%d)" % roster.get_count())

	# 주점 상호작용 시 UI 열림
	interact.interact(null)
	_check(ui.visible, "tavern interact opens recruitment UI")

	# 고용: Lumberjack A → Roster 정확히 1회 추가
	var actors_before: int = get_nodes_in_group("lumberjacks").size() + get_nodes_in_group("miners").size()
	ui._on_hire_pressed("lumberjack_A")
	_check(roster.get_count() == 1, "roster grew to 1 after hire (%d)" % roster.get_count())
	var w: WorkerData = roster.get_worker("lumberjack_A")
	_check(w != null, "Lumberjack A in roster")
	_check(w.display_name == "Lumberjack A", "Lumberjack A display name")
	_check(w.job == WorkerData.Job.LUMBERJACK, "Lumberjack A job is LUMBERJACK")
	_check(not w.is_assigned(), "hired worker unassigned")

	# 중복 고용 거부
	ui._on_hire_pressed("lumberjack_A")
	_check(roster.get_count() == 1, "duplicate hire rejected (roster stays 1)")

	# Miner 고용
	ui._on_hire_pressed("miner_A")
	_check(roster.get_count() == 2, "roster grew to 2 after miner hire (%d)" % roster.get_count())
	var m: WorkerData = roster.get_worker("miner_A")
	_check(m != null, "Miner A in roster")
	_check(m.job == WorkerData.Job.MINER, "Miner A job is MINER")

	# 고용 직후 월드 Worker Actor 미생성
	var actors_after: int = get_nodes_in_group("lumberjacks").size() + get_nodes_in_group("miners").size()
	_check(actors_after == actors_before, "no worker actor spawned on hire (%d -> %d)" % [actors_before, actors_after])

	# UI 닫기
	ui.close()
	_check(not ui.visible, "UI closes")

	# 회귀: 5개 핵심 건물 / 기존 시스템 유지
	_check(get_nodes_in_group("core_buildings").size() == 5, "5 core buildings intact")
	var floor_node: TileMapLayer = world.get_node("Floor") as TileMapLayer
	_check(floor_node != null and floor_node.get_used_cells().size() == 192 * 192, "world floor intact (192x192)")
	# TASK-011-5: 시작 시 테스트용 Worker Actor가 월드에 미리 배치되지 않는다.
	_check(get_nodes_in_group("lumberjacks").size() == 0, "no lumberjack actor at start (%d)" % get_nodes_in_group("lumberjacks").size())
	_check(get_nodes_in_group("miners").size() == 0, "no miner actor at start (%d)" % get_nodes_in_group("miners").size())

	print("TASK0113_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()
	return true


func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)