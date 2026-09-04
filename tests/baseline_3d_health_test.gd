extends SceneTree

const MAIN_SCENE := "res://scenes/main_3d.tscn"
const ACTOR_SCENES := [
	"res://scenes/lumberjack_3d.tscn",
	"res://scenes/mercenary_3d.tscn",
	"res://scenes/enemy_3d.tscn",
]
const DATA_SCRIPTS := [
	"res://scripts/worker_data.gd",
	"res://scripts/mercenary_data.gd",
]
const REQUIRED_AUTOLOADS := [
	"VillageResources", "GameTime", "WorkerRoster", "MercenaryRoster",
	"FirstEncounterSpawner", "DeathLedger", "ExplorationManager",
]

var _frames := 0
var _failed := false
var _main: Node = null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		print("FAIL: " + message)
		_failed = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_run_load_checks()
	elif _frames == 12:
		_run_runtime_checks()
		_finish()
		return true
	elif _frames > 600:
		print("BASELINE_3D_RESULT=TIMEOUT")
		quit(1)
		return true
	return false


func _run_load_checks() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene", "") == MAIN_SCENE,
		"project main scene is canonical 3D runtime")
	for autoload_name in REQUIRED_AUTOLOADS:
		_check(root.get_node_or_null(autoload_name) != null,
			"critical autoload available: %s" % autoload_name)

	for path in DATA_SCRIPTS:
		var script: Script = load(path)
		_check(script != null, "data script parses: %s" % path)
		if script != null:
			var instance: Variant = script.new()
			_check(instance != null, "data class instantiates: %s" % path)

	var packed: PackedScene = load(MAIN_SCENE)
	_check(packed != null, "main_3d scene loads")
	if packed != null:
		_main = packed.instantiate()
		_check(_main != null, "main_3d scene instantiates")
		if _main != null:
			root.add_child(_main)

	for path in ACTOR_SCENES:
		var actor_scene: PackedScene = load(path)
		_check(actor_scene != null, "3D actor scene loads: %s" % path)
		if actor_scene != null:
			var actor: Node = actor_scene.instantiate()
			_check(actor != null and actor is CharacterBody3D,
				"3D actor lifecycle instantiates: %s" % path)
			actor.free()


func _run_runtime_checks() -> void:
	if _main == null or not is_instance_valid(_main):
		_check(false, "main_3d remains alive after startup frames")
		return

	_check(_main.get_node_or_null("World3D") != null, "World3D is wired")
	_check(_main.get_node_or_null("HUD") != null, "Control/UI layer is wired")
	_check(get_first_node_in_group("tactical_command_ui_3d") is Control,
		"tactical command UI remains a Control")
	_check(root.get_node_or_null("GameTime") != null
		and root.get_node("GameTime").has_method("get_phase_name"),
		"DAY/NIGHT owner exposes the established phase contract")

	var camera_count := 0
	var nav_region_count := 0
	var nodes: Array[Node] = []
	_collect_nodes(_main, nodes)
	for node in nodes:
		if node is Camera3D:
			camera_count += 1
		elif node is NavigationRegion3D:
			nav_region_count += 1
	_check(camera_count == 1, "exactly one Camera3D owner")
	_check(nav_region_count == 1, "exactly one NavigationRegion3D owner")
	_check(get_nodes_in_group("camera_controller_3d").size() == 1,
		"exactly one camera input controller")
	_check(get_nodes_in_group("world_selection_3d").size() == 1,
		"exactly one world-selection input owner")
	_check(get_nodes_in_group("building_placement_3d").size() == 1,
		"exactly one building-placement input owner")
	_check(get_nodes_in_group("player").is_empty(),
		"no direct-combat Player actor exists")
	_check(get_nodes_in_group("players").is_empty(),
		"no alternate direct-combat Player actor group exists")


func _collect_nodes(node: Node, output: Array[Node]) -> void:
	output.append(node)
	for child in node.get_children():
		_collect_nodes(child, output)


func _finish() -> void:
	print("BASELINE_3D_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
