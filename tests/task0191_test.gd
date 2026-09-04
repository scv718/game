extends SceneTree

## TASK-019-1 Farm Building / Plot 3D 회귀 테스트.
## task3dbld0012_test.gd의 구조를 따른 신규 task019* 계열 테스트다.
##
## 검증 범위:
##   1. 계약: Farm3D가 Workplace3D -> Building3D 상속 경로를 따르고, 기존 생산시설
##      Worker Slot(2) / prompt / group("farms"/"farms_3d") 계약을 유지한다.
##   2. 배치: BuildingPlacement3D의 free-building 경로(KEY_5)로 배치, 비용 1회 차감,
##      셀 중심 snap, invalid(중첩/자금 부족) 무차감.
##   3. footprint/collision: BUILDING layer 수동 블로커 + 4x4 unit(32x32px 불변),
##      visual mesh와 분리, Interact Area3D(MASK_SELECTION) 제공.
##   4. 선택: WorldSelection3D가 farm Interact를 선택/해제한다(build mode off).
##   5. crop area: top-down에서 읽히도록 Visual/CropRows가 존재한다(순수 시각).
##   6. nav update: 배치가 Foundation debounced nav rebake를 연결한다.
##
## autoload는 --script 모드에서 컴파일 타임 식별자가 아니므로 노드 조회로만 사용한다.

enum Phase {
	SETUP, CONTRACT, SELECT_BASELINE, PLACE_FARM, VALIDATION, CROP_VISUAL,
	NAV_UPDATE, FINAL, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const START_WOOD := 500

## cell 중심(홀수 unit) 목표들. 서로 겹치지 않는 임의 지점.
const FARM_CELL := Vector3(5, 0, 5)
const FARM_OVERLAP_CELL := Vector3(5, 0, 5)
const FARM_FREE := Vector3(-5, 0, -5)
const TAVERN_LOGICAL := Vector2(-320, -320)

var _frame := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _sp := 0
var _world: Node3D = null
var _cam_ctl: Node = null
var _sel: Node = null
var _placement: Node = null
var _nav_manager: Node = null
var _game_time: Node = null
var _resources: Node = null
var _tavern: Node3D = null
var _nav_baseline := 0
var _wood_ledger := 0
var _tmp_a := 0
var _last_feedback := ""
var _last_mode_active := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_sp = 0


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK0191_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _aim(pos: Vector3) -> Vector3:
	return pos + Vector3(0.3, 0.0, 0.3)


func _screen_of(world_pos: Vector3) -> Vector2:
	return _cam_ctl.get_camera().unproject_position(world_pos)


func _push_motion(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	root.push_input(motion)


func _push_left_click(screen_pos: Vector2) -> void:
	_push_motion(screen_pos)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_pos
	root.push_input(event)


func _push_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event)


func _on_feedback(text: String) -> void:
	_last_feedback = text


func _on_mode_changed(active: bool) -> void:
	_last_mode_active = active


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.SELECT_BASELINE:
			_select_baseline()
		Phase.PLACE_FARM:
			_place_farm()
		Phase.VALIDATION:
			_validation()
		Phase.CROP_VISUAL:
			_crop_visual()
		Phase.NAV_UPDATE:
			_nav_update()
		Phase.FINAL:
			_final()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK0191_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	_world = world_scene

	_tavern = (load("res://scenes/core_building_3d.tscn") as PackedScene).instantiate()
	_tavern.core_type = "tavern"
	_tavern.set_logical_position(TAVERN_LOGICAL)
	_world.add_child(_tavern)

	_nav_manager = load("res://scripts/navigation_manager_3d.gd").new()
	_nav_manager.name = "NavManager"
	_world.add_child(_nav_manager)

