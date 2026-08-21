extends StaticBody2D
class_name Gate

## TASK-013-3 Gate Placement. 성문 1개는 Wall보다 넓은 footprint를 가진다.
## prototype 기준 3 logical tiles(48px): N/S Gate = 도로를 가로지르는 수평(48x16),
## E/W Gate = 도로를 가로지르는 수직(16x48) orientation.
## static collision(layer 3) + nav obstacle(parse_source_geometry_data)로
## collision/navigation 양쪽에 실제 반영된다.
## OPEN/CLOSED 상태 전환은 TASK-013-4에서 추가한다.

const HORIZONTAL_SIZE := Vector2(48, 16)
const VERTICAL_SIZE := Vector2(16, 48)

var direction := "north"
var orientation := "horizontal"


func _ready() -> void:
	add_to_group("gates")
	_apply_footprint()


## 배치 시 방향에 맞는 orientation/footprint를 적용한다.
func setup(dir: String) -> void:
	direction = dir
	orientation = "horizontal" if (dir == "north" or dir == "south") else "vertical"
	_apply_footprint()


func get_direction() -> String:
	return direction


func get_orientation() -> String:
	return orientation


func get_footprint_size() -> Vector2:
	return HORIZONTAL_SIZE if orientation == "horizontal" else VERTICAL_SIZE


func _apply_footprint() -> void:
	var size := get_footprint_size()
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		# 씬의 RectangleShape2D sub-resource는 인스턴스끼리 공유되므로,
		# 방향별 footprint를 인스턴스마다 독립 적용하려면 별도 shape를 생성한다.
		var shape := RectangleShape2D.new()
		shape.size = size
		col.shape = shape
	var vis := get_node_or_null("Visual") as Polygon2D
	if vis != null:
		vis.polygon = PackedVector2Array([
			Vector2.ZERO,
			Vector2(size.x, 0.0),
			size,
			Vector2(0.0, size.y),
		])