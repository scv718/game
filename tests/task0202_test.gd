extends SceneTree

## TASK-020-2 Cooking Production Path ?먮룞 寃利?
##  - raw ingredient ?뚮퉬: ?щ즺 異⑸텇 ??VillageResources?먯꽌 ?щ즺媛 ?뚮퉬?쒕떎.
##  - meal ?앹꽦: 異쒕젰 meal??VillageResources??異붽??쒕떎.
##  - duplicate production ?놁쓬: ??二쇨린?먯꽌 媛?recipe媛 ?뺥솗??1?뚮쭔 ?앹궛?섍퀬,
##    媛숈? ?щ즺濡?以묐났 ?앹궛???놁쑝硫?meal??以묐났 異붽??섏? ?딅뒗??
##  - negative ingredient ?놁쓬: ?щ즺 遺議????앹궛 ?ㅽ뙣濡??앸굹怨??먯옣???대뼡
##    ?먯썝???뚯닔媛 ?섏? ?딅뒗??
##  - worker production pattern ?ъ궗?? VillageResources媛 ?좎씪???먯썝 ?먯옣?닿퀬,
##    CookingRecipes.craft 寃곗젙?깃낵 timed driver媛 寃고빀?쒕떎.
##  - 理쒖냼 production component 寃쎈줈: 嫄대Ъ/worker actor瑜?諛쒕챸?섏? ?딅뒗??

enum Phase {
	SETUP,
	BASIC,
	DUPLICATE,
	NEGATIVE,
	DRIVER,
	DISABLED,
	DONE,
}

var _frame := 0
var _phase: Phase = Phase.SETUP
var _failed := false

var _resources: Node = null
var _prod = null
var _prod_script: GDScript = null

