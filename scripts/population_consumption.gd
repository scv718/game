extends Node

## TASK-018-2: Population Consumption Tick.
## 현재 존재하는 주민/Worker/Mercenary 인구가 DAY tick마다 Food를 소비하는
## 최소 소비 시스템.
## - per-frame 감소 금지: phase_changed(DAY 진입) 시점에만 1회 실행한다.
## - 기존 DAY/time tick(GameTime)과 결합해 DAY마다 소비 tick이 돈다.
## - 중복 없는 집계: Worker는 주민(Roster의 WorkerData)의 하위 집합이므로
##   인구 = 활성 주민(전체) + 활성 용병(alive)만 합산하고 Worker는 보고용으로만
##   따로 집계한다(중복 방지).
## - Food(COOKED_MEAL) 우선 소비, 부족하면 raw edible(RAW_EDIBLE)로 낮은
##   efficiency로 대체 소비하고, 둘 다 부족하면 shortage 양/상태를 기록한다.
## - exact rate는 CONSUMPTION_CONFIG 데이터로 분리해 DESIGN_TUNING에서 조정한다.
## - punitive starvation damage/death는 만들지 않는다(부족 상태만 기록).

## 인구 1명이 하루(DAY tick)에 소비하는 Food satiety 단위. DESIGN_TUNING 조정 대상.
const CONSUMPTION_CONFIG := {
	"per_capita_per_day": 2,
}

enum TickState {
	OK,
	RAW_FALLBACK,
	SHORTAGE,
}

const TICK_STATE_NAMES := {
	TickState.OK: "OK",
	TickState.RAW_FALLBACK: "RAW_FALLBACK",
	TickState.SHORTAGE: "SHORTAGE",
}

## 인구 집계 소스. 기본값은 WorkerRoster/MercenaryRoster autoload 조회이며,
## configure_sources()로 테스트/후속 도메인에서 교체할 수 있다.
var _resident_count_fn: Callable = Callable()
var _worker_count_fn: Callable = Callable()
var _mercenary_count_fn: Callable = Callable()

var _resources: Node = null
var _game_time: Node = null
var _worker_roster: Node = null
var _mercenary_roster: Node = null

var _last_tick: Dictionary = {}

signal consumption_tick(result: Dictionary)


func _ready() -> void:
	_resources = get_node_or_null("/root/VillageResources")
	_game_time = get_node_or_null("/root/GameTime")
	_worker_roster = get_node_or_null("/root/WorkerRoster")
	_mercenary_roster = get_node_or_null("/root/MercenaryRoster")
	_resident_count_fn = _default_resident_count
	_worker_count_fn = _default_worker_count
	_mercenary_count_fn = _default_mercenary_count
	if _game_time != null and _game_time.has_signal("phase_changed"):
		_game_time.phase_changed.connect(_on_phase_changed)


## 인구 집계 소스를 교체한다. worker는 resident의 하위 집합(배치된 주민)이므로
## 인구 합산에는 사용하지 않는다.
func configure_sources(resident_fn: Callable, worker_fn: Callable, mercenary_fn: Callable) -> void:
	_resident_count_fn = resident_fn
	_worker_count_fn = worker_fn
	_mercenary_count_fn = mercenary_fn


## DAY 진입 시 인구 소비 tick 1회 실행. NIGHT 진입은 무시한다.
func _on_phase_changed(phase: int, _day_number: int) -> void:
	if _game_time == null:
		return
	if int(phase) == int(_game_time.Phase.DAY):
		consume_tick()


## 현재 인구 수. Worker는 주민 하위 집합이라 중복 집계하지 않고
## 활성 주민(전체) + 활성 용병(alive)만 합산한다.
func get_population_count() -> int:
	return _source_count(_resident_count_fn) + _source_count(_mercenary_count_fn)


## 현재 활성(배치된) Worker 수. 인구 합산에는 포함되지 않는다(주민 하위 집합).
func get_active_worker_count() -> int:
	return _source_count(_worker_count_fn)


## 현재 활성(alive) 용병 수.
func get_active_mercenary_count() -> int:
	return _source_count(_mercenary_count_fn)


## 마지막 소비 tick 결과.
func get_last_tick() -> Dictionary:
	return _last_tick.duplicate()


## 마지막 소비 tick 상태(TickState). 소비가 없었으면 OK.
func get_tick_state() -> int:
	return int(_last_tick.get("state", TickState.OK))


func get_tick_state_name() -> String:
	return TICK_STATE_NAMES.get(get_tick_state(), "?")


## 인구 소비 tick을 즉시 실행한다. phase_changed(DAY) 시점과 동일한 로직이며,
## 결과 Dictionary를 반환하고 consumption_tick 시그널을 방출한다.
## deterministic: 동일한 인구/재고 입력에 대해 동일한 결과를 낸다.
## stock은 절대 음수가 되지 않는다(remove_food/spend 계약).
func consume_tick() -> Dictionary:
	var population := get_population_count()
	var rate := int(CONSUMPTION_CONFIG.get("per_capita_per_day", 0))
	var demand := population * rate
	var remaining := demand
	var consumed_cooked := 0
	var consumed_raw := 0
	if _resources != null:
		var consumed := _consume_to_meet_demand(remaining)
		consumed_cooked = int(consumed["cooked"])
		consumed_raw = int(consumed["raw"])
		remaining = int(consumed["remaining"])
	var state := TickState.OK
	if remaining > 0:
		state = TickState.SHORTAGE
	elif consumed_raw > 0:
		state = TickState.RAW_FALLBACK
	var day := 0
	if _game_time != null and _game_time.has_method("get_day_number"):
		day = int(_game_time.get_day_number())
	_last_tick = {
		"day": day,
		"population": population,
		"demand": demand,
		"consumed_cooked": consumed_cooked,
		"consumed_raw": consumed_raw,
		"shortage": maxi(remaining, 0),
		"state": state,
		"state_name": TICK_STATE_NAMES[state],
	}
	consumption_tick.emit(_last_tick)
	return _last_tick


## 요구량(remaining satiety)을 만족할 때까지 Food를 소비한다.
## COOKED_MEAL 우선, 부족하면 RAW_EDIBLE 순으로 소비하고, 각 food의
## efficiency만큼 요구량을 충족한다(재고 단위 정수 소비).
## 반환: {"cooked": int, "raw": int, "remaining": int}
func _consume_to_meet_demand(remaining: int) -> Dictionary:
	var cooked_cat := _cooked_category()
	var raw_cat := _raw_category()
	var cooked := 0
	var raw := 0
	for category in [cooked_cat, raw_cat]:
		for food_id in _food_ids_by_category(category):
			if remaining <= 0:
				break
			var eff := int(_resources.get_food_efficiency(food_id))
			if eff <= 0:
				continue
			var stock := int(_resources.get_food(food_id))
			if stock <= 0:
				continue
			var needed: int = (remaining + eff - 1) / eff
			var take: int = mini(stock, needed)
			if _resources.remove_food(food_id, take):
				if category == cooked_cat:
					cooked += take
				else:
					raw += take
				remaining -= take * eff
		if remaining <= 0:
			break
	return {"cooked": cooked, "raw": raw, "remaining": remaining}


func _food_ids_by_category(category: int) -> Array[String]:
	var out: Array[String] = []
	if _resources == null:
		return out
	var defs: Dictionary = _resources.FOOD_DEFS
	for food_id in defs.keys():
		if int(defs[food_id].get("category", -1)) == category:
			out.append(str(food_id))
	return out


func _cooked_category() -> int:
	if _resources != null:
		return int(_resources.FoodCategory.COOKED_MEAL)
	return 1


func _raw_category() -> int:
	if _resources != null:
		return int(_resources.FoodCategory.RAW_EDIBLE)
	return 0


func _source_count(fn: Callable) -> int:
	if fn.is_valid():
		return int(fn.call())
	return 0


func _default_resident_count() -> int:
	if _worker_roster != null and _worker_roster.has_method("get_count"):
		return int(_worker_roster.get_count())
	return 0


func _default_worker_count() -> int:
	if _worker_roster != null and _worker_roster.has_method("get_assigned_count"):
		return int(_worker_roster.get_assigned_count())
	return 0


func _default_mercenary_count() -> int:
	if _mercenary_roster != null and _mercenary_roster.has_method("get_alive_count"):
		return int(_mercenary_roster.get_alive_count())
	return 0