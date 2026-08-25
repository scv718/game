extends SceneTree

## TASK-3D-BLD-001-1 Building3D Base / Existing Building Scenes 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 검증 범위:
##   1. Foundation Interaction3D 계약 사용(Interactable3D 상속) + Building3D base(StaticBody3D).
##   2. 기존 building identity/data 유지(5종 core_type/label/level/prompt, 2D와 동일 값).
##   3. selectable collision(INTERACTABLE layer Area3D) + click -> 기존 UI/interaction 연결.
##   4. static world collision(BUILDING layer 본체 + nav bake 장애물 편입).
##   5. visual slot 구조(Visual 하위에만 mesh, collision 배제) + placeholder 식별성.
##   6. 2D Sprite/Collision Runtime 의존 없음(scene 노드 구조 검사).
##
## 전역 클래스 정적 의존을 피하는 관례(task3d0013/0014 규약)에 따라
## 스크립트는 load()로 늦게 로드한다. 배치 좌표는 기존 world.tscn 핵심 건물
## 배치(logical px)를 WorldCoords3D 변환으로 재사용한다(레이아웃 identity 보존).

enum Phase {
	SETUP, CONTRACT, SCENE_SETUP, IDENTITY, SELECTION, STATIC_COLLISION,
	VISUAL_SLOT, NO_2D_DEP, DONE,
}

const PHYSICS_WAIT_FRAMES := 30

## 기존 world.tscn 핵심 건물 배치와 동일한 logical 좌표(core_type -> logical px).
const LAYOUT := {
	"keep": Vector2(0, -148),
	"tavern": Vector2(-126, -48),
	"inn": Vector2(126, -48),
	"grocery": Vector2(-122, 116),
	"equipment": Vector2(122, 116),
}

## 기존 CoreBuilding identity/data와 동일해야 하는 기대값.
const EXPECTED_LABELS := {
	"keep": "거점",
	"tavern": "주점",
	"inn": "여관",
	"grocery": "식료품점",
	"equipment": "장비점",
}

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _sel: Node = null
var _cam_ctl: Node = null
var _game_time: Node = null
var _nav_manager: Node = null
var _building_script: GDScript = null
var _core_script: GDScript = null
var _interact_script: GDScript = null
var _buildings := {}
var _tavern_ui: Control = null
var _inn_ui: Control = null


class FakeRecruitmentUI extends Control:
	var open_count := 0

	func _init() -> void:
		add_to_group("recruitment_ui")
		visible = false

	func open() -> void:
		open_count += 1


class FakeInnRosterUI extends Control:
	var open_count := 0

	func _init() -> void:
		add_to_group("inn_roster_ui")
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


