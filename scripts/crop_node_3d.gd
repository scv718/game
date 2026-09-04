extends Node3D
class_name CropNode3D

## TASK-019-3 Crop growth / harvest node 3D.
## 농장 plot에 심어진 실제 작물 한 포기다. growth time이 지나면 시각 성장 단계를 거쳐
## READY가 되고, Farmer가 harvest(interact)하면 raw edible ingredient를 내놓고
## HARVESTED 후 재성장(regrowth/replant)한다.
##
## - decorative vegetation과 구분: 장식(decoration.gd)은 "decorations" 그룹 + 순수 시각이며
##   gameplay가 없다. CropNode3D는 별도 "crops_3d" 그룹 + can_interact/interact 계약을
##   가진 gameplay 노드다. collision/selection(INTERACTABLE) 없이 Farmer가 대상 노드로만
##   조회한다(마우스 직접 수확 차단 = 자원/Worker 전용 정책과 일관).
## - data-driven: 동작은 CropData 정의를 참조한다.
## - regrowth/replant 정책: 기존 설계에 확정된 regrowth 정책이 없어(TASK-019-3 범위),
##   최소 반복 production cycle로 캡슐화한다. harvest 후 HARVESTED -> (regrow_time 경과)
##   -> SEED로 재시작해 다시 성장한다. 수치는 `DESIGN_TUNING`.
## - visual growth stage 최소 표현: 성장 단계에 따라 시각 mesh의 균일 scale/색상/가시성을
##   바꾼다(gameplay footprint 없음, 순수 시각).
## - freed reference 안전: _exit_tree에서 claim과 timer를 정리하고 stale 참조를 남기지
##   않는다. farmer는 is_instance_valid 가드 규약으로 소비한다.

enum GrowthStage { SEED, GROWING, READY, HARVESTED }

const STAGE_NAMES := {
	GrowthStage.SEED: "SEED",
	GrowthStage.GROWING: "GROWING",
	GrowthStage.READY: "READY",
	GrowthStage.HARVESTED: "HARVESTED",
}

## 시각 성장 표현 색상(단계별 최소 표현). READY일 때 가장 성숙한 색.
const STAGE_COLORS := {
	GrowthStage.SEED: Color(0.45, 0.35, 0.2),
	GrowthStage.GROWING: Color(0.4, 0.6, 0.3),
	GrowthStage.READY: Color(0.9, 0.78, 0.28),
	GrowthStage.HARVESTED: Color(0.3, 0.28, 0.2),
}

## READY 시각 mesh 크기(최소 표현 상한). DESIGN_TUNING.
const READY_SCALE := 1.0
const SEED_SCALE := 0.25

var crop_data: CropData = null
var growth_time: float = 4.0
var raw_resource_id: String = "crop"
var harvest_amount: int = 1
var regrow_time: float = 3.0

var stage: GrowthStage = GrowthStage.SEED
var growth_elapsed: float = 0.0

## Farmer claim 규약(두 Farmer가 같은 포기를 동시에 수확하지 않도록).
var _claimed_by: Node = null

var _visual: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _mat_base := Color(0.4, 0.6, 0.3)
var _stem_visual: MeshInstance3D = null


func setup(p_data: CropData) -> void:
	crop_data = p_data
	growth_time = p_data.growth_time
	raw_resource_id = p_data.raw_resource_id
	harvest_amount = p_data.harvest_amount
	stage = GrowthStage.SEED
	growth_elapsed = 0.0


func _ready() -> void:
	add_to_group("crops_3d")
	if crop_data == null:
		crop_data = CropData.default_crop()
		growth_time = crop_data.growth_time
		raw_resource_id = crop_data.raw_resource_id
		harvest_amount = crop_data.harvest_amount
	_build_visual()
	_apply_visual()


func _build_visual() -> void:
	# game logic과 분리된 순수 시각 표현. gameplay footprint/collision 없음.
	_visual = MeshInstance3D.new()
	_visual.name = "CropVisual"
	_material = StandardMaterial3D.new()
	_material.roughness = 1.0
	var stem := CylinderMesh.new()
	stem.top_radius = 0.06
	stem.bottom_radius = 0.09
	stem.height = 0.7
	_visual.mesh = stem
	_visual.material_override = _material
	_visual.position = Vector3(0.0, 0.35, 0.0)
	add_child(_visual)
	# 잎/이삭 placeholder: 최소 성장 표현(스케일 단계)만으로도 충분하므로 상단 Mesh만 쓴다.


func _physics_process(delta: float) -> void:
	if stage == GrowthStage.SEED or stage == GrowthStage.GROWING:
		growth_elapsed += delta
		_update_stage_visual()
		if growth_elapsed >= growth_time:
			_advance_to_ready()
	elif stage == GrowthStage.HARVESTED:
		growth_elapsed += delta
		if growth_elapsed >= regrow_time:
			_replant()


## 성장 시간을 단계 수로 나눠 SEED -> GROWING -> (READY)로 진행한다.
## 최소 표현: 중간 단계에서도 시각 mesh가 자라난다.
func _update_stage_visual() -> void:
	if crop_data == null or crop_data.stage_count <= 1:
		return
	var progress := growth_elapsed / maxf(growth_time, 0.01)
	var stage_index := int(floorf(progress * float(crop_data.stage_count - 1)))
	var mid_stage := stage_index >= 1 and stage_index < crop_data.stage_count - 1
	if mid_stage and stage == GrowthStage.SEED:
		stage = GrowthStage.GROWING
		_apply_visual()


func _advance_to_ready() -> void:
	stage = GrowthStage.READY
	growth_elapsed = 0.0
	_apply_visual()


func _replant() -> void:
	stage = GrowthStage.SEED
	growth_elapsed = 0.0
	_claimed_by = null
	_apply_visual()


## READY 상태에서만 수확 가능. harvest 시 raw edible ingredient amount를 돌려준다.
func can_interact() -> bool:
	return stage == GrowthStage.READY


func interact(_interactor: Node) -> Dictionary:
	if stage != GrowthStage.READY:
		return {}
	var amount: int = maxi(harvest_amount, 1)
	stage = GrowthStage.HARVESTED
	growth_elapsed = 0.0
	_claimed_by = null
	_apply_visual()
	return {"resource_id": raw_resource_id, "amount": amount}


## -- Farmer claim 규약(ResourceNode3D.claim/release와 동일 감각). --
func is_claimed_by_other(farmer: Node) -> bool:
	return is_instance_valid(_claimed_by) and _claimed_by != farmer


func claim(farmer: Node) -> bool:
	if is_instance_valid(_claimed_by) and _claimed_by != farmer:
		return false
	_claimed_by = farmer
	return true


func release(farmer: Node) -> void:
	if _claimed_by == farmer or not is_instance_valid(_claimed_by):
		_claimed_by = null


func is_ready() -> bool:
	return stage == GrowthStage.READY


func get_stage_name() -> String:
	return STAGE_NAMES.get(stage, "?")


func _apply_visual() -> void:
	if _visual == null:
		return
	_material.albedo_color = STAGE_COLORS.get(stage, _mat_base)
	match stage:
		GrowthStage.SEED:
			_visual.visible = true
			_visual.scale = Vector3.ONE * SEED_SCALE
		GrowthStage.GROWING:
			_visual.visible = true
			_visual.scale = Vector3.ONE * (SEED_SCALE + 0.4)
		GrowthStage.READY:
			_visual.visible = true
			_visual.scale = Vector3.ONE * READY_SCALE
		GrowthStage.HARVESTED:
			_visual.visible = false


func _exit_tree() -> void:
	_claimed_by = null
