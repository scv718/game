extends StaticBody2D
class_name Wall

## TASK-013-1 자유 성벽 1 segment = 1 logical tile (16x16px) footprint.
## static collision + nav obstacle(parse_source_geometry_data)를 통해
## collision/navigation 양쪽에 실제 반영된다.
## Tiny Swords sprite scale/offset은 logical footprint와 독립이며,
## TASK-013-2에서 인접 연결 비주얼을 추가한다.

const FOOTPRINT := 16


func _ready() -> void:
	add_to_group("walls")
