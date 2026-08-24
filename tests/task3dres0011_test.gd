extends SceneTree

## TASK-3D-RES-001-1 ResourceNode3D Base / Selection 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. Foundation Interaction3D 계약 사용(Interactable3D 상속, Area3D 볼륨).
##   2. claim/release 경량 claim 규약(2D resource_node.gd와 동일 시맨틱).
##   3. Worker 전용 자원 정책(is_selectable == false)과 선택 광선 no-op.
##   4. 적절한 3D hit volume(RESOURCE layer body/area 조회로 식별).
##   5. decoration과 구분됨(비주얼 전용 mesh는 physics 조회에 걸리지 않음).
##   6. depletion/regrowth 시 visual/collision state 일관 + nav rebake 요청.
##   7. instance 제거/freed 후 claim 정리와 nav rebake 요청(stale state 부재).
##
## 전역 클래스 정적 의존을 피하는 관례(task3d0013/0014 규약)에 따라
## 스크립트는 load()로 늦게 로드한다. shape 수치 비교는 32bit float 오차를
## 흡수하는 근사 비교(task3d0014 _v3_near 규약)를 쓴다.

enum Phase {
	SETUP, CONTRACT, SCENE_SETUP, HIT_VOLUMES, SELECTION_POLICY,
	BLOCKING_REGRESSION, DEPLETE, DEPLETED_NAV_WAIT, REGROW_POLL,
	REGROW_NAV_WAIT, CLEANUP_SETUP, CLEANUP_CHECK, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const DEBOUNCE_WAIT_FRAMES := 20
const SHAPE_EPS := 0.001

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _sel: Node = null
var _cam_ctl: Node = null
var _game_time: Node = null
var _nav_manager: Node = null
var _res_script: GDScript = null
var _tree: Node3D = null
var _stone: Node3D = null
var _deco: MeshInstance3D = null
var _probe_target: Area3D = null
var _extra_tree: Node3D = null
var _rebuilds_marker := 0


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
	var interactor := root.get_node_or_null("GatherInteractor")
	if interactor != null:
		interactor.free()
	print("TASK3DRES0011_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= SHAPE_EPS


func _screen_of(world_pos: Vector3) -> Vector2:
	return _cam_ctl.get_camera().unproject_position(world_pos)


func _push_left_click(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_pos
	root.push_input(event)


## RESOURCE mask 수직 광선. bodies/areas 토글로 자원의 물리 volume을 식별한다.
func _downward_hit(xz: Vector3, bodies: bool, areas: bool) -> Dictionary:
	var space := _world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, 20.0, xz.z), Vector3(xz.x, -1.0, xz.z),
		CollisionLayers3D.RESOURCE)
	query.collide_with_bodies = bodies
	query.collide_with_areas = areas
	return space.intersect_ray(query)


func _trunk_shape() -> CylinderShape3D:
	return _tree.get_node("TrunkBlock/TrunkCollision").shape as CylinderShape3D


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.SCENE_SETUP:
			_scene_setup()
		Phase.HIT_VOLUMES:
			_hit_volumes()
		Phase.SELECTION_POLICY:
			_selection_policy()
		Phase.BLOCKING_REGRESSION:
			_blocking_regression()
		Phase.DEPLETE:
			_deplete()
		Phase.DEPLETED_NAV_WAIT:
			_depleted_nav_wait()
		Phase.REGROW_POLL:
			_regrow_poll()
		Phase.REGROW_NAV_WAIT:
			_regrow_nav_wait()
		Phase.CLEANUP_SETUP:
			_cleanup_setup()
		Phase.CLEANUP_CHECK:
			_cleanup_check()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DRES0011_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	_check(_world != null, "empty 3D world loads")
	_check(_cam_ctl != null, "camera controller 3D loads")
	_check(_sel != null, "world selection 3D loads")
	if _world == null or _cam_ctl == null or _sel == null:
		_finish()
		return
	# phase gate 판정을 결정적으로 만들기 위해 자동 시간 진행을 멈춘다(종료 시 복원).
	_game_time.set_auto_advance(false)
	_nav_manager = load("res://scripts/navigation_manager_3d.gd").new()
	_nav_manager.name = "NavManager"
	_world.add_child(_nav_manager)
	_enter(Phase.CONTRACT)


## -- CONTRACT: Foundation 계약 상속 + 기본값 + claim 규약 --
func _contract() -> void:
	_res_script = load("res://scripts/resource_node_3d.gd")
	var base_script: GDScript = load("res://scripts/interactable_3d.gd")
	_check(_res_script.get_base_script() == base_script,
		"ResourceNode3D extends the Foundation Interactable3D contract")
	var node: Area3D = _res_script.new()
	_check(node is Area3D, "ResourceNode3D contract is an Area3D hit volume holder")
	_check(not node.is_selectable(),
		"resource nodes stay worker-only via the is_selectable hook")
	_check(node.resource_id == "wood" and node.max_amount == 5
		and node.current_amount == 5 and node.gather_amount == 1,
		"gather amounts keep legacy defaults (wood 5x1)")
	_check(node.can_interact(), "fresh node with amount left can be gathered")
	node.free()

