extends Building3D
class_name Lumberyard3D

## TASK-3D-BLD-001-2 Lumberyard 3D. 기존 lumberyard.gd(Workplace = StaticBody2D)의
## 배치/식별 계약을 3D로 이전한 신규 파일이다. 기존 2D lumberyard.gd / lumberyard.tscn은
## LOCK 12에 따라 유지되며, 이 파일이 대신하는 것은 3D Runtime뿐이다.
##
## - gameplay footprint는 CollisionShape3D(Box XZ 4x4 unit = 논리 32x32px, 기존
##   BUILDING_SIZE 불변)가 단일 소스다. Visual slot placeholder mesh 크기와는 분리되어
##   있으며 실물 visual은 VIS 도메인이 slot의 mesh만 교체한다.
## - worker slot/assign/spawn 규약은 WRK 도메인(TASK-3D-WRK-001) 소유다. 여기서는
##   배치/선택 계약과 work_radius 데이터, 기존 prompt 포맷만 제공한다.
## - SpawnPoint/DepositPoint Marker3D는 기존 lumberyard.tscn logical px 위치를
##   WorldCoords3D 변환으로 보존한 것이다(WRK wiring 소비 대상).
## - group은 2D("lumberyards")와 분리된 "lumberyards_3d"를 사용한다.

@export var work_radius_px: float = 192.0
@export var max_workers: int = 2

@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh
@onready var _roof_mesh: MeshInstance3D = $Visual/RoofMesh

const PLACEHOLDER_BODY_COLOR := Color(0.62, 0.45, 0.28)


func _ready() -> void:
	super._ready()
	add_to_group("lumberyards_3d")
	_apply_placeholder()


func get_worker_label() -> String:
	return "Worker"


## 기존 Workplace.get_interact_prompt 포맷 유지. slot count 동적화(assign/unassign 반영)는
## WRK 도메인 wiring 대상이라 현재는 배치 직후 값(0 충원)을 반환한다.
func get_interact_prompt() -> String:
	return "Workers: %d/%d - Assign %s" % [0, max_workers, get_worker_label()]


## 기존 _ready의 Sprite2D visual 대신 placeholder 색 적용만 수행한다.
func _apply_placeholder() -> void:
	_body_mesh.material_override = _placeholder_material(PLACEHOLDER_BODY_COLOR)
	_roof_mesh.material_override = _placeholder_material(
		PLACEHOLDER_BODY_COLOR.darkened(0.35))


func _placeholder_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat
