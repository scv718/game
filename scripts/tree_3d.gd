extends ResourceNode3D
class_name WorldTree3D

## TASK-3D-RES-001-1/-2 Tree 3D. 기존 tree.gd(WorldTree)의 MATURE/STUMP/regrow
## 규약을 3D로 이전한 신규 파일이다. 기존 2D tree.gd / tree.tscn은 LOCK 12에 따라 유지.
##
## - state 전환 시 visual과 collision을 한 곳(_set_state)에서 함께 바꿔
##   depletion/regrowth 상태 일관을 보장한다(REQ: visual/collision state 일관).
## - collision 표현은 TrunkBlock(StaticBody3D, RESOURCE layer)의 CollisionShape3D
##   shape 리소스 교체다. mesh polygon(trimesh)을 쓰지 않는 단순 CylinderShape이며,
##   nav bake는 shape 노드/리소스의 실제 데이터를 파싱하므로 교체 후 반드시
##   request_rebuild_debounced로 rebake를 요청한다(gate 표현 규약과 동일 원칙).
##   주의: collision_shape.disabled 토글은 bake가 무시하므로 사용하지 않는다.
## - gameplay footprint(TrunkCollision r=0.75 unit = 2D trunk r=6px 환산 불변)는
##   Visual child의 scale variation과 분리되어 있다.
## - 제한적 visual variation: 배치 위치 hash를 seed로 하는 결정적 yaw/uniform scale
##   흔들기(HUMAN_CHECK: 복사/붙여넣기 숲 방지). Visual child에만 적용된다.

enum State { MATURE, STUMP }

@export var regrow_time: float = 20.0

## 제한적 visual variation 범위(균일 배율만 허용하는 월드 스케일 LOCK과 무관한
## 개체 표현 흔들기). 1.0 = 원본 스케일.
@export var variation_enabled: bool = true
@export var variation_scale_min: float = 0.9
@export var variation_scale_max: float = 1.15

var state: State = State.MATURE
var _regrow_timer: SceneTreeTimer = null

## stump 상태 충돌 shape. scene의 TrunkCollision이 가진 MATURE shape와 교체해 쓴다.
var _stump_shape: CylinderShape3D = null

var _variation_applied := false

@onready var _trunk_collision: CollisionShape3D = $TrunkBlock/TrunkCollision
@onready var _mature_shape: Shape3D = $TrunkBlock/TrunkCollision.shape
@onready var _visual: Node3D = $Visual
@onready var _canopy_visual: MeshInstance3D = $Visual/CanopyVisual
@onready var _trunk_visual: MeshInstance3D = $Visual/TrunkVisual
@onready var _stump_visual: MeshInstance3D = $Visual/StumpVisual


func _ready() -> void:
	super()
	_stump_shape = CylinderShape3D.new()
	_stump_shape.radius = 0.6
	_stump_shape.height = 0.5
	_apply_state()
	_apply_visual_variation()


func _on_depleted() -> void:
	_set_state(State.STUMP)
	if _regrow_timer != null or not is_inside_tree():
		return
	_regrow_timer = get_tree().create_timer(regrow_time)
	_regrow_timer.timeout.connect(_regrow)


func _regrow() -> void:
	_regrow_timer = null
	if not is_inside_tree() or state != State.STUMP:
		return
	current_amount = max_amount
	_set_state(State.MATURE)


## state 단일 진입점. visual 가시성과 collision shape를 항상 같이 맞춘 뒤
## nav rebake를 요청한다(장애물 크기가 바뀌므로 depletion/regrowth 모두 필요).
func _set_state(new_state: State) -> void:
	state = new_state
	_apply_state()
	NavigationPolicy3D.request_rebuild_debounced(get_tree())


func _apply_state() -> void:
	var mature := state == State.MATURE
	_canopy_visual.visible = mature
	_trunk_visual.visible = mature
	_stump_visual.visible = not mature
	_trunk_collision.shape = _mature_shape if mature else _stump_shape


## 결정적 visual variation. 같은 위치면 항상 같은 결과고, gameplay footprint에는
## 영향이 없다. 호출 시점에 global_position이 확정되어 있어야 하므로
## 배치 위치 지정 -> add_child 순서를 유지한다(표준 Godot 배치 관례).
func _apply_visual_variation() -> void:
	if not variation_enabled or _variation_applied or not is_inside_tree():
		return
	_variation_applied = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var s := rng.randf_range(variation_scale_min, variation_scale_max)
	_visual.scale = Vector3(s, s, s)
	_visual.rotation.y = deg_to_rad(rng.randf_range(-180.0, 180.0))
