extends SceneTree

## TASK-018-4: Food Regression test.
## Food economy foundation(TASK-018-1/2/3) 회귀 검증:
## - DAY 반복 consumption: 연속 DAY 진입마다 정확히 1회 소비 tick, NIGHT 진입은 무소비.
## - Worker/Mercenary population change: 주민/용병 인구 증감이 demand/소비에 반영.
## - raw fallback: Food 부족 시 raw edible fallback.
## - shortage: 둘 다 부족 시 shortage 상태/수량 기록, stock 음수 없음.
## - save/load stock persistence: 영구 Save/Load가 없다는 정책(기존)을 확인하고,
##   세션 내 DAY tick 간 stock이 리셋되지 않고 유지(persistence)됨을 검증.
## - DAY/NIGHT 회귀: DAY 진입 소비만 존재하고 NIGHT/대기 frame은 무변화.
## - 기존 Wood/Stone 영향 없음: Food 소비/적재가 wood/stone을 건드리지 않음.

enum TestPhase {
	SETUP, DAY_REPEAT, POP_CHANGE, RAW_FALLBACK, SHORTAGE, STOCK_PERSISTENCE,
	DAY_NIGHT_REGRESSION, IDLE_STABLE, WOOD_STONE, DONE
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

var _w1: WorkerData = null
var _w2: WorkerData = null
var _m1: MercenaryData = null

var _tick_events: Array = []


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
	print("TASK0184_RESULT=" + ("FAIL" if _failed else "PASS"))
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


func _setup_population_3() -> void:
	_w1 = _make_worker("rw1", "RWorker1")
	_w2 = _make_worker("rw2", "RWorker2")
	_m1 = _make_mercenary("rm1", "RMerc1")
	_worker_roster.add_worker(_w1)
	_worker_roster.add_worker(_w2)
	_merc_roster.add_mercenary(_m1)


## DAY → NIGHT → DAY 로 1 cycle 진행하고 DAY 진입에서 소비 tick이 1회 발생함을
## 검증한다. 반환: 해당 DAY tick의 결과 Dictionary(또는 빈 Dictionary).
func _advance_one_day(day_before: int) -> Dictionary:
	var tick_base: int = _tick_events.size()
	var stew_before: int = _res.get_food("stew")
	_gt.advance(_gt.get_phase_duration() + 1.0)
	_check(_gt.get_phase() == _gt.Phase.NIGHT, "DAY/NIGHT: advance -> NIGHT")
	_check(_tick_events.size() == tick_base, "DAY/NIGHT: no consumption tick on NIGHT entry")
	_check(_res.get_food("stew") == stew_before, "DAY/NIGHT: stock unchanged on NIGHT")
	_gt.advance(_gt.get_phase_duration() + 1.0)
	_check(_gt.get_phase() == _gt.Phase.DAY, "DAY/NIGHT: advance -> DAY")
	_check(_gt.get_day_number() == day_before + 1, "DAY/NIGHT: day number advanced by 1")
	_check(_tick_events.size() == tick_base + 1, "DAY/NIGHT: exactly one consumption tick on DAY entry")
	if _tick_events.is_empty():
		return {}
	return _tick_events.back()


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
			_enter(TestPhase.DAY_REPEAT)
		TestPhase.DAY_REPEAT:
			_clear_food()
			_setup_population_3()
			_check(_pc.get_population_count() == 3, "DAY_REPEAT: population 3 (2 residents + 1 mercenary)")
			_res.add_food("stew", 6)
			var day_before: int = _gt.get_day_number()
			var tick_base: int = _tick_events.size()
			var t1: Dictionary = _advance_one_day(day_before)
			_check(int(t1["day"]) == day_before + 1, "DAY_REPEAT: tick recorded on new day 1")
			_check(int(t1["demand"]) == 6, "DAY_REPEAT: demand 6 (pop 3 * rate 2)")
			_check(int(t1["consumed_cooked"]) == 2, "DAY_REPEAT: stew(eff 3) covers 6 demand with 2 units")
			_check(int(t1["state"]) == _pc.TickState.OK, "DAY_REPEAT: day 1 state OK")
			_check(_res.get_food("stew") == 4, "DAY_REPEAT: day 1 stock 6 -> 4")
			var t2: Dictionary = _advance_one_day(day_before + 1)
			_check(int(t2["day"]) == day_before + 2, "DAY_REPEAT: tick recorded on new day 2")
			_check(int(t2["demand"]) == 6, "DAY_REPEAT: day 2 demand still 6 (population unchanged)")
			_check(_res.get_food("stew") == 2, "DAY_REPEAT: day 2 stock 4 -> 2")
			var t3: Dictionary = _advance_one_day(day_before + 2)
			_check(int(t3["day"]) == day_before + 3, "DAY_REPEAT: tick recorded on new day 3")
			_check(_res.get_food("stew") == 0, "DAY_REPEAT: day 3 stock 2 -> 0")
			_check(_pc.get_tick_state() == _pc.TickState.OK, "DAY_REPEAT: day 3 state OK (exact demand met)")
			_check(_tick_events.size() == tick_base + 3,
				"DAY_REPEAT: exactly 3 consumption ticks over 3 DAYs (no drift)")
			_check(_res.get_food("stew") >= 0 and _res.get_food("berry") >= 0 \
					and _res.get_food("apple") >= 0, "DAY_REPEAT: no negative food stock")
			_enter(TestPhase.POP_CHANGE)
		TestPhase.POP_CHANGE:
			_clear_food()
			_check(_pc.get_population_count() == 3, "POP_CHANGE: baseline population 3")
			_check(_worker_roster.remove_worker(_w2), "POP_CHANGE: remove worker -> population down")
			_check(_pc.get_population_count() == 2, "POP_CHANGE: population 2 after worker removal")
			_res.add_food("stew", 6)
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["population"]) == 2, "POP_CHANGE: tick population reflects removal (2)")
			_check(int(t["demand"]) == 4, "POP_CHANGE: demand 4 (pop 2 * rate 2)")
			_check(int(t["consumed_cooked"]) == 2, "POP_CHANGE: 2 stew covers demand 4 deterministically")
			_check(_res.get_food("stew") == 4, "POP_CHANGE: stew 6 -> 4")
			_check(_worker_roster.assign(_w1, RefCounted.new()),
				"POP_CHANGE: assign worker to a dummy workplace")
			_check(_pc.get_population_count() == 2,
				"POP_CHANGE: worker assignment does not inflate population (dedup)")
			_check(_pc.get_active_worker_count() == 1,
				"POP_CHANGE: assigned worker reported as active worker")
			_worker_roster.unassign(_w1)
			_check(_pc.get_population_count() == 2, "POP_CHANGE: unassign keeps population 2")
			_clear_food()
			var m2: MercenaryData = _make_mercenary("rm2", "RMerc2")
			_check(_merc_roster.add_mercenary(m2), "POP_CHANGE: add mercenary")
			_check(_pc.get_population_count() == 3, "POP_CHANGE: population 3 after mercenary add")
			_res.add_food("stew", 6)
			var t2: Dictionary = _pc.consume_tick()
			_check(int(t2["population"]) == 3, "POP_CHANGE: tick population reflects add (3)")
			_check(int(t2["demand"]) == 6, "POP_CHANGE: demand 6 (pop 3 * rate 2)")
			_check(_res.get_food("stew") == 4, "POP_CHANGE: stew consumed 2 on pop 3 (6 -> 4)")
			_check(_merc_roster.remove_mercenary(m2), "POP_CHANGE: remove mercenary")
			_check(_pc.get_population_count() == 2, "POP_CHANGE: population 2 after mercenary removal")
			_check(_pc.get_active_worker_count() == 0,
				"POP_CHANGE: no assigned worker -> 0 active worker (dedup)")
			_enter(TestPhase.RAW_FALLBACK)
		TestPhase.RAW_FALLBACK:
			_clear_food()
			_res.add_food("stew", 1)
			_res.add_food("berry", 3)
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["demand"]) == 4, "RAW_FALLBACK: demand 4 (population 2)")
			_check(int(t["consumed_cooked"]) == 1, "RAW_FALLBACK: Food consumed first (priority)")
			_check(int(t["consumed_raw"]) == 1, "RAW_FALLBACK: remaining 1 covered by raw berry")
			_check(int(t["shortage"]) == 0, "RAW_FALLBACK: no shortage after raw fallback")
			_check(_pc.get_tick_state() == _pc.TickState.RAW_FALLBACK,
				"RAW_FALLBACK: Food 부족 -> state RAW_FALLBACK")
			_check(_res.get_food("stew") == 0 and _res.get_food("berry") == 2,
				"RAW_FALLBACK: fallback consumes only needed raw units")
			_enter(TestPhase.SHORTAGE)
		TestPhase.SHORTAGE:
			_clear_food()
			_res.add_food("stew", 1)
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["demand"]) == 4, "SHORTAGE: demand 4 (population 2)")
			_check(int(t["consumed_cooked"]) == 1, "SHORTAGE: available stew consumed first")
			_check(int(t["consumed_raw"]) == 0, "SHORTAGE: no raw available to fall back")
			_check(int(t["shortage"]) == 1, "SHORTAGE: shortage = unmet demand 1 explicitly recorded")
			_check(_pc.get_tick_state() == _pc.TickState.SHORTAGE, "SHORTAGE: state SHORTAGE")
			_check(_res.get_food("stew") == 0 and _res.get_food("berry") == 0 \
					and _res.get_food("apple") == 0, "SHORTAGE: stock never goes negative")
			_enter(TestPhase.STOCK_PERSISTENCE)
		TestPhase.STOCK_PERSISTENCE:
			_clear_food()
			_check(not _res.has_method("save_game") and not _res.has_method("load_game"),
				"STOCK_PERSISTENCE: no persistent Save/Load API (existing policy)")
			_res.add_food("stew", 6)
			_res.add_food("berry", 4)
			var day_before: int = _gt.get_day_number()
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_gt.get_day_number() == day_before + 1, "STOCK_PERSISTENCE: one DAY advanced")
			_check(_res.get_food("stew") == 4, "STOCK_PERSISTENCE: stew persists across DAY tick (6 -> 4)")
			_check(_res.get_food("berry") == 4,
				"STOCK_PERSISTENCE: unconsumed raw persists (untouched, no reset)")
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_res.get_food("stew") == 2, "STOCK_PERSISTENCE: stew persists on 2nd DAY (4 -> 2)")
			_check(_res.get_food("berry") == 4, "STOCK_PERSISTENCE: raw persists on 2nd DAY")
			_enter(TestPhase.DAY_NIGHT_REGRESSION)
		TestPhase.DAY_NIGHT_REGRESSION:
			_clear_food()
			_res.add_food("stew", 6)
			var tick_base: int = _tick_events.size()
			var day_before: int = _gt.get_day_number()
			_check(_gt.get_phase() == _gt.Phase.DAY, "DAY/NIGHT_REGRESSION: phase starts DAY")
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_gt.get_phase() == _gt.Phase.NIGHT, "DAY/NIGHT_REGRESSION: DAY -> NIGHT")
			_check(_tick_events.size() == tick_base, "DAY/NIGHT_REGRESSION: no tick on NIGHT entry")
			_gt.advance(_gt.get_phase_duration() + 1.0)
			_check(_gt.get_phase() == _gt.Phase.DAY, "DAY/NIGHT_REGRESSION: NIGHT -> DAY")
			_check(_tick_events.size() == tick_base + 1, "DAY/NIGHT_REGRESSION: one tick on DAY entry")
			_check(_res.get_food("stew") == 4, "DAY/NIGHT_REGRESSION: single cycle consumed 2 (6 -> 4)")
			_check(_gt.get_day_number() == day_before + 1, "DAY/NIGHT_REGRESSION: day incremented")
			_enter(TestPhase.IDLE_STABLE)
		TestPhase.IDLE_STABLE:
			if _elapsed() < 12:
				return false
			_check(_res.get_food("stew") == 4,
				"DAY/NIGHT_REGRESSION: no per-frame consumption while idle")
			_check(_tick_events.size() == 10,
				"DAY/NIGHT_REGRESSION: no extra consumption tick while idle")
			_enter(TestPhase.WOOD_STONE)
		TestPhase.WOOD_STONE:
			_clear_food()
			_res.add("wood", 10)
			_res.add("stone", 5)
			_res.add_food("stew", 6)
			var wood_before: int = _res.get_amount("wood")
			var stone_before: int = _res.get_amount("stone")
			var t: Dictionary = _pc.consume_tick()
			_check(int(t["demand"]) == 4, "WOOD_STONE: demand 4 (population 2)")
			_check(_res.get_amount("wood") == wood_before,
				"WOOD_STONE: wood untouched by food consumption")
			_check(_res.get_amount("stone") == stone_before,
				"WOOD_STONE: stone untouched by food consumption")
			_res.add_food("berry", 3)
			_res.remove_food("berry", 1)
			_check(_res.get_amount("wood") == wood_before,
				"WOOD_STONE: food add/remove does not touch wood")
			_check(_res.get_amount("stone") == stone_before,
				"WOOD_STONE: food add/remove does not touch stone")
			_res.add("wood", 3)
			_res.add("stone", 2)
			_check(_res.get_amount("wood") == wood_before + 3,
				"WOOD_STONE: wood still addable normally")
			_check(_res.get_amount("stone") == stone_before + 2,
				"WOOD_STONE: stone still addable normally")
			_check(_food_total() >= 0, "WOOD_STONE: food total never negative")
			_enter(TestPhase.DONE)
		TestPhase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0184_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	pass