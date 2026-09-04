extends SceneTree

## TASK-020-4 Cooking Regression 자동 검증.
## Farm → Cook → Consume vertical slice를 원장(VillageResources) 위에서 하나의 흐름으로
## 재현한다. TASK-019 Farm은 아직 QUEUED이므로 "crop/raw input" 단계는 생재료(crop/meat)가
## 원장에 유입되는 Farm 산출물 계약으로 표현한다.
##
## 검증 항목(큐):
##   - crop/raw input: 생재료가 원장에 유입되고 raw efficiency로 인식된다.
##   - recipe: CookingRecipes 정의가 유효하고 cooked 효율이 raw보다 높다.
##   - meal output: CookingProduction이 재료를 소비해 meal을 생성한다.
##   - consumption: MealConsumption이 meal을 raw보다 우선 소비한다.
##   - raw fallback: meal 부족 시 raw ingredient로 소비가 이어진다.
##   - Food HUD: hud.tscn의 FoodLabel(재료 합)/MealLabel(요리 합)이 원장과 동기화된다.
##   - DAY/NIGHT: GameTime DAY→NIGHT→DAY 전환에서도 생산/소비가 정상 동작한다.
##   - Worker production 회귀: cooking이 공용 원장의 wood/stone worker 생산을
##     오염시키지 않는다(재료 소비가 wood/stone과 무관, worker 반납 경로 정상).
##
## 주의: -s 기동 시 autoload 전역 식별자 참조 금지 규약(CMB-001-2와 동일)에 따라
## VillageResources/GameTime은 root.get_node_or_null로 접근하고, 신호는 duck-typing으로
## 연결한다. CookingRecipes/RecipeData는 class_name이므로 정적 참조 가능하다.

enum Phase {
	SETUP,
	RAW_INPUT,
	RECIPE,
	MEAL_OUTPUT,
	CONSUME,
	RAW_FALLBACK,
	FOOD_HUD,
	DAYNIGHT,
	WORKER,
	DONE,
}

const SETTLE_FRAMES := 5
const FRAME_LIMIT := 1000

var _frame := 0
var _phase: Phase = Phase.SETUP
var _failed := false

var _resources: Node = null
var _game_time: Node = null
var _prod = null
var _cons = null
var _prod_script: GDScript = null
var _cons_script: GDScript = null
var _hud: Node = null
var _food_label: Label = null
var _meal_label: Label = null

var _meal_produced := {}
var _meal_consumed := {}
var _raw_consumed := {}
var _shortages := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _seed(amounts: Dictionary) -> void:
	for key in _resources._amounts.keys():
		_resources._amounts[key] = 0
	for key in amounts.keys():
		_resources._amounts[key] = int(amounts[key])


func _reset_signals() -> void:
	_meal_produced.clear()
	_meal_consumed.clear()
	_raw_consumed.clear()
	_shortages = 0


