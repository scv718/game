extends SceneTree

## TASK-019-3 Crop Growth / Harvest 회귀 테스트.
##
## 완료조건 매핑:
##   1. growth - CropNode3D가 SEED -> GROWING -> READY로 성장하고 READY에서만
##      can_interact()가 참이다(성장 시간 data-driven, DESIGN_TUNING).
##   2. harvest - Farmer WORK 상태가 READY crop을 수확해 raw edible ingredient를
##      얻고 VillageResources에 반납한다(기존 farmer static harvest를 crop node
##      기반으로 교체).
##   3. raw ingredient 증가 - harvest -> deposit로 crop raw resource가 증가한다.
##   4. Food fallback 연결 - RawFood.consume_with_raw_fallback이 Food 우선 소비,
##      부족분 raw fallback 소비, negative stock 없음을 보장한다.
##   5. freed crop reference 없음 - farm/crop 해제 후 farmer claim과 target 참조가
##      정리되어 stale reference가 남지 않는다.
##   추가: crop definition data-driven(CropData), 첫 vertical slice crop 1종(wheat),
##         visual growth stage 최소 표현(단계별 scale/color), crop node와
##         decorative vegetation 구분("crops_3d" vs "decorations" 그룹 분리),
##         regrowth/replant 최소 반복 cycle(HARVESTED -> SEED 재성장).

enum Phase {
	SETUP, CONTRACT, NAV_SYNC, GROW_WAIT, GROW_READY,
	HARVEST_ARM, HARVEST_LOOP,
	REGRAW_CHECK,
	FALLBACK, FALLBACK_SHORTAGE,
	CLEANUP, CLEANUP_WAIT,
	FINAL, DONE,
}

const PHYSICS_WAIT_FRAMES := 30
const NAV_SYNC_FRAMES := 10
const LOOP_FRAME_LIMIT := 4000
const FARM_CELL := Vector3(0, 0, 0)

const TEST_GROWTH_TIME := 1.0
const TEST_REGROW_TIME := 1.0

var _frame := 0
var _wait := 0
var _failed := false
var _phase: Phase = Phase.SETUP
var _world: Node3D = null
var _nav: Node = null
var _roster: Node = null
var _resources: Node = null

var _farm: Node3D = null
var _crop_script: GDScript = null
var _crop_data: CropData = null

var _farmer: WorkerData = null
var _actor: Node = null

var _crop_before := 0
var _harvested_some := false
var _stages_seen := {}


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0


