extends SceneTree

## TASK-018-1: Food Data / Village Resource Integration test.
## Verifies the VillageResources autoload Food-layer data/API meets the requirements:
## - Food stock add/remove/query.
## - raw edible ingredient category / query.
## - consumption efficiency metadata.
## - cooked meal category extension point exists.
## - no negative stock.
## - resource UI event (changed) can be connected.

enum TestPhase {
	SETUP, ADD_QUERY, CATEGORY, EFFICIENCY, REMOVE_NEGATIVE, SIGNAL, DONE
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _phase_start := 0
var _failed := false
var _res: Node = null
var _signal_events: Array = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: TestPhase) -> void:
	_phase = new_phase
	_phase_start = _frame


func _elapsed() -> int:
	return _frame - _phase_start


func _finish() -> void:
	print("TASK0181_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _on_changed(resource_id: String, _amount: int) -> void:
	_signal_events.append(resource_id)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < 8:
				return false
			_res = root.get_node_or_null("VillageResources")
			_check(_res != null, "VillageResources autoload exists")
			if _res == null:
				_enter(TestPhase.DONE)
				return false
			_res.changed.connect(_on_changed)
			_enter(TestPhase.ADD_QUERY)
		TestPhase.ADD_QUERY:
			_check(_res.is_food("berry"), "berry is a known food item")
			_check(_res.is_food("apple"), "apple is a known food item")
			_check(not _res.is_food("wood"), "wood is not a food item")
			_check(not _res.is_food("nonexistent"), "unknown id is not food")
			_check(_res.get_food("berry") == 0, "food starts at 0")
			_check(_res.add_food("berry", 5), "add_food berry 5 succeeds")
			_check(_res.get_food("berry") == 5, "berry stock is 5")
			_check(_res.get_amount("berry") == 5, "food integrates with base resource amount")
			_check(_res.add_food("berry", 3), "add_food berry 3 succeeds")
			_check(_res.get_food("berry") == 8, "berry stock accumulates to 8")
			_enter(TestPhase.CATEGORY)
		TestPhase.CATEGORY:
			_check(_res.is_raw_edible("berry"), "berry is raw edible")
			_check(_res.is_raw_edible("apple"), "apple is raw edible")
			_check(_res.get_food_category("berry") == _res.FoodCategory.RAW_EDIBLE, "berry category is RAW_EDIBLE")
			_check(_res.get_food_category("apple") == _res.FoodCategory.RAW_EDIBLE, "apple category is RAW_EDIBLE")
			_check(not _res.is_cooked("berry"), "berry is not a cooked meal")
			_check(_res.get_food_category("nonexistent") == -1, "unknown food category is -1")
			var raw_ids: Array = _res.get_raw_edible_food_ids()
			_check(raw_ids.has("berry") and raw_ids.has("apple"), "raw edible query lists raw items")
			_check(_res.FoodCategory.COOKED_MEAL > _res.FoodCategory.RAW_EDIBLE, "cooked meal category extension point exists")
			_enter(TestPhase.EFFICIENCY)
		TestPhase.EFFICIENCY:
			_check(_res.get_food_efficiency("berry") > 0, "raw food has efficiency metadata")
			_check(_res.get_food_efficiency("apple") > 0, "apple has efficiency metadata")
			_check(_res.get_food_efficiency("nonexistent") == 0, "unknown food efficiency is 0")
			_enter(TestPhase.REMOVE_NEGATIVE)
		TestPhase.REMOVE_NEGATIVE:
			_check(_res.remove_food("berry", 3), "remove_food 3 succeeds")
			_check(_res.get_food("berry") == 5, "berry stock decreases to 5")
			_check(not _res.remove_food("berry", 100), "over-spend remove rejected")
			_check(_res.get_food("berry") >= 0, "no negative food stock on over-spend")
			_check(_res.remove_food("berry", 5), "remove remaining succeeds")
			_check(_res.get_food("berry") == 0, "berry stock reaches 0 without negative")
			_check(not _res.remove_food("berry", 1), "remove from empty rejected")
			_check(_res.get_food("berry") == 0, "empty stock stays 0 (no negative)")
			_check(not _res.add_food("wood", 1), "cannot add food for non-food id")
			_check(not _res.remove_food("wood", 1), "cannot remove food for non-food id")
			_check(_res.get_amount("wood") == 0, "wood stock unaffected by food api")
			_enter(TestPhase.SIGNAL)
		TestPhase.SIGNAL:
			var before: int = _signal_events.size()
			_res.add_food("apple", 2)
			_check(_signal_events.size() == before + 1, "add_food emits changed event")
			_res.remove_food("apple", 1)
			_check(_signal_events.size() == before + 2, "remove_food emits changed event")
			_check(_signal_events[before] == "apple", "changed event carries food id")
			_enter(TestPhase.DONE)
		TestPhase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0181_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	pass