	var worker_a := Node.new()
	var worker_b := Node.new()
	var claim_node: Area3D = _res_script.new()
	_check(claim_node.claim(worker_a), "first worker claims an unclaimed node")
	_check(not claim_node.claim(worker_b), "duplicate claim by a second worker is rejected")
	_check(claim_node.is_claimed_by_other(worker_b),
		"claimed node reports other workers via is_claimed_by_other")
	claim_node.release(worker_b)
	_check(claim_node.is_claimed(), "release by a different worker does not clear the claim")
	claim_node.release(worker_a)
	_check(not claim_node.is_claimed(), "release by the claiming worker clears the claim")
	_check(claim_node.claim(worker_b), "node can be reclaimed after release")
	claim_node.free()
	worker_a.free()
	worker_b.free()
	_enter(Phase.SCENE_SETUP)


## -- SCENE_SETUP: scene 인스턴스 + physics 등록 대기 --
func _scene_setup() -> void:
	if _tree == null:
		_tree = (load("res://scenes/tree_3d.tscn") as PackedScene).instantiate()
		_tree.position = Vector3(6.0, 0.0, -4.0)
		_tree.regrow_time = 0.25
		_world.add_child(_tree)

		_stone = (load("res://scenes/stone_deposit_3d.tscn") as PackedScene).instantiate()
		_stone.position = Vector3(-12.0, 0.0, 8.0)
		_world.add_child(_stone)

		_deco = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 1.0, 2.0)
		_deco.mesh = box
		_deco.position = Vector3(-30.0, 0.5, -30.0)
		_world.add_child(_deco)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_check(_tree.is_in_group("resource_nodes_3d"),
		"Tree3D joins the worker-facing resource_nodes_3d group")
	_check(_tree.prompt == "채집", "tree prompt keeps the legacy gather prompt")
	_check(_stone.is_in_group("stone_deposits_3d"),
		"StoneDeposit3D joins the dedicated stone_deposits_3d group")
	_enter(Phase.HIT_VOLUMES)


## -- HIT_VOLUMES: 3D hit volume 존재 + decoration 구분 --
func _hit_volumes() -> void:
	var tree_body := _downward_hit(_tree.global_position, true, false)
	_check(tree_body.get("collider") == _tree.get_node("TrunkBlock"),
		"tree exposes a solid TrunkBlock volume on the RESOURCE layer")
	var tree_area := _downward_hit(_tree.global_position, false, true)
	_check(tree_area.get("collider") == _tree,
		"tree root Area3D carries a probeable interaction volume on RESOURCE layer")
	var stone_body := _downward_hit(_stone.global_position, true, false)
	_check(stone_body.get("collider") == _stone.get_node("Block"),
		"stone deposit exposes its Block volume on the RESOURCE layer")
	var stone_area := _downward_hit(_stone.global_position, false, true)
	_check(stone_area.is_empty(),
		"stone deposit stays out of area probes (pure static block + anchor)")
	var deco_body := _downward_hit(_deco.global_position, true, false)
	var deco_area := _downward_hit(_deco.global_position, false, true)
	_check(deco_body.is_empty() and deco_area.is_empty(),
		"decoration visuals are structurally invisible to resource probes")
	var trunk_shape := _trunk_shape()
	_check(trunk_shape != null and _near(trunk_shape.radius, 0.75)
		and _near(trunk_shape.height, 2.4),
		"mature trunk uses a simple gameplay shape (r=0.75 unit = legacy 6px)")
	_enter(Phase.SELECTION_POLICY)


