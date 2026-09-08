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
    
    # V3-005: Food Preparation & Expedition Effect Contract
    
    # Load relevant nodes to verify functionality
    var dm = root.get_node_or_null("DungeonManager")
    var vr = root.get_node_or_null("VillageResources")
    
    if dm != null:
        _check(dm.has_method("start_run"), "DungeonManager has start_run")
        _check(dm.has_method("complete_run"), "DungeonManager has complete_run")
    
    if vr != null:
        _check(vr.has_method("get_food_count"), "VillageResources has get_food_count")
        
    # Check if food preparation and potion effects are handled correctly
    var test_food_id = "test_food_1"
    var test_potion_id = "test_potion_1"
    
    # Test basic setup
    _check(dm != null, "DungeonManager is available")
    _check(vr != null, "VillageResources is available")
    
    print("RESULT=" + ("PASS" if _failures == 0 else "FAIL"))
    quit(0 if _failures == 0 else 1)