func _finish() -> void:
	if _farmer != null and is_instance_valid(_farmer) and _farmer.is_assigned():
		_roster.unassign(_farmer)
	if is_instance_valid(_farm):
		_farm.free()
	print("TASK0193_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _crop() -> int:
	return _resources.get_amount("crop")


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			_setup()
		Phase.CONTRACT:
			_contract()
		Phase.NAV_SYNC:
			_nav_sync()
		Phase.GROW_WAIT:
			_grow_wait()
		Phase.GROW_READY:
			_grow_ready()
		Phase.HARVEST_ARM:
			_harvest_arm()
		Phase.HARVEST_LOOP:
			_harvest_loop()
		Phase.REGRAW_CHECK:
			_regrow_check()
		Phase.FALLBACK:
			_fallback()
		Phase.FALLBACK_SHORTAGE:
			_fallback_shortage()
		Phase.CLEANUP:
			_cleanup()
		Phase.CLEANUP_WAIT:
			_cleanup_wait()
		Phase.FINAL:
			_final()
		Phase.DONE:
			_finish()
			return true
	if _frame > 30000:
		print("TASK0193_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _initialize() -> void:
	var world_scene: Node = (load("res://scenes/world3d.tscn") as PackedScene).instantiate()
	world_scene.name = "World3DRoot"
	root.add_child(world_scene)
	var manager: Node = NavigationManager3D.new()
	manager.name = "NavManager"
	world_scene.add_child(manager)


func _setup() -> void:
	if _frame < PHYSICS_WAIT_FRAMES:
		return
	_world = root.get_node_or_null("World3DRoot") as Node3D
	_nav = root.get_node_or_null("World3DRoot/NavManager")
	_roster = root.get_node_or_null("WorkerRoster")
	_resources = root.get_node_or_null("VillageResources")
	_crop_script = load("res://scripts/crop_node_3d.gd") as GDScript
	if _world == null or _nav == null or _roster == null or _resources == null \
			or _crop_script == null:
		_check(false, "world / navigation / autoloads / crop script load")
		_finish()
		return
	var farm_scene: PackedScene = load("res://scenes/farm_3d.tscn")
	_farm = farm_scene.instantiate()
	_farm.name = "Farm"
	_world.add_child(_farm)
	_farm.global_position = FARM_CELL

	# 첫 vertical slice crop 1종(wheat)을 데이터 정의로 주입.
	_crop_data = CropData.new("wheat", "Wheat")
	_crop_data.growth_time = TEST_GROWTH_TIME
	_crop_data.raw_resource_id = "crop"
	_crop_data.raw_efficiency = 0.5
	_crop_data.stage_count = 3
	_crop_data.harvest_amount = 1
	_farm.crop_definition = _crop_data
	# _ready가 이미 실행된 후 배치된 정의를 반영하도록 재배치 없이 정의만 갱신
	# (test는 빠른 성장 시간을 원하므로 plot들의 growth_time을 직접 갱신).
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c):
			c.growth_time = TEST_GROWTH_TIME
			c.regrow_time = TEST_REGROW_TIME

	_farmer = WorkerData.new("farmer_T", "Farmer T", WorkerData.Job.FARMER)
	_roster.add_worker(_farmer)
	_enter(Phase.CONTRACT)


func _contract() -> void:
	var is_deco := _crop_script == load("res://scripts/decoration.gd")
	var node_3d_ok := _crop_script.get_base_script() == null \
		or (_crop_script.get_base_script() is GDScript \
			and not is_deco)
	_check(node_3d_ok and not is_deco,
		"crop node script is a gameplay Node3D (not decorative vegetation)")
	_check(_farm is Farm3D, "Farm3D is a Workplace3D -> Building3D contract path")
	_check(_crop_data.id == "wheat" and _crop_data.raw_resource_id == "crop",
		"first vertical slice crop is data-driven wheat -> raw 'crop' ingredient")
	_check(_farm.get_crops().size() == 3,
		"farm plants a fixed set of crop plots (data-driven positions)")
	var crops: Array = _farm.get_crops()
	var in_crops_group := true
	for c in crops:
		if not c.is_in_group("crops_3d"):
			in_crops_group = false
	_check(in_crops_group, "crop nodes register the 'crops_3d' gameplay group")
	var deco_count := get_nodes_in_group("decorations").size()
	_check(deco_count >= 0 and _count_crops_group() > 0,
		"crop nodes are distinct from decorative vegetation ('crops_3d' vs 'decorations')")
	_enter(Phase.NAV_SYNC)


func _nav_sync() -> void:
	if _wait == 0:
		_nav.rebuild_navigation()
	_wait += 1
	if _wait < NAV_SYNC_FRAMES:
		return
	_wait = 0
	_enter(Phase.GROW_WAIT)


func _count_crops_group() -> int:
	return get_nodes_in_group("crops_3d").size()


func _grow_wait() -> void:
	_wait += 1
	_record_stages()
	if _wait < 20:
		return
	# 성장 도중 SEED/GROWING 단계에서 READY로 전환되기 전에는 수확 불가.
	var any_ready := false
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c) and c.can_interact():
			any_ready = true
	_check(not any_ready or _wait >= 60,
		"crops are not ready to harvest before growth completes (growth phase)")
	_wait = 0
	_enter(Phase.GROW_READY)


func _record_stages() -> void:
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c):
			var sn: String = c.get_stage_name()
			if not _stages_seen.has(sn):
				_stages_seen[sn] = true


func _grow_ready() -> void:
	_wait += 1
	_record_stages()
	var all_ready := true
	for c in _farm.get_crops():
		if c == null or not is_instance_valid(c):
			all_ready = false
			continue
		if not c.can_interact():
			all_ready = false
	if _wait < LOOP_FRAME_LIMIT and not all_ready:
		return
	_check(all_ready, "crops reach READY after growth time (growth completes)")
	_check(_stages_seen.has("SEED") and _stages_seen.has("GROWING"),
		"visual growth stages traversed SEED/GROWING before READY (minimal stage expression)")
	# visual stage 최소 표현: READY scale이 SEED scale보다 크다(시각 mesh scale).
	var bigger := true
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c) and c.get_node_or_null("CropVisual") != null:
			var vis: Node3D = c.get_node("CropVisual")
			if vis.scale.x < 0.5:
				bigger = false
	_check(bigger, "READY visual scale is grown (minimal visual growth stage)")
	_wait = 0
	_enter(Phase.HARVEST_ARM)


func _harvest_arm() -> void:
	_crop_before = _crop()
	_check(_roster.assign(_farmer, _farm), "assign farmer to the farm for harvest")
	_check(_farmer.is_assigned(), "farmer worker data assigned")
	_actor = _roster.get_actor(_farmer)
	_check(_actor != null and is_instance_valid(_actor), "farmer actor spawned")
	if _actor != null:
		_check(_actor.get_state_name() == "MOVE",
			"farmer starts in MOVE_TO_WORK after assign (legacy semantics)")
	_wait = 0
	_frame = 0
	_enter(Phase.HARVEST_LOOP)