func _check_resource_non_negative() -> void:
	for key in _resources._amounts.keys():
		if _resources._amounts[key] < 0:
			_check(false, "no negative stock: %s >= 0" % str(key))
			return
	_check(true, "no resource became negative in the ledger")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < SETTLE_FRAMES:
				return false
			_setup()
		Phase.RAW_INPUT:
			if _frame < 3:
				return false
			_check_raw_input()
			_phase = Phase.RECIPE
			_frame = 0
		Phase.RECIPE:
			if _frame < 3:
				return false
			_check_recipe()
			_phase = Phase.MEAL_OUTPUT
			_frame = 0
		Phase.MEAL_OUTPUT:
			if _frame < 3:
				return false
			_check_meal_output()
			_phase = Phase.CONSUME
			_frame = 0
		Phase.CONSUME:
			if _frame < 3:
				return false
			_check_consume()
			_phase = Phase.RAW_FALLBACK
			_frame = 0
		Phase.RAW_FALLBACK:
			if _frame < 3:
				return false
			_check_raw_fallback()
			_phase = Phase.FOOD_HUD
			_frame = 0
		Phase.FOOD_HUD:
			if _frame < 3:
				return false
			_check_food_hud()
			_phase = Phase.DAYNIGHT
			_frame = 0
		Phase.DAYNIGHT:
			if _frame < 3:
				return false
			_check_daynight()
			_phase = Phase.WORKER
			_frame = 0
		Phase.WORKER:
			if _frame < 3:
				return false
			_check_worker()
			_phase = Phase.DONE
			_frame = 0
		Phase.DONE:
			if _frame < 2:
				return false
			_cleanup()
			print("TASK0204_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > FRAME_LIMIT:
		print("TASK0204_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _setup() -> void:
	_resources = root.get_node_or_null("VillageResources")
	_game_time = root.get_node_or_null("GameTime")
	_prod_script = load("res://scripts/cooking_production.gd") as GDScript
	_cons_script = load("res://scripts/meal_consumption.gd") as GDScript
	if _resources == null or _game_time == null or _prod_script == null or _cons_script == null:
		_check(false, "VillageResources/GameTime autoloads + cooking scripts load")
		quit()
		return
	_prod = _prod_script.new()
	_prod.name = "CookingProd"
	root.add_child(_prod)
	_prod.set_resource_source(_resources)
	_prod.meal_produced.connect(_on_meal_produced)
	_cons = _cons_script.new()
	_cons.name = "MealConsumption"
	root.add_child(_cons)
	_cons.set_resource_source(_resources)
	_cons.meal_consumed.connect(_on_meal_consumed)
	_cons.raw_consumed.connect(_on_raw_consumed)
	_cons.shortage_occurred.connect(_on_shortage)
	# DAY/NIGHT 판정을 결정적으로 통제하기 위해 auto advance를 끄고 phase 경계를
	# 명시적 advance()로만 넘는다(기존 game_time.gd 테스트 규약).
	_game_time.set_auto_advance(false)
	_game_time._elapsed = 0.0
	var hud_scene: PackedScene = load("res://ui/hud.tscn")
	_check(hud_scene != null, "hud.tscn loads")
	if hud_scene == null:
		quit()
		return
	_hud = hud_scene.instantiate()
	_hud.name = "HUDRegress"
	root.add_child(_hud)
	_food_label = _hud.get_node("%FoodLabel") as Label
	_meal_label = _hud.get_node("%MealLabel") as Label
	_check(_food_label != null and _meal_label != null, "Food HUD labels present")
	_check(not _prod.get_recipe_ids().is_empty(), "production recipe list populated")
	_phase = Phase.RAW_INPUT
	_frame = 0


func _on_meal_produced(recipe_id: String, _output: String, amount: int) -> void:
	_meal_produced[recipe_id] = int(_meal_produced.get(recipe_id, 0)) + amount


func _on_meal_consumed(resource_id: String, amount: int) -> void:
	_meal_consumed[resource_id] = int(_meal_consumed.get(resource_id, 0)) + amount


func _on_raw_consumed(resource_id: String, amount: int) -> void:
	_raw_consumed[resource_id] = int(_raw_consumed.get(resource_id, 0)) + amount


func _on_shortage(_need_remaining: float) -> void:
	_shortages += 1


## crop/raw input: 생재료 유입 + raw food 인식.
func _check_raw_input() -> void:
	_seed({"crop": 4, "meat": 3, "wood": 20, "stone": 5})
	_check(_resources.get_amount("crop") == 4, "raw crop input present in ledger")
	_check(_resources.get_amount("meat") == 3, "raw meat input present in ledger")
	_check(CookingRecipes.get_raw_efficiency("crop") == 1.0, "crop raw efficiency 1.0")
	_check(CookingRecipes.get_raw_efficiency("meat") == 2.0, "meat raw efficiency 2.0")
	_check(_cons.is_meal("crop") == false and _cons.is_meal("meat") == false,
		"raw ingredients are not meals")
	_check_resource_non_negative()


## recipe: 전체 정의 유효 + cooked 효율 > raw 직접 섭취 합.
func _check_recipe() -> void:
	var report := CookingRecipes.validate_all()
	_check(report["valid"] == true, "all recipe definitions valid")
	var cm := CookingRecipes.get_recipe("cooked_meat")
	var hs := CookingRecipes.get_recipe("hearty_stew")
	_check(cm != null and cm.is_valid() and hs != null and hs.is_valid(),
		"first slice recipes valid (cooked_meat + hearty_stew)")
	_check(cm.efficiency > cm.get_raw_efficiency(), "cooked_meat cooked > raw")
	_check(hs.efficiency > hs.get_raw_efficiency(), "hearty_stew cooked > raw")


## meal output: 재료 소비 + meal 생성 (원장).
func _check_meal_output() -> void:
	_seed({"crop": 4, "meat": 4, "wood": 20, "stone": 5})
	_reset_signals()
	var r1 = _prod.craft_recipe("cooked_meat")
	var r2 = _prod.craft_recipe("hearty_stew")
	_check(r1["success"] == true, "cooked_meat production succeeds")
	_check(r2["success"] == true, "hearty_stew production succeeds")
	# cooked_meat: meat 2 소비. hearty_stew: meat 1 + crop 2 소비.
	_check(_resources.get_amount("meat") == 1, "raw meat consumed (4 - 2 - 1 = 1)")
	_check(_resources.get_amount("crop") == 2, "raw crop consumed (4 - 2 = 2)")
	_check(_resources.get_amount("meal_cooked_meat") == 1, "meal_cooked_meat produced")
	_check(_resources.get_amount("meal_hearty_stew") == 1, "meal_hearty_stew produced")
	_check(_meal_produced.get("cooked_meat", 0) == 1 and _meal_produced.get("hearty_stew", 0) == 1,
		"meal_produced signal fired once per recipe")
	_check_resource_non_negative()


## consumption: meal이 raw보다 우선 소비된다.
func _check_consume() -> void:
	_seed({"meal_cooked_meat": 2, "meal_hearty_stew": 1, "meat": 5, "crop": 5})
	_reset_signals()
	var r = _cons.consume_need(10.0)
	_check(r["met"] == true, "need 10.0 met with meals available")
	# priority: tier 내림차순(hearty_stew 10eff) 먼저 → cooked_meat(6eff).
	_check(int(r["consumed"].get("meal_hearty_stew", 0)) == 1,
		"hearty_stew consumed first (tier/efficiency priority)")
	_check(int(r["consumed"].get("meal_cooked_meat", 0)) == 0,
		"cooked_meat untouched when hearty_stew alone meets need")
	_check(r["consumed"].get("meat", 0) == 0 and r["consumed"].get("crop", 0) == 0,
		"raw not consumed when meal satisfies need")
	_check(_meal_consumed.get("meal_hearty_stew", 0) == 1, "meal_consumed signal fired")
	_check(_raw_consumed.is_empty(), "no raw_consumed signal when meal sufficient")
	_check_resource_non_negative()


## raw fallback: meal 부족 시 raw ingredient로 이어진다.
func _check_raw_fallback() -> void:
	_seed({"meal_cooked_meat": 0, "meal_hearty_stew": 0, "meat": 5, "crop": 2})
	_reset_signals()
	var r = _cons.consume_need(6.0)
	_check(r["met"] == true, "need met via raw fallback")
	_check(int(r["consumed"].get("meat", 0)) == 3, "raw fallback consumed 3 meat")
	_check(r["consumed"].get("meal_cooked_meat", 0) == 0 and r["consumed"].get("meal_hearty_stew", 0) == 0,
		"no meal consumed in fallback path")
	_check(_raw_consumed.get("meat", 0) == 3, "raw_consumed signal fired")
	_check(_meal_consumed.is_empty(), "no meal_consumed signal in fallback path")
	_check_resource_non_negative()


## Food HUD: FoodLabel(재료 합)/MealLabel(요리 합)이 원장과 동기화된다.
func _check_food_hud() -> void:
	_seed({})
	# HUD 갱신은 VillageResources.changed 시그널 기반 → add()로 유입해야 동기화된다.
	_resources.add("crop", 3)
	_resources.add("meat", 2)
	_resources.add("meal_cooked_meat", 2)
	_check(_food_label.text == "Food: 5", "Food HUD label sums raw crop+meat (3+2=5) got '%s'" % _food_label.text)
	_check(_meal_label.text == "Meal: 2", "Meal HUD label sums cooked meals (2) got '%s'" % _meal_label.text)
	# 재료 소비(요리) 시 HUD도 갱신된다.
	_resources.add("wood", 3)
	_check(_food_label.text == "Food: 5", "Food HUD ignores non-food resources (wood)")
	_seed({})
	_resources.add("meal_hearty_stew", 1)
	_check(_meal_label.text == "Meal: 1", "Meal HUD updates to 1 after reset")
	_check_resource_non_negative()


## DAY/NIGHT: DAY→NIGHT→DAY 전환에서도 생산/소비/원장/HUD 정상.
func _check_daynight() -> void:
	_game_time.set_durations(0.5, 0.3)
	_game_time._elapsed = 0.0
	var start_day: int = _game_time.get_day_number()
	_check(_game_time.get_phase_name() == "DAY", "starts in DAY phase")
	# DAY → NIGHT.
	_game_time.advance(0.6)
	_check(_game_time.get_phase_name() == "NIGHT", "advance crosses into NIGHT")
	_seed({"crop": 4, "meat": 4})
	_reset_signals()
	var r = _prod.craft_recipe("cooked_meat")
	_check(r["success"] == true, "cooking production works during NIGHT")
	# NIGHT → DAY.
	_game_time.advance(0.4)
	_check(_game_time.get_phase_name() == "DAY", "advance returns to DAY")
	_check(_game_time.get_day_number() == start_day + 1, "day number advanced after night")
	_seed({"meal_cooked_meat": 1, "meat": 2})
	_reset_signals()
	var c = _cons.consume_need(6.0)
	_check(c["met"] == true, "meal consumption works during DAY after night")
	_check(int(c["consumed"].get("meal_cooked_meat", 0)) == 1, "DAY consumption used meal")
	# DAY로 복귀 시 HUD phase 라벨이 정상 동작(기존 DayTimeLabel 유지).
	var day_label: Label = _hud.get_node("%DayTimeLabel") as Label
	_check(day_label != null and day_label.text.begins_with("DAY"), "HUD daytime label intact (got '%s')" % (day_label.text if day_label else "none"))
	_check_resource_non_negative()


## Worker production 회귀: cooking이 공용 원장의 wood/stone worker 생산을 오염시키지 않는다.
func _check_worker() -> void:
	_seed({"wood": 10, "stone": 10, "crop": 6, "meat": 6})
	_reset_signals()
	# worker가 반납하는 생산 경로(VillageResources.add wood/stone)와 요리 소비를 병행.
	var wood_before: int = _resources.get_amount("wood")
	var stone_before: int = _resources.get_amount("stone")
	var r1 = _prod.craft_recipe("cooked_meat")
	var r2 = _prod.craft_recipe("hearty_stew")
	_check(r1["success"] == true and r2["success"] == true, "cooking succeeds alongside worker stock")
	_check(_resources.get_amount("wood") == wood_before, "cooking does not consume wood")
	_check(_resources.get_amount("stone") == stone_before, "cooking does not consume stone")
	# worker 반납(add) 경로가 요리 이후에도 정상 동작한다.
	_resources.add("wood", 4)
	_resources.add("stone", 3)
	_check(_resources.get_amount("wood") == wood_before + 4, "worker wood deposit still works after cooking")
	_check(_resources.get_amount("stone") == stone_before + 3, "worker stone deposit still works after cooking")
	# food 재료가 wood/stone 자원과 혼입되지 않는다.
	_check(_cons.is_meal("wood") == false and _cons.is_meal("stone") == false,
		"wood/stone are not treated as meals")
	_check_resource_non_negative()


func _cleanup() -> void:
	if _prod != null and is_instance_valid(_prod):
		_prod.queue_free()
	if _cons != null and is_instance_valid(_cons):
		_cons.queue_free()
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()


func _initialize() -> void:
	pass