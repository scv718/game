extends SceneTree

## TASK-018-3: Food HUD / Shortage Feedback test.
## 3D Main World를 부팅해 실제 HUD 위에서 검증한다.
## - FoodLabel이 총 Food 재고를 Wood/Stone과 구분된 라벨로 표시/갱신.
## - PopulationConsumption consume_tick 결과에 따라 Food 경고가 표시된다:
##   SHORTAGE → 명확한 부족 경고, RAW_FALLBACK → 비효율 raw 소비 안내, OK → 숨김.
## - DAY 진입 소비 tick과 HUD 연동(Food label + 경고 갱신).
## - UI가 world input을 차단해야 하는 기존 규칙 유지: StatusPanel은 STOP(차단),
##   FoodWarningLabel은 IGNORE(안내성 Label이 월드 입력을 추가 차단하지 않음).

enum TestPhase {
	SETUP, HUD_NODES, FOOD_LABEL, SHORTAGE, RAW_FALLBACK, OK, DAY_TICK, INPUT_RULE, DONE
}

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"
const SETTLE_FRAMES := 8

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _phase_start := 0
var _wait := 0
var _failed := false

var _main: Node = null
var _hud: Node = null
var _res: Node = null
var _pc: Node = null
var _gt: Node = null
var _worker_roster: Node = null
var _merc_roster: Node = null

var _food_label: Label = null
var _food_warning_label: Label = null
var _wood_label: Label = null
var _stone_label: Label = null
var _status_panel: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(new_phase: TestPhase) -> void:
	_phase = new_phase
	_phase_start = _frame
	_wait = 0


func _elapsed() -> int:
	return _frame - _phase_start


