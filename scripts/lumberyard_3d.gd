extends Workplace3D
class_name Lumberyard3D

## TASK-3D-BLD-001-2 Lumberyard 3D. 기존 lumberyard.gd(Workplace = StaticBody2D)의
## 배치/식별 계약을 3D로 이전한 신규 파일이다. 기존 2D lumberyard.gd / lumberyard.tscn은
## LOCK 12에 따라 유지되며, 이 파일이 대신하는 것은 3D Runtime뿐이다.
##
## - gameplay footprint는 CollisionShape3D(Box XZ 4x4 unit = 논리 32x32px, 기존
##   BUILDING_SIZE 불변)가 단일 소스다. Visual slot placeholder mesh 크기와는 분리되어
##   있으며 실물 visual은 VIS 도메인이 slot의 mesh만 교체한다.
## - worker slot/assign/spawn 규약은 Workplace3D(TASK-3D-INT-001-2에서 2D workplace.gd의
##   3D판으로 확정) 상속으로 충족한다. max_workers = 2(기존 벌목장 slot 불변).
##   spawn_worker_actor는 2D lumberyard.gd와 동일 순서로 SpawnPoint에 Lumberjack Actor를
##   생성한다(res://scenes/lumberjack_3d.tscn).
## - group은 3D 전용 "lumberyards_3d"와 여관 UI가 조회하는 기존 lookup명 "lumberyards"
##   양쪽에 등록한다(BuildingPlacement3D의 dual-group 등록 방식과 동일. 3D Main World에는
##   2D workplace이 없으므로 어느 runtime에서도 오염이 없다).
## - SpawnPoint/DepositPoint Marker3D는 기존 lumberyard.tscn logical px 위치를
##   WorldCoords3D 변환으로 보존한 것이다.
## - work_radius(px) 프로퍼티명은 WRK 도메인 duck-typed 계약(lumberjack_3d가
##   workplace.get("work_radius") 조회)을 따른다.

@export var work_radius: float = 192.0

@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh
@onready var _roof_mesh: MeshInstance3D = $Visual/RoofMesh

const PLACEHOLDER_BODY_COLOR := Color(0.62, 0.45, 0.28)


func _init() -> void:
	max_workers = 2


func _ready() -> void:
	super._ready()
	add_to_group("lumberyards")
	add_to_group("lumberyards_3d")
	_apply_placeholder()


func get_worker_group() -> String:
	return "lumberjacks_3d"


## TASK-037-1 upgrade contract identity(BuildingUpgrade3D 단일 소스).
func get_upgrade_identity() -> String:
	return "lumberyard"


func get_worker_label() -> String:
	return "Worker"


## TASK-011-5: Lumberjack Actor를 이 시설의 SpawnPoint에 생성하고 기존 FSM을 시작한다.
func spawn_worker_actor(worker: WorkerData) -> Node:
	var scene: PackedScene = load("res://scenes/lumberjack_3d.tscn")
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
