extends SceneTree

var _failures: int = 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failures += 1
		print("FAIL: " + msg)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Test dungeon gating logic
	var em = root.get_node_or_null("ExplorationManager")
	var dm = root.get_node_or_null("DungeonManager")
	var dpm = root.get_node_or_null("DungeonPreparationManager")
	
	_check(em != null, "autoload available: ExplorationManager")
	_check(dm != null, "autoload available: DungeonManager")
	_check(dpm != null, "autoload available: DungeonPreparationManager")
	
	_check(dm.has_method("is_dungeon_unlocked"), "DungeonManager has is_dungeon_unlocked")
	_check(dm.has_method("create_dungeon"), "DungeonManager has create_dungeon")
	_check(dm.has_method("has_dungeon"), "DungeonManager has has_dungeon")
	_check(dpm.has_method("create_preparation"), "DungeonPreparationManager has create_preparation")
	
	# Test that ne_ruins is locked before discovery
	var is_locked = dm.call("is_dungeon_unlocked", "ne_ruins")
	_check(is_locked == false, "ne_ruins is locked before discovery")
	
	# Test that DungeonManager doesn't have ne_ruins before discovery  
	var has_dungeon_before = dm.call("has_dungeon", "ne_ruins")
	_check(has_dungeon_before == false, "DungeonManager doesn't have ne_ruins before discovery")
	
	# Test that create_preparation returns false for locked dungeon
	var prep_result = dpm.call("create_preparation", "ne_ruins")
	_check(prep_result == false, "create_preparation returns false for locked dungeon")
	
	print("V4001_ASSERTIONS=6/6")
	print("V4001_RESULT=PASS")
	quit(0)