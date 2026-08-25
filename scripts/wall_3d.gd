extends StaticBody3D
class_name Wall3D

## TASK-3D-BLD-001-2 Wall segment 3D 최소 표현. 기존 wall.gd(StaticBody2D)의
## 배치/철거 대상 계약을 3D로 이전한 신규 파일이다. 기존 2D wall.gd / wall.tscn은
## LOCK 12에 따라 유지된다.
##
## - gameplay footprint는 CollisionShape3D(Box XZ 2x2 unit = 논리 16x16px, 기존
##   WALL_FOOTPRINT 불변)가 단일 소스고 Visual slot mesh 크기와 분리되어 있다.
## - collision layer는 WALL(CollisionLayers3D 단일 소스), mask 0 수동 블로커다.
##   MASK_ACTOR_SOLID/MASK_PLACEMENT_BLOCKERS/nav bake에 자동 참여한다.
## - group은 2D("walls")와 분리된 "walls_3d"를 사용한다.
##
## TASK-3D-BLD-001-3: 연결 비주얼. 기존 wall.gd(TASK-013-2)의 인접 merge 규약을
## 3D로 이전한다. 인접 N/E/S/W Wall3D가 있으면 각 방향으로 간격 중간(cell 절반,
## 1 unit)까지 link box를 늘려 직선/코너/끝이 이어져 보이게 한다.
## collision footprint(2x2 unit)는 절대 변경하지 않는다(시각만 표현).
## placement 배치/철거 후 호출되는 refresh_visual()은 멱등(idempotent)하며,
## 실제 mesh 교체는 VIS 도메인 슬롯($Visual 하위)만 손대는 구조를 유지한다.

const FOOTPRINT_SIZE_PX := Vector2(16, 16)

## 기존 wall.gd의 인접 판정 epsilon((diff - dir * FOOTPRINT).length_squared() < 1px^2)을
## unit 공간으로 환산한 값이다.
const NEIGHBOR_EPSILON_SQ := WorldCoords3D.PX_TO_UNIT * WorldCoords3D.PX_TO_UNIT
const LINK_NAME_PREFIX := "Link"

const PLACEHOLDER_COLOR := Color(0.5, 0.5, 0.54)

@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh


func _ready() -> void:
	add_to_group("walls_3d")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLACEHOLDER_COLOR
	mat.roughness = 1.0
	_body_mesh.material_override = mat
	refresh_visual()


func get_footprint_size() -> Vector2:
	return FOOTPRINT_SIZE_PX


## 인접 Wall 여부: grid 상에서 정확히 cell 1칸(GRID_CELL_UNITS)만큼 떨어진 위치에
## Wall3D가 있는지. 기존 wall.gd _has_neighbor의 3D판이며 Y 성분은 무시한다.
func _has_neighbor(dir: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("walls_3d"):
		if node == self or not is_instance_valid(node):
			continue
		var other := node as Node3D
		if other == null:
			continue
		var diff: Vector3 = other.global_position - global_position
		diff.y = 0.0
		if (diff - dir * WorldCoords3D.GRID_CELL_UNITS).length_squared() \
				< NEIGHBOR_EPSILON_SQ:
			return true
	return false


## link box들을 인접 상태에 맞게 갱신. collision shape은 건드리지 않는다.
## 반복 호출해도 결과가 동일하다(멱등).
func refresh_visual() -> void:
	if not is_inside_tree():
		return
	for dir_name in WorldCoords3D.DIRECTION_XZ:
		_update_link(dir_name)


func _update_link(dir_name: String) -> void:
	var dir: Vector3 = WorldCoords3D.DIRECTION_XZ[dir_name]
	var link_name := LINK_NAME_PREFIX + dir_name.capitalize()
	var existing := get_node_or_null("Visual/" + link_name)
	var has_link := existing != null and not existing.is_queued_for_deletion()
	var wanted := _has_neighbor(dir)
	if wanted and not has_link:
		_create_link(link_name, dir)
	elif not wanted and has_link:
		existing.free()


## 간격 중간(인접 cell 절반 = GRID_CELL_UNITS * 0.5)까지 확장된 link box.
## 폭은 gameplay footprint와 동일하고 높이는 본체 visual mesh를 따른다.
func _create_link(link_name: String, dir: Vector3) -> void:
	var body_height := (_body_mesh.mesh as BoxMesh).size.y
	var foot_units := FOOTPRINT_SIZE_PX.x * WorldCoords3D.PX_TO_UNIT
	var ext_units := WorldCoords3D.GRID_CELL_UNITS * 0.5
	var mesh := BoxMesh.new()
	mesh.size = Vector3(
		absf(dir.x) * ext_units + absf(dir.z) * foot_units,
		body_height,
		absf(dir.x) * foot_units + absf(dir.z) * ext_units)
	var link := MeshInstance3D.new()
	link.name = link_name
	link.mesh = mesh
	link.position = Vector3(dir.x, 0.0, dir.z) * (foot_units + ext_units) * 0.5 \
		+ Vector3(0.0, body_height * 0.5, 0.0)
	link.material_override = _body_mesh.material_override
	get_node("Visual").add_child(link)