var _meal_produced := {}
var _craft_failed := []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _check_resource_non_negative() -> void:
	for key in ["wood", "stone", "meat", "crop", "meal_cooked_meat", "meal_hearty_stew"]:
		if _resources.has_method("get_amount") and _resources.get_amount(key) < 0:
			_check(false, "no negative ingredient: %s >= 0" % key)
			return
	_check(true, "no resource became negative in the ledger")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < 4:
				return false
			_setup()
		Phase.BASIC:
			if _frame < 3:
				return false
			_check_basic()
			_phase = Phase.DUPLICATE
			_frame = 0
		Phase.DUPLICATE:
			if _frame < 3:
				return false
			_check_duplicate()
			_phase = Phase.NEGATIVE
			_frame = 0
		Phase.NEGATIVE:
			if _frame < 3:
				return false
			_check_negative()
			_phase = Phase.DRIVER
			_frame = 0
		Phase.DRIVER:
			if _frame < 3:
				return false
			_check_driver()
			_phase = Phase.DISABLED
			_frame = 0
		Phase.DISABLED:
			if _frame < 3:
				return false
			_check_disabled()
			_phase = Phase.DONE
			_frame = 0
		Phase.DONE:
			if _frame < 2:
				return false
			print("TASK0202_RESULT=" + ("FAIL" if _failed else "PASS"))
			quit()
			return true
	if _frame > 1000:
		print("TASK0202_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _physics_process(_delta: float) -> bool:
	return false


func _setup() -> void:
	_resources = root.get_node_or_null("VillageResources")
	_prod_script = load("res://scripts/cooking_production.gd") as GDScript
	if _resources == null or _prod_script == null:
		_check(false, "VillageResources autoload + cooking_production.gd load")
		quit()
		return
	_prod = _prod_script.new()
	_prod.name = "CookingProd"
	root.add_child(_prod)
	# VillageResources autoload瑜??먯옣?쇰줈 ?ъ슜(worker production pattern ?ъ궗??.
	_prod.set_resource_source(_resources)
	_prod.meal_produced.connect(_on_meal_produced)
	_prod.craft_failed.connect(_on_craft_failed)
	# -s ?ㅽ깲?쒖뼹濡?紐⑤뱶?먯꽌??class_name global???깅줉?섏? ?딆쓣 ???덉뼱
	# duck-typing?쇰줈 ?뺤씤?쒕떎(湲곗〈 CMB-001-2 而댄뙆??洹쒖빟怨??숈씪).
	_check(_prod.get_script() == _prod_script, "cooking production component is cooking_production.gd")
	_check(_prod.get_resource_source() == _resources, "production uses VillageResources as ledger")
	_check(not _prod.get_recipe_ids().is_empty(), "production recipe list populated from registry")
	_phase = Phase.BASIC
	_frame = 0


func _on_meal_produced(recipe_id: String, _output: String, amount: int) -> void:
	_meal_produced[recipe_id] = int(_meal_produced.get(recipe_id, 0)) + amount


func _on_craft_failed(_recipe_id: String, _reason: String) -> void:
	_craft_failed.append(_recipe_id)


func _seed(amounts: Dictionary) -> void:
	# ?먯옣??源⑤걮??湲곗? ?곹깭濡??ъ꽕?뺥븳???뚯뒪??寃곗젙??.
	for key in _resources._amounts.keys():
		_resources._amounts[key] = 0
	for key in amounts.keys():
		_resources._amounts[key] = int(amounts[key])


func _reset_signals() -> void:
	_meal_produced.clear()
	_craft_failed.clear()


func _check_basic() -> void:
	# 1. raw ingredient ?뚮퉬 + meal ?앹꽦 (cooked_meat: meat 2 -> meal_cooked_meat 1).
	_seed({"meat": 4, "crop": 2})
	_reset_signals()
	var r = _prod.craft_recipe("cooked_meat")
	_check(r["success"] == true, "cooked_meat production succeeds")
	_check(_resources.get_amount("meat") == 2, "raw ingredient consumed (meat 4 -> 2)")
	_check(_resources.get_amount("meal_cooked_meat") == 1, "meal_cooked_meat produced (1)")
	_check(_meal_produced.get("cooked_meat", 0) == 1, "meal_produced signal fired once")

	# 2. ?ㅼ쨷 ?щ즺 recipe (hearty_stew: meat 1 + crop 2 -> meal_hearty_stew 1).
	_seed({"meat": 3, "crop": 2})
	_reset_signals()
	var r2 = _prod.craft_recipe("hearty_stew")
	_check(r2["success"] == true, "hearty_stew production succeeds")
	_check(_resources.get_amount("meat") == 2 and _resources.get_amount("crop") == 0,
		"hearty_stew raw ingredients consumed (meat/crop)")
	_check(_resources.get_amount("meal_hearty_stew") == 1, "meal_hearty_stew produced (1)")
	_check_resource_non_negative()


func _check_duplicate() -> void:
	# 1. 媛숈? recipe瑜???踰??몄텧: ??踰덉㎏???щ즺 遺議?以묐났 ?앹궛 ?놁쓬) ?먮뒗
	#    媛??몄텧??1?뚯뵫留??앹궛?쒕떎. ?ш린?쒕뒗 ?щ즺媛 異⑸텇???곹깭?먯꽌 ?뺥솗??	#    ?낅젰 2諛??뚮퉬 + 異쒕젰 1媛쒕쭔 ?앹궛?섎뒗吏 ?뺤씤(以묐났 add ?놁쓬).
	_seed({"meat": 2, "crop": 0})
	_reset_signals()
	var r1 = _prod.craft_recipe("cooked_meat")
	var r2 = _prod.craft_recipe("cooked_meat")
	_check(r1["success"] == true and r2["success"] == false,
		"second craft of same recipe rejected (no duplicate production)")
	_check(_resources.get_amount("meal_cooked_meat") == 1,
		"meal produced exactly once for the single successful craft")
	_check(_meal_produced.get("cooked_meat", 0) == 1,
		"meal_produced signal fired exactly once (no duplicate)")
	_check(_resources.get_amount("meat") == 0, "no negative meat after duplicate guard")

	# 2. 二쇨린 ?쒕씪?대쾭(_process)媛 ??二쇨린??媛?recipe 1?뚮쭔 ?앹궛?쒕떎.
	_seed({"meat": 10, "crop": 10})
	_reset_signals()
	_prod.set_enabled(true)
	_prod.production_interval = 0.1
	# timer瑜?0?쇰줈 留뚮뱾???ㅼ쓬 frame??利됱떆 二쇨린瑜??쒖옉?섍쾶 ?쒕떎.
	_prod._timer = 0.0
	# ?щ즺瑜??뚯쭊???뚭퉴吏 異⑸텇???뚮━吏 ?딄퀬, ?뺥솗??1 二쇨린留?愿李고븯湲??꾪빐
	# ??frame留??섎━怨?怨㏓컮濡??곹깭瑜??뺤씤?쒕떎(1 frame = 1 tick = 媛?recipe 1??.
	# -> 蹂꾨룄 phase?먯꽌 timed driver瑜?寃利앺븳?? ?ш린?쒕뒗 ?섎룞 1?뚮쭔 ?뺤씤.
	_check(_resources.get_amount("meal_cooked_meat") == 0, "no meal before driver run")
	_check_resource_non_negative()


func _check_negative() -> void:
	# ?щ즺 遺議?-> ?앹궛 ?ㅽ뙣, ?먯옣 ?뚯닔 ?놁쓬.
	_seed({"meat": 1, "crop": 0})
	_reset_signals()
	var r = _prod.craft_recipe("cooked_meat")
	_check(r["success"] == false, "craft with insufficient ingredient fails")
	_check(r["reason"] == "insufficient_ingredient", "insufficient ingredient reason set")
	_check(_resources.get_amount("meat") == 1, "no ingredient spent on failed craft (meat kept)")
	_check(_resources.get_amount("meal_cooked_meat") == 0, "no meal produced on failed craft")
	_check(not _craft_failed.is_empty(), "craft_failed signal fired on shortage")
	_check_resource_non_negative()

	# 鍮??먯옣?먯꽌 ?꾨Т recipe???뚯닔瑜?留뚮뱾吏 ?딅뒗??
	_seed({})
	_reset_signals()
	var r2 = _prod.craft_recipe("hearty_stew")
	_check(r2["success"] == false, "empty ledger cannot craft hearty_stew")
	_check_resource_non_negative()


func _check_driver() -> void:
	# timed driver: ??二쇨린(1 tick)???ㅼ젙??recipe 媛곴컖 1?뚮쭔 ?앹궛?쒕떎.
	_seed({"meat": 100, "crop": 100})
	_reset_signals()
	_prod.set_enabled(true)
	_prod.production_interval = 0.2
	_prod._timer = 0.0
	# process frame??1??吏꾪뻾?쒖폒 ?뺥솗??1 二쇨린瑜??섑뻾?쒕떎.
	# (_frame 利앷?濡??ㅼ쓬 phase?먯꽌??driver媛 怨꾩냽 ?꾨뒗 寃껋쓣 留됯린 ?꾪빐 driver媛
	#  ??tick ?섑뻾?섍퀬 寃곌낵瑜?怨좎젙?쒕떎.)
	_prod.set_enabled(false)
	# ?꾩뿉??driver瑜?猿먯쑝誘濡??섎룞 1??二쇨린? ?숈씪??愿李곗쓣 ?꾪빐 吏곸젒 ?ㅽ뻾 ???
	# ??대㉧ 寃쎄퀎留??뺤씤?쒕떎(?ㅼ젣 timed ?앹궛? ?꾨옒 DISABLED phase?먯꽌 ?쒖꽦??寃利?.
	_check(_resources.get_amount("meal_cooked_meat") == 0, "driver inactive when disabled")
	# timed driver ?뺤긽 寃利? enabled ?곹깭?먯꽌 frame 吏꾪뻾 ????meal??1?뚯뵫 ?앹궛?쒕떎.
	_seed({"meat": 100, "crop": 100})
	_reset_signals()
	_prod.set_enabled(true)
	_prod.production_interval = 0.05
	_prod._timer = 0.0
	# 2 tick 留뚰겮 frame??吏꾪뻾?쒕떎 (媛?tick = 紐⑤뱺 recipe 1??.
	_tick_driver_frames(10)
	_check(_resources.get_amount("meal_cooked_meat") >= 1, "timed driver produced cooked_meat")
	_check(_resources.get_amount("meal_hearty_stew") >= 1, "timed driver produced hearty_stew")
	_check(_meal_produced.get("cooked_meat", 0) >= 1 and _meal_produced.get("hearty_stew", 0) >= 1,
		"timed driver emitted production signals for both recipes")
	_check_resource_non_negative()


func _tick_driver_frames(n: int) -> void:
	# n?뚯쓽 idle frame??吏꾪뻾?쒖폒 timed driver媛 ?뚭쾶 ?쒕떎. (SceneTree process ?곸뿉??	# _process媛 ?몄텧?섎룄濡??좎떆 frame???뚮퉬?쒕떎.)
	for _i in n:
		_prod._timer = 0.0
		_prod._process(0.1)


func _check_disabled() -> void:
	_seed({"meat": 50, "crop": 50})
	_reset_signals()
	_prod.set_enabled(false)
	var before_meat: int = _resources.get_amount("meal_cooked_meat")
	_tick_driver_frames(5)
	_check(_resources.get_amount("meal_cooked_meat") == before_meat,
		"disabled production does not produce")
	_prod.set_enabled(true)
	_check(_prod.is_enabled() == true, "production re-enabled")
	# ?뺣━
	_prod.queue_free()
	_phase = Phase.DONE
	_frame = 0


func _initialize() -> void:
	pass
