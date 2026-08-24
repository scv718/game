extends SceneTree

## TASK-3D-RES-001-3 Resource Regression 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위(큐 자동검증 항목 대응):
##   - Tree claim / duplicate claim 없음.
##   - Tree depletion / regrowth.
##   - Stone source state(occupy/release/get_quarry).
##   - VillageResources Wood/Stone 반영.
##   - freed resource reference 없음.
##   - Foundation selection/raycast 회귀(자원 뒤 대상 선택 포함).
##   - 3D Runtime에서 2D Resource Actor 의존 없음(scene 노드 구조 검사).

enum Phase {
	SETUP, WOOD_LOOP, REGROW_WAIT, SECOND_GATHER, STONE_STATE,
	FREED_REF_WAIT, FREED_REF_CHECK, SELECTION_REGRESSION, NO_2D_DEP, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const DEBOUNCE_WAIT_FRAMES := 20

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _sel: Node = null
var _cam_ctl: Node = null
var _game_time: Node = null
var _nav_manager: Node = null
var _resources: Node = null
var _tree: Node3D = null
var _stone: Node3D = null
var _worker_a: Node = null
var _worker_b: Node = null
var _interactor: Node = null
var _doomed_tree: Node3D = null
var _probe_target: Area3D = null
var _rebuilds_marker := 0
var _doomed_created := false


class ProbeInteractable extends "res://scripts/interactable_3d.gd":
	var interact_count := 0

	func interact(_interactor: Node) -> Variant:
		interact_count += 1
		return {}


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DRES0013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _screen_of(world_pos: Vector3) -> Vector2:
	return _cam_ctl.get_camera().unproject_position(world_pos)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.WOOD_LOOP:
			_wood_loop()
		Phase.REGROW_WAIT:
			_regrow_wait()
		Phase.SECOND_GATHER:
			_second_gather()
		Phase.STONE_STATE:
			_stone_state()
		Phase.FREED_REF_WAIT:
			_freed_ref_wait()
		Phase.FREED_REF_CHECK:
			_freed_ref_check()
		Phase.SELECTION_REGRESSION:
			_selection_regression()
		Phase.NO_2D_DEP:
			_no_2d_dep()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DRES0013_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	var cam_scene: Node = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	cam_scene.name = "CamController"
	root.add_child(cam_scene)
	_sel = load("res://scripts/world_selection_3d.gd").new()
	_sel.name = "WorldSelection3D"
	root.add_child(_sel)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_cam_ctl = root.get_node_or_null("CamController")
	_game_time = root.get_node_or_null("GameTime")
	_resources = root.get_node_or_null("VillageResources")
	_check(_world != null, "3D world loads")
	_check(_resources != null, "VillageResources autoload available to the 3D runtime")
	if _world == null or _cam_ctl == null or _sel == null or _resources == null:
		_finish()
		return
	_game_time.set_auto_advance(false)
	_nav_manager = load("res://scripts/navigation_manager_3d.gd").new()
	_nav_manager.name = "NavManager"
	_world.add_child(_nav_manager)

	_tree = (load("res://scenes/tree_3d.tscn") as PackedScene).instantiate()
	_tree.name = "RegressionTree"
	_tree.position = Vector3(8.0, 0.0, -6.0)
	_tree.regrow_time = 0.25
	_world.add_child(_tree)

	_stone = (load("res://scenes/stone_deposit_3d.tscn") as PackedScene).instantiate()
	_stone.name = "RegressionDeposit"
	_stone.position = Vector3(-16.0, 0.0, 12.0)
	_world.add_child(_stone)

	_worker_a = Node.new()
	_worker_a.name = "WorkerA"
	root.add_child(_worker_a)
	_worker_b = Node.new()
	_worker_b.name = "WorkerB"
	root.add_child(_worker_b)
	_interactor = Node.new()
	_interactor.name = "Interactor"
	root.add_child(_interactor)
	_enter(Phase.WOOD_LOOP)


## -- WOOD_LOOP: claim -> 채집 -> VillageResources wood 반영 -> 고갈 --
func _wood_loop() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_check(_tree.claim(_worker_a), "lumberjack worker claims the tree in 3D")
	_check(not _tree.claim(_worker_b),
		"duplicate claim from a second worker stays rejected (claim policy)")
	_check(_tree.is_claimed_by_other(_worker_b), "other workers see the active claim")