func _finish() -> void:
	print("TASK0183_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _clear_food() -> void:
	for food_id in _res.FOOD_DEFS.keys():
		var amt: int = _res.get_food(food_id)
		if amt > 0:
			_res.remove_food(food_id, amt)


func _food_total() -> int:
	var total := 0
	for food_id in _res.FOOD_DEFS.keys():
		total += _res.get_food(food_id)
	return total


func _make_worker(id: String, name: String) -> WorkerData:
	return WorkerData.new(id, name, WorkerData.Job.LUMBERJACK)


func _make_mercenary(id: String, name: String) -> MercenaryData:
	return MercenaryData.new(id, name, MercenaryData.MercClass.SWORDSMAN)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		TestPhase.SETUP:
			if _frame < SETTLE_FRAMES:
				return false
			_res = root.get_node_or_null("VillageResources")
			_pc = root.get_node_or_null("PopulationConsumption")
			_gt = root.get_node_or_null("GameTime")
			_worker_roster = root.get_node_or_null("WorkerRoster")
			_merc_roster = root.get_node_or_null("MercenaryRoster")
			_main = root.get_node_or_null("Main3D")
			_check(_res != null, "VillageResources autoload exists")
			_check(_pc != null, "PopulationConsumption autoload exists")
			_check(_gt != null, "GameTime autoload exists")
			_check(_main != null, "3D Main World boots from main scene")
			if _main == null:
				_enter(TestPhase.DONE)
				return false
			_gt.set_auto_advance(false)
			_enter(TestPhase.HUD_NODES)
		TestPhase.HUD_NODES:
			_hud = _main.get_node_or_null("HUD")
			_status_panel = _hud.get_node_or_null("StatusPanel") if _hud != null else null
			_food_label = _hud.get_node_or_null("StatusPanel/FoodLabel") as Label \
					if _hud != null else null
			_food_warning_label = _hud.get_node_or_null("FoodWarningLabel") as Label \
					if _hud != null else null
			_wood_label = _hud.get_node_or_null("StatusPanel/WoodLabel") as Label \
					if _hud != null else null
			_stone_label = _hud.get_node_or_null("StatusPanel/StoneLabel") as Label \
					if _hud != null else null
			_check(_hud != null, "HUD exists in Main3D")
			_check(_status_panel != null, "StatusPanel intact")
			_check(_food_label != null, "FoodLabel exists in HUD")
			_check(_food_warning_label != null, "FoodWarningLabel exists in HUD")
			_check(_wood_label != null and _stone_label != null, "Wood/Stone labels intact")
			_check(_food_label != null and _food_label.text == "Food: 0",
				"Food label starts at total 0 (text=%s)" % (_food_label.text if _food_label else "none"))
			_check(_food_warning_label != null and not _food_warning_label.visible,
				"Food warning hidden before any consumption tick")
			_enter(TestPhase.FOOD_LABEL)
		TestPhase.FOOD_LABEL:
			_res.add_food("berry", 3)
			_res.add_food("apple", 2)
			_check(_food_label.text == "Food: 5", "Food label sums food stock (text=%s)" % _food_label.text)
			_res.add("wood", 7)
			_res.add("stone", 4)
			_check(_wood_label.text == "Wood: 7", "Wood HUD still works (text=%s)" % _wood_label.text)
			_check(_stone_label.text == "Stone: 4", "Stone HUD still works (text=%s)" % _stone_label.text)
			_check(_food_label.text == "Food: 5", "Food label unaffected by Wood/Stone change")
			_res.remove_food("berry", 1)
			_check(_food_label.text == "Food: 4", "Food label updates on food removal (text=%s)" % _food_label.text)
			_enter(TestPhase.SHORTAGE)
		TestPhase.SHORTAGE:
			_clear_food()
			var w1: WorkerData = _make_worker("w1", "Worker1")
			var w2: WorkerData = _make_worker("w2", "Worker2")
			var m1: MercenaryData = _make_mercenary("m1", "Merc1")
			_check(_worker_roster.add_worker(w1), "add worker 1")
			_check(_worker_roster.add_worker(w2), "add worker 2")
			_check(_merc_roster.add_mercenary(m1), "add mercenary 1")
			_check(_pc.get_population_count() == 3, "population 3 (residents 2 + mercenary 1)")
			_res.add_food("stew", 1)
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["state"]) == _pc.TickState.SHORTAGE, "tick state SHORTAGE")
			_check(int(t["shortage"]) == 3, "shortage amount 3 recorded")
			_check(_food_warning_label.visible, "shortage warning visible")
			_check(_food_warning_label.text == "Food Shortage: -3 today",
				"shortage warning text clear (text=%s)" % _food_warning_label.text)
			_check(_food_label.text == "Food: 0", "food label reflects consumed stock (text=%s)" % _food_label.text)
			_enter(TestPhase.RAW_FALLBACK)
		TestPhase.RAW_FALLBACK:
			_clear_food()
			_res.add_food("stew", 1)
			_res.add_food("berry", 3)
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["state"]) == _pc.TickState.RAW_FALLBACK, "tick state RAW_FALLBACK")
			_check(int(t["consumed_raw"]) == 3, "raw fallback consumed 3 raw berry")
			_check(_food_warning_label.visible, "raw fallback warning visible")
			_check(_food_warning_label.text.begins_with("Raw ingredients eaten:")
					and _food_warning_label.text.contains("low efficiency"),
				"raw fallback warning notes low efficiency (text=%s)" % _food_warning_label.text)
			_check(_food_label.text == "Food: 0", "raw fallback consumes stock to 0 (text=%s)" % _food_label.text)
			_enter(TestPhase.OK)
		TestPhase.OK:
			_clear_food()
			_res.add_food("stew", 6)
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["state"]) == _pc.TickState.OK, "tick state OK")
			_check(not _food_warning_label.visible, "warning hidden on OK tick")
			_check(_food_label.text == "Food: 4", "food label after OK consumption (text=%s)" % _food_label.text)
			_enter(TestPhase.DAY_TICK)
		TestPhase.DAY_TICK:
			_clear_food()
			_res.add_food("stew", 6)
			var day_before: int = _gt.get_day_number()
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_gt.get_phase() == _gt.Phase.NIGHT, "advance -> NIGHT (no DAY tick yet)")
			_check(_res.get_food("stew") == 6, "no consumption on NIGHT entry")
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_gt.get_phase() == _gt.Phase.DAY, "advance -> DAY")
			_check(_gt.get_day_number() == day_before + 1, "day advanced by 1")
			_check(_res.get_food("stew") == 4, "DAY tick consumed stew (6 -> 4)")
			_check(_food_label.text == "Food: 4", "DAY tick reflected in Food label (text=%s)" % _food_label.text)
			_check(not _food_warning_label.visible, "DAY tick OK -> warning hidden")
			_clear_food()
			_res.add_food("stew", 1)
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_gt.get_phase() == _gt.Phase.DAY, "advance -> DAY (shortage case)")
			_check(_food_warning_label.visible, "DAY tick shortage -> warning visible")
			_check(_food_warning_label.text.begins_with("Food Shortage:"),
				"DAY tick shortage warning text (text=%s)" % _food_warning_label.text)
			_check(_food_label.text == "Food: 0", "DAY tick shortage consumes stock (text=%s)" % _food_label.text)
			_enter(TestPhase.INPUT_RULE)
		TestPhase.INPUT_RULE:
			_check(_status_panel is Control and (_status_panel as Control).mouse_filter \
					== Control.MOUSE_FILTER_STOP,
				"StatusPanel keeps MOUSE_FILTER_STOP (UI blocks world input rule maintained)")
			_check(_food_warning_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"FoodWarningLabel is MOUSE_FILTER_IGNORE (no extra world input blocking)")
			_check(_food_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"FoodLabel is MOUSE_FILTER_IGNORE (informational only)")
			_enter(TestPhase.DONE)
		TestPhase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0183_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	if packed != null:
		_main = packed.instantiate()
		_main.name = "Main3D"
		root.add_child(_main)