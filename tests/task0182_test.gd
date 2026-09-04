extends SceneTree

## TASK-018-2: Population Consumption Tick test.
## Verifies the PopulationConsumption autoload meets the requirements:
## - per-frame 감소 금지 (DAY tick에만 소비, NIGHT 진입/대기 frame은 무변화).
## - 기존 DAY/time tick(GameTime)과 결합 (DAY 진입 시 자동 tick 1회).
## - active resident/worker/mercenary 중복 없는 집계 (Worker는 주민 하위 집합).
## - Food(COOKED_MEAL) 우선 소비, 부족 시 raw edible fallback, 둘 다 부족 → shortage.
## - 인구 0 → consumption 0, 인구 N → deterministic consumption.
## - stock 음수 없음.
## - exact rate는 CONSUMPTION_CONFIG 데이터.

enum TestPhase {
	SETUP, POP_ZERO, DEDUP, DETERMINISTIC, RAW_FALLBACK, SHORTAGE, DAY_TICK, STABLE, DONE
}

var _frame := 0
var _phase: TestPhase = TestPhase.SETUP
var _phase_start := 0
var _failed := false

var _res: Node = null
var _pc: Node = null
var _gt: Node = null
var _worker_roster: Node = null
var _merc_roster: Node = null

var _tick_events: Array = []
var _day_tick_base := 0


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
	print("TASK0182_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _on_tick(_result: Dictionary) -> void:
	_tick_events.append(_result)


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
			if _frame < 8:
				return false
			_res = root.get_node_or_null("VillageResources")
			_pc = root.get_node_or_null("PopulationConsumption")
			_gt = root.get_node_or_null("GameTime")
			_worker_roster = root.get_node_or_null("WorkerRoster")
			_merc_roster = root.get_node_or_null("MercenaryRoster")
			_check(_res != null, "VillageResources autoload exists")
			_check(_pc != null, "PopulationConsumption autoload exists")
			_check(_gt != null, "GameTime autoload exists")
			_check(_worker_roster != null, "WorkerRoster autoload exists")
			_check(_merc_roster != null, "MercenaryRoster autoload exists")
			if _res == null or _pc == null:
				_enter(TestPhase.DONE)
				return false
			_gt.set_auto_advance(false)
			if not _pc.consumption_tick.is_connected(_on_tick):
				_pc.consumption_tick.connect(_on_tick)
			_enter(TestPhase.POP_ZERO)
		TestPhase.POP_ZERO:
			_clear_food()
			var before: int = _food_total()
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["population"]) == 0, "population 0 -> tick")
			_check(int(t["demand"]) == 0, "population 0 -> demand 0")
			_check(int(t["consumed_cooked"]) == 0 and int(t["consumed_raw"]) == 0,
				"population 0 -> consumption 0")
			_check(int(t["shortage"]) == 0, "population 0 -> shortage 0")
			_check(_pc.get_tick_state() == _pc.TickState.OK, "population 0 -> state OK")
			_check(_food_total() == before, "population 0 -> no stock change")
			_enter(TestPhase.DEDUP)
		TestPhase.DEDUP:
			var w1: WorkerData = _make_worker("w1", "Worker1")
			var w2: WorkerData = _make_worker("w2", "Worker2")
			var m1: MercenaryData = _make_mercenary("m1", "Merc1")
			_check(_worker_roster.add_worker(w1), "add worker 1")
			_check(_worker_roster.add_worker(w2), "add worker 2")
			_check(_merc_roster.add_mercenary(m1), "add mercenary 1")
			_check(_pc.get_population_count() == 3,
				"population = residents(2) + mercenaries(1) = 3")
			_check(_pc.get_population_count() != 5, "workers are not double counted")
			_check(_pc.get_active_worker_count() == 0, "no assigned worker yet")
			_check(_pc.get_active_mercenary_count() == 1, "1 alive mercenary active")
			_check(_worker_roster.assign(w1, RefCounted.new()), "assign worker 1 to a workplace")
			_check(_pc.get_active_worker_count() == 1,
				"assigned worker reported as active worker")
			_check(_pc.get_population_count() == 3,
				"worker assignment does not inflate population (dedup)")
			_worker_roster.unassign(w1)
			_enter(TestPhase.DETERMINISTIC)
		TestPhase.DETERMINISTIC:
			_clear_food()
			_res.add_food("stew", 6)
			var t1: Dictionary = _pc.consume_tick()
			_check(int(t1["demand"]) == 6, "population 3 * rate 2 -> demand 6")
			_check(int(t1["consumed_cooked"]) == 2,
				"stew(eff 3) covers 6 demand with 2 units")
			_check(int(t1["consumed_raw"]) == 0, "no raw used when Food sufficient")
			_check(int(t1["shortage"]) == 0, "no shortage when Food sufficient")
			_check(_pc.get_tick_state() == _pc.TickState.OK, "Food sufficient -> state OK")
			_check(_res.get_food("stew") == 4, "stew consumed deterministically (6 -> 4)")
			_check(_res.get_food("berry") == 0 and _res.get_food("apple") == 0,
				"raw ingredients untouched when Food sufficient")
			_res.add_food("stew", 2)
			var t2: Dictionary = _pc.consume_tick()
			_check(int(t2["consumed_cooked"]) == int(t1["consumed_cooked"])
					and int(t2["consumed_raw"]) == int(t1["consumed_raw"])
					and int(t2["shortage"]) == int(t1["shortage"]),
				"deterministic: identical population/stock -> identical result")
			_check(_res.get_food("stew") == 4, "deterministic repeat consumes same amount")
			_enter(TestPhase.RAW_FALLBACK)
		TestPhase.RAW_FALLBACK:
			_clear_food()
			_res.add_food("stew", 1)
			_res.add_food("berry", 3)
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["demand"]) == 6, "demand 6")
			_check(int(t["consumed_cooked"]) == 1, "Food consumed first (priority)")
			_check(int(t["consumed_raw"]) == 3, "remaining 3 covered by raw berry")
			_check(int(t["shortage"]) == 0, "no shortage after raw fallback")
			_check(_pc.get_tick_state() == _pc.TickState.RAW_FALLBACK,
				"Food 부족 -> state RAW_FALLBACK")
			_check(_res.get_food("stew") == 0 and _res.get_food("berry") == 0,
				"fallback consumes stocks down to 0")
			_enter(TestPhase.SHORTAGE)
		TestPhase.SHORTAGE:
			_clear_food()
			_res.add_food("stew", 1)
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["demand"]) == 6, "demand 6")
			_check(int(t["consumed_cooked"]) == 1, "available stew consumed first")
			_check(int(t["consumed_raw"]) == 0, "no raw available to fall back")
			_check(int(t["shortage"]) == 3, "shortage = unmet demand 3 explicitly recorded")
			_check(_pc.get_tick_state() == _pc.TickState.SHORTAGE,
				"둘 다 부족 -> state SHORTAGE")
			_check(_res.get_food("stew") == 0, "stew consumed to 0")
			_check(_res.get_food("stew") >= 0 and _res.get_food("berry") >= 0 \
					and _res.get_food("apple") >= 0, "no negative food stock")
			_enter(TestPhase.DAY_TICK)
		TestPhase.DAY_TICK:
			_clear_food()
			_res.add_food("stew", 6)
			_day_tick_base = _tick_events.size()
			var stew_before: int = _res.get_food("stew")
			var day_before: int = _gt.get_day_number()
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_gt.get_phase() == _gt.Phase.NIGHT, "advance -> NIGHT")
			_check(_tick_events.size() == _day_tick_base, "no consumption on NIGHT entry")
			_check(_res.get_food("stew") == stew_before, "stock unchanged on NIGHT")
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_gt.get_phase() == _gt.Phase.DAY, "advance -> DAY")
			_check(_gt.get_day_number() == day_before + 1, "day advanced by 1")
			_check(_tick_events.size() == _day_tick_base + 1,
				"exactly one consumption tick on DAY entry")
			var last: Dictionary = _pc.get_last_tick()
			_check(int(last["day"]) == day_before + 1, "tick recorded on the new day")
			_check(int(last["population"]) == 3, "DAY tick population 3")
			_check(_res.get_food("stew") == 4, "DAY tick consumed 2 stew (6 -> 4)")
			_check(_res.get_food("berry") == 0, "DAY tick used no raw when Food sufficient")
			_enter(TestPhase.STABLE)
		TestPhase.STABLE:
			if _elapsed() < 12:
				return false
			_check(_res.get_food("stew") == 4, "no per-frame consumption while idle")
			_check(_tick_events.size() == _day_tick_base + 1,
				"no extra consumption tick while idle")
			_enter(TestPhase.DONE)
		TestPhase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0182_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	pass