func _finish() -> void:
	if _game_time != null and is_instance_valid(_game_time):
		_game_time.set_auto_advance(true)
	print("TASK3DBLD0011_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


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


func _push_right_click(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = screen_pos
	root.push_input(event)


func _interact_of(core_type: String) -> Area3D:
	return _buildings[core_type].get_node("Interact")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.SCENE_SETUP:
			_scene_setup()
		Phase.IDENTITY:
			_identity()
		Phase.SELECTION:
			_selection()
		Phase.STATIC_COLLISION:
			_static_collision()
		Phase.VISUAL_SLOT:
			_visual_slot()
		Phase.NO_2D_DEP:
			_no_2d_dep()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DBLD0011_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	_enter(Phase.CONTRACT)


## -- CONTRACT: Foundation/base 계약 상속 + 기존 identity/data 보존 --
func _contract() -> void:
	_building_script = load("res://scripts/building_3d.gd")
	_core_script = load("res://scripts/core_building_3d.gd")
	_interact_script = load("res://scripts/core_building_interactable_3d.gd")
	var interact_base: GDScript = load("res://scripts/interactable_3d.gd")
	_check(_building_script.get_instance_base_type() == "StaticBody3D",
		"Building3D base is a StaticBody3D (static world collision holder)")
	_check(_core_script.get_base_script() == _building_script,
		"CoreBuilding3D extends the Building3D base")
	_check(_interact_script.get_base_script() == interact_base,
		"CoreBuildingInteractable3D extends the Foundation Interactable3D contract")

	var default_node: StaticBody3D = _core_script.new()
	_check(default_node.core_type == "tavern",
		"default core_type keeps the legacy tavern default")
	default_node.free()

	var clean_data := true
	for core_type in EXPECTED_LABELS:
		var node: StaticBody3D = _core_script.new()
		node.core_type = core_type
		var label: String = EXPECTED_LABELS[core_type]
		if node.get_core_type() != core_type \
				or node.get_building_label() != label \
				or node.get_level() != 1 \
				or node.get_interact_prompt() != "%s (Lv.1)" % label:
			clean_data = false
			print("  identity drift in core_type=%s" % core_type)
		node.free()
	_check(clean_data,
		"all 5 core types keep the legacy label/level/prompt identity data")
	_enter(Phase.SCENE_SETUP)


## -- SCENE_SETUP: 5종 핵심 건물을 기존 world.tscn 배치 좌표에 인스턴스 --
func _scene_setup() -> void:
	if _buildings.is_empty():
		for core_type in LAYOUT:
			var building: StaticBody3D = (load("res://scenes/core_building_3d.tscn") as PackedScene).instantiate()
			building.name = "Core_" + core_type
			building.core_type = core_type
			building.set_logical_position(LAYOUT[core_type])
			_world.add_child(building)
			_buildings[core_type] = building
		# 건물이 이미 있는 상태에서 nav manager를 붙여 초기 bake가 건물을 파싱하게 한다.
		_nav_manager = load("res://scripts/navigation_manager_3d.gd").new()
		_nav_manager.name = "NavManager"
		_world.add_child(_nav_manager)
		_tavern_ui = FakeRecruitmentUI.new()
		_tavern_ui.name = "FakeRecruitmentUI"
		root.add_child(_tavern_ui)
		_inn_ui = FakeInnRosterUI.new()
		_inn_ui.name = "FakeInnRosterUI"
		root.add_child(_inn_ui)
		_wait = 0
		return
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	_wait = 0
	_enter(Phase.IDENTITY)


## -- IDENTITY: group/layer/prompt 등 runtime 등록 상태 --
func _identity() -> void:
	var clean := true
	for core_type in _buildings:
		var building: StaticBody3D = _buildings[core_type]
		var interact: Area3D = _interact_of(core_type)
		if not building.is_in_group("buildings_3d") \
				or not building.is_in_group("core_buildings_3d"):
			clean = false
			print("  missing 3D groups on %s" % core_type)
		if building.collision_layer != CollisionLayers3D.BUILDING \
				or building.collision_mask != 0:
			clean = false
			print("  bad body layer/mask on %s" % core_type)
		if interact.collision_layer != CollisionLayers3D.INTERACTABLE \
				or interact.collision_mask != 0:
			clean = false
			print("  bad interact layer/mask on %s" % core_type)
		if interact.prompt != building.get_interact_prompt():
			clean = false
			print("  prompt not delegated from building data on %s" % core_type)
		if interact.get_core_building() != building:
			clean = false
			print("  interact does not delegate to its building on %s" % core_type)
	_check(clean,
		"all 5 buildings register 3D groups/layers and delegate prompts to building data")
	_check(_buildings["tavern"].get_interact_prompt() == "주점 (Lv.1)",
		"tavern prompt keeps the legacy format (주점 (Lv.1))")
	_enter(Phase.SELECTION)


## -- SELECTION: click -> 선택 + 기존 UI/interaction 연결 --
func _selection() -> void:
	# 주점 클릭 -> 기존 recruitment_ui open 계약.
	_push_left_click(_screen_of(_interact_of("tavern").global_position))
	_check(_sel.get_selected() == _interact_of("tavern"),
		"clicking the tavern selects its Interactable3D volume")
	_check(_tavern_ui.open_count == 1,
		"tavern click opens the legacy recruitment_ui via the same group contract")
	# 여관 클릭 -> 기존 inn_roster_ui open 계약.
	_push_left_click(_screen_of(_interact_of("inn").global_position))
	_check(_sel.get_selected() == _interact_of("inn"),
		"clicking the inn selects the inn volume")
	_check(_inn_ui.open_count == 1 and _tavern_ui.open_count == 1,
		"inn click opens the legacy inn_roster_ui and does not retrigger the tavern")
	# 거점/식료품점/장비점 클릭 -> 선택은 되고 UI open은 없음(최소 prompt 경계 유지).
	_push_left_click(_screen_of(_interact_of("keep").global_position))
	_check(_sel.get_selected() == _interact_of("keep"),
		"keep is selectable like in 2D")
	_push_left_click(_screen_of(_interact_of("grocery").global_position))
	_check(_sel.get_selected() == _interact_of("grocery"),
		"grocery is selectable like in 2D")
	_check(_interact_of("grocery").interact(_sel).is_empty(),
		"prompt-only buildings keep the legacy empty interact result")
	_check(_tavern_ui.open_count == 1 and _inn_ui.open_count == 1,
		"prompt-only building clicks never open any UI")
	# 빈 지면 클릭 -> 선택 변경 없음(안전 no-op).
	var ground_missed = _sel.select_at_screen_position(_screen_of(Vector3(60.0, 0.0, 60.0)))
	_check(ground_missed == null and _sel.get_selected() == _interact_of("grocery"),
		"empty ground click is a safe no-op that keeps the current selection")
	# 우클릭 -> 선택 해제(기존 규약).
	_push_right_click(_screen_of(_interact_of("grocery").global_position))
	_check(_sel.get_selected() == null, "right-click clears the building selection")
	_enter(Phase.STATIC_COLLISION)


## -- STATIC_COLLISION: 본체 정적 충돌 + nav bake 장애물 편입 --
func _static_collision() -> void:
	var tavern_xz: Vector3 = _buildings["tavern"].global_position
	var space := _world.get_world_3d().direct_space_state
	var solid_query := PhysicsRayQueryParameters3D.create(
		Vector3(tavern_xz.x, 20.0, tavern_xz.z), Vector3(tavern_xz.x, -1.0, tavern_xz.z),
		CollisionLayers3D.MASK_ACTOR_SOLID)
	var solid_hit := space.intersect_ray(solid_query)
	_check(solid_hit.get("collider") == _buildings["tavern"],
		"building body blocks actors as a static BUILDING layer collider")
	var select_query := PhysicsRayQueryParameters3D.create(
		Vector3(tavern_xz.x, 20.0, tavern_xz.z), Vector3(tavern_xz.x, -1.0, tavern_xz.z),
		CollisionLayers3D.MASK_SELECTION)
	select_query.collide_with_bodies = false
	select_query.collide_with_areas = true
	var select_hit := space.intersect_ray(select_query)
	_check(select_hit.get("collider") == _interact_of("tavern"),
		"selection probe hits the Interact area, not the building body (2D convention)")
	# nav bake가 건물 본체를 장애물로 편입했는지: 건물 관통 직선 경로가 우회되는지 확인.
	var from := Vector3(0.0, 0.0, -12.0)
	var to := Vector3(0.0, 0.0, -25.0)
	var path := NavigationServer3D.map_get_path(_nav_manager.get_navigation_map(), from, to, true)
	_check(_nav_manager.is_target_reachable(from, to),
		"destination behind the keep stays reachable")
	var detoured := false
	for point in path:
		if absf(point.x) > 0.5:
			detoured = true
	_check(path.size() > 2 and detoured,
		"navigation routes around the static keep collision (baked obstacle)")
	_enter(Phase.VISUAL_SLOT)


## -- VISUAL_SLOT: visual/game logic 분리 + placeholder 식별성 --
func _visual_slot() -> void:
	var tavern: StaticBody3D = _buildings["tavern"]
	_check(tavern.visual_slot != null and tavern.visual_slot is Node3D
		and tavern.visual_slot.name == "Visual",
		"Building3D exposes the Visual slot for the VIS domain")
	var meshes_outside_slot := 0
	var physics_inside_slot := 0
	for child in tavern.get_children():
		if child == tavern.visual_slot:
			var stack: Array[Node] = [child]
			while not stack.is_empty():
				var node: Node = stack.pop_back()
				if node is CollisionShape3D or node is CollisionObject3D:
					physics_inside_slot += 1
				stack.append_array(node.get_children())
		else:
			var stack: Array[Node] = [child]
			while not stack.is_empty():
				var node: Node = stack.pop_back()
				if node is MeshInstance3D or node is Label3D:
					meshes_outside_slot += 1
				stack.append_array(node.get_children())
	_check(meshes_outside_slot == 0,
		"no visual mesh lives outside the Visual slot")
	_check(physics_inside_slot == 0,
		"Visual slot holds no collision/physics nodes (visual/logic separation)")
	var body_mesh: MeshInstance3D = tavern.get_node("Visual/BodyMesh")
	var inn_mesh: MeshInstance3D = _buildings["inn"].get_node("Visual/BodyMesh")
	var tavern_color: Color = body_mesh.material_override.albedo_color
	var inn_color: Color = inn_mesh.material_override.albedo_color
	_check(tavern_color != inn_color,
		"placeholder colors differ per core_type (top-down identifiability)")
	_check(tavern.get_node("Visual/NameLabel").text == "주점",
		"nameplate shows the legacy building label")
	_enter(Phase.NO_2D_DEP)


## -- NO_2D_DEP: 3D 건물 scene에 2D Sprite/Collision 의존 없음 --
func _no_2d_dep() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	var allowed := {
		"Node3D": true, "Area3D": true, "StaticBody3D": true,
		"CollisionShape3D": true, "MeshInstance3D": true, "Label3D": true,
	}
	var instance: Node = (load("res://scenes/core_building_3d.tscn") as PackedScene).instantiate()
	var stack: Array[Node] = [instance]
	var clean := true
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not allowed.has(node.get_class()):
			clean = false
			print("  offending node: %s (%s)" % [node.name, node.get_class()])
		stack.append_array(node.get_children())
	instance.free()
	_check(clean,
		"building scene contains only 3D runtime nodes (no 2D sprite/collision dependency)")
	_finish()
