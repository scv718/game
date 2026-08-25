extends SceneTree

## TASK-3D-BLD-001-4 Building Regression 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 큐 자동검증 10항목을 하나의 통합 시나리오로 회귀 고정한다:
##   1.  Building selection(클릭 선택 / 빈 지면 no-op / 우클릭 해제).
##   2.  placement(B 토글 -> 클릭 배치, 정확한 cell, 비용 1회 차감).
##   3.  invalid(건물 겹침 / 월드 bounds / 자금 부족 - 전부 무차감).
##   4.  remove/refund(R remove mode, Wall/Gate 전액 환불, 최종 원장 일치).
##   5.  Wall(corner grid 연속 배치, 인접 허용, 겹침 거부).
##   6.  Gate(corridor 밖 거부, N/S 수평 / E/W 수직 중심선 snap).
##   7.  UI interaction(tavern -> recruitment_ui open, Gate 토글 prompt 갱신,
##       build mode 중 선택 게이트).
##   8.  pan/zoom coordinates(pan/zoom 후 live ray 기준 정확 cell, 옛 픽셀 무효화).
##   9.  3D collision(본체 MASK_ACTOR_SOLID 차단 + 선택은 Interact Area 경유,
##       Gate CLOSED probe 차단/nav 우회, OPEN 통과).
##   10. Resource overlap validation(tree trunk 겹침 배치 거부).
##
## 모든 배치/철거는 실제 입력 이벤트(push_input)와 placement 진입점을 경유한다.
## 비용 회귀는 VillageResources 원장(_wood_ledger)으로 프레임마다 대조한다.
## autoload는 --script 모드에서 컴파일 타임 식별자가 아니므로 노드 조회로만 사용하고,
## class_name 유틸(CollisionLayers3D/WorldCoords3D)만 정적 참조한다.

enum Phase {
	SETUP, SELECTION_UI, PLACE, PAN_ZOOM, INVALID, WALL_GATE,
	COLLISION_CLOSED, COLLISION_OPEN, REMOVE_REFUND, FINAL, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const START_WOOD := 500

## fixture 배치(0012 회귀에서 경계가 검증된 좌표 재사용).
const TAVERN_LOGICAL := Vector2(-320, -320)
const TREE_POS := Vector3(-32, 0, 32)
const TREE_CELL_CENTER := Vector3(-31, 0, 31)
## cell 중심(홀수 unit) 목표들.
const CELL_C1 := Vector3(25, 0, 25)
const CELL_C2 := Vector3(9, 0, -23)
const CELL_C3 := Vector3(-23, 0, -9)
const CELL_FREE := Vector3(13, 0, 13)
## Wall corner(짝수 unit) / Gate corridor 목표.
const WALL_A := Vector3(20, 0, 20)
const WALL_B := Vector3(22, 0, 20)
const GATE_NORTH := Vector3(0, 0, -80)
const GATE_EAST := Vector3(60, 0, 0)
const GATE_MISSED := Vector3(0, 0, -40)
## Gate nav 통과 판정용 지점(북 corridor 안/밖).
const INSIDE := Vector3(0, 0, -70)
const OUTSIDE := Vector3(0, 0, -90)

var _frame := 0
var _pf := 0
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
var _fake_tavern_ui: Control = null
var _probe: CharacterBody3D = null
var _gate_north: Node = null
var _last_feedback := ""
var _last_mode_active := false
var _wood_ledger := 0
var _nav_marker := 0
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
	_pf = 0


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DBLD0014_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _wait_frames(count: int) -> bool:
	_pf += 1
	return _pf >= count


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


func _push_right_click(screen_pos: Vector2) -> void:
	_push_motion(screen_pos)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
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


func _find_gate_at(pos: Vector3) -> Node:
	for node in get_nodes_in_group("gates_3d"):
		var gate := node as StaticBody3D
		if gate != null and gate.global_position.is_equal_approx(pos):
			return gate
	return null


func _probe_blocked() -> bool:
	return _probe.test_move(
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, -74.0)), Vector3(0.0, 0.0, -16.0))


