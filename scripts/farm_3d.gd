extends Workplace3D
class_name Farm3D

## TASK-019-1 Farm Building / Plot 3D. 기존 lumberyard_3d.gd의 Workplace 계약을
## 재사용한 신규 3D Farm workplace다. 기존 2D farm 파일은 존재하지 않으며(LOCK 12에
## 따라 임의로 2D farm을 만들지 않는다) 이 3D 파일이 최소 Farm workplace 1종을 담당한다.
##
## - gameplay footprint는 CollisionShape3D(Box XZ 4x4 unit = 논리 32x32px, 기존
##   BUILDING_SIZE 불변)가 단일 소스다. Visual slot placeholder mesh 크기와는 분리되어
##   있으며 실물 visual은 VIS 도메인이 slot의 mesh만 교체한다.
## - worker slot/assign/spawn 규약은 Workplace3D(TASK-3D-INT-001-2 확정) 상속으로
##   충족한다. max_workers = 2(기존 생산시설 초기 Worker Slot 2 기준). Farmer Actor
##   spawn은 TASK-019-2에서 spawn_worker_actor로 연결한다.
## - crop area가 top-down에서 읽히도록 Visual 하위에 crop row placeholder mesh를
##   가진다(녹색 crop strip). 이것은 순수 시각이며 collision/nav와 무관하다.
## - group은 여관 UI가 조회하는 기존 lookup명 계열("farms")과 3D 전용("farms_3d")
##   양쪽에 등록한다(Lumberyard3D dual-group 등록 방식과 동일).
## - work_radius(px) 프로퍼티명은 WRK 도메인 duck-typed 계약을 따른다.

@export var work_radius: float = 192.0

@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh
@onready var _roof_mesh: MeshInstance3D = $Visual/RoofMesh

const PLACEHOLDER_BODY_COLOR := Color(0.62, 0.68, 0.4)

## TASK-019-3: 농장이 기본으로 심는 crop 정의. data-driven(CropData)이며 첫 vertical
## slice는 1종(WHEAT)만 등록한다.
var crop_definition: CropData = null

## TASK-019-3: 심어진 crop plot 리스트(배치 순서 보존).
var _crops: Array[Node] = []

## TASK-019-3: crop plot 배치용 로컬 좌표(시각 CropRows와 정렬). DESIGN_TUNING.
const CROP_PLOT_POSITIONS := [
	Vector3(-1.6, 0.0, -1.2),
	Vector3(0.0, 0.0, -1.2),
	Vector3(1.6, 0.0, -1.2),
]


func _init() -> void:
	max_workers = 2


func _ready() -> void:
	super._ready()
	add_to_group("farms")
	add_to_group("farms_3d")
	_apply_placeholder()
	if crop_definition == null:
		crop_definition = CropData.default_crop()
	_plant_crops()


## TASK-019-3: 정의된 crop 종류로 이 농장의 plot에 CropNode3D를 심는다.
## 결정적(고정 위치)이며 생성 순서가 항상 같다. crop_definition이 변경되어도
## 재배치 없이 _ready에서 1회 심는다.
func _plant_crops() -> void:
	var crop_scene: PackedScene = load("res://scenes/crop_node_3d.tscn")
	var idx := 0
	for local_pos in CROP_PLOT_POSITIONS:
		var crop := crop_scene.instantiate() as CropNode3D
		crop.name = "Crop%d" % idx
		crop.setup(crop_definition)
		add_child(crop)
		crop.position = local_pos
		_crops.append(crop)
		idx += 1


## TASK-019-3: 이 농장이 관리하는 crop plot 목록.
func get_crops() -> Array[Node]:
	return _crops.duplicate()


## TASK-019-3: READY 상태인 crop 중 주어진 farmer가 claim 가능한 가장 가까운 1개.
func find_harvestable_crop(farmer: Node, max_dist_units: float = INF) -> CropNode3D:
	var origin: Vector3 = global_position
	var best: CropNode3D = null
	var best_d := INF
	for c in _crops:
		var crop := c as CropNode3D
		if crop == null or not is_instance_valid(crop):
			continue
		if not crop.can_interact():
			continue
		if crop.is_claimed_by_other(farmer):
			continue
		var d := WorldCoords3D.distance_xz(origin, crop.global_position)
		if d > max_dist_units:
			continue
		if d < best_d:
			best = crop
			best_d = d
	return best


func get_worker_group() -> String:
	return "farmers_3d"


func get_worker_label() -> String:
	return "Farmer"


## TASK-019-2: 두 Farmer가 안정적으로 작업할 WorkPoint를 배치 index 기반으로
## 돌려준다(quarry_3d.gd의 get_work_point_for 계약과 동일). Marker가 없으면
## "WorkPoint" 자식(없으면 null)을 돌려준다.
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


## TASK-019-2: Farmer Actor를 이 시설의 SpawnPoint에 생성하고 기존 FSM을 시작한다.
func spawn_worker_actor(worker: WorkerData) -> Node:
	var scene: PackedScene = load("res://scenes/farmer_3d.tscn")
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
	for child in $Visual/CropRows.get_children():
		if child is MeshInstance3D:
			child.material_override = _placeholder_material(
				Color(0.35, 0.6, 0.28, 0.9))


func _placeholder_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat
