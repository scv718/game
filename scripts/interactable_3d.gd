extends Area3D
class_name Interactable3D

## TASK-3D-001-4 3D Selection / Interaction 공통 계약 base.
## 기존 interactable.gd(Area2D)의 최소 계약(prompt / can_interact / interact)을
## dimension-neutral 시그니처 그대로 Area3D로 이전한 신규 파일이다.
## 기존 2D interactable.gd와 4개 서브클래스는 LOCK 12에 따라 reference로 유지되며
## re-base는 각 도메인(RES/BLD) 전환 태스크가 자기 파일만 수행한다.
##
## - 이 노드는 선택/상호작용 표현 계약만 제공하며 game data owner를 강제하지 않는다.
##   실제 데이터/기능은 각 도메인 노드가 소유하고 interactable은 위임만 한다
##   (기존 GateInteractable이 Gate parent를 참조하는 구성과 동일).
## - collision layer는 CollisionLayers3D.LAYER_INTERACTABLE(value 256) 단일 소스,
##   collision_mask = 0 (물리 블록 아님, 선택 probe 전용).
## - Resource 계열(나무/채석장 자원 블록 등)은 기존 정책대로 Worker 전용을 유지하기 위해
##   INTERACTABLE layer에 올리지 않거나 is_selectable()을 false로 재정의한다
##   (마우스 직접 채집 차단 - world_selection.gd allow-list 정책의 대체 hook).
## - 단일 대상 선택만 지원한다. Box/Drag selection, RTS formation framework,
##   범용 ECS는 도입하지 않는다(TASK-3D-001-4 금지 항목).

@export var prompt: String = "상호작용"


func can_interact() -> bool:
	return true


## 마우스 선택 허용 여부. 기존 world_selection.gd가 타입 allow-list로 강제하던
## "선택 가능 카테고리" 판정을 대상 측 hook으로 이전한 것이다.
func is_selectable() -> bool:
	return true


func interact(_interactor: Node) -> Variant:
	return null