	for i in 5:
		var result: Dictionary = _tree.interact(_worker_a)
		if not result.is_empty():
			_resources.add(result["resource_id"], result["amount"])
	_check(_tree.current_amount == 0, "tree fully depletes across the gather loop")
	_check(not _tree.can_interact(), "depleted tree refuses further interaction")
	_check(_resources.get_amount("wood") == 5,
		"VillageResources reflects every gathered wood unit (5)")
	_enter(Phase.REGROW_WAIT)


func _regrow_wait() -> void:
	_wait += 1
	if _tree.state != 0:
		if _wait > 300:
			print("FAIL: tree did not regrow within the polling window")
			_failed = true
			_finish()
		return
	_wait = 0
	_check(_tree.current_amount == 5, "regrowth policy restores max_amount")
	_tree.release(_worker_a)
	_check(not _tree.is_claimed(), "claim release lets the loop restart later")
	_enter(Phase.SECOND_GATHER)


## -- SECOND_GATHER: regrow 이후 재작업 가능(기존 regrow 재확인 규약) --
func _second_gather() -> void:
	_check(_tree.claim(_worker_a), "released tree can be reclaimed after regrowth")
	var result: Dictionary = _tree.interact(_worker_a)
	_resources.add(result.get("resource_id", ""), result.get("amount", 0))
	_check(_resources.get_amount("wood") == 6,
		"post-regrowth gather adds new wood through the same contract")
	_enter(Phase.STONE_STATE)


## -- STONE_STATE: deposit occupancy + stone 생산 의미 --
func _stone_state() -> void:
	var quarry_mock := Node.new()
	quarry_mock.name = "QuarryMock"
	root.add_child(quarry_mock)
	_check(_stone.occupy(quarry_mock), "quarry binds onto the free deposit")
	_check(_stone.is_occupied() and _stone.get_quarry() == quarry_mock,
		"occupied deposit reports its bound quarry (source state)")
	var second_quarry := Node.new()
	second_quarry.name = "SecondQuarry"
	root.add_child(second_quarry)
	_check(not _stone.occupy(second_quarry),
		"second quarry cannot bind onto an occupied deposit")
	second_quarry.free()
	quarry_mock.free()
	_stone.release()
	_check(not _stone.is_occupied(), "deposit frees up when the quarry releases it")
	_resources.add("stone", 3)
	_check(_resources.get_amount("stone") == 3,
		"VillageResources keeps reflecting produced stone units")
	_enter(Phase.FREED_REF_WAIT)


## -- FREED_REF_WAIT/FREED_REF_CHECK: freed 자원 참조 정리 --
func _freed_ref_wait() -> void:
	if not _doomed_created:
		_doomed_created = true
		_doomed_tree = (load("res://scenes/tree_3d.tscn") as PackedScene).instantiate()
		_doomed_tree.name = "DoomedTree"
		_doomed_tree.position = Vector3(-4.0, 0.0, -18.0)
		_world.add_child(_doomed_tree)
		_check(_doomed_tree.claim(_worker_b), "doomed tree claimed before free")
		_rebuilds_marker = _nav_manager.nav_rebuild_count
		_doomed_tree.queue_free()
		return
	_wait += 1
	if _wait < DEBOUNCE_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.FREED_REF_CHECK)


## -- FREED_REF_CHECK: freed 자원 잔여 인스턴스/rebake 요청 확인 --
func _freed_ref_check() -> void:
	_check(not is_instance_valid(_doomed_tree),
		"freed tree leaves no orphan instance behind")
	_check(_nav_manager.nav_rebuild_count > _rebuilds_marker,
		"freed resource still requested its final navigation rebake")
	_enter(Phase.SELECTION_REGRESSION)


## -- SELECTION_REGRESSION: Foundation 선택 계약 위에서 자원 정책 유지 --
func _selection_regression() -> void:
	if _probe_target == null:
		_probe_target = ProbeInteractable.new()
		_probe_target.collision_layer = CollisionLayers3D.INTERACTABLE
		_probe_target.collision_mask = 0
		var sphere := SphereShape3D.new()
		sphere.radius = 1.0
		var shape := CollisionShape3D.new()
		shape.shape = sphere
		_probe_target.add_child(shape)
		_probe_target.position = Vector3(26.0, 1.0, 10.0)
		_world.add_child(_probe_target)
		# 자원(deposit block)을 광선 경로 지면 교차점에 세워 가림을 강제한다.
		var ground_hit: Vector3 = _cam_ctl.ground_point_from_screen(
			_screen_of(_probe_target.global_position))
		_stone.position = WorldCoords3D.flatten(ground_hit)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	var returned = _sel.select_at_screen_position(_screen_of(_probe_target.global_position))
	_check(returned == _probe_target,
		"stone deposit on the click ray never blocks the interactable behind it")
	_push_right_click_center()
	_check(_sel.get_selected() == null, "right-click deselect still works over resources")
	_probe_target.queue_free()
	_probe_target = null
	_stone.position = Vector3(-16.0, 0.0, 12.0)
	_wait = 0
	_enter(Phase.NO_2D_DEP)


func _push_right_click_center() -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_visible_rect().size * 0.5
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = root.get_visible_rect().size * 0.5
	root.push_input(event)


## -- NO_2D_DEP: 3D 자원 scene에 2D Resource Actor 의존 없음 --
func _no_2d_dep() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	var allowed := {
		"Node3D": true, "Area3D": true, "StaticBody3D": true,
		"CollisionShape3D": true, "MeshInstance3D": true,
	}
	var clean := true
	for scene_path in ["res://scenes/tree_3d.tscn", "res://scenes/stone_deposit_3d.tscn"]:
		var instance: Node = (load(scene_path) as PackedScene).instantiate()
		var stack: Array[Node] = [instance]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if not allowed.has(node.get_class()):
				clean = false
				print("  offending node in %s: %s (%s)" % [scene_path, node.name, node.get_class()])
			stack.append_array(node.get_children())
		instance.free()
	_check(clean,
		"resource scenes contain only 3D runtime nodes (no 2D actor dependency)")
	_finish()
