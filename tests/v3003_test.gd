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
	# autoload 검증
	_check(root.get_node_or_null("VillageResources") != null, "autoload available: VillageResources")
	_check(root.get_node_or_null("GameTime") != null, "autoload available: GameTime")
	_check(root.get_node_or_null("WorkerRoster") != null, "autoload available: WorkerRoster")
	_check(root.get_node_or_null("MercenaryRoster") != null, "autoload available: MercenaryRoster")
	_check(root.get_node_or_null("FirstEncounterSpawner") != null, "autoload available: FirstEncounterSpawner")
	_check(root.get_node_or_null("DeathLedger") != null, "autoload available: DeathLedger")
	_check(root.get_node_or_null("ExplorationManager") != null, "autoload available: ExplorationManager")
	_check(root.get_node_or_null("WaveManager") != null, "autoload available: WaveManager")
	_check(root.get_node_or_null("DungeonManager") != null, "autoload available: DungeonManager")
	_check(root.get_node_or_null("DungeonPreparationManager") != null, "autoload available: DungeonPreparationManager")
	
	# 기능 검증
	var dm = root.get_node_or_null("DungeonManager")
	if dm != null:
		_check(dm.has_method("start_run"), "DungeonManager has start_run")
		_check(dm.has_method("complete_run"), "DungeonManager has complete_run")
		_check(dm.has_method("fail_run"), "DungeonManager has fail_run")
	
	var wm = root.get_node_or_null("WaveManager")
	if wm != null:
		_check(wm.has_method("get_wave_count"), "WaveManager has get_wave_count")
		_check(wm.has_method("get_threat_level"), "WaveManager has get_threat_level")
	
	print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)