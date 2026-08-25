extends SceneTree

## TASK-3D-BLD-001-2 BuildingPlacement XZ Grid 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. 계약: placement controller 시그널/is_active, BUILD_COSTS/footprint 상수가
##      기존 2D building_placement.gd와 동일 값, 3D 건물 scene들의 layer/footprint.
##   2. snap: cell 중심 snap(Building)과 corner snap(Wall/Gate)이 기존 2D 점유 셀과 동일.
##   3. pan/zoom 상태에서의 mouse ray -> ground XZ -> grid placement 정확성.
##   4. ghost: 투명 material 표시, valid=초록/invalid·remove=빨강, 타입별 footprint 치수.
##   5. validation: building/resource/tree overlap, 월드 bounds, 자금 부족, Gate Corridor.
##   6. 비용 1회 차감 / invalid 무차감 / remove 전액 환불(기존 정책 회귀).
##   7. build mode 중 입력 ownership(선택 게이트) + Foundation nav rebake 연결.
##
## 카메라 의존 판정은 모두 push된 실제 input event 경로로 수행한다. snap 결과가
## 셀 경계 float 오차로 뒤집히지 않게 배치 클릭은 셀 내부를 겨냥하고(_aim),
## remove pick처럼 snap이 관여하지 않는 클릭은 정확한 좌표를 쓴다.
## autoload는 --script 모드에서 컴파일 타임 식별자가 아니므로 노드 조회로만 사용한다.

enum Phase {
	SETUP, CONTRACT, SNAP, SELECTION_BASELINE, PLACE_LUMBERYARD, PAN_ZOOM,
	GHOST, VALIDATION, QUARRY_FLOW, WALL_GATE, REMOVE_REFUND, FINAL_CHECKS, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const START_WOOD := 500

## fixture 배치(서로 겹치지 않는 임의 cell/corner 정렬 지점).
const TAVERN_LOGICAL := Vector2(-320, -320)
const TREE_POS := Vector3(-32, 0, 32)
const DEPOSIT_POS := Vector3(36, 0, 36)
## cell 중심(홀수 unit) 목표들.
const CELL_C1 := Vector3(25, 0, 25)
const CELL_C2 := Vector3(9, 0, -23)
const CELL_C3 := Vector3(-23, 0, -9)
const CELL_FREE := Vector3(13, 0, 13)
const TREE_CELL_CENTER := Vector3(-31, 0, 31)
## Wall corner(짝수 unit) / Gate corridor 목표.
const WALL_A := Vector3(20, 0, 20)
const WALL_B := Vector3(22, 0, 20)
const GATE_NORTH := Vector3(0, 0, -80)
const GATE_EAST := Vector3(60, 0, 0)
const GATE_MISSED := Vector3(0, 0, -40)

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
var _deposit: Node3D = null
var _fake_tavern_ui: Control = null
var _last_feedback := ""
var _last_mode_active := false
var _wood_ledger := 0
var _nav_baseline := 0
var _tmp_a: Variant = null
var _tmp_b: Variant = null


class FakeRecruitmentUI extends Control:
	var open_count := 0

	func _init() -> void:
		add_to_group("recruitment_ui")
		visible = false