func _segment_hits_gate(a: Vector3, b: Vector3, box: AABB) -> bool:
	var steps := int(ceil(a.distance_to(b) / 0.25)) + 1
	for i in steps:
		var p := a.lerp(b, float(i) / float(steps))
		if p.x >= box.position.x and p.x <= box.end.x \
				and p.z >= box.position.z and p.z <= box.end.z:
			return true
	return false


## nav 경로가 북쪽 Gate footprint(XZ)를 가로지르는지(CLOSED=false, OPEN=true).
func _path_crosses_gate() -> bool:
	var path := NavigationServer3D.map_get_path(
		_nav_manager.get_navigation_map(), INSIDE, OUTSIDE, true)
	if path.size() < 2:
		return false
	var half: Vector2 = _gate_north.get_footprint_size() * 0.5 * WorldCoords3D.PX_TO_UNIT
	var center: Vector3 = _gate_north.global_position
	var box := AABB(
		Vector3(center.x - half.x, 0.0, center.z - half.y),
		Vector3(half.x * 2.0, 0.0, half.y * 2.0))
	for i in range(1, path.size()):
		if _segment_hits_gate(path[i - 1], path[i], box):
			return true
	return false


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.SELECTION_UI:
			_selection_ui()
		Phase.PLACE:
			_place()
		Phase.PAN_ZOOM:
			_pan_zoom()
		Phase.INVALID:
			_invalid()
		Phase.WALL_GATE:
			_wall_gate()
		Phase.COLLISION_CLOSED:
			_collision_closed()
		Phase.COLLISION_OPEN:
			_collision_open()
		Phase.REMOVE_REFUND:
			_remove_refund()
		Phase.FINAL:
			_final()
		Phase.DONE:
			_finish()
			return true
	if _frame > 5000:
		print("TASK3DBLD0014_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	if _world == null or _cam_ctl == null or _placement == null \
			or _sel == null or _game_time == null or _resources == null:
		_finish()
		return
	# phase gate 판정을 결정적으로 만들기 위해 자동 시간 진행을 멈춘다(종료 시 복원).
	_game_time.set_auto_advance(false)
	_check(_game_time.get_phase() == _game_time.Phase.DAY, "test runs in DAY phase")
	_placement.feedback.connect(_on_feedback)
	_placement.mode_changed.connect(_on_mode_changed)
	_resources.add("wood", START_WOOD)
	_wood_ledger = START_WOOD
	# Gate passage collision 통과 검증용 fixture(0013 probe body 규약 재사용).
	_probe = CharacterBody3D.new()
	_probe.name = "PhysicsProbe"
	_probe.collision_layer = CollisionLayers3D.WORKER
	_probe.collision_mask = CollisionLayers3D.MASK_ACTOR_SOLID
	var probe_shape := CollisionShape3D.new()
	var probe_box := BoxShape3D.new()
	probe_box.size = Vector3(1.0, 2.0, 1.0)
	probe_shape.shape = probe_box
	probe_shape.position.y = 1.0
	_probe.add_child(probe_shape)
	_world.add_child(_probe)
	_enter(Phase.SELECTION_UI)


## -- SELECTION_UI: 클릭 선택 + 기존 UI open + no-op/우클릭 해제 --
func _selection_ui() -> void:
	match _sp:
		0:
			_push_left_click(_screen_of(_tavern.get_node("Interact").global_position))
		1:
			_check(_sel.get_selected() == _tavern.get_node("Interact"),
				"clicking the tavern selects its Interactable3D volume")
			_check(_fake_tavern_ui.open_count == 1,
				"tavern click opens the legacy recruitment_ui (UI interaction)")
			var missed = _sel.select_at_screen_position(_screen_of(Vector3(60, 0, 60)))
			_check(missed == null and _sel.get_selected() == _tavern.get_node("Interact"),
				"empty ground click is a safe no-op that keeps the selection")
			_push_right_click(_screen_of(_tavern.get_node("Interact").global_position))
		2:
			_check(_sel.get_selected() == null, "right-click clears the building selection")
			_enter(Phase.PLACE)
			return
	_sp += 1


## -- PLACE: B 토글 -> 클릭 배치 -> 정확한 cell + 비용 1회 차감 --
func _place() -> void:
	match _sp:
		0:
			_push_key(KEY_B)
		1:
			_check(_placement.is_active(), "B key activates build mode")
			_check(_last_mode_active, "mode_changed signal reports activation")
			_push_left_click(_screen_of(_aim(CELL_C1)))
		2:
			var yards := get_nodes_in_group("lumberyards_3d")
			_check(yards.size() == 1, "one lumberyard exists after the placement click")
			if yards.size() == 1:
				_check(yards[0].position.is_equal_approx(CELL_C1),
					"placed lumberyard occupies exactly the aimed grid cell center")
			_wood_ledger -= 10
			_check(_resources.get_amount("wood") == _wood_ledger,
				"cost is deducted exactly once for a valid placement")
			_check(_last_feedback == "Lumberyard built",
				"placement feedback keeps the legacy message")
			_check(not _placement.is_active(),
				"build mode exits after a single-place building succeeds")
			_enter(Phase.PAN_ZOOM)
			return
	_sp += 1


## -- PAN_ZOOM: pan/zoom 후에도 live camera ray 기준 정확한 target cell --
func _pan_zoom() -> void:
	match _sp:
		0:
			# pan 전 화면 픽셀을 캡처한다(pan 후 같은 픽셀은 다른 cell을 가리킨다).
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
			_push_key(KEY_B)
			_push_left_click(_tmp_b)
		5:
			var expected: Vector3 = _placement._snap_cell_center(
				_cam_ctl.ground_point_from_screen(_tmp_b))
			var yards := get_nodes_in_group("lumberyards_3d")
			_check(yards.size() == 4 and yards[3].position.is_equal_approx(expected),
				"a stale pre-pan screen pixel maps through the live camera ray to its new cell")
			if yards.size() == 4:
				_check(not yards[3].position.is_equal_approx(CELL_C1),
					"a stale screen pixel no longer targets the pre-pan cell")
			_wood_ledger -= 10
			_check(_resources.get_amount("wood") == _wood_ledger,
				"cost ledger stays exact across pan/zoom placements")
			_enter(Phase.INVALID)
			return
	_sp += 1


## -- INVALID: 건물 겹침/자원 겹침/bounds/자금 부족 전부 무차감 --
func _invalid() -> void:
	match _sp:
		0:
			# PAN_ZOOM이 lumberyard 배치로 mode를 종료하므로 type 확인 후 재진입한다.
			_push_key(KEY_1)
			_push_key(KEY_B)
		1:
			_check(_placement.is_active(), "build mode re-activates for invalid checks")
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
			_enter(Phase.WALL_GATE)
			return
	_sp += 1


## -- WALL_GATE: corner grid 연속 배치/인접 허용/겹침 거부/Gate corridor 규칙 --
func _wall_gate() -> void:
	match _sp:
		0:
			_push_key(KEY_3)
			_push_key(KEY_B)
		1:
			_check(_placement.is_active(), "build mode active for wall/gate checks")
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
			_check(_sel.get_selected() == null,
				"click during build mode does not change the selection")
			_push_key(KEY_4)
			_push_left_click(_screen_of(_aim(GATE_MISSED)))
		6:
			_check(get_nodes_in_group("gates_3d").is_empty(),
				"gate outside every corridor is rejected (corridor 밖 invalid)")
			_check(_last_feedback == "Invalid gate position",
				"gate rejection keeps the legacy feedback")
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
			_enter(Phase.COLLISION_CLOSED)
			return
	_sp += 1


## -- COLLISION_CLOSED: 건물 본체 충돌/선택 볼륨 분리 + CLOSED gate 차단 --
func _collision_closed() -> void:
	match _sp:
		0:
			_gate_north = _find_gate_at(GATE_NORTH)
			_check(_gate_north != null, "north gate reference captured for collision probes")
			var tavern_xz: Vector3 = _tavern.global_position
			var space := _world.get_world_3d().direct_space_state
			var solid_query := PhysicsRayQueryParameters3D.create(
				Vector3(tavern_xz.x, 20.0, tavern_xz.z), Vector3(tavern_xz.x, -1.0, tavern_xz.z),
				CollisionLayers3D.MASK_ACTOR_SOLID)
			_check(space.intersect_ray(solid_query).get("collider") == _tavern,
				"building body blocks actors as a static BUILDING layer collider")
			var select_query := PhysicsRayQueryParameters3D.create(
				Vector3(tavern_xz.x, 20.0, tavern_xz.z), Vector3(tavern_xz.x, -1.0, tavern_xz.z),
				CollisionLayers3D.MASK_SELECTION)
			select_query.collide_with_bodies = false
			select_query.collide_with_areas = true
			_check(space.intersect_ray(select_query).get("collider") == _tavern.get_node("Interact"),
				"selection probe hits the Interact area, not the building body (2D convention)")
			_pf = 0
			_sp = 1
		1:
			if not _wait_frames(PHYSICS_WAIT_FRAMES):
				return
			_check(_probe_blocked(),
				"CLOSED gate blocks a physics probe (test_move)")
			_check(not _path_crosses_gate(),
				"CLOSED gate: nav path detours around the footprint")
			_enter(Phase.COLLISION_OPEN)


## -- COLLISION_OPEN: OPEN 통과 + Interact toggle(UI)로 재폐쇄 --
func _collision_open() -> void:
	match _sp:
		0:
			_gate_north.set_open(true)
			_check(_gate_north.is_open() and not _gate_north.is_closed(),
				"set_open(true) opens the placed gate")
			_check(_gate_north.get_node_or_null("CollisionShape3D") == null,
				"OPEN gate removes its passage collision shape (Foundation convention)")
			var mat: StandardMaterial3D = _gate_north.get_node("Visual/BodyMesh").material_override
			_check(mat.albedo_color.is_equal_approx(_gate_north.COLOR_OPEN),
				"OPEN visual state shows the legacy translucent color")
			_pf = 0
			_sp = 1
		1:
			if not _wait_frames(PHYSICS_WAIT_FRAMES):
				return
			_check(not _probe_blocked(), "OPEN gate lets a physics probe through")
			_check(_path_crosses_gate(), "OPEN gate: nav path crosses the footprint")
			_pf = 0
			_sp = 2
		2:
			# Player 상호작용 경로(Interactable3D.toggle)로 되닫는다(UI interaction).
			var gi: Area3D = _gate_north.get_node("Interact")
			_check(gi.prompt == "Gate (OPEN) - Toggle",
				"gate prompt reflects the OPEN state before the toggle")
			gi.interact(null)
			_check(_gate_north.is_closed(),
				"Interact toggle closes the gate through the legacy UI contract")
			_check(gi.prompt == "Gate (CLOSED) - Toggle",
				"gate prompt refreshes after the state change")
			_pf = 0
			_sp = 3
		3:
			if not _wait_frames(PHYSICS_WAIT_FRAMES):
				return
			_check(_gate_north.get_node_or_null("CollisionShape3D") != null,
				"re-closed gate restores its passage collision shape")
			_check(_probe_blocked(), "re-closed gate blocks the physics probe again")
			_enter(Phase.REMOVE_REFUND)


## -- REMOVE_REFUND: R remove mode + Wall/Gate 전액 환불(기존 정책) --
func _remove_refund() -> void:
	match _sp:
		0:
			# 이후 철거 2건의 debounced rebake 증가를 재기 위한 기준선.
			_nav_marker = _nav_manager.nav_rebuild_count
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
				"B key exits build mode after the remove-mode regression")
			_enter(Phase.FINAL)
			return
	_sp += 1


## -- FINAL: 최종 원장 일치 + nav rebake 연결 + 잔존 물건 집계 --
func _final() -> void:
	match _sp:
		0:
			_check(_resources.get_amount("wood") == _wood_ledger,
				"cost/refund regression ledger matches VillageResources exactly")
			_pf = 0
			_sp = 1
		1:
			# nav rebake가 debounce 프레임만큼 진행될 때까지 같은 스텝에 잔류한다.
			# 첫 실행 import 지연 환경을 고려해 넉넉한 대기(0012 절대 프레임 게이트와 동일 여유).
			if not _wait_frames(PHYSICS_WAIT_FRAMES * 4):
				return
			_check(_nav_manager.nav_rebuild_count > _nav_marker,
				"placements/removals reach the Foundation debounced nav rebake")
			_check(get_nodes_in_group("walls_3d").size() == 1
				and get_nodes_in_group("gates_3d").size() == 1
				and get_nodes_in_group("lumberyards_3d").size() == 4,
				"surviving world contents match the regression scenario")
			_enter(Phase.DONE)
