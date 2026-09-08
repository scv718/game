extends SceneTree

const MAIN_SCENE := "res://scenes/main_3d.tscn"
const DUNGEON_MANAGER := "res://scripts/dungeon_manager.gd"
const DUNGEON_PREPARATION_MANAGER := "res://scripts/dungeon_preparation_manager.gd"

var _frames := 0
var _failed := false

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
		print("V3-013_RESULT=TIMEOUT")
		quit(1)
		return true
	return false

func _run_load_checks() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	_check(packed != null, "main_3d scene loads")

	var dungeon_manager: Script = load(DUNGEON_MANAGER)
	_check(dungeon_manager != null, "DungeonManager script parses")

	var prep_manager: Script = load(DUNGEON_PREPARATION_MANAGER)
	_check(prep_manager != null, "DungeonPreparationManager script parses")

func _run_runtime_checks() -> void:
	# Validate autoloads are present
	var required_autoloads := [
		"VillageResources", "GameTime", "WorkerRoster", "MercenaryRoster",
		"FirstEncounterSpawner", "DeathLedger", "ExplorationManager",
		"WaveManager", "DungeonManager", "DungeonPreparationManager"
	]
	
	for autoload_name in required_autoloads:
		var node := root.get_node_or_null(autoload_name)
		_check(node != null, "critical autoload available: %s" % autoload_name)

	# Test DungeonManager methods exist
	var dm := root.get_node_or_null("DungeonManager")
	if dm != null:
		_check(dm.has_method("start_run"), "DungeonManager has start_run method")
		_check(dm.has_method("complete_run"), "DungeonManager has complete_run method")
		_check(dm.has_method("fail_run"), "DungeonManager has fail_run method")
		_check(dm.has_method("get_dungeon_state"), "DungeonManager has get_dungeon_state method")
		_check(dm.has_method("get_completion_count"), "DungeonManager has get_completion_count method")

func _finish() -> void:
	print("V3-013_RESULT=" + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)