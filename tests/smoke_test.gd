extends SceneTree

## SMOKE / regression baseline for the 3D-migrated project.
## The project moved from 2D to a Stylized Top-down 3D runtime and the main scene
## is now main_3d.tscn, so this regression boots the 3D Main World and verifies the
## core foundations (World / Camera / Content / Core Buildings / Navigation /
## VillageResources) are composed correctly.
##
## Checks:
##   1. project main scene = main_3d.tscn (entry point).
##   2. 3D Main World boots (Main3D / World3D).
##   3. exactly one Camera3D, no legacy 2D Actor/Collision/Nav nodes.
##   4. no runtime player Actor (design lock).
##   5. WorldContent3D composes 60 trees + a StoneDeposit deterministically.
##   6. all five core buildings (Keep/Tavern/Inn/Grocery/Equipment) exist once.
##   7. NavigationManager3D finished its initial bake.
##   8. camera/selection/placement/HUD/map services are wired.
##   9. VillageResources autoload + TASK-018-1 Food data (stock/raw edible/
##      efficiency/cooked extension/no negative stock/changed event) works.
##  10. PopulationConsumption autoload + TASK-018-2 consumption tick present and
##      safe in the booted world (explicit demand/shortage/population, no negative).

enum Phase { SETUP, INSTANCE_WAIT, AUDIT, FOOD_AUDIT, CONSUMPTION_AUDIT, DONE }

const MAIN_SCENE_PATH := "res://scenes/main_3d.tscn"

const SETTLE_FRAMES := 8

var _frame := 0
var _phase: Phase = Phase.SETUP
var _wait := 0
var _failed := false

var _main: Node = null
var _world: Node = null
var _content: Node = null
var _resources: Node = null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		print("FAIL: " + msg)
		_failed = true


func _enter(p: Phase) -> void:
	_phase = p
	_wait = 0


func _group_count(group_name: String) -> int:
	return get_nodes_in_group(group_name).size()


func _iterate_tree(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_iterate_tree(child))
	return out


func _finish() -> void:
	print("SMOKE_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit()


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		Phase.SETUP:
			if _frame < SETTLE_FRAMES:
				return false
			_resources = root.get_node_or_null("VillageResources")
			_check(_resources != null, "VillageResources autoload exists")
			_enter(Phase.INSTANCE_WAIT)
		Phase.INSTANCE_WAIT:
			if _wait == 0:
				var packed: PackedScene = load(MAIN_SCENE_PATH)
				_main = packed.instantiate()
				_main.name = "Main3D"
				root.add_child(_main)
			if _wait < SETTLE_FRAMES:
				_wait += 1
				return false
			_world = root.get_node_or_null("Main3D/World3D")
			_content = _world.get_node_or_null("WorldContent3D") if _world != null else null
			_enter(Phase.AUDIT)
		Phase.AUDIT:
			_audit()
			_enter(Phase.FOOD_AUDIT)
		Phase.FOOD_AUDIT:
			_food_audit()
			_enter(Phase.CONSUMPTION_AUDIT)
		Phase.CONSUMPTION_AUDIT:
			_consumption_audit()
			_enter(Phase.DONE)
		Phase.DONE:
			_finish()
			return true
	if _frame > 600:
		print("SMOKE_RESULT=TIMEOUT phase=%s" % str(_phase))
		quit()
		return true
	return false


func _audit() -> void:
	_check(String(ProjectSettings.get_setting(
				"application/run/main_scene")) == MAIN_SCENE_PATH,
		"project entry stays on the 3D main scene path")
	_check(_main != null and _world != null,
		"3D Main World boots from the project main scene")
	_check(get_nodes_in_group("player").size() == 0,
		"no runtime player Actor (design lock)")
	var camera_count := 0
	var legacy_2d := 0
	for node in _iterate_tree(root):
		if node is Camera3D:
			camera_count += 1
		if node is Node2D or node is CharacterBody2D or node is Area2D \
				or node is NavigationAgent2D:
			legacy_2d += 1
	_check(camera_count == 1, "exactly one Camera3D drives the runtime view")
	_check(legacy_2d == 0,
		"live runtime holds no 2D Actor/Camera/Collision/Nav nodes (%d)" % legacy_2d)
	_check(_content != null and _content.get_tree_count() == 60 \
			and _group_count("resource_nodes_3d") == 60,
		"WorldContent3D composes exactly 60 tree resource nodes")
	var deposit: Node = _content.get_stone_deposit() if _content != null else null
	_check(deposit != null, "WorldContent3D composes a StoneDeposit")
	var expected := {"keep": 0, "tavern": 0, "inn": 0, "grocery": 0, "equipment": 0}
	for building in get_nodes_in_group("core_buildings_3d"):
		expected[building.get_core_type()] += 1
	var all_once := true
	for t in expected:
		if expected[t] != 1:
			all_once = false
	_check(all_once, "all five core buildings exist exactly once")
	_check(get_nodes_in_group("core_buildings_3d").size() == 5,
		"core buildings register as 3D interactables")
	var nav: Node = _world.get_node_or_null("NavigationManager3D")
	_check(nav != null and nav.nav_rebuild_count >= 1,
		"initial navigation bake covers the composed world")
	_check(get_first_node_in_group("camera_controller_3d") != null \
			and get_first_node_in_group("world_selection_3d") != null \
			and get_first_node_in_group("building_placement_3d") != null \
			and _main.get_node_or_null("HUD") != null \
			and _main.get_node_or_null("WorldMapOverlay") != null,
		"camera/selection/placement/HUD/map services are all wired")


func _food_audit() -> void:
	_check(_resources.is_food("berry") and _resources.is_food("apple"),
		"TASK-018-1: raw edible food items are registered")
	_check(_resources.get_food("berry") == 0, "TASK-018-1: food stock starts at 0")
	_check(_resources.add_food("berry", 4), "TASK-018-1: add_food succeeds")
	_check(_resources.get_food("berry") == 4, "TASK-018-1: food query reflects add")
	_check(_resources.is_raw_edible("berry"), "TASK-018-1: berry is raw edible")
	_check(_resources.get_food_efficiency("berry") > 0,
		"TASK-018-1: raw food has consumption efficiency metadata")
	_check(not _resources.remove_food("berry", 99),
		"TASK-018-1: over-spend remove rejected")
	_check(_resources.get_food("berry") == 4,
		"TASK-018-1: no negative stock on over-spend")
	_check(_resources.remove_food("berry", 4), "TASK-018-1: remove succeeds")
	_check(_resources.get_food("berry") == 0, "TASK-018-1: stock reaches 0 cleanly")


func _food_total() -> int:
	var total := 0
	for food_id in _resources.FOOD_DEFS.keys():
		total += _resources.get_food(food_id)
	return total


func _consumption_audit() -> void:
	var pc: Node = root.get_node_or_null("PopulationConsumption")
	_check(pc != null, "TASK-018-2: PopulationConsumption autoload exists")
	if pc == null:
		return
	var stock_before: int = _food_total()
	var t: Dictionary = pc.consume_tick()
	_check(int(t.get("demand", -1)) >= 0, "TASK-018-2: consumption tick records demand")
	_check(int(t.get("shortage", -1)) >= 0, "TASK-018-2: shortage amount is explicit")
	_check(int(t.get("population", -1)) >= 0, "TASK-018-2: population count is explicit")
	_check(_food_total() == stock_before and stock_before >= 0,
		"TASK-018-2: no negative stock / no spurious spend in fresh boot")


func _initialize() -> void:
	root.size = Vector2i(1152, 648)