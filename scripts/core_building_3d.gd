extends Building3D
class_name CoreBuilding3D

## TASK-3D-BLD-001-1 중앙 핵심 마을 건물 3D.
## 기존 core_building.gd(CoreBuilding)의 identity/data 계약을 3D로 이전한 신규 파일이다.
## 기존 2D core_building.gd / core_building.tscn은 LOCK 12에 따라 유지된다.
##
## - 거점/주점/여관/식료품점/장비점 5종은 core_type 하나로 구분되며 scene은 1개를
##   파라미터로 재사용한다(기존 core_building.tscn 구성 동일).
## - core_type/label/level/prompt 형식은 2D CoreBuilding과 동일 값을 유지한다
##   (기존 building identity/data 보존). BuildingPlacement 대상이 아니며
##   업그레이드 효과/비용 시스템은 여전히 없고 level은 1로 유지한다.
## - 2D Sprite2D AtlasTexture 대신 placeholder는 Visual slot 하위 primitive mesh +
##   per-type 식별 색 + Label3D nameplate로 식별한다. Quaternius 실물 visual은
##   VIS 태스크가 이 slot의 mesh만 교체하는 구조다(placeholder는 무수정 교체 대상).
## - 상호작용 연결(주점 고용 UI / 여관 Roster UI)은 core_building_interactable_3d.gd가
##   2D core_building_interactable.gd와 동일 그룹 계약으로 수행한다.
## - group은 2D("core_buildings")와 분리된 "core_buildings_3d"를 사용한다.

@export var core_type: String = "tavern"

## 기존 CoreBuilding.CONFIGS의 label 데이터와 동일 값(identity 보존).
const LABELS := {
	"keep": "거점",
	"tavern": "주점",
	"inn": "여관",
	"grocery": "식료품점",
	"equipment": "장비점",
}

## placeholder 건물별 식별 색. 실물 visual 투입 시 VIS가 slot과 함께 교체한다.
const PLACEHOLDER_COLORS := {
	"keep": Color(0.55, 0.58, 0.66),
	"tavern": Color(0.74, 0.52, 0.3),
	"inn": Color(0.5, 0.66, 0.46),
	"grocery": Color(0.82, 0.7, 0.36),
	"equipment": Color(0.62, 0.46, 0.64),
}

@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh
@onready var _roof_mesh: MeshInstance3D = $Visual/RoofMesh
@onready var _name_label: Label3D = $Visual/NameLabel
@onready var _visual: Node3D = $Visual

## TASK-022-3: 여관 레벨별 prop(장식) 변형 메쉬. 실물 visual 투입 시 VIS가
## placeholder slot을교체하며, 이 변형은 그 위에 얹히는 prop variation일 뿐이다.
const PROP_COLOR := Color(0.42, 0.34, 0.26)
const FLAG_COLOR := Color(0.9, 0.82, 0.5)

## Quaternius building part mapping per core_type.
const BUILDING_PARTS := {
	"keep": {
		"wall": "bld/wall_brick_straight",
		"roof": "bld/roof_roundtiles_6x6",
		"scale": 1.0,
	},
	"tavern": {
		"wall": "bld/wall_plaster_woodgrid",
		"roof": "bld/roof_roundtiles_6x6",
		"scale": 1.0,
	},
	"inn": {
		"wall": "bld/wall_brick_window_wide",
		"roof": "bld/roof_roundtiles_6x6",
		"scale": 1.0,
	},
	"grocery": {
		"wall": "bld/wall_plaster_straight",
		"roof": "bld/roof_wooden_2x1",
		"scale": 0.9,
	},
	"equipment": {
		"wall": "bld/wall_brick_straight",
		"roof": "bld/roof_wooden_2x1",
		"scale": 0.9,
	},
}

var _quaternius_models: Array = []

## 업그레이드 레벨 변화를 visual에 반영하기 위한 레벨 시그널 연결.
var _props_root: Node3D = null


func _ready() -> void:
	super._ready()
	add_to_group("core_buildings_3d")
	if core_type == "inn" and InnCapacity != null:
		InnCapacity.level_changed.connect(_on_inn_level_changed)
	_apply_config()


## 기존 _apply_config(Sprite2D texture/scale/offset)의 3D판. Visual slot 하위
## placeholder 표현만 건드리며logic/collision에는 손대지 않는다.
func _apply_config() -> void:
	var color: Color = PLACEHOLDER_COLORS.get(core_type, PLACEHOLDER_COLORS["tavern"])
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = color
	body_material.roughness = 1.0
	_body_mesh.material_override = body_material
	var roof_material := StandardMaterial3D.new()
	roof_material.albedo_color = color.darkened(0.35)
	roof_material.roughness = 1.0
	_roof_mesh.material_override = roof_material
	_name_label.text = get_building_label()
	_replace_with_quaternius()
	if core_type == "inn" and InnCapacity != null:
		_update_inn_visual(InnCapacity.get_level())


