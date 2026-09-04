extends SceneTree

## TASK-021-1 Wild Herb Resource3D 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task02* 계열(migration map 운영 규칙 5).
##
## 검증 범위(완료조건 매핑):
##   1. Herb source: WildHerb3D가 ResourceNode3D를 상속하고 "resource_nodes_3d"
##      그룹으로 Worker 탐색 대상이 되며 scene으로 생성 가능.
##   2. acquire stock: HerbGatherer3D(기존 Worker pattern 최소 확장)가 herb를
##      채집해 VillageResources에 "herb"로 반납(deposit)한다.
##   3. depletion/regrowth: 소진 -> PICKED, regrow_time 경과 -> GROWN + 수량 복구.
##   4. visual/readability: 모든 mesh는 Visual child 하위, 성장/채집 표현이 구분되고
##      top-down에서 green 실루엣으로 Wood/Stone과 식별된다.
##   5. Player 직접 채집 없음: is_selectable() == false(마우스 직접 채집 차단).

enum Phase {
	SETUP, CONTRACT, SCENE_SETUP, VISUAL, DEPLETE, REGROW_POLL,
	STOCK_SETUP, STOCK_WAIT, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const SHAPE_EPS := 0.001

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav: Node = null
var _resources: Node = null
var _herb_script: GDScript = null
var _gatherer_script: GDScript = null
var _herb: Node3D = null
var _worker = null
var _workplace: Node3D = null
var _herb_before := 0
var _regrow_started := false


class DuckWorkplace extends Node3D:
	var work_radius: float = 192.0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	for n in [_herb, _worker, _workplace]:
		if n != null and is_instance_valid(n):
			n.free()
	print("TASK0211_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= SHAPE_EPS


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.SCENE_SETUP:
			_scene_setup()
		Phase.VISUAL:
			_visual()
		Phase.DEPLETE:
			_deplete()
		Phase.REGROW_POLL:
			_regrow_poll()
		Phase.STOCK_SETUP:
			_stock_setup()
		Phase.STOCK_WAIT:
			_stock_wait()
		Phase.DONE:
			_finish()
			return true
	if _frame > 4000:
		print("TASK0211_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)


func _setup() -> void:
	if _frame < 8:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_resources = root.get_node_or_null("VillageResources")
	_herb_script = load("res://scripts/wild_herb_3d.gd") as GDScript
	_gatherer_script = load("res://scripts/herb_gatherer_3d.gd") as GDScript
	if _world == null or _resources == null or _herb_script == null or _gatherer_script == null:
		_check(false, "world3d / VillageResources / herb & gatherer scripts load")
		_finish()
		return
	_nav = NavigationManager3D.new()
	_nav.name = "NavManager"
	_world.add_child(_nav)
	_enter(Phase.CONTRACT)


## -- CONTRACT: 상속/기본값/claim/is_selectable/그룹 규약 --
func _contract() -> void:
	var base_script: GDScript = load("res://scripts/resource_node_3d.gd")
	_check(_herb_script.get_base_script() == base_script,
		"WildHerb3D extends ResourceNode3D (기준 RES 계약 상속)")
	var node: Area3D = _herb_script.new()
	_check(node is Area3D, "WildHerb3D contract is an Area3D (Interactable3D 계약)")
	_check(node.resource_id == "herb", "herb resource_id is 'herb'")
	_check(node.max_amount == 5 and node.current_amount == 5 and node.gather_amount == 1,
		"herb gather defaults stay legacy (5x1)")
	_check(not node.is_selectable(),
		"herb stays worker-only via the is_selectable hook (no Player direct gather)")
	_check(node.can_interact(), "fresh herb with amount left can be gathered")
	var worker_a := Node.new()
	var worker_b := Node.new()
	_check(node.claim(worker_a), "first worker claims an unclaimed herb")
	_check(not node.claim(worker_b), "duplicate claim by a second worker is rejected")
	node.release(worker_a)
	_check(not node.is_claimed(), "release by the claiming worker clears the herb claim")
	node.free()
	worker_a.free()
	worker_b.free()
	_enter(Phase.SCENE_SETUP)


## -- SCENE_SETUP: scene 인스턴스 + physics 등록 대기 --
func _scene_setup() -> void:
	if _herb == null:
		_herb = (load("res://scenes/wild_herb_3d.tscn") as PackedScene).instantiate()
		_herb.name = "WildHerb"
		_herb.position = Vector3(0.0, 0.0, 0.0)
		_herb.regrow_time = 0.25
		_world.add_child(_herb)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_check(_herb.is_in_group("resource_nodes_3d"),
		"WildHerb3D joins the worker-facing resource_nodes_3d group")
	_check(_herb.prompt == "채집", "herb prompt keeps the legacy gather prompt")
	_enter(Phase.VISUAL)


## -- VISUAL: Visual child 분리 + green 식별성 + 성장/채집 표현 구분 --
func _visual() -> void:
	var visual: Node3D = _herb.get_node("Visual")
	var grown := _herb.get_node("Visual/GrownVisual") as MeshInstance3D
	var picked := _herb.get_node("Visual/PickedVisual") as MeshInstance3D
	var mesh_in_visual := 0
	for child in visual.get_children():
		if child is MeshInstance3D:
			mesh_in_visual += 1
	_check(mesh_in_visual == 2,
		"all herb meshes live under the dedicated Visual child (logic-free)")
	for child in _herb.get_children():
		if child is MeshInstance3D:
			_check(false, "herb root must not own render meshes directly")
	var leaf_mat: StandardMaterial3D = grown.mesh.material
	_check(leaf_mat.albedo_color.g > leaf_mat.albedo_color.r + 0.1,
		"grown herb reads green from the top-down camera (distinct from wood/stone)")
	_check(grown.visible and not picked.visible,
		"fresh herb shows only the grown plant representation")
	_check(not _herb.is_selectable(),
		"scene herb also refuses mouse selection (Player direct gather blocked)")
	_enter(Phase.DEPLETE)


## -- DEPLETE: interact 소진 -> PICKED 상태 즉시 확인 --
func _deplete() -> void:
	var interactor := Node.new()
	interactor.name = "GatherInteractor"
	root.add_child(interactor)
	for i in 5:
		var result: Dictionary = _herb.interact(interactor)
		_check(result.get("amount", 0) == 1 and result.get("resource_id") == "herb",
			"gather %d returns 1 herb via legacy dict contract" % (i + 1))
	interactor.free()
	_check(_herb.current_amount == 0, "current_amount reaches 0 after 5 gathers")
	_check(_herb.state == 1, "depleted herb enters PICKED state immediately")
	_check(not _herb.get_node("Visual/GrownVisual").visible
		and _herb.get_node("Visual/PickedVisual").visible,
		"picked state shows only the bare-ground representation")
	_check(not _herb.can_interact(), "picked herb cannot be gathered further")
	_enter(Phase.REGROW_POLL)


## -- REGROW_POLL: regrow_time 경과 후 GROWN 복구 --
func _regrow_poll() -> void:
	_wait += 1
	if _herb.state != 0:
		if _wait > 300:
			print("FAIL: herb did not regrow within the polling window")
			_failed = true
			_finish()
		return
	_wait = 0
	_check(true, "herb regrows to GROWN after regrow_time")
	_check(_herb.current_amount == 5 and _herb.can_interact(),
		"regrowth restores the full gather amount")
	_check(_herb.get_node("Visual/GrownVisual").visible
		and not _herb.get_node("Visual/PickedVisual").visible,
		"regrown herb restores the grown plant representation")
	# 결정적 visual variation 재확인(같은 위치 = 같은 결과).
	_enter(Phase.STOCK_SETUP)


## -- STOCK_SETUP: HerbGatherer3D worker를 workplace에 배치하고 herb 반납 관찰 --
func _stock_setup() -> void:
	# 배치 도중 새로 깨끗한 herb 하나(worker가 소진/regrow 사이클로 계속 채집).
	if _workplace == null:
		_herb_before = int(_resources.get_amount("herb"))
		_workplace = DuckWorkplace.new()
		_workplace.name = "HerbField"
		_world.add_child(_workplace)
		_workplace.global_position = Vector3(0.0, WorldCoords3D.GROUND_Y, 8.0)
		var deposit := Node3D.new()
		deposit.name = "DepositPoint"
		_workplace.add_child(deposit)
		deposit.position = Vector3(0, 0, 3)
		# workplace 가까이 새 herb 배치(worker가 즉시 후보로 잡도록).
		_herb.position = Vector3(0.0, WorldCoords3D.GROUND_Y, 12.0)
		_herb.current_amount = 5
		_herb._set_state(0)
		# worker 배치.
		_worker = _gatherer_script.new()
		_worker.name = "HerbGatherer"
		_world.add_child(_worker)
		_worker.global_position = Vector3(0.0, WorldCoords3D.GROUND_Y, 8.0)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_nav.rebuild_navigation()
	_worker._on_assigned(_workplace)
	_check(_worker.is_assigned(), "herb gatherer assigned to the herb field workplace")
	_enter(Phase.STOCK_WAIT)


## -- STOCK_WAIT: worker가 herb를 채집해 VillageResources 'herb'로 반납 --
func _stock_wait() -> void:
	var herb_now: int = int(_resources.get_amount("herb"))
	if herb_now > _herb_before:
		_check(herb_now - _herb_before > 0,
			"worker gather acquires 'herb' stock into VillageResources (+%d)"
				% (herb_now - _herb_before))
		_check(_worker.carried_amount == 0,
			"worker deposit clears carry after returning stock")
		var state_name: String = _worker.get_state_name()
		_check(state_name in ["IDLE", "FIND", "MOVE", "GATHER", "RETURN", "DEPOSIT"],
			"herb gatherer stays in a valid FSM state (%s)" % state_name)
		_finish()
		return
	if _frame > 4000:
		_check(false, "worker did not deposit herb stock within the budget")
		_finish()