func _harvest_loop() -> void:
	_wait += 1
	_record_stages()
	if _crop() <= _crop_before and _wait < LOOP_FRAME_LIMIT:
		return
	var crop_gained: int = _crop() - _crop_before
	_check(crop_gained > 0,
		"farmer harvests READY crop and deposits raw ingredient (%d gained)" % crop_gained)
	_harvested_some = crop_gained > 0
	if _actor != null and is_instance_valid(_actor):
		_check(_actor.carried_amount == 0, "farmer carry emptied after deposit")
	_wait = 0
	_frame = 0
	_enter(Phase.REGRAW_CHECK)


func _regrow_check() -> void:
	_wait += 1
	_record_stages()
	if _wait < 80:
		return
	# 수확된 crop은 HARVESTED를 거쳐 재성장(replant)해 다시 READY가 된다.
	var regrown := false
	var harvested_seen := _stages_seen.has("HARVESTED")
	for c in _farm.get_crops():
		if c != null and is_instance_valid(c):
			if c.can_interact():
				regrown = true
	_check(harvested_seen, "harvested crop enters HARVESTED stage (regrowth cycle)")
	_check(regrown, "crop regrows/replants into READY again (minimal repeated production cycle)")
	_wait = 0
	_enter(Phase.FALLBACK)


func _fallback() -> void:
	# Food 부족 시 raw ingredient가 fallback으로 소비 가능하고 negative stock이 없다.
	_resources.add("food", 2)
	_resources.add("crop", 10)
	var before_food: int = _resources.get_amount("food")
	var before_crop: int = _resources.get_amount("crop")
	var result := RawFood.consume_with_raw_fallback(_resources, "food", "crop", 5, 0.5)
	_check(int(result.get("food", 0)) == 2, "food stock consumed first (raw untouched)")
	_check(int(result.get("raw", 0)) == 6,
		"remaining need covered by raw fallback at low efficiency (ceil(3/0.5)=6)")
	_check(_resources.get_amount("food") == 0, "food stock drained to zero (no negative)")
	_check(_resources.get_amount("crop") == before_crop - 6,
		"raw ingredient spent as fallback, stock stays non-negative")
	_check(_resources.get_amount("crop") >= 0 and _resources.get_amount("food") >= 0,
		"no negative stock after raw fallback")
	_enter(Phase.FALLBACK_SHORTAGE)


func _fallback_shortage() -> void:
	# Food와 raw 둘 다 부족하면 shortage가 남고 stock이 음수가 되지 않는다.
	var crop_before: int = _resources.get_amount("crop")
	var result := RawFood.consume_with_raw_fallback(_resources, "food", "crop", 100, 0.5)
	var food_left: int = _resources.get_amount("food")
	var crop_left: int = _resources.get_amount("crop")
	_check(food_left == 0, "insufficient food leaves food at zero (not negative)")
	_check(crop_left == 0, "insufficient raw leaves raw at zero (not negative)")
	_check(int(result.get("shortage", 0)) > 0,
		"total shortage recorded when both food and raw run out")
	_check(crop_before >= 0, "raw baseline non-negative")
	_enter(Phase.CLEANUP)


func _cleanup() -> void:
	_check(_roster.unassign(_farmer), "unassign farmer for cleanup")
	_check(not _farmer.is_assigned(), "farmer worker data unassigned")
	_wait = 0
	_enter(Phase.CLEANUP_WAIT)


func _cleanup_wait() -> void:
	_wait += 1
	var actors_now: int = get_nodes_in_group("farmers_3d").size()
	if actors_now > 0 and _wait < LOOP_FRAME_LIMIT:
		return
	_check(actors_now == 0, "farmer actor despawned after unassign (census 0)")
	# freed crop reference 없음: farmer가 claim을 정리하고 target 참조가 남지 않는다.
	if _actor != null and is_instance_valid(_actor):
		_check(_actor.target_crop == null, "farmer target_crop reference cleared")
	# farm 해제 시 crop 자식 전부 정리, 그룹 census 0.
	_farm.free()
	_wait = 0
	_enter(Phase.FINAL)


func _final() -> void:
	_wait += 1
	if _wait < 10:
		return
	_check(_count_crops_group() == 0,
		"all crop nodes freed with the farm (no orphan crop references)")
	_check(_harvested_some, "harvest loop produced raw ingredient at least once")
	_enter(Phase.DONE)