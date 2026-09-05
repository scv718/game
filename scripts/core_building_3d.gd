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
## - 2D Sprite2D AtlasTexture 대신 Visual slot 하위의 Quaternius 모듈 조립으로
##   실제 건물 silhouette를 구성한다. collision/interaction은 기존 owner가 유지한다.
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

## fallback 식별 색. 실물 visual이 로드되지 않을 때만 사용한다.
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

const CUTESKULL_CITY := preload("res://assets/cuteskull-medieval-city/city16.fbx")
const CUTESKULL_BUILDINGS := {
	"keep": ["Church_2", "Castle_Tower_3", "Castle_Tower_1", "Castle_Tower_2"],
	"tavern": ["House_3_1"],
	"inn": ["House_7_1"],
	"grocery": ["House_4_1"],
	"equipment": ["House_5_1"],
}

## Quaternius building part mapping per core_type. 각 type은 wall/roof와 모듈 수를
## 달리해 generic house 복제를 피한다.
const BUILDING_PARTS := {
	"keep": {
		"wall": "bld/wall_brick_straight",
		"door": "bld/wall_brick_door_flat",
		"window": "bld/wall_brick_window_wide",
		"floor": "bld/floor_brick",
		"roof": "bld/roof_roundtiles_6x6",
		"cells": 3,
		"visual_scale": 0.72,
		"roof_scale": 0.82,
	},
	"tavern": {
		"wall": "bld/wall_plaster_woodgrid",
		"door": "bld/wall_plaster_door_flat",
		"window": "bld/wall_plaster_window_wide",
		"floor": "bld/floor_wood_light",
		"roof": "bld/roof_roundtiles_6x6",
		"cells": 2,
		"visual_scale": 0.78,
		"roof_scale": 0.65,
	},
	"inn": {
		"wall": "bld/wall_brick_window_wide",
		"door": "bld/wall_brick_door_flat",
		"window": "bld/wall_brick_window_wide",
		"floor": "bld/floor_brick",
		"roof": "bld/roof_roundtiles_6x6",
		"cells": 2,
		"visual_scale": 0.76,
		"roof_scale": 0.62,
	},
	"grocery": {
		"wall": "bld/wall_plaster_straight",
		"door": "bld/wall_plaster_door_flat",
		"window": "bld/wall_plaster_window_wide",
		"floor": "bld/floor_wood_light",
		"roof": "bld/overhang_roof_plaster",
		"cells": 2,
		"visual_scale": 0.7,
		"roof_scale": 0.76,
	},
	"equipment": {
		"wall": "bld/wall_brick_straight",
		"door": "bld/wall_brick_door_flat",
		"window": "bld/wall_brick_window_wide",
		"floor": "bld/floor_brick",
		"roof": "bld/roof_wooden_2x1",
		"cells": 2,
		"visual_scale": 0.72,
		"roof_scale": 0.68,
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


## Replace placeholder BoxMesh with a complete Quaternius modular building.
func _replace_with_quaternius() -> void:
	# Clear previous replacement root and hide primitive placeholders.
	for m in _quaternius_models:
		if is_instance_valid(m):
			m.free()
	_quaternius_models.clear()
	var parts: Dictionary = BUILDING_PARTS.get(core_type, {})
	if parts.is_empty():
		return
	_body_mesh.visible = false
	_roof_mesh.visible = false
	var replacement := Node3D.new()
	replacement.name = "ReplacementBuildingRoot"
	_visual.add_child(replacement)
	_quaternius_models.append(replacement)
	if _replace_with_cuteskull(replacement):
		return
	_assemble_modular_room(replacement, parts)


func _replace_with_cuteskull(root: Node3D) -> bool:
	var names: Array = CUTESKULL_BUILDINGS.get(core_type, [])
	if names.is_empty():
		return false
	var source_root := CUTESKULL_CITY.instantiate()
	var placed := 0
	for source_name in names:
		var source := source_root.get_node_or_null("88edabdafae14a9ca65722f3a709ce8a_fbx/RootNode2/" + source_name) as Node3D
		if source == null:
			continue
		var model := source.duplicate() as Node3D
		model.name = "Cuteskull_%s" % source_name
		var local_yaw := 0.0
		if core_type == "keep":
			if source_name == "Church_2":
				model.position = Vector3.ZERO
			elif source_name == "Castle_Tower_3":
				model.position = Vector3(-3.4, 0.0, -2.6)
			elif source_name == "Castle_Tower_1":
				model.position = Vector3(3.6, 0.0, -2.0)
			else:
				model.position = Vector3(3.2, 0.0, 3.0)
		else:
			model.position = Vector3.ZERO
		var model_scale := 0.145
		if source_name == "Castle_Tower_3":
			model_scale = 0.076
		elif source_name == "Castle_Tower_1":
			model_scale = 0.082
		elif source_name == "Castle_Tower_2":
			model_scale = 0.095
		elif source_name == "Castle_Wall":
			model_scale = 0.09
		elif core_type != "keep":
			model_scale = 0.17
		model.scale = Vector3.ONE * model_scale
		_normalize_cuteskull_model(model)
		_orient_cuteskull_model(model, local_yaw)
		model.set_meta("asset_source", "Cuteskull city16.fbx")
		model.set_meta("source_node", source_name)
		model.set_meta("kind", "core_building_visual")
		root.add_child(model)
		placed += 1
	source_root.free()
	return placed > 0


func _normalize_cuteskull_model(model: Node) -> void:
	for child in model.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			var aabb := (child as MeshInstance3D).mesh.get_aabb()
			# Source FBX is Z-up: center its XY footprint and put its minimum Z
			# on the source ground before applying the Y-up parent rotation.
			child.position = Vector3(-aabb.position.x - aabb.size.x * 0.5,
				-aabb.position.y - aabb.size.y * 0.5, -aabb.position.z)
			return


func _orient_cuteskull_model(model: Node3D, yaw_deg: float) -> void:
	var authored_scale := model.scale
	model.basis = Basis(Vector3.UP, deg_to_rad(yaw_deg)) \
		* Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	model.scale = authored_scale


func _assemble_modular_room(root: Node3D, parts: Dictionary) -> void:
	var cells: int = int(parts.get("cells", 2))
	var visual_scale: float = float(parts.get("visual_scale", 0.72))
	var roof_scale: float = float(parts.get("roof_scale", 0.65))
	var wall_key: String = String(parts.get("wall", ""))
	var door_key: String = String(parts.get("door", wall_key))
	var window_key: String = String(parts.get("window", wall_key))
	var floor_key: String = String(parts.get("floor", "bld/floor_brick"))
	var half := float(cells)
	# Floor tiles create an explicit footprint, while the outer wall ring keeps
	# the entrance readable from the fixed top-down camera.
	for x in range(cells):
		for z in range(cells):
			_add_building_model(root, floor_key,
				Vector3(-half + 1.0 + x * 2.0, 0.0,
					half - 1.0 - z * 2.0), 0.0, visual_scale)
	for i in range(cells):
		var offset := -half + 1.0 + i * 2.0
		_add_building_model(root, wall_key, Vector3(offset, 0.0, -half),
			0.0, visual_scale)
		_add_building_model(root, wall_key, Vector3(-half, 0.0, offset),
			90.0, visual_scale)
		_add_building_model(root, wall_key, Vector3(half, 0.0, offset),
			90.0, visual_scale)
		# South side: centered door, windows on the remaining modules.
		var front_key := door_key if i == cells / 2 else window_key
		_add_building_model(root, front_key, Vector3(offset, 0.0, half),
			180.0, visual_scale)
	var roof := _add_building_model(root, String(parts.get("roof", "")),
		Vector3(0.0, 3.75, 0.0), 0.0, roof_scale)
	if roof != null:
		root.set_meta("roof_asset", parts.get("roof", ""))
	if core_type == "keep":
		_add_building_model(root, "bld/stairs_exterior_straight",
			Vector3(0.0, 0.0, half + 1.1), 180.0, visual_scale * 0.8)
		_add_building_model(root, "prop/torch_metal",
			Vector3(-half - 0.8, 0.0, half - 0.5), 0.0, 0.75)
		_add_building_model(root, "prop/torch_metal",
			Vector3(half + 0.8, 0.0, half - 0.5), 0.0, 0.75)
		# Four short stone piers give the Keep a compact defensive silhouette
		# without changing the gameplay footprint or adding collision owners.
		for corner in [Vector3(-2.5, 0.0, -2.5), Vector3(2.5, 0.0, -2.5),
				Vector3(-2.5, 0.0, 2.5), Vector3(2.5, 0.0, 2.5)]:
			_add_building_model(root, "bld/wall_brick_straight", corner,
				90.0, visual_scale * 0.82)
			_add_building_model(root, "bld/roof_roundtiles_6x6",
				corner + Vector3(0.0, 3.35, 0.0), 0.0, 0.34)
	elif core_type == "tavern":
		_add_building_model(root, "bld/chimney", Vector3(1.0, 0.0, -0.6),
			0.0, visual_scale)
		_add_building_model(root, "prop/lantern_wall",
			Vector3(half + 0.25, 1.6, half - 0.5), 90.0, 0.72)
	elif core_type == "inn":
		_add_building_model(root, "bld/chimney", Vector3(-1.0, 0.0, -0.6),
			0.0, visual_scale)
		_add_building_model(root, "bld/shutters_wide_open",
			Vector3(half + 0.2, 1.1, -0.1), 90.0, visual_scale * 0.8)
	elif core_type == "equipment":
		_add_building_model(root, "bld/chimney", Vector3(0.8, 0.0, -0.7),
			0.0, visual_scale)
		_add_building_model(root, "tool/anvil", Vector3(half + 0.65, 0.0, 0.7),
			15.0, visual_scale * 0.72)
		_add_building_model(root, "tool/workbench",
			Vector3(-half - 0.65, 0.0, 0.7), -15.0, visual_scale * 0.72)
	elif core_type == "grocery":
		_add_building_model(root, "prop/stall_empty",
			Vector3(0.0, 0.0, half + 1.0), 180.0, visual_scale * 0.82)


func _add_building_model(root: Node3D, key: String, pos: Vector3,
		yaw_deg: float, uniform_scale: float) -> Node3D:
	if key.is_empty():
		return null
	var model := VisualAssetCatalog3D.instantiate_model(key)
	if model == null:
		push_error("CoreBuilding3D: replacement model failed '%s'" % key)
		return null
	model.position = pos
	model.rotation.y = deg_to_rad(yaw_deg)
	model.scale = Vector3.ONE * uniform_scale
	model.visible = true
	model.set_meta("catalog_key", key)
	model.set_meta("kind", "core_building_visual")
	root.add_child(model)
	_enable_model_meshes(model)
	_apply_role_tone(model, key)
	return model


func _enable_model_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).visible = true
		_enable_model_meshes(child)


func _apply_role_tone(node: Node, key: String) -> void:
	var tone := Color(0.42, 0.42, 0.42)
	if core_type == "keep":
		# Keep stone is cool gray; its roof is charcoal slate.
		tone = Color(0.31, 0.34, 0.37) if key.begins_with("bld/roof") \
			else Color(0.52, 0.54, 0.55)
	elif key.begins_with("bld/roof"):
		tone = {
			"tavern": Color(0.30, 0.27, 0.23),
			"inn": Color(0.29, 0.30, 0.29),
			"grocery": Color(0.34, 0.29, 0.23),
			"equipment": Color(0.27, 0.28, 0.29),
		}.get(core_type, Color(0.32, 0.29, 0.25))
	else:
		tone = {
			"tavern": Color(0.52, 0.43, 0.34),
			"inn": Color(0.47, 0.46, 0.42),
			"grocery": Color(0.55, 0.48, 0.34),
			"equipment": Color(0.42, 0.43, 0.43),
		}.get(core_type, Color(0.45, 0.45, 0.45))
	var material := StandardMaterial3D.new()
	material.albedo_color = tone
	material.roughness = 0.92
	for child in node.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_override = material
		_apply_tone_to_children(child, material)


func _apply_tone_to_children(node: Node, material: StandardMaterial3D) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).material_override = material
		_apply_tone_to_children(child, material)


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
