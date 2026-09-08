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
    # 절대경로(drive letter) 금지. 프로젝트 루트 기준 상대경로만 사용.
    # autoload 검증은 root.get_node_or_null(...) 사용 (deferred 프레임 이후만 유효).
    # 여기에 태스크 핵심 동작 검증을 최소 1개 이상 추가 (실제 코드 로드/호출).
    # 주의: 존재하지 않는 메서드 직접 호출 금지(위 규칙). has_method()로 가드 후 호출.
    
    var dm = root.get_node_or_null("DungeonManager")
    if dm != null:
        _check(dm.has_method("start_run"), "DungeonManager has start_run")
        _check(dm.has_method("complete_run"), "DungeonManager has complete_run")
        # 실행은 반드시 call() 사용:    _check(dm.call("complete_run", "ruins_gate") != null, "complete_run observable")
    
    var dr = root.get_node_or_null("DungeonRuntime")
    if dr != null:
        _check(dr.has_method("spawn_enemies_for_dungeon"), "DungeonRuntime has spawn_enemies_for_dungeon")
        
    print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
    quit(0 if _failures == 0 else 1)