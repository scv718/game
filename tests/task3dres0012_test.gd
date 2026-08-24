extends SceneTree

## TASK-3D-RES-001-2 Tree / Stone Resource Visual 회귀 테스트.
## 기존 2D 테스트 파일은 수정하지 않는 신규 task3d* 계열(migration map 운영 규칙 5).
##
## 참고: Quaternius `Stylized Nature MegaKit` 실물 mesh는 VIS 도메인
## (TASK-3D-VIS-001-1 Asset Acquire / Import) 소유다. 이 태스크는 자원 visual의
## 구조적 계약을 검증한다 - placeholder primitive가 지키아 할 규칙과 동일하다.
##
## 검증 범위:
##   1. visual child와 game logic 분리(모든 mesh는 Visual Node3D 하위에 존재).
##   2. gameplay collision은 단순 shape(Cylinder/Sphere)이고 mesh polygon(trimesh)
##      을 그대로 쓰지 않는다.
##   3. top-down 식별성: Tree와 Stone이 서로 다른 알베도 실루엣을 가진다.
##   4. 제한적 visual variation: 위치 기반 결정적 yaw/uniform scale 흔들기.
##     - 같은 위치면 항상 같은 결과(재현 가능).
##     - 다른 위치면 다른 결과(반복감 완화).
##   5. gameplay footprint는 visual scale 변경과 분리(충돌 shape 불변).
##   6. stump/regrowth visual이 state 전환과 연결됨(001-1의 state 일관 재확인).

enum Phase { SETUP, STRUCTURE, IDENTIFY, VARIATION_SAME, VARIATION_DIFFERENT,
	FOOTPRINT, STUMP_LINK, DONE }

const PHYSICS_WAIT_FRAMES := 10
const SHAPE_EPS := 0.001

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _tree_a: Node3D = null
var _tree_b: Node3D = null
var _tree_c: Node3D = null
var _stone: Node3D = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p