	_cam_ctl = (load("res://scenes/camera_controller_3d.tscn") as PackedScene).instantiate()
	_cam_ctl.name = "CamController"
	root.add_child(_cam_ctl)
	_sel = load("res://scripts/world_selection_3d.gd").new()
	_sel.name = "WorldSelection3D"
	root.add_child(_sel)
	_placement = load("res://scripts/building_placement_3d.gd").new()
	_placement.name = "BuildingPlacement3D"
	root.add_child(_placement)


func _setup() -> void:
	if _frame < 8:
		return
	_check(_world != null, "empty 3D world loads")
	_check(_cam_ctl != null, "camera controller 3D loads")
	_check(_placement != null, "building placement 3D loads")
	_check(_sel != null, "world selection 3D loads")
	_game_time = root.get_node_or_null("GameTime")
	_resources = root.get_node_or_null("VillageResources")
	_check(_resources != null, "VillageResources autoload available to the 3D runtime")
	_game_time.set_auto_advance(false)
	_check(_game_time.get_phase() == _game_time.Phase.DAY, "test runs in DAY phase")
	_placement.feedback.connect(_on_feedback)
	_placement.mode_changed.connect(_on_mode_changed)
	_resources.add("wood", START_WOOD)
	_wood_ledger = START_WOOD
	_enter(Phase.CONTRACT)


## -- CONTRACT: Farm3D 계약(상속/footprint/group/prompt) --
func _contract() -> void:
	var placement_script: GDScript = load("res://scripts/building_placement_3d.gd")
	_check(placement_script.get_instance_base_type() == "Node3D",
		"BuildingPlacement3D is a Node3D controller")
	_check(_placement.BUILD_COSTS.has("farm")
		and _placement.BUILD_COSTS["farm"] == {"wood": 10},
		"farm joins the legacy building economy with a single wood cost")

	var farm_script: GDScript = load("res://scripts/farm_3d.gd")
	var wp_base: GDScript = load("res://scripts/workplace_3d.gd")
	var bld_base: GDScript = load("res://scripts/building_3d.gd")
	_check(farm_script.get_base_script() == wp_base and wp_base.get_base_script() == bld_base,
		"Farm3D extends Workplace3D extends Building3D (기존 생산시설 상속 경로)")
	_check(_placement._building_scene_for("farm") != null,
		"BuildingPlacement3D resolves the farm scene for free-building placement")