	func open() -> void:
		open_count += 1


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
	print("TASK3DBLD0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


## 셀 경계 float 오차 방지용 안쪽 겨냥 오프셋.
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


func _push_wheel_down(screen_pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = screen_pos
	root.push_input(event)


func _spend_to(amount: int) -> void:
	_resources.spend("wood", _resources.get_amount("wood") - amount)


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
		Phase.SNAP:
			_snap_phase()
		Phase.SELECTION_BASELINE:
			_selection_baseline()
		Phase.PLACE_LUMBERYARD:
			_place_lumberyard()
		Phase.PAN_ZOOM:
			_pan_zoom()
		Phase.GHOST:
			_ghost()
		Phase.VALIDATION:
			_validation()
		Phase.QUARRY_FLOW:
			_quarry_flow()
		Phase.WALL_GATE:
			_wall_gate()
		Phase.REMOVE_REFUND:
			_remove_refund()
		Phase.FINAL_CHECKS:
			_final_checks()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DBLD0012_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)

	_world = world_scene
	var tree: Node3D = (load("res://scenes/tree_3d.tscn") as PackedScene).instantiate()
	tree.position = TREE_POS
	_world.add_child(tree)
	_deposit = (load("res://scenes/stone_deposit_3d.tscn") as PackedScene).instantiate()
	_deposit.position = DEPOSIT_POS
	_world.add_child(_deposit)
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
	_fake_tavern_ui = FakeRecruitmentUI.new()
	_fake_tavern_ui.name = "FakeRecruitmentUI"
	root.add_child(_fake_tavern_ui)


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
	# phase gate 판정을 결정적으로 만들기 위해 자동 시간 진행을 멈춘다(종료 시 복원).
	_game_time.set_auto_advance(false)
	_check(_game_time.get_phase() == _game_time.Phase.DAY, "test runs in DAY phase")
	_placement.feedback.connect(_on_feedback)
	_placement.mode_changed.connect(_on_mode_changed)
	# 비용/환불 회귀의 기준 자금.
	_resources.add("wood", START_WOOD)
	_wood_ledger = START_WOOD
	_enter(Phase.CONTRACT)


## -- CONTRACT: 2D placement 계약 parity + 3D 건물 scene layer/footprint --
func _contract() -> void:
	var placement_script: GDScript = load("res://scripts/building_placement_3d.gd")
	_check(placement_script.get_instance_base_type() == "Node3D",
		"BuildingPlacement3D is a Node3D controller")
	_check(_placement.is_in_group("building_placement"),
		"controller joins the legacy building_placement group (HUD/Selection3D contract)")
	_check(_placement.is_in_group("building_placement_3d"),
		"controller joins the dimension-explicit building_placement_3d group")
	for signal_name in ["mode_changed", "feedback", "building_type_changed"]:
		_check(_placement.has_signal(signal_name),
			"controller exposes the legacy %s signal" % signal_name)
	_check(not _placement.is_active(), "build mode starts inactive")

	var expected_costs := {
		"lumberyard": {"wood": 10},
		"quarry": {"wood": 10},
		"wall": {"wood": 2},
		"gate": {"wood": 5},
	}
	_check(_placement.BUILD_COSTS == expected_costs,
		"BUILD_COSTS keeps the legacy 2D economy values")
	_check(_placement.BUILDING_FOOTPRINT_PX == Vector2(32, 32)
		and _placement.WALL_FOOTPRINT_PX == Vector2(16, 16)
		and _placement.GATE_HORIZONTAL_SIZE_PX == Vector2(48, 16)
		and _placement.GATE_VERTICAL_SIZE_PX == Vector2(16, 48),
		"gameplay footprint constants keep the legacy 2D logical px values")
	_check(is_equal_approx(_placement.DEPOSIT_SNAP_RADIUS_UNITS, 6.0),
		"deposit snap radius is the legacy 48px converted to units")
	_check(is_equal_approx(_placement.PLACE_MASK, CollisionLayers3D.MASK_PLACEMENT_BLOCKERS),
		"overlap validation uses the Foundation MASK_PLACEMENT_BLOCKERS single source")

	var lum_script: GDScript = load("res://scripts/lumberyard_3d.gd")
	var qua_script: GDScript = load("res://scripts/quarry_3d.gd")
	var bld_base: GDScript = load("res://scripts/building_3d.gd")
	_check(lum_script.get_base_script() == bld_base, "Lumberyard3D extends Building3D")
	_check(qua_script.get_base_script() == bld_base, "Quarry3D extends Building3D")
	var wall_script: GDScript = load("res://scripts/wall_3d.gd")
	var gate_script: GDScript = load("res://scripts/gate_3d.gd")
	_check(wall_script.get_instance_base_type() == "StaticBody3D",
		"Wall3D is a static world collider")
	_check(gate_script.get_instance_base_type() == "StaticBody3D",
		"Gate3D is a static world collider")

	# scene 계약: layer/mask/interact/footprint와 visual mesh의 크기 분리.
	var lumberyard: StaticBody3D = (load("res://scenes/lumberyard_3d.tscn") as PackedScene).instantiate()
	_check(lumberyard.collision_layer == CollisionLayers3D.BUILDING
		and lumberyard.collision_mask == 0,
		"Lumberyard3D body sits on the BUILDING layer as a manual blocker")
	var lum_shape: BoxShape3D = lumberyard.get_node("CollisionShape3D").shape
	var lum_mesh: BoxMesh = lumberyard.get_node("Visual/BodyMesh").mesh
	_check(lum_shape.size.x == 4.0 and lum_shape.size.z == 4.0,
		"Lumberyard3D gameplay footprint is the legacy 32x32px (4x4 unit)")
	_check(lum_mesh.size.x != lum_shape.size.x,
		"Lumberyard3D visual mesh size is decoupled from the gameplay footprint")
	_check(lumberyard.has_node("Interact")
		and lumberyard.get_node("Interact").collision_layer == CollisionLayers3D.INTERACTABLE,
		"Lumberyard3D exposes a selectable Interactable3D volume")
	_check(lumberyard.get_interact_prompt() == "Workers: 0/2 - Assign Worker",
		"Lumberyard3D keeps the legacy workplace prompt format")
	lumberyard.free()

	var quarry: StaticBody3D = (load("res://scenes/quarry_3d.tscn") as PackedScene).instantiate()
	_check(quarry.collision_layer == CollisionLayers3D.BUILDING
		and quarry.has_node("MiningPoint") and quarry.has_node("WorkPoint")
		and quarry.has_node("WorkPoint2") and quarry.has_node("SpawnPoint"),
		"Quarry3D keeps the legacy workplace marker identity")
	_check(quarry.get_interact_prompt() == "Workers: 0/2 - Assign Miner",
		"Quarry3D keeps the legacy workplace prompt format")
	quarry.free()

	var wall: StaticBody3D = (load("res://scenes/wall_3d.tscn") as PackedScene).instantiate()
	_check(wall.collision_layer == CollisionLayers3D.WALL and wall.collision_mask == 0,
		"Wall3D body sits on the WALL layer as a manual blocker")
	wall.free()

	var gate: StaticBody3D = (load("res://scenes/gate_3d.tscn") as PackedScene).instantiate()
	_check(gate.collision_layer == CollisionLayers3D.GATE and gate.collision_mask == 0,
		"Gate3D body sits on the GATE layer as a manual blocker")
	_check(gate.get_footprint_size() == Vector2(48, 16)
		and gate.get_orientation() == "horizontal",
		"Gate3D defaults to the horizontal N/S corridor footprint")
	gate.setup("east")
	var gate_shape: BoxShape3D = gate.get_node("CollisionShape3D").shape
	_check(gate.get_footprint_size() == Vector2(16, 48)
		and gate.get_orientation() == "vertical"
		and gate_shape.size.x == 2.0 and gate_shape.size.z == 6.0,
		"Gate3D setup(east) swaps to the vertical footprint collision")
	gate.setup("north")
	_check(gate.get_node("CollisionShape3D").shape.size.x == 6.0,
		"Gate3D setup re-applies an independent per-instance shape")
	gate.free()
	_enter(Phase.SNAP)


## -- SNAP: 기존 2D grid 의미 보존(cell 중심/corner) + Gate Corridor 해석 --
func _snap_phase() -> void:
	_check(_placement._snap_cell_center(Vector3(1.1, 0, 3.9)) == Vector3(1, 0, 3),
		"snap maps points into their logical grid cell centers (building)")
	_check(_placement._snap_cell_center(Vector3(-0.1, 0, -0.1)) == Vector3(-1, 0, -1),
		"snap stays stable on negative coordinates")
	_check(WorldCoords3D.snap_xz_to_grid(Vector3(21.3, 4.0, 20.7)) == Vector3(20, 4, 20),
		"wall/gate corner snap preserves Y per the Foundation util contract")
	_check(_placement._gate_direction_at(Vector3(0, 0, -70)) == "north",
		"gate direction resolves the north corridor from world XZ")
	_check(_placement._gate_direction_at(Vector3(60, 0, 0)) == "east",
		"gate direction resolves the east corridor from world XZ")
	_check(_placement._gate_direction_at(GATE_MISSED) == "",
		"outside every corridor resolves to no direction")
	_check(_placement._extents_for_gate(GATE_NORTH) == Vector2(24, 8)
		and _placement._extents_for_gate(GATE_EAST) == Vector2(8, 24),
		"gate half-extents keep the legacy horizontal/vertical px sizes")
	_enter(Phase.SELECTION_BASELINE)


## -- SELECTION_BASELINE: build mode off 상태에서 기존 선택 계약 동작 --
func _selection_baseline() -> void:
	var tavern_interact: Area3D = _tavern.get_node("Interact")
	match _sp:
		0:
			_push_left_click(_screen_of(tavern_interact.global_position))
		1:
			_check(_sel.get_selected() == tavern_interact,
				"clicking the tavern still selects it while build mode is off")
			_check(_fake_tavern_ui.open_count == 1,
				"legacy tavern UI open contract still works in the 3D runtime")
			_enter(Phase.PLACE_LUMBERYARD)
			return
	_sp += 1


## -- PLACE_LUMBERYARD: B 토글 + 클릭 배치 + 비용 1회 차감 --
func _place_lumberyard() -> void:
	match _sp:
		0:
			_push_key(KEY_B)
		1:
			_check(_placement.is_active(), "B key activates build mode")
			_check(_last_mode_active, "mode_changed signal reports activation")
			_push_left_click(_screen_of(_aim(CELL_C1)))
		2:
			var yards := get_nodes_in_group("lumberyards_3d")
			_check(yards.size() == 1, "one lumberyard exists after the click")
			if yards.size() == 1:
				_check(yards[0].position.is_equal_approx(CELL_C1),
					"placed lumberyard occupies exactly the aimed grid cell center")
			_wood_ledger -= 10
			_check(_resources.get_amount("wood") == _wood_ledger,
				"cost is deducted exactly once for a valid placement")
			_check(_last_feedback == "Lumberyard built", "feedback keeps the legacy message")
			_check(not _placement.is_active(),
				"build mode exits after a single-place building succeeds")
			_check(_placement._ghost == null, "ghost is cleaned up after exit")
			_enter(Phase.PAN_ZOOM)
			return
	_sp += 1


## -- PAN_ZOOM: pan/zoom 이후에도 live camera 기준 target cell 정확 --
func _pan_zoom() -> void:
	match _sp:
		0:
			# pan 전 화면 픽셀을 먼저 캡처한다(pan 후 같은 픽셀은 다른 cell을 가리킨다).
			_tmp_b = _screen_of(CELL_C1)
			_push_key(KEY_B)
			_cam_ctl.pan_camera(Vector3(12, 0, -18))
		1:
			_push_left_click(_screen_of(_aim(CELL_C2)))
		2:
			var yards := get_nodes_in_group("lumberyards_3d")
			_check(yards.size() == 2 and yards[1].position.is_equal_approx(CELL_C2),
				"panned camera still targets the exact aimed grid cell")
			_wood_ledger -= 10
			_check(_resources.get_amount("wood") == _wood_ledger,
				"each valid placement deducts its own single cost under pan")
			_tmp_a = _cam_ctl.get_zoom_target()
			_push_wheel_down(Vector2(320, 240))
		3:
			# C2 배치 성공으로 단일 배치 건물은 build mode를 자동 종료하므로 재진입한다.
			_push_key(KEY_B)
			_check(_cam_ctl.get_zoom_target() < _tmp_a,
				"mouse wheel zooms out during the placement workflow")
			_push_left_click(_screen_of(_aim(CELL_C3)))
		4:
			var yards := get_nodes_in_group("lumberyards_3d")
			_check(yards.size() == 3 and yards[2].position.is_equal_approx(CELL_C3),
				"zoomed camera still targets the exact aimed grid cell")
			_wood_ledger -= 10
			# pan 전에 캡처한 옛 화면 픽셀은 이제 다른 지점을 가리켜야 한다.
			# C3 배치 성공으로 다시 자동 종료됐으므로 이번 클릭 전에도 재진입한다.
			_push_key(KEY_B)
			_push_left_click(_tmp_b)
		5:
			var expected: Vector3 = _placement._snap_cell_center(
				_cam_ctl.ground_point_from_screen(_tmp_b))
			var yards := get_nodes_in_group("lumberyards_3d")
			_check(yards.size() == 4 and yards[3].position.is_equal_approx(expected),
				"a pre-pan screen pixel maps through the live camera ray to its new cell")
			if yards.size() == 4:
				_check(not yards[3].position.is_equal_approx(CELL_C1),
					"a stale screen pixel no longer targets the pre-pan cell")
			_wood_ledger -= 10
			_check(_resources.get_amount("wood") == _wood_ledger,
				"cost ledger stays exact across pan/zoom placements")
			_enter(Phase.GHOST)
			return
	_sp += 1


## -- GHOST: 투명 material + valid/invalid 색 + 타입별 footprint 치수 --
func _ghost() -> void:
	match _sp:
		0:
			_push_key(KEY_1)
			_push_key(KEY_B)
		1:
			_push_motion(_screen_of(_aim(Vector3(1, 0, 1))))
		2:
			_check(_placement._ghost != null, "ghost appears while build mode is active")
			if _placement._ghost != null:
				_check(_placement._ghost.position.is_equal_approx(Vector3(1, 0, 1)),
					"ghost follows the mouse ground point snapped to the cell center")
				var box: BoxMesh = _placement._ghost_rect.mesh
				_check(box.size.is_equal_approx(Vector3(4, 0.5, 4)),
					"lumberyard ghost box mirrors the gameplay footprint, not the visual mesh")
				var mat: StandardMaterial3D = _placement._footprint_material
				_check(mat.albedo_color.is_equal_approx(_placement.COLOR_VALID),
					"valid ghost shows green")
				_check(mat.albedo_color.a < 1.0
					and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
					"ghost material is transparent (3D material 표시)")
				var disc: CylinderMesh = _placement._ghost_radius_fill.mesh
				_check(is_equal_approx(disc.top_radius, 24.0),
					"work radius ring uses the legacy 192px radius converted to units")
			_push_motion(_screen_of(_aim(CELL_C1)))
		3:
			var mat: StandardMaterial3D = _placement._footprint_material
			_check(mat.albedo_color.is_equal_approx(_placement.COLOR_INVALID),
				"invalid overlap ghost shows red before any cost is paid")
			_push_key(KEY_3)
			_push_motion(_screen_of(_aim(Vector3(1, 0, 1))))
		4:
			var box: BoxMesh = _placement._ghost_rect.mesh
			_check(box.size.is_equal_approx(Vector3(2, 0.5, 2)),
				"wall ghost box switches to the legacy 16x16px footprint")
			_push_key(KEY_4)
			_push_motion(_screen_of(_aim(Vector3(0.5, 0, -79.2))))
		5:
			_check(_placement._ghost.position.is_equal_approx(GATE_NORTH),
				"gate ghost snaps to the corridor centerline corner")
			var box: BoxMesh = _placement._ghost_rect.mesh
			_check(box.size.is_equal_approx(Vector3(6, 0.5, 2)),
				"gate ghost box switches to the horizontal corridor footprint")
			_push_key(KEY_R)
		6:
			var mat: StandardMaterial3D = _placement._footprint_material
			_check(mat.albedo_color.is_equal_approx(_placement.COLOR_INVALID),
				"remove mode ghost shows red regardless of validity")
			_check(_last_feedback == "Remove mode: click Wall to demolish",
				"remove mode keeps the legacy feedback message")
			_push_key(KEY_R)
			_push_key(KEY_B)
		7:
			_check(_placement._ghost == null,
				"ghost is freed when build mode deactivates via B")
			_enter(Phase.VALIDATION)
			return
	_sp += 1


## -- VALIDATION: overlap/bounds/funds 규칙과 무차감 --
func _validation() -> void:
	match _sp:
		0:
			# GHOST 페이즈가 building type을 gate(KEY_4)로 남기므로 검증 대상인
			# lumberyard로 되돌린 뒤 build mode에 재진입한다.
			_push_key(KEY_1)
			_push_key(KEY_B)
		1:
			_check(_placement.is_active(), "build mode re-activates for validation checks")
			_push_left_click(_screen_of(_aim(CELL_C1)))
		2:
			_check(get_nodes_in_group("lumberyards_3d").size() == 4,
				"overlapping an existing building places nothing")
			_check(_last_feedback == "Invalid position",
				"overlap feedback keeps the legacy message")
			_check(_resources.get_amount("wood") == _wood_ledger,
				"invalid placement never deducts cost")
			_push_left_click(_screen_of(_aim(TREE_CELL_CENTER)))
		3:
			_check(get_nodes_in_group("lumberyards_3d").size() == 4,
				"overlapping a tree trunk block places nothing (resource overlap)")
			_check(_resources.get_amount("wood") == _wood_ledger,
				"tree overlap does not deduct cost")
			# bounds 밖 목표는 화면 클릭으로 만들 수 없으므로 진입점을 직접 호출한다.
			_placement._try_place_at(Vector3(300, 0, 300))
		4:
			_check(get_nodes_in_group("lumberyards_3d").size() == 4,
				"out-of-bounds footprint places nothing (ground bounds validation)")
			_check(_last_feedback == "Invalid position",
				"bounds rejection keeps the legacy feedback")
			_tmp_a = _resources.get_amount("wood")
			_spend_to(5)
			_wood_ledger = 5
		5:
			_check(_resources.get_amount("wood") == 5, "funds drained to below cost")
			_push_left_click(_screen_of(_aim(CELL_FREE)))
		6:
			_check(get_nodes_in_group("lumberyards_3d").size() == 4,
				"insufficient funds places nothing")
			_check(_last_feedback == "Not enough Wood",
				"insufficient funds keeps the legacy feedback")
			_check(_resources.get_amount("wood") == 5,
				"failed affordability never touches resources")
			_resources.add("wood", _tmp_a - 5)
			_wood_ledger = _tmp_a
		7:
			_check(_resources.get_amount("wood") == _wood_ledger,
				"funds restored to the regression ledger baseline")
			_push_key(KEY_B)
			_enter(Phase.QUARRY_FLOW)
			return
	_sp += 1


## -- QUARRY_FLOW: deposit snap/occupy/bind + 중복/부재 invalid --
func _quarry_flow() -> void:
	match _sp:
		0:
			_push_key(KEY_2)
			_push_key(KEY_B)
		1:
			_push_left_click(_screen_of(_aim(DEPOSIT_POS)))
		2:
			var quarries := get_nodes_in_group("quarries_3d")
			_check(quarries.size() == 1, "quarry is placed from the deposit click")
			if quarries.size() == 1:
				_check(quarries[0].position.is_equal_approx(DEPOSIT_POS),
					"quarry sits at the deposit anchor, not the raw click point")
				_check(quarries[0].get_deposit() == _deposit,
					"quarry binds the deposit (occupy contract)")
			_check(_deposit.is_occupied(), "deposit reports occupied after binding")
			_wood_ledger -= 10
			_check(_resources.get_amount("wood") == _wood_ledger,
				"quarry cost deducted once")
			_check(_last_feedback == "Quarry built", "quarry feedback keeps the legacy message")
			_push_key(KEY_B)
		3:
			_push_left_click(_screen_of(_aim(Vector3(34, 0, 34))))
		4:
			_check(get_nodes_in_group("quarries_3d").size() == 1,
				"occupied deposit rejects a second quarry")
			_check(_last_feedback == "Deposit already has a Quarry",
				"occupied deposit keeps the legacy feedback")
			_check(_resources.get_amount("wood") == _wood_ledger,
				"rejected quarry does not deduct cost")
			_push_left_click(_screen_of(_aim(Vector3(0, 0, 0))))
		5:
			_check(get_nodes_in_group("quarries_3d").size() == 1,
				"no nearby deposit places nothing")
			_check(_last_feedback == "No Stone Deposit nearby",
				"missing deposit keeps the legacy feedback")
			_push_key(KEY_B)
			_enter(Phase.WALL_GATE)
			return
	_sp += 1


## -- WALL_GATE: 연속 배치/인접 허용/겹침 거부/Gate corridor 규칙 --
func _wall_gate() -> void:
	match _sp:
		0:
			_push_key(KEY_3)
			_push_key(KEY_B)
		1:
			_push_left_click(_screen_of(_aim(WALL_A)))
		2:
			_check(get_nodes_in_group("walls_3d").size() == 1,
				"first wall segment placed on the corner grid")
			_wood_ledger -= 2
			_check(_last_feedback == "Wall built", "wall feedback keeps the legacy message")
			_check(_placement.is_active(),
				"build mode stays active after a wall (연속 배치 정책 유지)")
			_push_left_click(_screen_of(_aim(WALL_B)))
		3:
			_check(get_nodes_in_group("walls_3d").size() == 2,
				"edge-touching adjacent wall is allowed (인접 허용)")
			_wood_ledger -= 2
			_push_left_click(_screen_of(_aim(WALL_A)))
		4:
			_check(get_nodes_in_group("walls_3d").size() == 2,
				"positive-area wall overlap is rejected")
			_check(_last_feedback == "Invalid wall position",
				"wall overlap keeps the legacy feedback")
			_check(_resources.get_amount("wood") == _wood_ledger,
				"rejected wall does not deduct cost")
			# build mode 중 입력 ownership: selection은 게이트된다.
			_check(not _sel.can_handle_world_click(),
				"world selection is gated while build mode owns clicks")
			_push_left_click(_screen_of(_tavern.get_node("Interact").global_position))
		5:
			_check(_sel.get_selected() == _tavern.get_node("Interact"),
				"click during build mode does not change the selection")
			_push_key(KEY_4)
			_push_left_click(_screen_of(_aim(GATE_MISSED)))
		6:
			_check(_last_feedback == "Invalid gate position",
				"gate outside every corridor is rejected (corridor 밖 invalid)")
			_check(_resources.get_amount("wood") == _wood_ledger,
				"rejected gate does not deduct cost")
			_push_left_click(_screen_of(_aim(GATE_NORTH)))
		7:
			var gates := get_nodes_in_group("gates_3d")
			_check(gates.size() == 1, "gate inside the north corridor places")
			if gates.size() == 1:
				_check(gates[0].position.is_equal_approx(GATE_NORTH),
					"gate snaps to the road centerline corner (x=0 고정)")
				_check(gates[0].get_orientation() == "horizontal",
					"north gate crosses the road horizontally (3D X 축)")
			_wood_ledger -= 5
			_check(_last_feedback == "Gate built", "gate feedback keeps the legacy message")
			_push_left_click(_screen_of(_aim(GATE_EAST)))
		8:
			var gates := get_nodes_in_group("gates_3d")
			_check(gates.size() == 2, "east corridor gate places too")
			if gates.size() == 2:
				_check(gates[1].position.is_equal_approx(GATE_EAST),
					"east gate snaps to the z=0 centerline")
				_check(gates[1].get_orientation() == "vertical",
					"east gate crosses the road vertically (3D Z 축)")
			_wood_ledger -= 5
			_enter(Phase.REMOVE_REFUND)
			return
	_sp += 1


## -- REMOVE_REFUND: R remove mode + 전액 환불(기존 정책) --
func _remove_refund() -> void:
	match _sp:
		0:
			# 이후 철거 2건의 debounced rebake 증가를 재기 위한 기준선.
			_nav_baseline = _nav_manager.nav_rebuild_count
			_push_key(KEY_R)
		1:
			_check(_last_feedback == "Remove mode: click Wall to demolish",
				"R toggles remove mode with the legacy feedback")
			# remove pick은 snap이 관여하지 않으므로 정확한 좌표를 클릭한다.
			_push_left_click(_screen_of(WALL_B))
		2:
			_check(get_nodes_in_group("walls_3d").size() == 1,
				"clicked wall segment is removed")
			_wood_ledger += 2
			_check(_last_feedback == "Wall removed (+2 Wood)",
				"wall removal refunds the full legacy cost")
			_check(_resources.get_amount("wood") == _wood_ledger,
				"refund amount matches the paid cost exactly")
			_push_left_click(_screen_of(GATE_NORTH))
		3:
			_check(get_nodes_in_group("gates_3d").size() == 1,
				"clicked gate is removed")
			_wood_ledger += 5
			_check(_last_feedback == "Gate removed (+5 Wood)",
				"gate removal refunds its own cost")
			_push_left_click(_screen_of(Vector3(0, 0, 0)))
		4:
			_check(_last_feedback == "No wall to remove",
				"empty ground remove click is a safe no-op")
			_push_key(KEY_R)
			_push_key(KEY_B)
		5:
			_check(_last_feedback == "Remove mode off",
				"remove mode toggles off with the legacy feedback")
			_check(not _placement.is_active(),
				"B key exits build mode after remove-mode regression")
			_enter(Phase.FINAL_CHECKS)
			return
	_sp += 1


## -- FINAL_CHECKS: 원장 일치 + nav rebake 연결 + 잔존 물건 집계 --
func _final_checks() -> void:
	match _sp:
		0:
			_check(_resources.get_amount("wood") == _wood_ledger,
				"cost/refund regression ledger matches VillageResources exactly")
		1:
			# nav rebake가 debounce 프레임만큼 진행될 때까지 같은 스텝에 잔류한다.
			if _frame <= PHYSICS_WAIT_FRAMES * 4:
				return
			_check(_nav_manager.nav_rebuild_count > _nav_baseline,
				"placements/removals reach the Foundation debounced nav rebake")
			_check(get_nodes_in_group("walls_3d").size() == 1
				and get_nodes_in_group("gates_3d").size() == 1
				and get_nodes_in_group("lumberyards_3d").size() == 4
				and get_nodes_in_group("quarries_3d").size() == 1,
				"surviving world contents match the regression scenario")
			_enter(Phase.DONE)
			return
	_sp += 1