func _finish() -> void:
	print("TASK3DRES0012_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _visual_scale(tree: Node3D) -> Vector3:
	return (tree.get_node("Visual") as Node3D).scale


func _visual_yaw(tree: Node3D) -> float:
	return (tree.get_node("Visual") as Node3D).rotation.y


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= SHAPE_EPS


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.STRUCTURE:
			_structure()
		Phase.IDENTIFY:
			_identify()
		Phase.VARIATION_SAME:
			_variation_same()
		Phase.VARIATION_DIFFERENT:
			_variation_different()
		Phase.FOOTPRINT:
			_footprint()
		Phase.STUMP_LINK:
			_stump_link()
		Phase.DONE:
			_finish()
			return true
	if _frame > 3000:
		print("TASK3DRES0012_RESULT=TIMEOUT phase=%s" % str(_phase))
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
	if _world == null:
		_finish()
		return
	_tree_a = (load("res://scenes/tree_3d.tscn") as PackedScene).instantiate()
	_tree_a.position = Vector3(4.0, 0.0, 4.0)
	_world.add_child(_tree_a)

	_tree_b = (load("res://scenes/tree_3d.tscn") as PackedScene).instantiate()
	_tree_b.position = Vector3(4.0, 0.0, 4.0)
	_world.add_child(_tree_b)

	_tree_c = (load("res://scenes/tree_3d.tscn") as PackedScene).instantiate()
	_tree_c.position = Vector3(-14.0, 0.0, 9.0)
	_world.add_child(_tree_c)

	_stone = (load("res://scenes/stone_deposit_3d.tscn") as PackedScene).instantiate()
	_stone.position = Vector3(20.0, 0.0, -12.0)
	_world.add_child(_stone)
	_enter(Phase.STRUCTURE)


## -- STRUCTURE: visual child / game logic 분리 + 단순 충돌 shape --
func _structure() -> void:
	_wait += 1
	if _wait < PHYSICS_WAIT_FRAMES:
		return
	var visual: Node3D = _tree_a.get_node("Visual")
	var mesh_count := 0
	for child in visual.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
	_check(mesh_count == 3,
		"all tree meshes live under the dedicated Visual child (logic-free)")
	for child in _tree_a.get_children():
		if child is MeshInstance3D:
			_check(false, "tree root must not own render meshes directly")
	_check(_stone.get_node_or_null("Visual/RockVisual") is MeshInstance3D,
		"stone deposit keeps its rock mesh inside a Visual child too")

	var trunk_shape: Shape3D = _tree_a.get_node("TrunkBlock/TrunkCollision").shape
	_check(trunk_shape is CylinderShape3D,
		"trunk collision uses a simple cylinder, not a mesh polygon")
	var block_shape: Shape3D = _stone.get_node("Block/CollisionShape3D").shape
	_check(block_shape is SphereShape3D,
		"stone block collision uses a simple sphere, not a mesh polygon")
	_check(not trunk_shape is ConcavePolygonShape3D
		and not block_shape is ConcavePolygonShape3D,
		"no resource collision is a baked trimesh (gameplay-first shapes)")
	_enter(Phase.IDENTIFY)


## -- IDENTIFY: top-down에서 종류 식별 가능(알베도 구분) --
func _identify() -> void:
	var canopy_mat: StandardMaterial3D = \
		(_tree_a.get_node("Visual/CanopyVisual") as MeshInstance3D).mesh.material
	var rock_mat: StandardMaterial3D = \
		(_stone.get_node("Visual/RockVisual") as MeshInstance3D).mesh.material
	var canopy: Color = canopy_mat.albedo_color
	var rock: Color = rock_mat.albedo_color
	_check(canopy.g > canopy.r + 0.05,
		"tree canopy reads green from the top-down camera")
	_check(absf(rock.r - rock.g) < 0.02 and absf(rock.g - rock.b) < 0.02,
		"stone deposit reads neutral gray (distinct resource silhouette)")
	_check(canopy.g > rock.g,
		"canopy and rock stay distinguishable at zoom-out brightness levels")
	_enter(Phase.VARIATION_SAME)


## -- VARIATION_SAME: 결정성 - 같은 위치면 동일한 variation --
func _variation_same() -> void:
	var same_pose: bool = _near(_visual_scale(_tree_a).x, _visual_scale(_tree_b).x) \
		and absf(_visual_yaw(_tree_a) - _visual_yaw(_tree_b)) <= SHAPE_EPS
	_check(same_pose,
		"identical placement produces identical variation (deterministic seed)")
	_enter(Phase.VARIATION_DIFFERENT)


## -- VARIATION_DIFFERENT: 다른 위치면 다른 variation(제한 범위 내) --
func _variation_different() -> void:
	var differs: bool = absf(_visual_scale(_tree_a).x - _visual_scale(_tree_c).x) > SHAPE_EPS \
		or absf(_visual_yaw(_tree_a) - _visual_yaw(_tree_c)) > SHAPE_EPS
	_check(differs,
		"different placements produce different variation (anti copy-paste forest)")
	var s := _visual_scale(_tree_c).x
	_check(s >= _tree_c.variation_scale_min - SHAPE_EPS
		and s <= _tree_c.variation_scale_max + SHAPE_EPS,
		"variation stays inside the exported limited range")
	_enter(Phase.FOOTPRINT)


## -- FOOTPRINT: visual scale과 gameplay footprint 분리 --
func _footprint() -> void:
	var shape: CylinderShape3D = _tree_c.get_node("TrunkBlock/TrunkCollision").shape
	_check(_near(shape.radius, 0.75) and _near(shape.height, 2.4),
		"trunk footprint keeps its gameplay size under any visual variation")
	var interact_shape: SphereShape3D = \
		_tree_c.get_node("InteractionShape").shape as SphereShape3D
	_check(_near(interact_shape.radius, 1.875),
		"interaction volume footprint is likewise variation-independent")
	_enter(Phase.STUMP_LINK)


## -- STUMP_LINK: stump/regrowth visual이 기존 state 전환과 연결됨 --
func _stump_link() -> void:
	if not _tree_a.has_meta("_stump_checked"):
		_tree_a.set_meta("_stump_checked", true)
		var interactor := Node.new()
		interactor.name = "VisualTestInteractor"
		root.add_child(interactor)
		_tree_a.current_amount = 1
		_tree_a.interact(interactor)
		interactor.free()
		_check((_tree_a.get_node("Visual/StumpVisual") as MeshInstance3D).visible
			and not (_tree_a.get_node("Visual/CanopyVisual") as MeshInstance3D).visible,
			"depletion swaps the Visual child to its stump representation")
		_tree_a._regrow()
		_check(not (_tree_a.get_node("Visual/StumpVisual") as MeshInstance3D).visible
			and (_tree_a.get_node("Visual/CanopyVisual") as MeshInstance3D).visible,
			"regrowth restores the mature representation in the same Visual slot")
		_finish()