	var farm: StaticBody3D = (load("res://scenes/farm_3d.tscn") as PackedScene).instantiate()
	_check(farm.collision_layer == CollisionLayers3D.BUILDING
		and farm.collision_mask == 0,
		"Farm3D body sits on the BUILDING layer as a manual blocker")
	var farm_shape: BoxShape3D = farm.get_node("CollisionShape3D").shape
	_check(farm_shape.size.x == 4.0 and farm_shape.size.z == 4.0,
		"Farm3D gameplay footprint is the legacy 32x32px (4x4 unit)")
	var body_mesh: BoxMesh = farm.get_node("Visual/BodyMesh").mesh
	_check(body_mesh.size.x != farm_shape.size.x,
		"Farm3D visual mesh size is decoupled from the gameplay footprint")
	_check(farm.has_node("Interact")
		and farm.get_node("Interact").collision_layer == CollisionLayers3D.INTERACTABLE,
		"Farm3D exposes a selectable Interactable3D volume")
	_check(farm.get_slot_capacity() == 2, "Farm3D keeps the legacy 2 worker slot policy")
	_check(farm.get_worker_label() == "Farmer",
		"Farm3D exposes the Farmer worker label for the roster UI")
	_check(farm.get_interact_prompt() == "Workers: 0/2 - Assign Farmer",
		"Farm3D keeps the legacy workplace prompt format")
	# placeholder material 적용 + group 이중 등록 확인.
	farm._ready()
	_check(farm.is_in_group("farms") and farm.is_in_group("farms_3d"),
		"Farm3D joins the roster lookup group and the dimension-explicit 3D group")
	_check(farm.has_node("Visual/CropRows"),
		"Farm3D carries a CropRows visual slot for the crop area")
	farm.free()
	_enter(Phase.SELECT_BASELINE)


## -- SELECT_BASELINE: build mode off 상태에서 선택/해제 계약 --
func _select_baseline() -> void:
	match _sp:
		0:
			_push_left_click(_screen_of(_tavern.get_node("Interact").global_position))
		1:
			_check(_sel.get_selected() == _tavern.get_node("Interact"),
				"clicking the tavern still selects it while build mode is off")
			_check(_sel.can_handle_world_click(),
				"world selection handles clicks in DAY outside build mode")
			_enter(Phase.PLACE_FARM)
			return
	_sp += 1


## -- PLACE_FARM: KEY_5 + 클릭 배치 + 비용 1회 차감 + 셀 중심 --
func _place_farm() -> void:
	match _sp:
		0:
			_push_key(KEY_5)
			_push_key(KEY_B)
		1:
			_check(_placement.is_active(), "B key activates build mode for farm")
			_check(_last_mode_active, "mode_changed signal reports activation")
			_push_left_click(_screen_of(_aim(FARM_CELL)))
		2:
			var farms := get_nodes_in_group("farms_3d")
			_check(farms.size() == 1, "one farm exists after the click")
			if farms.size() == 1:
				_check(farms[0].position.is_equal_approx(FARM_CELL),
					"placed farm occupies exactly the aimed grid cell center")
			_wood_ledger -= 10
			_check(_resources.get_amount("wood") == _wood_ledger,
				"farm cost is deducted exactly once for a valid placement")
			_check(_last_feedback == "Farm built", "farm feedback matches the placement")
			_check(not _placement.is_active(),
				"build mode exits after a single-place farm succeeds")
			_check(_placement._ghost == null, "ghost is cleaned up after farm placement")
			_enter(Phase.VALIDATION)
			return
	_sp += 1


## -- VALIDATION: 중첩/자금 부족 무차감 --
func _validation() -> void:
	match _sp:
		0:
			_push_key(KEY_5)
			_push_key(KEY_B)
		1:
			_push_left_click(_screen_of(_aim(FARM_OVERLAP_CELL)))
		2:
			_check(get_nodes_in_group("farms_3d").size() == 1,
				"overlapping an existing farm places nothing")
			_check(_last_feedback == "Invalid position",
				"overlap feedback keeps the legacy message")
			_check(_resources.get_amount("wood") == _wood_ledger,
				"invalid farm placement never deducts cost")
			# 자금 부족 무차감.
			_tmp_a = _resources.get_amount("wood")
			_resources.spend("wood", _resources.get_amount("wood") - 5)
			_wood_ledger = 5
		3:
			_check(_resources.get_amount("wood") == 5, "funds drained to below cost")
			_push_left_click(_screen_of(_aim(FARM_FREE)))
		4:
			_check(get_nodes_in_group("farms_3d").size() == 1,
				"insufficient funds places no farm")
			_check(_last_feedback == "Not enough Wood",
				"insufficient funds keeps the legacy feedback")
			_check(_resources.get_amount("wood") == 5,
				"failed affordability never touches resources")
			_resources.add("wood", _tmp_a - 5)
			_wood_ledger = _tmp_a
		5:
			_check(_resources.get_amount("wood") == _wood_ledger,
				"funds restored to the regression ledger baseline")
			_push_key(KEY_B)
			_enter(Phase.CROP_VISUAL)
			return
	_sp += 1


## -- CROP_VISUAL: crop rows 존재 + 순수 시각(collision 없음) --
func _crop_visual() -> void:
	var farms := get_nodes_in_group("farms_3d")
	_check(farms.size() == 1, "farm still exists for the crop visual check")
	if farms.size() == 1:
		var crop_rows := farms[0].get_node("Visual/CropRows")
		_check(crop_rows.get_child_count() >= 1,
			"farm crop rows are present for top-down readability")
		var any_mesh := false
		for child in crop_rows.get_children():
			if child is MeshInstance3D:
				any_mesh = true
		_check(any_mesh, "crop rows render placeholder mesh strips (순수 시각)")
		# crop visual이 footprint collision에 기여하지 않는지(순수 시각).
		var visual_has_collision := false
		for child in farms[0].get_children():
			if child is CollisionShape3D and child.name != "CollisionShape3D":
				visual_has_collision = true
		_check(not visual_has_collision,
			"crop rows add no extra collision (visual-only, footprint unaffected)")
	_enter(Phase.NAV_UPDATE)


## -- NAV_UPDATE: farm 배치가 Foundation debounced nav rebake 연결 --
func _nav_update() -> void:
	match _sp:
		0:
			_nav_baseline = _nav_manager.nav_rebuild_count
			# 두 번째 farm을 배치해 rebake 증가를 유발한다.
			_push_key(KEY_5)
			_push_key(KEY_B)
		1:
			_push_left_click(_screen_of(_aim(Vector3(-15, 0, 5))))
		2:
			_check(get_nodes_in_group("farms_3d").size() == 2,
				"second farm places on a free cell")
			_wood_ledger -= 10
			_check(_resources.get_amount("wood") == _wood_ledger,
				"second farm cost deducted once")
			_enter(Phase.FINAL)
			return
	_sp += 1


## -- FINAL: 원장 일치 + nav rebake 진행 + 잔존 물건 집계 --
func _final() -> void:
	match _sp:
		0:
			if _frame <= PHYSICS_WAIT_FRAMES * 4:
				return
			_check(_nav_manager.nav_rebuild_count > _nav_baseline,
				"farm placements reach the Foundation debounced nav rebake")
			_check(get_nodes_in_group("farms_3d").size() == 2,
				"surviving farms match the regression scenario")
			_check(get_nodes_in_group("lumberyards_3d").size() == 0
				and get_nodes_in_group("quarries_3d").size() == 0,
				"farm placement does not create other workplace types")
			_check(_resources.get_amount("wood") == _wood_ledger,
				"cost ledger matches VillageResources exactly")
			_enter(Phase.DONE)
			return
	_sp += 1
