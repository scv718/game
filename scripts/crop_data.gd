extends RefCounted
class_name CropData

## TASK-019-3 Crop definition (data-driven).
## 농작물 한 종류의 정의를 데이터로 분리한다. Farm3D가 배치할 CropNode3D는 이 정의를
## 참조해 growth time / raw ingredient / 시각 성장 단계 수를 결정한다.
## 첫 vertical slice는 1종(WHEAT)만 등록한다. 추가 종은 이 데이터 클래스 인스턴스를
## 더 만들면 된다(문자열 하드코딩 분기 없이 data-driven 확장).
##
## - growth_time: READY까지 걸리는 시간(초). `DESIGN_TUNING`.
## - raw_resource_id: harvest 시 VillageResources에 증가시키는 raw edible ingredient id.
## - raw_efficiency: Food raw fallback 소비 효율(가공 음식보다 낮음). `DESIGN_TUNING`.
## - stage_count: 시각 성장 단계 수(최소 표현, SEED 포함). `DESIGN_TUNING`.

var id: String = "wheat"
var display_name: String = "Wheat"
var growth_time: float = 4.0
var raw_resource_id: String = "crop"
var raw_efficiency: float = 0.5
var stage_count: int = 3
var harvest_amount: int = 1


func _init(p_id: String = "wheat", p_name: String = "Wheat") -> void:
	id = p_id
	display_name = p_name


static func default_crop() -> CropData:
	var c := CropData.new("wheat", "Wheat")
	c.growth_time = 4.0
	c.raw_resource_id = "crop"
	c.raw_efficiency = 0.5
	c.stage_count = 3
	c.harvest_amount = 1
	return c
