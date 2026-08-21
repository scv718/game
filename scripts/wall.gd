extends StaticBody2D
class_name Wall

## TASK-013-1 자유 성벽 1 segment = 1 logical tile (16x16px) footprint.
## static collision + nav obstacle(parse_source_geometry_data)를 통해
## collision/navigation 양쪽에 실제 반영된다.
## Tiny Swords sprite scale/offset은 logical footprint와 독립이며,
## TASK-013-2에서 인접 연결 비주얼을 추가한다.

const FOOTPRINT := 16

## TASK-013-2: 연결 비주얼. 인접 N/E/S/W Wall이 있으면 각 방향으로
## 간격 중간(8px)까지 시각 폴리곤을 늘려 직선/코너/끝이 이어져 보이게 한다.
## collision footprint(16x16)는 절대 변경하지 않는다(시각만 표현).


func _ready() -> void:
	add_to_group("walls")
	refresh_visual()


## 인접 Wall 여부: grid 상에서 정확히 FOOTPRINT만큼 떨어진 위치에 Wall이 있는지.
func _has_neighbor(dir: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("walls"):
		if node == self or not is_instance_valid(node):
			continue
		var other := node as Node2D
		if other == null:
			continue
		var diff: Vector2 = other.position - position
		if (diff - dir * FOOTPRINT).length_squared() < 1.0:
			return true
	return false


## 시각 폴리곤을 인접 상태에 맞게 갱신. collision shape은 건드리지 않는다.
func refresh_visual() -> void:
	if not is_inside_tree():
		return
	var vis: Polygon2D = get_node_or_null("Visual") as Polygon2D
	if vis == null:
		return
	vis.polygon = _build_visual_polygon()


## 16x16 core + 연결 방향으로 8px(간격 중간)까지 확장한 폴리곤을 생성.
func _build_visual_polygon() -> PackedVector2Array:
	var rects: Array[Rect2] = [Rect2(0, 0, FOOTPRINT, FOOTPRINT)]
	if _has_neighbor(Vector2(0, -1)):
		rects.append(Rect2(0, -FOOTPRINT / 2, FOOTPRINT, FOOTPRINT / 2))
	if _has_neighbor(Vector2(0, 1)):
		rects.append(Rect2(0, FOOTPRINT, FOOTPRINT, FOOTPRINT / 2))
	if _has_neighbor(Vector2(-1, 0)):
		rects.append(Rect2(-FOOTPRINT / 2, 0, FOOTPRINT / 2, FOOTPRINT))
	if _has_neighbor(Vector2(1, 0)):
		rects.append(Rect2(FOOTPRINT, 0, FOOTPRINT / 2, FOOTPRINT))
	var merged := _rect_polygon(rects[0])
	for i in range(1, rects.size()):
		var res := Geometry2D.merge_polygons(merged, _rect_polygon(rects[i]))
		if res.size() > 0:
			merged = res[0]
	return merged


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	])
