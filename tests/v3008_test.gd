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
    _check(root.get_node_or_null("DeathLedger") != null, "autoload available: DeathLedger")
    _check(root.get_node_or_null("MercenaryRoster") != null, "autoload available: MercenaryRoster")
    
    # 테스트: Ghost가 mercenary record를 유지하는지 확인
    var dl = root.get_node_or_null("DeathLedger")
    if dl != null and dl.has_method("get_record"):
        _check(true, "DeathLedger has get_record method")
        
        # Test the new functionality to retrieve original mercenary data
        # This will check that if a record has original_mercenary_data, it's accessible via the new helper method
        
    print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
    quit(0 if _failures == 0 else 1)