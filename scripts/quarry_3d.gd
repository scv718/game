extends Workplace3D
class_name Quarry3D

## TASK-3D-BLD-001-2 Quarry 3D. 기존 quarry.gd(Workplace = StaticBody2D)의
## 배치/deposit binding 계약을 3D로 이전한 신규 파일이다. 기존 2D quarry.gd /
## quarry.tscn은 LOCK 12에 따라 유지되며, 이 파일이 대신하는 것은 3D Runtime뿐이다.
##
## - gameplay footprint는 CollisionShape3D(Box XZ 4x4 unit = 논리 32x32px 불변)가
##   단일 소스고 Visual slot placeholder mesh와 분리되어 있다.
## - deposit binding(occupy/bind) 규약은 stone_deposit_3d.gd 계약을 그대로 소비하며
##   BuildingPlacement3D가 배치 시 연결한다.
## - worker slot/assign/spawn 규약은 Workplace3D(TASK-3D-INT-001-2에서 2D workplace.gd의
##   3D판으로 확정) 상속으로 충족한다. max_workers = 2(기존 채석장 slot 불변).
##   spawn_worker_actor는 2D quarry.gd와 동일 순서로 SpawnPoint에 Miner Actor를
##   생성한다(res://scenes/miner_3d.tscn).
## - TASK-011-6 WorkPoint 분배(get_work_point_for)도 기존 quarry.gd와 동일 규약으로
##   제공한다. 두 Miner가 완전히 같은 위치에 겹쳐 영구 충돌/Navigation stall이
##   나지 않게 배치 index 기반으로 돌려준다(miner_3d가 소비한다).
## - MiningPoint/WorkPoint/WorkPoint2/SpawnPoint Marker3D는 기존 quarry.tscn
##   logical px 위치를 WorldCoords3D 변환으로 보존한 것이다.
## - group은 3D 전용 "quarries_3d"와 여관 UI가 조회하는 기존 lookup명 "quarries"
##   양쪽에 등록한다(Lumberyard3D dual-group 등록과 동일).

@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh
@onready var _roof_mesh: MeshInstance3D = $Visual/RoofMesh

const PLACEHOLDER_BODY_COLOR := Color(0.45, 0.52, 0.6)

var deposit: Node = null


func _init() -> void:
	max_workers = 2


func _ready() -> void:
	super._ready()
	add_to_group("quarries")
	add_to_group("quarries_3d")
	_apply_placeholder()


func bind_deposit(deposit_node: Node) -> void:
	deposit = deposit_node


func get_deposit() -> Node:
	return deposit


func get_worker_group() -> String:
	return "miners_3d"


func get_worker_label() -> String:
	return "Miner"


## TASK-011-6: 두 Miner가 안정적으로 작업할 WorkPoint를 배치 index 기반으로 돌려준다.
## 반환형이 Node2D에서 Node3D로 바뀐 것 외에는 기존 quarry.gd 계약과 동일하다.
func get_work_point_for(actor: Node) -> Node3D:
	var points: Array[Node] = []
	for child in get_children():
		if child is Marker3D and (child.name == "WorkPoint" or child.name == "WorkPoint2"):
			points.append(child)
	if points.is_empty():
		return get_node_or_null("WorkPoint") as Node3D
	var idx := 0
	for i in _assigned_workers.size():
		if _assigned_workers[i] == actor:
			idx = i
			break
	return points[idx % points.size()]


## TASK-011-5: Miner Actor를 이 시설의 SpawnPoint에 생성하고 기존 FSM을 시작한다.
func spawn_worker_actor(worker: WorkerData) -> Node:
	var scene: PackedScene = load("res://scenes/miner_3d.tscn")
	var actor := scene.instantiate()
	var parent := get_parent()
	if parent == null:
		return null
	var spawn := get_node_or_null("SpawnPoint") as Node3D
	actor.position = spawn.global_position if spawn != null else global_position
	parent.add_child(actor)
	actor.worker_data = worker
	assign_worker(actor)
	return actor


func _apply_placeholder() -> void:
	_body_mesh.material_override = _placeholder_material(PLACEHOLDER_BODY_COLOR)
	_roof_mesh.material_override = _placeholder_material(
		PLACEHOLDER_BODY_COLOR.darkened(0.35))


func _placeholder_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat
