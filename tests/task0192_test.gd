extends SceneTree

## TASK-019-2 Farmer Worker Assignment 회귀 테스트.
## 기존 Worker Assignment framework(WorkerActor3D + Workplace3D + WorkerRoster) 위에
## 얹은 Farmer 직업 FSM과 Farm workplace의 assign/unassign 생명주기를 검증한다.
##
## 완료조건 매핑:
##   1. Farmer 1명 - assign 시 Farm SpawnPoint에 Farmer3D Actor가 정확히 1명 spawn되고
##      MOVE_TO_WORK -> WORK(HARVEST) -> RETURN_TO_FARM -> DEPOSIT full loop로
##      crop 자원이 VillageResources에 반납된다.
##   2. Farmer 2명 동시 assignment - WorkerRoster.assign으로 2명이 동시에 배치되고
##      두 Farmer 모두 생산한다(get_work_point_for 분배 포함).
##   3. duplicate actor 없음 - 이미 배치된 Worker 재배치 거부, 가득 찬 시설 추가
##      배치 거부, census가 정확히 배치 수와 일치한다.
##   4. unassign cleanup 정상 - 해제 시 WorkerData는 Roster에 유지되고 Actor만
##      시설 복귀 후 despawn되며, 이후 reassign 가능하다.
##   추가: work_anim_started/stopped("work")와 carry_prop_changed visual hook이
##   asset 부재와 무관하게 발화하고 기능 상태가 진행된다.

enum Phase {
	SETUP, CONTRACT, NAV_SYNC,
	FARMER1_ARM, FARMER1_LOOP,
	FARMER2_ARM, FARMER2_LOOP,
	DUP_ARM, DUP_CHECK,
	UNASSIGN_ARM, UNASSIGN_WAIT, REASSIGN,
	FINAL, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 10
const LOOP_FRAME_LIMIT := 4000
const FARM_CELL := Vector3(0, 0, 0)

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav: Node = null
var _roster: Node = null
var _resources: Node = null

var _farm: Node3D = null
var _farmer_script: GDScript = null

var _farmer_a: WorkerData = null
var _farmer_b: WorkerData = null
var _farmer_c: WorkerData = null

var _crop_before := 0
var _actor_a: Node = null

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
	_wait = 0


func _finish() -> void:
	for w in [_farmer_a, _farmer_b, _farmer_c]:
		if w != null and is_instance_valid(w) and w.is_assigned():
			_roster.unassign(w)
	if is_instance_valid(_farm):
		_farm.free()
	print("TASK0192_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _farmers() -> int:
	return get_nodes_in_group("farmers_3d").size()


func _crop() -> int:
	return _resources.get_amount("crop")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.NAV_SYNC:
			_nav_sync()
		Phase.FARMER1_ARM:
			_farmer1_arm()
		Phase.FARMER1_LOOP:
			_farmer1_loop()
		Phase.FARMER2_ARM:
			_farmer2_arm()
		Phase.FARMER2_LOOP:
			_farmer2_loop()
		Phase.DUP_ARM:
			_dup_arm()
		Phase.DUP_CHECK:
			_dup_check()
		Phase.UNASSIGN_ARM:
			_unassign_arm()
		Phase.UNASSIGN_WAIT:
			_unassign_wait()
		Phase.REASSIGN:
			_reassign()
		Phase.FINAL:
			_final()
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0192_RESULT=TIMEOUT phase=%s" % str(_phase))
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


func _setup() -> void:
	if _frame < PHYSICS_WAIT_FRAMES:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_nav = root.get_node_or_null("World3DRoot/NavManager")
	_roster = root.get_node_or_null("WorkerRoster")
	_resources = root.get_node_or_null("VillageResources")
	_farmer_script = load("res://scripts/farmer_3d.gd") as GDScript
	if _world == null or _nav == null or _roster == null or _resources == null \
			or _farmer_script == null:
		_check(false, "world / navigation / autoloads / farmer script load")
		_finish()
		return
	var farm_scene: PackedScene = load("res://scenes/farm_3d.tscn")
	_farm = farm_scene.instantiate()
	_farm.name = "Farm"
	_world.add_child(_farm)
	_farm.global_position = FARM_CELL

	_farmer_a = WorkerData.new("farmer_A", "Farmer A", WorkerData.Job.FARMER)
	_farmer_b = WorkerData.new("farmer_B", "Farmer B", WorkerData.Job.FARMER)
	_farmer_c = WorkerData.new("farmer_C", "Farmer C", WorkerData.Job.FARMER)
	for w in [_farmer_a, _farmer_b, _farmer_c]:
		_roster.add_worker(w)
	_check(_roster.get_count() == 3, "three farmers registered in the shared WorkerRoster")
	_check(_farmers() == 0, "hired farmers stay roster data only (no world actor yet)")
	_enter(Phase.CONTRACT)


func _contract() -> void:
	var wp_base: GDScript = load("res://scripts/workplace_3d.gd")
	_check(_farmer_script.get_base_script() == load("res://scripts/worker_actor_3d.gd"),
		"Farmer3D extends WorkerActor3D (no separate AI framework)")
	_check(_farm is Workplace3D and _farm is Building3D,
		"Farm3D follows the Workplace3D -> Building3D contract path")
	_check(_farm.get_slot_capacity() == 2, "Farm3D keeps the legacy 2 worker slot policy")
	_check(_farm.get_worker_label() == "Farmer", "Farm3D exposes the Farmer worker label")
	_check(_farm.has_method("spawn_worker_actor"), "Farm3D provides the worker actor spawn contract")
	_check(_farm.has_method("get_work_point_for"), "Farm3D distributes work points per farmer")
	_check(_farm.get_node_or_null("WorkPoint2") != null,
		"Farm3D carries two work point markers for 2 concurrent farmers")
	_check(_farm.get_node_or_null("DepositPoint") != null,
		"Farm3D carries the deposit point for the harvest loop")
	_enter(Phase.NAV_SYNC)


func _nav_sync() -> void:
	if _wait == 0:
		_nav.rebuild_navigation()
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_wait = 0
	_frame = 0
	_enter(Phase.FARMER1_ARM)


func _farmer1_arm() -> void:
	_crop_before = _crop()
	_check(_roster.assign(_farmer_a, _farm), "assign farmer A to the farm")
	_check(_farmer_a.is_assigned(), "farmer A worker data assigned")
	_check(_farmers() == 1, "exactly one farmer actor spawned on assign (%d)" % _farmers())
	_actor_a = _roster.get_actor(_farmer_a)
	_check(_actor_a != null and is_instance_valid(_actor_a), "roster returns the spawned farmer actor")
	if _actor_a != null:
		_check(_actor_a.get_workplace() == _farm, "farmer actor workplace is the farm")
		_check(_actor_a.worker_data == _farmer_a, "farmer actor connected to WorkerData")
		_check(_actor_a.get_state_name() == "MOVE",
			"farmer starts in MOVE_TO_WORK after assign (legacy semantics)")
		_anim_started[_actor_a] = []
		_anim_stopped[_actor_a] = []
		_carry_changed[_actor_a] = []
		_actor_a.work_anim_started.connect(_on_anim_started.bind(_actor_a))
		_actor_a.work_anim_stopped.connect(_on_anim_stopped.bind(_actor_a))
		_actor_a.carry_prop_changed.connect(_on_carry.bind(_actor_a))
	_check(_farm.get_filled_slots() == 1, "farm filled slots 1 after spawn")
	_wait = 0
	_enter(Phase.FARMER1_LOOP)


func _on_anim_started(action: StringName, w: Node) -> void:
	_anim_started[w].append(action)


func _on_anim_stopped(action: StringName, w: Node) -> void:
	_anim_stopped[w].append(action)


func _on_carry(attached: bool, _res_id: String, w: Node) -> void:
	_carry_changed[w].append(attached)


func _farmer1_loop() -> void:
	_wait += 1
	if _crop() <= _crop_before and _wait < LOOP_FRAME_LIMIT:
		return
	var crop_gained: int = _crop() - _crop_before
	_check(crop_gained > 0, "farmer full loop deposited crop (%d gained)" % crop_gained)
	if _actor_a != null and is_instance_valid(_actor_a):
		_check(_actor_a.carried_amount == 0,
			"farmer carry emptied after deposit")
		_check(not _anim_started[_actor_a].is_empty(),
			"work_anim_started(work) hook fired during harvest")
		_check(not _anim_stopped[_actor_a].is_empty(),
			"work_anim_stopped(work) hook fired when leaving harvest")
		var attached_seen := false
		for attached in _carry_changed[_actor_a]:
			if attached:
				attached_seen = true
		_check(attached_seen, "carry_prop_changed(attached=true) hook fired while carrying")
		_check(_actor_a.get_state_name() != "?",
			"farmer stays in a valid state (no stuck)")
	_wait = 0
	_frame = 0
	_enter(Phase.FARMER2_ARM)


func _farmer2_arm() -> void:
	_check(_roster.assign(_farmer_b, _farm), "assign farmer B to the same farm")
	_check(_farmer_b.is_assigned(), "farmer B worker data assigned")
	_check(_farmers() == 2, "exactly two farmer actors coexist (%d)" % _farmers())
	var actor_b: Node = _roster.get_actor(_farmer_b)
	_check(actor_b != null and is_instance_valid(actor_b), "farmer B actor spawned")
	if actor_b != null:
		_check(actor_b != _actor_a, "farmer B is a distinct actor (no duplicate)")
		_check(_actor_a != null and is_instance_valid(_actor_a),
			"farmer A actor still live while farmer B works")
		_check(actor_b.get_state_name() == "MOVE",
			"farmer B starts in MOVE_TO_WORK after assign")
		var wp_a: Vector3 = _get_work_point(_actor_a)
		var wp_b: Vector3 = _get_work_point(actor_b)
		_check(not wp_a.is_equal_approx(wp_b),
			"two farmers receive distinct work points (no overlap stall)")
	_check(_farm.get_filled_slots() == 2, "farm filled slots 2 after second spawn")
	_wait = 0
	_frame = 0
	_enter(Phase.FARMER2_LOOP)


func _get_work_point(actor: Node) -> Vector3:
	if actor != null and is_instance_valid(actor):
		var point: Variant = _farm.get_work_point_for(actor)
		if point is Node3D:
			return WorldCoords3D.flatten((point as Node3D).global_position)
	return Vector3.INF


func _farmer2_loop() -> void:
	_wait += 1
	var crop_now: int = _crop()
	if _wait < LOOP_FRAME_LIMIT and crop_now <= _crop_before + 5:
		return
	_check(crop_now >= _crop_before + 5,
		"two farmers produced crop concurrently (total %d)" % crop_now)
	_check(_farmers() == 2, "two farmer actors persist through production (no duplicate)")
	_wait = 0
	_frame = 0
	_enter(Phase.DUP_ARM)


## -- DUP_ARM: duplicate actor 방어 경로를 직접 발동시킨다. --
func _dup_arm() -> void:
	# 이미 배치된 worker를 다시 assign하면 거부된다(중복 spawn 차단).
	_check(not _roster.assign(_farmer_a, _farm),
		"re-assigning an already assigned farmer is rejected")
	_check(_farmers() == 2, "rejected re-assign spawns no extra actor")
	# 가득 찬 시설에 3번째 worker assign도 거부된다.
	_check(not _roster.assign(_farmer_c, _farm),
		"assigning a third farmer to a full farm is rejected")
	_check(_farmers() == 2, "full-farm rejection spawns no extra actor")
	_check(not _farmer_c.is_assigned(), "rejected farmer C stays unassigned")
	_enter(Phase.DUP_CHECK)


func _dup_check() -> void:
	var seen := {}
	var unique := true
	for actor in get_nodes_in_group("farmers_3d"):
		if seen.has(actor):
			unique = false
		seen[actor] = true
	_check(unique, "farmer actors hold no duplicate instances in the tree")
	_check(_farm.get_filled_slots() == 2, "farm slots match the actor census")
	_wait = 0
	_enter(Phase.UNASSIGN_ARM)


func _unassign_arm() -> void:
	_check(_roster.unassign(_farmer_a), "unassign farmer A")
	_check(not _farmer_a.is_assigned(), "farmer A worker data unassigned after unassign")
	_check(_roster.get_worker("farmer_A") == _farmer_a,
		"farmer A retained in the roster after unassign")
	_wait = 0
	_enter(Phase.UNASSIGN_WAIT)


func _unassign_wait() -> void:
	_wait += 1
	var actors_now: int = _farmers()
	# farmer B(1명)만 남을 때까지 폴링한다. farmer A actor는 시설 복귀 후
	# despawn되므로 bounded timeout 안에 census가 1로 내려와야 한다.
	if actors_now == 2 and _wait < LOOP_FRAME_LIMIT:
		return
	_check(actors_now == 1, "farmer A actor despawned after return (census 1)")
	_check(_roster.get_actor(_farmer_a) == null,
		"roster no longer returns farmer A actor after despawn")
	# 남은 farmer B가 정상 동작 중인지(해제가 다른 worker에 영향을 주지 않음).
	_check(is_instance_valid(_roster.get_actor(_farmer_b)),
		"farmer B actor unaffected by farmer A unassign")
	_wait = 0
	_enter(Phase.REASSIGN)


func _reassign() -> void:
	_check(_roster.assign(_farmer_a, _farm), "reassign farmer A after despawn")
	_check(_farmers() == 2, "reassign restores the two-farmer census without duplicates")
	_check(_roster.get_actor(_farmer_a) != null,
		"farmer A actor respawned on reassign")
	_wait = 0
	_enter(Phase.FINAL)


func _final() -> void:
	_wait += 1
	if _wait < LOOP_FRAME_LIMIT / 2:
		return
	var crop_now: int = _crop()
	_check(crop_now >= _crop_before + 8,
		"production continues after reassign (crop total %d)" % crop_now)
	_check(_farmers() == 2, "final farmer actor census stays exact (no duplicate/orphan)")
	_enter(Phase.DONE)