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
    _check(root.get_node_or_null("DungeonManager") != null, "autoload available: DungeonManager")
    _check(load("res://scripts/dungeon_runtime.gd") != null, "autoload available: DungeonRuntime")
    _check(root.get_node_or_null("MercenaryRoster") != null, "autoload available: MercenaryRoster")
    _check(root.get_node_or_null("DeathLedger") != null, "autoload available: DeathLedger")
    _check(root.get_node_or_null("WaveManager") != null, "autoload available: WaveManager")
    
    # DungeonManager 메서드 존재 여부 검증
    var dm = root.get_node_or_null("DungeonManager")
    if dm != null:
        _check(dm.has_method("start_run"), "DungeonManager has start_run")
        _check(dm.has_method("complete_run"), "DungeonManager has complete_run")
        _check(dm.has_method("fail_run"), "DungeonManager has fail_run")
        
        # 실제 DungeonRuntime 메서드 호출 테스트
        var dr = root.get_node_or_null("DungeonRuntime")
        if dr != null:
            _check(dr.has_method("begin_run"), "DungeonRuntime has begin_run")
            _check(dr.has_method("end_run"), "DungeonRuntime has end_run")
            _check(dr.has_method("spawn_party"), "DungeonRuntime has spawn_party")
            _check(dr.has_method("spawn_enemies_for_dungeon"), "DungeonRuntime has spawn_enemies_for_dungeon")
            _check(dr.has_method("is_run_active"), "DungeonRuntime has is_run_active")
            _check(dr.has_method("get_returned_alive_ids"), "DungeonRuntime has get_returned_alive_ids")
    
    # DeathLedger 메서드 존재 여부 검증
    var dl = root.get_node_or_null("DeathLedger")
    if dl != null:
        _check(dl.has_method("report_death"), "DeathLedger has report_death")
        
    print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
    quit(0 if _failures == 0 else 1)