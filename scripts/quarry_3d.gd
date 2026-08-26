extends Building3D
class_name Quarry3D

## TASK-3D-BLD-001-2 Quarry 3D. 기존 quarry.gd(Workplace = StaticBody2D)의
## 배치/deposit binding 계약을 3D로 이전한 신규 파일이다. 기존 2D quarry.gd /
## quarry.tscn은 LOCK 12에 따라 유지된다.
##
## - gameplay footprint는 CollisionShape3D(Box XZ 4x4 unit = 논리 32x32px 불변)가
##   단일 소스고 Visual slot placeholder mesh와 분리되어 있다.
## - deposit binding(occupy/bind) 규약은 stone_deposit_3d.gd 계약을 그대로 소비하며
##   BuildingPlacement3D가 배치 시 연결한다. work point 소비는 WRK 도메인 소유다.
## - MiningPoint/WorkPoint/WorkPoint2/SpawnPoint Marker3D는 기존 quarry.tscn
##   logical px 위치를 WorldCoords3D 변환으로 보존한 것이다(WRK wiring 대상).
## - group은 2D("quarries")와 분리된 "quarries_3d"를 사용한다.

@export var max_workers: int = 2

var deposit: Node = null

@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh
@onready var _roof_mesh: MeshInstance3D = $Visual/RoofMesh

const PLACEHOLDER_BODY_COLOR := Color(0.45, 0.52, 0.6)


func _ready() -> void:
	super._ready()
	add_to_group("quarries_3d")
	_apply_placeholder()


func bind_deposit(deposit_node: Node) -> void:
	deposit = deposit_node


func get_deposit() -> Node:
	return deposit


func get_worker_label() -> String:
	return "Miner"


## 기존 Workplace.get_interact_prompt 포맷 유지. slot count 동적화는
## WRK 도메인 wiring 대상이라 현재는 배치 직후 값(0 충원)을 반환한다.
func get_interact_prompt() -> String:
	return "Workers: %d/%d - Assign %s" % [0, max_workers, get_worker_label()]


func _apply_placeholder() -> void:
	_body_mesh.material_override = _placeholder_material(PLACEHOLDER_BODY_COLOR)
	_roof_mesh.material_override = _placeholder_material(
		PLACEHOLDER_BODY_COLOR.darkened(0.35))


func _placeholder_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat
