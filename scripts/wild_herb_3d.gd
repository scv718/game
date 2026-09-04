extends ResourceNode3D
class_name WildHerb3D

## TASK-021-1 Wild Herb Resource 3D.
## 기존 tree_3d.gd(WorldTree3D)의 depletion/regrowth 상태 규약을 재사용한 야생 약초
## 자원 소스다. 기준 ResourceNode3D(RES 도메인 claim/interact 계약)를 그대로 상속하며,
## herb/potion 이외 새 시스템(animal/NPC 등)을 억지로 만들지 않는다.
##
## - game logic은 이 노드가 소유하고 visual 표현은 자식 Visual에 둔다
##   (tree_3d.gd Visual child 계약 동일 - game logic/visual 분리).
## - herb는 작은 지피 식물이라 nav 장애물/물리 블록(TrunkBlock)을 갖지 않는다.
##   따라서 depletion/regrowth가 nav rebake를 요구하지 않으며, _exit_tree에서도
##   nav rebake를 요청하지 않는다(tree의 trunk와 달리 collision footprint가 없음).
## - depletion -> PICKED(땅이 비어 보임), regrow_time 경과 후 GROWN 복구.
##   tree_3d의 stump/regrow 규약과 동일 의미이며 collision이 없으므로
##   state 일관은 visual 가시성 하나로 유지한다.
## - is_selectable()은 ResourceNode3D 기본값(false) 그대로 - Player 마우스 직접
##   채집 차단 정책(Foundation 계약) 유지. 획득 경로는 Worker 전용
##   (HerbGatherer3D)이다. Player Avatar 직접 채집을 새로 만들지 않는다.
## - Herb visual은 Stylized Nature MegaKit 우선이나 실물 mesh는 VIS 도메인
##   (TASK-3D-VIS-001-1) 소유이므로, task3dres0012_test 관례대로 placeholder
##   primitive가 동일한 구조 계약(Visual child)을 지킨다.

enum State { GROWN, PICKED }

@export var regrow_time: float = 8.0

## 제한적 visual variation(tree_3d.gd와 동일 계약 - 위치 hash 결정적 흔들기).
@export var variation_enabled: bool = true
@export var variation_scale_min: float = 0.85
@export var variation_scale_max: float = 1.15

var state: State = State.GROWN
var _regrow_timer: SceneTreeTimer = null
var _variation_applied := false

@onready var _visual: Node3D = $Visual
@onready var _grown_visual: MeshInstance3D = $Visual/GrownVisual
@onready var _picked_visual: MeshInstance3D = $Visual/PickedVisual


## base(ResourceNode3D)의 기본 resource_id가 "wood"이므로, wild herb는 herb로
## 초기화한다. _init에서 설정해 new()/scene 두 경로 모두에 적용한다(exported
## 기본값 대체, scene에서 resource_id를 override하지 않음).
func _init() -> void:
	resource_id = "herb"


func _ready() -> void:
	super()
	_apply_state()
	_apply_visual_variation()


func _on_depleted() -> void:
	_set_state(State.PICKED)
	if _regrow_timer != null or not is_inside_tree():
		return
	_regrow_timer = get_tree().create_timer(regrow_time)
	_regrow_timer.timeout.connect(_regrow)


func _regrow() -> void:
	_regrow_timer = null
	if not is_inside_tree() or state != State.PICKED:
		return
	current_amount = max_amount
	_set_state(State.GROWN)


## state 단일 진입점. herb는 collision footprint가 없으므로 visual 가시성만 전환한다
## (tree의 _set_state가 collision shape + nav rebake를 함께 다루는 것과 대조).
func _set_state(new_state: State) -> void:
	state = new_state
	_apply_state()


func _apply_state() -> void:
	var grown := state == State.GROWN
	_grown_visual.visible = grown
	_picked_visual.visible = not grown


## 결정적 visual variation(tree_3d.gd 계약과 동일). gameplay footprint 영향 없음.
func _apply_visual_variation() -> void:
	if not variation_enabled or _variation_applied or not is_inside_tree():
		return
	_variation_applied = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var s := rng.randf_range(variation_scale_min, variation_scale_max)
	_visual.scale = Vector3(s, s, s)
	_visual.rotation.y = deg_to_rad(rng.randf_range(-180.0, 180.0))


## herb는 nav/물리 footprint가 없으므로 exit 시 nav rebake를 요청하지 않는다.
## claim 정리는 base(ResourceNode3D._exit_tree)와 동일하게 수행한다.
func _exit_tree() -> void:
	_claimed_by = null
