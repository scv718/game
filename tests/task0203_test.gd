extends SceneTree

## TASK-020-3 Meal Consumption / Efficiency 자동 검증.
##  - cooked meal 소비: meal이 raw보다 우선 소비된다(결정적 정책, data-driven).
##  - raw 대비 효율 차이: 같은 need를 채우는 데 meal은 적은 단위로, raw는 많은
##    단위로 소비된다(cooked 효율 > raw 효율).
##  - raw fallback: meal 부족 시 raw ingredient로 소비가 이어진다.
##  - shortage loop: meal/raw 모두 부족해도 stock이 음수가 되지 않고 shortage
##    상태가 결정적으로 반복된다.
##  - meal_consumed / raw_consumed / shortage_occurred signal 정상 발화.

enum Phase {
	SETUP,
	EFFICIENCY,
	MEAL_PRIORITY,
	RAW_FALLBACK,
	SHORTAGE,
	LOOP,
	DONE,
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _failed := false

var _resources: Node = null
var _cons = null
var _cons_script: GDScript = null

var _meal_consumed := {}
var _raw_consumed := {}
var _shortages := []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 4:
				return false
			_setup()
		Phase.EFFICIENCY:
			if _frame < 3:
				return false
			_check_efficiency()
			_phase = Phase.MEAL_PRIORITY
			_frame = 0
		Phase.MEAL_PRIORITY:
			if _frame < 3:
				return false
			_check_meal_priority()
			_phase = Phase.RAW_FALLBACK
			_frame = 0
		Phase.RAW_FALLBACK:
			if _frame < 3:
				return false
			_check_raw_fallback()
			_phase = Phase.SHORTAGE
			_frame = 0
		Phase.SHORTAGE:
			if _frame < 3:
				return false
			_check_shortage()
			_phase = Phase.LOOP
			_frame = 0
		Phase.LOOP:
			if _frame < 3:
				return false
			_check_loop()
			_phase = Phase.DONE
			_frame = 0
		Phase.DONE:
			if _frame < 2:
				return false
			print("TASK0203_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 1000:
		print("TASK0203_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _setup() -> void:
	_resources = root.get_node_or_null("VillageResources")
	_cons_script = load("res://scripts/meal_consumption.gd") as GDScript
	if _resources == null or _cons_script == null:
		_check(false, "VillageResources autoload + meal_consumption.gd load")
		quit()
		return
	_cons = _cons_script.new()
	_cons.name = "MealConsumption"
	root.add_child(_cons)
	_cons.set_resource_source(_resources)
	_cons.meal_consumed.connect(_on_meal_consumed)
	_cons.raw_consumed.connect(_on_raw_consumed)
	_cons.shortage_occurred.connect(_on_shortage)
	_check(_cons.get_script() == _cons_script, "meal consumption component is meal_consumption.gd")
	_check(_cons.get_resource_source() == _resources, "consumption uses VillageResources as ledger")
	var prio: Array = _cons.get_consumption_priority()
	_check(not prio.is_empty(), "consumption priority populated from registry")
	_check(_cons.is_meal("meal_cooked_meat") and _cons.is_meal("meal_hearty_stew"),
		"meal resource ids recognized as meals")
	_check(not _cons.is_meal("meat") and not _cons.is_meal("crop"), "raw resource ids not meals")
	_phase = Phase.EFFICIENCY
	_frame = 0


func _on_meal_consumed(resource_id: String, amount: int) -> void:
	_meal_consumed[resource_id] = int(_meal_consumed.get(resource_id, 0)) + amount


func _on_raw_consumed(resource_id: String, amount: int) -> void:
	_raw_consumed[resource_id] = int(_raw_consumed.get(resource_id, 0)) + amount


func _on_shortage(need_remaining: float) -> void:
	_shortages.append(need_remaining)


func _seed(amounts: Dictionary) -> void:
	for key in _resources._amounts.keys():
		_resources._amounts[key] = 0
	for key in amounts.keys():
		_resources._amounts[key] = int(amounts[key])


func _reset_signals() -> void:
	_meal_consumed.clear()
	_raw_consumed.clear()
	_shortages.clear()


func _check_efficiency() -> void:
	# 1. 효율 기준: meal 효율이 raw 직접 섭취보다 높다.
	_check(_cons.get_resource_efficiency("meal_cooked_meat") == 6.0, "cooked_meat efficiency = 6.0")
	_check(_cons.get_resource_efficiency("meal_hearty_stew") == 10.0, "hearty_stew efficiency = 10.0")
	_check(_cons.get_resource_efficiency("meat") == 2.0, "raw meat efficiency = 2.0")
	_check(_cons.get_resource_efficiency("crop") == 1.0, "raw crop efficiency = 1.0")
	_check(
		_cons.get_resource_efficiency("meal_cooked_meat") > _cons.get_resource_efficiency("meat")
		and _cons.get_resource_efficiency("meal_hearty_stew") > _cons.get_resource_efficiency("crop"),
		"cooked meal efficiency exceeds raw for the same ingredient"
	)

	# 2. 우선순위 정책: meal(높은 tier)이 raw보다 먼저 온다(결정적).
	var prio: Array = _cons.get_consumption_priority()
	var idx_meal: int = prio.find("meal_hearty_stew")
	var idx_cooked: int = prio.find("meal_cooked_meat")
	var idx_meat: int = prio.find("meat")
	var idx_crop: int = prio.find("crop")
	_check(idx_meal >= 0 and idx_cooked >= 0 and idx_meat >= 0 and idx_crop >= 0,
		"priority contains all meals and raw fallbacks")
	_check(idx_cooked < idx_meat and idx_cooked < idx_crop, "cooked meal prioritized before raw")
	_check(idx_meal < idx_meat and idx_meal < idx_crop, "hearty_stew prioritized before raw")

	# 3. 같은 need(6.0)를 채울 때: meal은 1단위, raw meat는 3단위 필요 → 효율 차이.
	_seed({"meal_cooked_meat": 10, "meat": 10, "crop": 10})
	_reset_signals()
	var r_meal = _cons.consume_need(6.0)
	_check(r_meal["met"] == true, "need 6.0 met using cooked meal")
	_check(int(r_meal["consumed"].get("meal_cooked_meat", 0)) == 1, "cooked meal consumes 1 unit for need 6.0")
	_check(r_meal["efficiency_gained"] == 6.0, "cooked meal gains 6.0 efficiency")
	_seed({"meal_cooked_meat": 0, "meat": 10, "crop": 10})
	_reset_signals()
	var r_raw = _cons.consume_need(6.0)
	_check(r_raw["met"] == true, "need 6.0 met using raw meat")
	_check(int(r_raw["consumed"].get("meat", 0)) == 3, "raw meat consumes 3 units for need 6.0 (low efficiency)")
	_check(
		int(r_meal["consumed"].get("meal_cooked_meat", 0)) == 1 and int(r_raw["consumed"].get("meat", 0)) == 3,
		"cooked meal requires fewer units than raw for the same need (efficiency difference)"
	)
	_check_resource_non_negative()


func _check_meal_priority() -> void:
	# meal과 raw가 모두 있을 때 meal이 먼저 소비되고 raw는 건드리지 않는다.
	_seed({"meal_cooked_meat": 2, "meat": 5, "crop": 5})
	_reset_signals()
	var r = _cons.consume_need(6.0)
	_check(r["met"] == true, "need met when both meal and raw available")
	_check(int(r["consumed"].get("meal_cooked_meat", 0)) == 1, "meal consumed first (1 cooked_meat)")
	_check(r["consumed"].get("meat", 0) == 0 and r["consumed"].get("crop", 0) == 0,
		"raw not consumed when meal satisfies the need")
	_check(_resources.get_amount("meal_cooked_meat") == 1, "meal stock decreased by consumed amount")
	_check(_resources.get_amount("meat") == 5 and _resources.get_amount("crop") == 5,
		"raw stock untouched when meal sufficient")
	_check(_meal_consumed.get("meal_cooked_meat", 0) == 1, "meal_consumed signal fired")
	_check(_raw_consumed.is_empty(), "no raw_consumed signal when meal sufficient")
	_check_resource_non_negative()


func _check_raw_fallback() -> void:
	# meal이 부족하면 raw ingredient로 fallback 소비된다.
	_seed({"meal_cooked_meat": 0, "meat": 5, "crop": 0})
	_reset_signals()
	var r = _cons.consume_need(6.0)
	_check(r["met"] == true, "need met via raw fallback")
	_check(int(r["consumed"].get("meat", 0)) == 3, "raw fallback consumed 3 meat (eff 2.0 each)")
	_check(r["consumed"].get("meal_cooked_meat", 0) == 0, "no meal consumed in fallback path")
	_check(_resources.get_amount("meat") == 2, "raw meat stock consumed correctly (5 -> 2)")
	_check(_raw_consumed.get("meat", 0) == 3, "raw_consumed signal fired for fallback")
	_check(_meal_consumed.is_empty(), "no meal_consumed signal in fallback path")
	_check_resource_non_negative()


func _check_shortage() -> void:
	# meal/raw 모두 부족 → shortage 상태, stock 음수 없음, 결정적.
	_seed({"meal_cooked_meat": 0, "meat": 1, "crop": 1})
	_reset_signals()
	var r = _cons.consume_need(6.0)
	_check(r["met"] == false, "need not met -> shortage")
	_check(r["shortage"] == true, "shortage flag set")
	_check(int(r["consumed"].get("meat", 0)) == 1 and int(r["consumed"].get("crop", 0)) == 1,
		"all available raw consumed (meat 1 + crop 1)")
	_check(absf(float(r["need_remaining"]) - 3.0) < 0.001, "need_remaining = 3.0 (6 - 2 - 1)")
	_check(absf(float(r["efficiency_gained"]) - 3.0) < 0.001, "efficiency gained = 3.0 from raw")
	_check(not _shortages.is_empty(), "shortage_occurred signal fired")
	_check(_resources.get_amount("meat") == 0 and _resources.get_amount("crop") == 0,
		"stock depleted but not negative")
	_check_resource_non_negative()


func _check_loop() -> void:
	# 반복 소비(shortage loop)에서도 stock 음수 없이 안정적으로 shortage 상태 유지.
	_seed({})
	_reset_signals()
	for _i in 5:
		var r = _cons.consume_need(6.0)
		_check(r["shortage"] == true, "shortage repeated on empty ledger (iter %d)" % _i)
	_check(_shortages.size() == 5, "shortage_occurred fired every iteration")
	_check_resource_non_negative()

	# need 0이면 아무것도 소비하지 않고 met.
	_seed({"meal_cooked_meat": 3, "meat": 3})
	_reset_signals()
	var r0 = _cons.consume_need(0.0)
	_check(r0["met"] == true and r0["consumed"].is_empty(), "zero need consumes nothing and is met")
	_check(_resources.get_amount("meal_cooked_meat") == 3 and _resources.get_amount("meat") == 3,
		"no stock consumed on zero need")
	_check_resource_non_negative()

	_cons.queue_free()
	_phase = Phase.DONE
	_frame = 0


func _check_resource_non_negative() -> void:
	for key in _resources._amounts.keys():
		if _resources._amounts[key] < 0:
			_check(false, "no negative stock: %s >= 0" % str(key))
			return
	_check(true, "no resource became negative in the ledger")


func _initialize() -> void:
	pass