## -- SELECTION_POLICY: 마우스 직접 채집 차단(Worker 전용 유지) --
func _selection_policy() -> void:
	var canopy_top: Vector3 = _tree.global_position + Vector3(0.0, 3.0, 0.0)
	_push_left_click(_screen_of(canopy_top))
	_check(_sel.get_selected() == null,
		"clicking a tree never selects or gathers it from the mouse (worker-only policy)")
	_push_left_click(_screen_of(_stone.global_position + Vector3(0.0, 1.0, 0.0)))
	_check(_sel.get_selected() == null,
		"clicking a stone deposit is also a safe selection no-op")
	_check(_tree.current_amount == 5,
		"no mouse interaction leaked gather amounts out of the tree")
	_enter(Phase.BLOCKING_REGRESSION)


## -- BLOCKING_REGRESSION: 자원이 뒤 대상 선택을 가리지 않는다 --
func _blocking_regression() -> void:
	if _probe_target == null:
		_probe_target = ProbeInteractable.new()
		_probe_target.collision_layer = CollisionLayers3D.INTERACTABLE
		_probe_target.collision_mask = 0
		var sphere := SphereShape3D.new()
		sphere.radius = 1.0
		var shape := CollisionShape3D.new()
		shape.shape = sphere
		_probe_target.add_child(shape)
		_probe_target.position = Vector3(24.0, 1.0, 24.0)
		_world.add_child(_probe_target)
		# 카메라 광선과 지면 교차점에 나무를 정확히 올려 '자원에 가림' 시나리오를 강제한다.
		# trunk(높이 2.4 unit)가 광선을 먼저 가로지르는 위치다.
		var ground_hit: Vector3 = _cam_ctl.ground_point_from_screen(
			_screen_of(_probe_target.global_position))
		_tree.position = WorldCoords3D.flatten(ground_hit) \
			if ground_hit != Vector3.INF else _probe_target.global_position
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	var ray: Dictionary = _cam_ctl.screen_to_world_ray(_screen_of(_probe_target.global_position))
	var space := _world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray["origin"], ray["origin"] + ray["direction"] * 2000.0,
		CollisionLayers3D.MASK_ACTOR_SOLID)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var occluder_hit := space.intersect_ray(query)
	var hit_collider: Object = occluder_hit.get("collider")
	_check(hit_collider == _tree.get_node("TrunkBlock") or hit_collider == _tree,
		"the forced-occlusion scene really puts a tree volume on the click ray")
	var returned = _sel.select_at_screen_position(_screen_of(_probe_target.global_position))
	_check(returned == _probe_target,
		"a tree standing on the click ray never blocks the interactable behind it")
	_check(_probe_target.interact_count == 1,
		"occluded-scene click still runs exactly the target interact()")
	_probe_target.queue_free()
	_probe_target = null
	_tree.position = Vector3(6.0, 0.0, -4.0)
	_stone.position = Vector3(-12.0, 0.0, 8.0)
	_wait = 0
	_enter(Phase.DEPLETE)


## -- DEPLETE: interact 소진 -> STUMP 전환은 동기적으로 즉시 확인 --
func _deplete() -> void:
	var interactor := Node.new()
	interactor.name = "GatherInteractor"
	root.add_child(interactor)
	for i in 5:
		var result: Dictionary = _tree.interact(interactor)
		_check(result.get("amount", 0) == 1 and result.get("resource_id") == "wood",
			"gather %d returns 1 wood via legacy dict contract" % (i + 1))
	_check(_tree.current_amount == 0, "current_amount reaches 0 after 5 gathers")
	_check(_tree.state == 1, "depleted tree enters STUMP state immediately")
	_check(not _tree.get_node("Visual/CanopyVisual").visible
		and not _tree.get_node("Visual/TrunkVisual").visible
		and _tree.get_node("Visual/StumpVisual").visible,
		"stump state shows only the stump visual")
	var shape := _trunk_shape()
	_check(_near(shape.radius, 0.6) and _near(shape.height, 0.5),
		"stump collision shrinks with the visual (visual/collision consistency)")
	_check(not _tree.can_interact(), "stump cannot be gathered further")
	_check(_tree.interact(interactor).is_empty(), "interact on a stump returns empty dict")
	_rebuilds_marker = _nav_manager.nav_rebuild_count
	_wait = 0
	_enter(Phase.DEPLETED_NAV_WAIT)


func _depleted_nav_wait() -> void:
	_wait += 1
	if _wait < DEBOUNCE_WAIT_FRAMES:
		return
	_wait = 0
	_check(_nav_manager.nav_rebuild_count > _rebuilds_marker,
		"stump collision change requested a debounced navigation rebake")
	_rebuilds_marker = _nav_manager.nav_rebuild_count
	_enter(Phase.REGROW_POLL)


func _regrow_poll() -> void:
	_wait += 1
	if _tree.state != 0:
		if _wait > 300:
			print("FAIL: tree did not regrow within the polling window")
			_failed = true
			_finish()
		return
	_wait = 0
	_check(true, "tree regrows to MATURE after regrow_time")
	_check(_tree.current_amount == 5 and _tree.can_interact(),
		"regrowth restores the full gather amount")
	_check(_tree.get_node("Visual/CanopyVisual").visible
		and _tree.get_node("Visual/TrunkVisual").visible
		and not _tree.get_node("Visual/StumpVisual").visible,
		"regrown tree restores mature visuals")
	var shape := _trunk_shape()
	_check(_near(shape.radius, 0.75) and _near(shape.height, 2.4),
		"regrown trunk collision restores the mature footprint")
	_rebuilds_marker = _nav_manager.nav_rebuild_count
	_enter(Phase.REGROW_NAV_WAIT)


func _regrow_nav_wait() -> void:
	_wait += 1
	if _wait < DEBOUNCE_WAIT_FRAMES:
		return
	_wait = 0
	_check(_nav_manager.nav_rebuild_count > _rebuilds_marker,
		"regrowth also refreshed the navigation obstacle state")
	_enter(Phase.CLEANUP_SETUP)


## -- CLEANUP_SETUP: claim된 나무 제거 시 정리 검증 --
func _cleanup_setup() -> void:
	if _extra_tree == null:
		_extra_tree = (load("res://scenes/tree_3d.tscn") as PackedScene).instantiate()
		_extra_tree.name = "ExtraTree"
		_extra_tree.position = Vector3(-18.0, 0.0, -14.0)
		_world.add_child(_extra_tree)
		var worker := Node.new()
		worker.name = "ClaimWorker"
		root.add_child(worker)
		_check(_extra_tree.claim(worker), "extra tree claimed before removal")
		_world.remove_child(_extra_tree)
		_check(not _extra_tree.is_claimed(),
			"leaving the tree clears its claim immediately (no stale claim)")
		_rebuilds_marker = _nav_manager.nav_rebuild_count
		_extra_tree.queue_free()
		root.get_node("ClaimWorker").queue_free()
		_enter(Phase.CLEANUP_CHECK)


## -- CLEANUP_CHECK: freed 자원의 rebake 요청 + 잔여 참조 없음 --
func _cleanup_check() -> void:
	_wait += 1
	if _wait < DEBOUNCE_WAIT_FRAMES:
		return
	_check(not is_instance_valid(_extra_tree),
		"removed tree instance is fully freed (no orphan nodes)")
	_check(_nav_manager.nav_rebuild_count > _rebuilds_marker,
		"freed resource still requested its final navigation rebake")
	_check(root.get_node_or_null("ClaimWorker") == null,
		"fake claimer cleaned up (test-side stale reference check)")
	_finish()
