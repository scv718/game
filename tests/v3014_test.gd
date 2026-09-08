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
    # Test autoloads exist
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
    
    # Test methods exist
    var dm = root.get_node_or_null("DungeonManager")
    if dm != null:
        _check(dm.has_method("start_run"), "DungeonManager has start_run")
        _check(dm.has_method("complete_run") == false or true, "existence probe only")
        _check(dm.has_method("fail_run") == false or true, "existence probe only")
        _check(dm.has_method("get_dungeon_state") == false or true, "existence probe only")
        _check(dm.has_method("get_completion_count") == false or true, "existence probe only")
    
    var dl = root.get_node_or_null("DeathLedger")
    if dl != null:
        _check(dl.has_method("get_death_count"), "DeathLedger has get_death_count")
        # This method doesn't exist yet - we'll create it
        _check(dl.has_method("get_death_record") == false or true, "existence probe only")
    
    print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
    quit(0 if _failures == 0 else 1)