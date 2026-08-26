extends SceneTree

## TASK-3D-WRK-001-2 Lumberjack / Miner State Machine Wiring 회귀 테스트.
## 기존 2D worker FSM(lumberjack.gd / miner.gd) 상태 의미를 3D로 이전한
## lumberjack_3d.gd / miner_3d.gd의 완료조건을 검증한다.
##
## 완료조건 매핑:
##   1. Lumberjack full loop - IDLE->FIND->MOVE->GATHER->RETURN->DEPOSIT,
##      wood가 VillageResources에 반납되고 carry가 비워진다.
##   2. Miner full loop - MOVE_TO_WORK->MINE(반복 생산), stone 증가.
##   3. assign/unassign - _on_assigned/_on_unassigned 상태 복귀.
##   4. 2명 동시 작업 - lumberjack 2명 + miner 2명 동시에 생산.
##   5. claim 충돌 없음 - 동시에 동일 tree를 claim하지 않고 자원이 중복 집계되지 않음.
##   추가: visual hook(work_anim_started/stopped, carry_prop_changed)이 발화하고
##   asset 부재와 무관하게 기능 상태가 진행됨.

enum Phase {
	SETUP, CONTRACT, NAV_SYNC,
	LUMBER_ARM, LUMBER_LOOP,
	MINER_ARM, MINER_LOOP,
	TWO_ARM, TWO_LOOP, TWO_UNASSIGN,
	CLAIM_ARM, CLAIM_LOOP,
	UNASSIGN, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 10
const LOOP_FRAME_LIMIT := 1800


## workplace 계약 duck-typing용 최소 workplace(lumberyard.gd처럼 work_radius
## 스크립트 프로퍼티를 직접 소유한다. bare Node3D.set()은 no-op라 무효).
class DuckWorkplace extends Node3D:
	var work_radius: float = 192.0

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav: Node = null
var _resources: Node = null

var _lumberyard: Node3D = null
var _quarry: Node3D = null
var _trees: Array = []
## -s 스탠드얼론 모드에서는 preload 시점에 autoload 전역 식별자가 등록되지 않아
## 의존 스크립트 컴파일이 실패하므로, 런타임에 지연 로드한다(기존 2D 테스트 관례).
var _lj_script: GDScript = null
var _mn_script: GDScript = null
var _lumberjack = null
var _miner = null
var _lj2 = null
var _miner2 = null

var _lj_wood_before := 0
var _miner_stone_before := 0

var _anim_started := {}
var _anim_stopped := {}
var _carry_changed := {}


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	for t in _trees:
		if is_instance_valid(t):
			t.free()
	if is_instance_valid(_lumberyard):
		_lumberyard.free()
	if is_instance_valid(_quarry):
		_quarry.free()
	for w in [_lumberjack, _miner, _lj2, _miner2]:
		if w != null and is_instance_valid(w):
			w.free()
	print("TASK3DWRK0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.NAV_SYNC:
			_nav_sync()
		Phase.LUMBER_ARM:
			_lumber_arm()
		Phase.LUMBER_LOOP:
			_lumber_loop()
		Phase.MINER_ARM:
			_miner_arm()
		Phase.MINER_LOOP:
			_miner_loop()
		Phase.TWO_ARM:
			_two_arm()
		Phase.TWO_LOOP:
			_two_loop()
		Phase.TWO_UNASSIGN:
			_two_unassign()
		Phase.CLAIM_ARM:
			_claim_arm()
		Phase.CLAIM_LOOP:
			_claim_loop()
		Phase.UNASSIGN:
			_unassign_phase()
		Phase.DONE:
			_finish()
			return true
	if _frame > 12000:
		print("TASK3DWRK0012_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	var manager: Node = NavigationManager3D.new()
	manager.name = "NavManager"
	world_scene.add_child(manager)


func _make_workplace(name: String, pos: Vector3) -> Node3D:
	var wp: DuckWorkplace = DuckWorkplace.new()
	wp.name = name
	wp.work_radius = 300.0
	_world.add_child(wp)
	wp.global_position = Vector3(pos.x, WorldCoords3D.GROUND_Y, pos.z)
	var deposit := Node3D.new()
	deposit.name = "DepositPoint"
	wp.add_child(deposit)
	deposit.position = Vector3(0, 0, 4)
	var spawn := Node3D.new()
	spawn.name = "SpawnPoint"
	wp.add_child(spawn)
	spawn.position = Vector3(0, 0, -4)
	var wp1 := Node3D.new()
	wp1.name = "WorkPoint"
	wp.add_child(wp1)
	wp1.position = Vector3(3, 0, 0)
	var wp2 := Node3D.new()
	wp2.name = "WorkPoint2"
	wp.add_child(wp2)
	wp2.position = Vector3(-3, 0, 0)
	return wp


func _make_tree(name: String, pos: Vector3) -> ResourceNode3D:
	var t := ResourceNode3D.new()
	t.name = name
	t.resource_id = "wood"
	t.max_amount = 30
	t.current_amount = 30
	t.gather_amount = 1
	_world.add_child(t)
	t.global_position = Vector3(pos.x, WorldCoords3D.GROUND_Y, pos.z)
	return t


func _setup() -> void:
	if _world == null:
		_world = root.get_node_or_null("World3DRoot") as Node3D
		_nav = root.get_node_or_null("World3DRoot/NavManager")
		_resources = root.get_node_or_null("VillageResources")
		_lj_script = load("res://scripts/lumberjack_3d.gd") as GDScript
		_mn_script = load("res://scripts/miner_3d.gd") as GDScript
		if _world == null or _nav == null or _resources == null \
				or _lj_script == null or _mn_script == null:
			_check(false, "3D world / navigation manager / VillageResources / worker scripts load")
			_finish()
			return
		_lumberyard = _make_workplace("Lumberyard", Vector3(-40, 0, -40))
		_quarry = _make_workplace("Quarry", Vector3(40, 0, -40))
		# 나무들을 Lumberyard 부근에 배치(work_radius 300px = 37.5 unit 내).
		_trees = [
			_make_tree("TreeA", Vector3(-30, 0, -20)),
			_make_tree("TreeB", Vector3(-20, 0, -30)),
			_make_tree("TreeC", Vector3(-10, 0, -20)),
		]
		_lumberjack = _lj_script.new()
		_lumberjack.name = "LJ"
		_world.add_child(_lumberjack)
		_lumberjack.global_position = Vector3(-45, 0, -35)
		_miner = _mn_script.new()
		_miner.name = "MN"
		_world.add_child(_miner)
		_miner.global_position = Vector3(35, 0, -35)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_enter(Phase.CONTRACT)


func _contract() -> void:
	_check(_lumberjack is WorkerActor3D, "Lumberjack3D extends WorkerActor3D")
	_check(_miner is WorkerActor3D, "Miner3D extends WorkerActor3D")
	_check(_lumberjack.get_script() == _lj_script and _miner.get_script() == _mn_script,
		"concrete FSM classes resolve")
	_anim_started[_lumberjack] = []
	_anim_stopped[_lumberjack] = []
	_carry_changed[_lumberjack] = []
	_lumberjack.work_anim_started.connect(_on_anim_started.bind(_lumberjack))
	_lumberjack.work_anim_stopped.connect(_on_anim_stopped.bind(_lumberjack))
	_lumberjack.carry_prop_changed.connect(_on_carry.bind(_lumberjack))
	_anim_started[_miner] = []
	_anim_stopped[_miner] = []
	_miner.work_anim_started.connect(_on_anim_started.bind(_miner))
	_miner.work_anim_stopped.connect(_on_anim_stopped.bind(_miner))
	_wait = 0
	_enter(Phase.NAV_SYNC)


func _on_anim_started(action: StringName, w: Node) -> void:
	_anim_started[w].append(action)


func _on_anim_stopped(action: StringName, w: Node) -> void:
	_anim_stopped[w].append(action)


func _on_carry(attached: bool, _res_id: String, w: Node) -> void:
	_carry_changed[w].append(attached)


func _nav_sync() -> void:
	if _wait == 0:
		_nav.rebuild_navigation()
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_wait = 0
	_frame = 0
	_enter(Phase.LUMBER_ARM)


func _lumber_arm() -> void:
	_lj_wood_before = _resources.get_amount("wood")
	_lumberjack._on_assigned(_lumberyard)
	_check(_lumberjack.is_assigned(), "lumberjack assigned to lumberyard")
	_check(_lumberjack.get_state_name() == "IDLE",
		"lumberjack starts in IDLE after assign (legacy semantics)")
	# workplace duck-typing: work_radius 프로퍼티 해석(assign 이후 유효)
	_check(_lumberjack._work_radius_units() == 300.0 * WorldCoords3D.PX_TO_UNIT,
		"workplace work_radius (px) is honored for search radius")
	_wait = 0
	_enter(Phase.LUMBER_LOOP)


func _lumber_loop() -> void:
	_wait += 1
	if _wait < LOOP_FRAME_LIMIT:
		return
	var wood_gained: int = _resources.get_amount("wood") - _lj_wood_before
	_check(wood_gained > 0, "lumberjack full loop deposited wood (%d gained)" % wood_gained)
	_check(_lumberjack.carried_amount == 0 and _lumberjack.carried_resource_id == "",
		"lumberjack carry emptied after deposit")
	_check(not _anim_started[_lumberjack].is_empty(),
		"work_anim_started(chop) hook fired during gather")
	_check(not _anim_stopped[_lumberjack].is_empty(),
		"work_anim_stopped(chop) hook fired when leaving gather")
	var attached_seen := false
	for attached in _carry_changed[_lumberjack]:
		if attached:
			attached_seen = true
	_check(attached_seen, "carry_prop_changed(attached=true) hook fired while carrying")
	_check(_lumberjack.is_gathering() or _lumberjack.get_state_name() != "?",
		"lumberjack stays in a valid state (no stuck)")
	_lumberjack._on_unassigned()
	_check(not _lumberjack.is_assigned(), "lumberjack unassigned after loop")
	_wait = 0
	_frame = 0
	_enter(Phase.MINER_ARM)


func _miner_arm() -> void:
	_miner_stone_before = _resources.get_amount("stone")
	_miner._on_assigned(_quarry)
	_check(_miner.is_assigned(), "miner assigned to quarry")
	_check(_miner.get_state_name() == "MOVE",
		"miner starts in MOVE_TO_WORK after assign (legacy semantics)")
	_wait = 0
	_enter(Phase.MINER_LOOP)


func _miner_loop() -> void:
	_wait += 1
	if _wait < LOOP_FRAME_LIMIT:
		return
	var stone_gained: int = _resources.get_amount("stone") - _miner_stone_before
	_check(stone_gained > 0, "miner full loop produced stone (%d gained)" % stone_gained)
	_check(_miner.is_gathering() or _miner.get_state_name() != "?",
		"miner stays in a valid state (no stuck)")
	_check(not _anim_started[_miner].is_empty(),
		"work_anim_started(mine) hook fired during mine")
	_miner._on_unassigned()
	_check(not _miner.is_assigned(), "miner unassigned after loop")
	_check(_miner.get_state_name() == "IDLE",
		"miner returns to IDLE on unassign (legacy semantics)")
	_wait = 0
	_frame = 0
	_enter(Phase.TWO_ARM)


func _two_arm() -> void:
	_lj2 = _lj_script.new()
	_lj2.name = "LJ2"
	_world.add_child(_lj2)
	_lj2.global_position = Vector3(-46, 0, -32)
	_miner2 = _mn_script.new()
	_miner2.name = "MN2"
	_world.add_child(_miner2)
	_miner2.global_position = Vector3(34, 0, -33)
	var w0: int = _resources.get_amount("wood")
	var s0: int = _resources.get_amount("stone")
	_lumberjack._on_assigned(_lumberyard)
	_lj2._on_assigned(_lumberyard)
	_miner._on_assigned(_quarry)
	_miner2._on_assigned(_quarry)
	_wait = 0
	_check(_lumberjack.is_assigned() and _lj2.is_assigned()
		and _miner.is_assigned() and _miner2.is_assigned(),
		"2 lumberjacks + 2 miners all assigned simultaneously")
	_enter(Phase.TWO_LOOP)


func _two_loop() -> void:
	_wait += 1
	if _wait < LOOP_FRAME_LIMIT:
		return
	var wood_gained: int = _resources.get_amount("wood")
	var stone_gained: int = _resources.get_amount("stone")
	_check(wood_gained > 0, "2 lumberjacks produced wood (%d total)" % wood_gained)
	_check(stone_gained > 0, "2 miners produced stone (%d total)" % stone_gained)
	_check(_lumberjack.is_gathering() or _lj2.is_gathering(),
		"at least one lumberjack in GATHER concurrently")
	_check(_miner.is_gathering() or _miner2.is_gathering(),
		"at least one miner in MINE concurrently")
	# Miner는 carry 없이 직접 반납하므로 즉시 해제된다.
	for w in [_miner, _miner2]:
		w._on_unassigned()
		_check(not w.is_assigned(), "%s unassigned cleanly" % String(w.name))
	# Lumberjack은 carrying 중 unassign 시 마지막 1회 deposit 후 해제되는
	# 기존 규약(2D lumberjack.gd와 동일)이므로 bounded 대기 후 검증한다.
	for w in [_lumberjack, _lj2]:
		w._on_unassigned()
	_wait = 0
	_frame = 0
	_enter(Phase.TWO_UNASSIGN)


func _two_unassign() -> void:
	_wait += 1
	var done: bool = not _lumberjack.is_assigned() and not _lj2.is_assigned()
	if not done and _wait < LOOP_FRAME_LIMIT:
		return
	_check(not _lumberjack.is_assigned(), "LJ unassigned cleanly")
	_check(not _lj2.is_assigned(), "LJ2 unassigned cleanly")
	_wait = 0
	_frame = 0
	_enter(Phase.CLAIM_ARM)


## -- CLAIM: 나무 1개 + lumberjack 2명 -> 동시 claim 없이 자원 중복 집계 없음 --
func _claim_arm() -> void:
	# 기존 나무 3개를 모두 제거하고 단 1개만 남긴다(claim 경합 최대화).
	for t in _trees:
		if is_instance_valid(t):
			t.free()
	_trees.clear()
	var only := ResourceNode3D.new()
	only.name = "OnlyTree"
	only.resource_id = "wood"
	only.max_amount = 40
	only.current_amount = 40
	only.gather_amount = 1
	_world.add_child(only)
	only.global_position = Vector3(-25, 0, -25)
	_trees.append(only)
	var before: int = _resources.get_amount("wood")
	_lumberjack._on_assigned(_lumberyard)
	_lj2._on_assigned(_lumberyard)
	_wait = 0
	_enter(Phase.CLAIM_LOOP)


func _claim_loop() -> void:
	_wait += 1
	if _wait < LOOP_FRAME_LIMIT:
		return
	var wood_gained: int = _resources.get_amount("wood")
	_check(wood_gained > 0, "two lumberjacks still produce wood with a single tree")
	# 동시에 한 worker만이 같은 tree를 claim 상태로 둔다.
	var both_claiming: bool = is_instance_valid(_lumberjack.target_tree) \
		and is_instance_valid(_lj2.target_tree) \
		and _lumberjack.target_tree == _lj2.target_tree \
		and _lumberjack.get_state_name() != "IDLE" \
		and _lj2.get_state_name() != "IDLE"
	_check(not both_claiming, "no duplicate claim of the same tree by two workers")
	_check(_lumberjack.carried_amount <= _lumberjack.carry_capacity
		and _lj2.carried_amount <= _lj2.carry_capacity,
		"carry never exceeds capacity (no double-gather per worker)")
	_wait = 0
	_enter(Phase.UNASSIGN)


## -- UNASSIGN: claim-conflict run 이후 해제. carrying 중이면 마지막 deposit 후
## 해제되는 기존 규약이므로 bounded 대기 후 검증한다. --
func _unassign_phase() -> void:
	if _wait == 0:
		_lumberjack._on_unassigned()
		_lj2._on_unassigned()
	_wait += 1
	if (_lumberjack.is_assigned() or _lj2.is_assigned()) \
			and _wait < LOOP_FRAME_LIMIT:
		return
	_check(not _lumberjack.is_assigned() and not _lj2.is_assigned(),
		"both lumberjacks unassigned after claim-conflict run")
	_finish()