## Replace placeholder BoxMesh with Quaternius building parts.
func _replace_with_quaternius() -> void:
	# Clear previous models
	for m in _quaternius_models:
		if is_instance_valid(m):
			m.queue_free()
	_quaternius_models.clear()
	var parts: Dictionary = BUILDING_PARTS.get(core_type, {})
	if parts.is_empty():
		return
	# Hide placeholder meshes
	_body_mesh.visible = false
	_roof_mesh.visible = false
	# Wall model (main body)
	var wall_key: String = parts.get("wall", "")
	if not wall_key.is_empty():
		var wall_model := VisualAssetCatalog3D.instantiate_model(wall_key)
		if wall_model != null:
			var s: float = parts.get("scale", 1.0)
			wall_model.scale = Vector3(s, s, s)
			wall_model.position = Vector3(0.0, 1.5, 0.0)
			_visual.add_child(wall_model)
			_quaternius_models.append(wall_model)
	# Roof model
	var roof_key: String = parts.get("roof", "")
	if not roof_key.is_empty():
		var roof_model := VisualAssetCatalog3D.instantiate_model(roof_key)
		if roof_model != null:
			var s: float = parts.get("scale", 1.0)
			roof_model.scale = Vector3(s, s, s)
			roof_model.position = Vector3(0.0, 3.9, 0.0)
			_visual.add_child(roof_model)
			_quaternius_models.append(roof_model)


func get_core_type() -> String:
	return core_type


## TASK-022-2: 여관은 InnCapacity(데이터 기반 업그레이드 레벨)를 레벨 소스로 사용한다.
## 그 외 핵심 건물은 여전히 업그레이드 미구현이므로 1을 유지한다(2D와 동일 계약).
func get_level() -> int:
	if core_type == "inn":
		return InnCapacity.get_level()
	return 1


func get_building_label() -> String:
	return String(LABELS.get(core_type, LABELS["tavern"]))


func get_interact_prompt() -> String:
	return "%s (Lv.%d)" % [get_building_label(), get_level()]


## TASK-022-3: 여관 레벨에 따른 placeholder prop/visual variation.
## 기존 Body/Roof placeholder는 유지하고, 레벨이 오를수록 장식 prop을 추가해
## "업그레이드가 시각적으로 드러난다"를 표현한다. logic/collision은 건드리지 않는다.
## 레벨 1: 변화 없음(기본). 레벨 2: 출입구 옆 확장 박스 + 깃발. 레벨 3: 추가 확장 + 지붕 마감.
func _update_inn_visual(level: int) -> void:
	_clear_props()
	if level >= 2:
		_add_prop_box(Vector3(2.2, 0.9, 1.0), Vector3(1.0, 1.0, 1.0), PROP_COLOR)
		_add_prop_box(Vector3(-2.2, 1.2, -1.2), Vector3(0.8, 0.8, 0.8), PROP_COLOR.darkened(0.2))
		_add_flag(Vector3(0.0, 4.6, 0.0))
	if level >= 3:
		_add_prop_box(Vector3(0.0, 4.5, 0.0), Vector3(4.6, 0.4, 4.6),
			PLACEHOLDER_COLORS["inn"].darkened(0.45))
		_add_prop_box(Vector3(-2.6, 0.9, 0.0), Vector3(0.6, 1.4, 0.6), PROP_COLOR.darkened(0.3))


## prop 루트를 한 번만 생성하고 재사용한다. queue_free로 루트를 갈아엎으면
## 같은 이름("InnProps")의 freed 노드가 같은 프레임에 남아 get_node가 오래된
## 빈 노드를 반환하는 문제가 있어, 루트는 유지하고 자식 prop만 비운다.
func _ensure_props_root() -> Node3D:
	if _props_root == null or not is_instance_valid(_props_root):
		_props_root = Node3D.new()
		_props_root.name = "InnProps"
		_visual.add_child(_props_root)
	return _props_root


func _clear_props() -> void:
	var root := _ensure_props_root()
	for child in root.get_children():
		child.free()


func _add_prop_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "PropBox"
	mi.mesh = BoxMesh.new()
	(mi.mesh as BoxMesh).size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos
	_ensure_props_root().add_child(mi)


func _add_flag(pos: Vector3) -> void:
	var pole := MeshInstance3D.new()
	pole.name = "FlagPole"
	pole.mesh = CylinderMesh.new()
	(pole.mesh as CylinderMesh).top_radius = 0.04
	(pole.mesh as CylinderMesh).bottom_radius = 0.04
	(pole.mesh as CylinderMesh).height = 1.6
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.4, 0.36, 0.3)
	pole.material_override = pole_mat
	pole.position = pos
	_ensure_props_root().add_child(pole)
	var banner := MeshInstance3D.new()
	banner.name = "FlagBanner"
	banner.mesh = BoxMesh.new()
	(banner.mesh as BoxMesh).size = Vector3(0.8, 0.45, 0.05)
	var banner_mat := StandardMaterial3D.new()
	banner_mat.albedo_color = FLAG_COLOR
	banner.material_override = banner_mat
	banner.position = pos + Vector3(0.4, 0.4, 0.0)
	_ensure_props_root().add_child(banner)


func _on_inn_level_changed(level: int, _worker_capacity: int, _mercenary_capacity: int) -> void:
	if core_type != "inn":
		return
	_update_inn_visual(level)
	_name_label.text = get_building_label()
