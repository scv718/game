extends RefCounted
class_name RawFood

## TASK-019-3 raw edible ingredient → Food raw fallback 소비 연결.
##
## TASK-018(Food system)가 아직 미구현이므로, 농작물에서 나온 raw edible ingredient가
## Food raw fallback으로 소비 가능하다는 최소 연결점을 여기서 제공한다. TASK-018이
## 본격 Food stock/consumption tick을 구현하면 이 유틸의 소비 규약을 그대로 소비한다.
##
## 규칙:
##   - raw ingredient는 가공 없이 먹을 수 있으나 효율이 낮다(가공 음식 대비 낮은
##     efficiency - `DESIGN_TUNING`).
##   - Food stock이 부족할 때 raw edible ingredient를 fallback으로 소비한다.
##   - negative stock 없음: 필요한 만큼만 spend한다(부족 시 사용 가능분만 사용).
##
## VillageResources는 id별 정수 stock을 가지므로, raw ingredient를 "food"와 별개
## raw 카테고리로 취급해 Food 부족 시 fallback spend 경로를 제공한다.

const DEFAULT_RAW_EFFICIENCY := 0.5


## Food stock이 부족할 때 raw ingredient를 fallback으로 소비해 부족분을 채운다.
## consume_food는 반드시 Food stock을 먼저 쓰고, 부족분만 raw로 spend한다.
## 실제 게임 consumption tick은 TASK-018이 담당하며, 여기서는 "raw가 food 부족분을
## fallback으로 메울 수 있고 stock이 음수가 되지 않는다"는 계약을 검증 가능하게 한다.
static func consume_with_raw_fallback(
		resources: Node,
		food_id: String,
		raw_id: String,
		need: int,
		raw_efficiency: float = DEFAULT_RAW_EFFICIENCY) -> Dictionary:
	var used_food := 0
	var used_raw := 0
	if need <= 0 or resources == null or not is_instance_valid(resources):
		return {"food": used_food, "raw": used_raw, "shortage": 0}

	# 1) Food 우선 소비.
	var food_stock := int(resources.get_amount(food_id))
	used_food = mini(food_stock, need)
	var remaining := need - used_food
	if used_food > 0:
		resources.spend(food_id, used_food)

	# 2) 부족분은 raw ingredient를 낮은 효율로 fallback 소비.
	if remaining > 0:
		# raw efficiency 반영: 효율 e일 때 부족분을 채우려면 ceil(remaining / e)만큼
		# raw가 필요하다. stock을 초과하면 사용 가능분만 사용한다.
		var raw_needed := ceili(float(remaining) / maxf(raw_efficiency, 0.01))
		var raw_stock := int(resources.get_amount(raw_id))
		used_raw = mini(raw_stock, raw_needed)
		if used_raw > 0:
			resources.spend(raw_id, used_raw)
		# raw efficiency로 환산한 실제 "채워진" food량.
		var filled_by_raw := int(floorf(float(used_raw) * raw_efficiency))
		remaining -= filled_by_raw

	return {
		"food": used_food,
		"raw": used_raw,
		"shortage": maxi(remaining, 0),
	}


## raw ingredient가 food fallback으로 소비 가능한지(가공 없이 먹을 수 있는지) 조회.
static func is_raw_edible(raw_id: String, raw_ids: Array[String]) -> bool:
	return raw_ids.has(raw_id)
