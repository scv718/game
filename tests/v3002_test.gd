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
	# Test that autoload services exist and are accessible
	_check(root.get_node_or_null("VillageResources") != null, "autoload available: VillageResources")
	_check(root.get_node_or_null("WorkerRoster") != null, "autoload available: WorkerRoster")
	_check(root.get_node_or_null("DungeonManager") != null, "autoload available: DungeonManager")
	_check(root.get_node_or_null("DeathLedger") != null, "autoload available: DeathLedger")
	_check(root.get_node_or_null("WaveManager") != null, "autoload available: WaveManager")
	
	# Test that DungeonManager has required methods
	var dm = root.get_node_or_null("DungeonManager")
	if dm != null:
		_check(dm.has_method("complete_run"), "DungeonManager has complete_run")
		_check(dm.has_method("fail_run"), "DungeonManager has fail_run")
	
	# Test integration with WaveManager
	if dm != null and dm.has_method("complete_run"):
		var wave_manager = root.get_node_or_null("WaveManager")
		if wave_manager != null:
			_check(wave_manager.has_method("report_dungeon_result"), "WaveManager has report_dungeon_result")
	
	print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)