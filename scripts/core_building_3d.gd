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


func _ready() -> void:
	super._ready()
	add_to_group("core_buildings_3d")
	_apply_config()


## 기존 _apply_config(Sprite2D texture/scale/offset)의 3D판. Visual slot 하위
## placeholder 표현만 건드리며 logic/collision에는 손대지 않는다.
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


func get_core_type() -> String:
	return core_type


func get_level() -> int:
	return 1


func get_building_label() -> String:
	return String(LABELS.get(core_type, LABELS["tavern"]))


func get_interact_prompt() -> String:
	return "%s (Lv.%d)" % [get_building_label(), get_level()]
