extends StaticBody3D
class_name Building3D

## TASK-3D-BLD-001-1 Building 3D base.
## 기존 building.gd(StaticBody2D, "buildings" group)의 최소 계약을 3D로 이전한 신규 파일이다.
## 기존 2D building.gd / core_building.gd / workplace.gd 계열은 LOCK 12에 따라 reference로
## 유지되며, 이 파일들이 대신하는 것은 3D Runtime뿐이다.
##
## - game logic은 이 노드 계층이 소유하고, mesh/visual은 전부 자식 Visual(Node3D) slot
##   하위에 둔다(visual과 game logic 분리). Quaternius 건물 visual(TASK-3D-VIS)은
##   이 slot 하위 mesh만 교체하며 logic/충돌/선택 계약은 무수정이다.
## - 본체 collision은 BUILDING layer(CollisionLayers3D 단일 소스) + mask 0 수동 블로커다.
##   MASK_ACTOR_SOLID에 참여해 Actor를 막고, nav bake(PARSED_GEOMETRY_STATIC_COLLIDERS)에
##   정적 world collision으로 파싱된다.
## - 선택/상호작용은 자식 Interactable3D(Area3D, INTERACTABLE layer)가 Foundation 계약으로
##   수행한다. 본체는 selection probe(MASK_SELECTION)에 조회되지 않는다(기존 2D 관례 동일).
## - group은 2D("buildings")와 분리된 "buildings_3d"를 사용한다.


## VIS 도메인이 mesh를 교체하는 유일한 slot. 하위는 순수 시각 노드만 허용된다
## (collision shape / physics 노드 배치 금지 - visual/logic 분리 LOCK).
@onready var visual_slot: Node3D = $Visual


func _ready() -> void:
	add_to_group("buildings_3d")


## logical 2D 좌표를 이 건물의 지면 배치 좌표로 변환하는 편의 함수.
## 기존 world.tscn 배치 좌표를 그대로 3D runtime 경로에서 재사용하기 위함이다.
func set_logical_position(logical: Vector2) -> void:
	position = WorldCoords3D.to_world_xz(logical)
